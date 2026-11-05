import { useState } from "react"
import { Add01Icon } from "@/components/icons/Add01Icon"
import type { AccountOverview, ManualCorrectionOutcome, ManualOrderPreview, SourceActivity } from "../../../shared/contract"
import { Alert } from "@/components/arc/alert/alert"
import { Badge } from "@/components/arc/badge/badge"
import { Button } from "@/components/arc/button/button"
import { Drawer, DrawerContent } from "@/components/arc/drawer/drawer"
import { Switch } from "@/components/arc/switch/switch"
import { dateTime } from "@/lib/format"
import { type Draft, MODE_REASON, MODE_TITLE, draftFromCall, guessDraft, isValid, newDraft, reviewMode, toInstruction, withMarketPrice } from "./manual-draft"
import { type Outcome, hasSent, isReady } from "./manual-preview"
import { PreviewRow } from "./PreviewRow"
import { holdings as heldBy, livePrice } from "./quote"
import { refusalLine, refusalReason } from "@/lib/reasons"
import styles from "./sheet.module.css"
import { TradeFields } from "./TradeFields"
import { useQuotes } from "./use-quotes"
import type { WaitingCall } from "./waiting"

/** One drafted trade checked in one account, and the id its order goes out under, kept so a retry never places it twice. */
interface Check {
  previewId: string
  commandId: string
  accountId: string
  index: number
  preview: ManualOrderPreview | null
  error: string | null
}

const MAX_TRADES = 20

/**
 * The owner says what a post should do and sends it: the post, each trade's fields, the accounts, and one button that
 * always does the next step. Underneath it is the engine's manual correction: saved, previewed fresh in each account,
 * then confirmed (ADR-0007). The confirmation dialog comes from the main process, built from the engine's own plan.
 */
export function ManualReviewSheet({
  source,
  call,
  accounts: allAccounts,
  guruName,
  now,
  onClose,
}: {
  source: SourceActivity
  call: WaitingCall | null
  accounts: AccountOverview[]
  guruName: string | null
  now: Date
  /** Closed; something may have been checked or placed, so the page reads again. */
  onClose: () => void
}) {
  // An account can copy only a post it received: the guru's calls reach the one account it copies into.
  const reached = new Set(source.destinations.map((d) => d.account_id))
  const accounts = reached.size === 0 ? allAccounts : allAccounts.filter((a) => reached.has(a.account_id))
  const mode = reviewMode(call)
  const [selected, setSelected] = useState<ReadonlySet<string>>(() => {
    const waiting = new Set(call?.accountIds ?? source.destinations.filter((d) => d.status === "review_required").map((d) => d.account_id))
    return new Set(accounts.map((a) => a.account_id).filter((id) => waiting.has(id)))
  })
  // Copying fills in the calls the post waits on; otherwise the reader's reading, and when it had none, the
  // likeliest trade in the post's words.
  const [start] = useState(() => {
    const calls = call && call.calls.length > 0 ? call.calls : source.suggested?.length ? source.suggested : source.instructions
    if (calls.length > 0) return { drafts: calls.map(draftFromCall), guessed: false }
    const guess = guessDraft(source.text, heldBy(accounts, selected).map((h) => h.symbol))
    return { drafts: [guess ?? newDraft()], guessed: guess !== null }
  })
  const [drafts, setDrafts] = useState<Draft[]>(start.drafts)
  const guessed = start.guessed

  const [correctionId, setCorrectionId] = useState<string | null>(null)
  const [saved, setSaved] = useState<ManualCorrectionOutcome | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [checks, setChecks] = useState<Check[]>([])
  const [checking, setChecking] = useState(false)
  const [sending, setSending] = useState(false)
  const [outcomes, setOutcomes] = useState<Record<string, Outcome>>({})

  const chosen = accounts.filter((a) => selected.has(a.account_id))
  const held = heldBy(accounts, selected)
  const quoting = (chosen[0] ?? accounts[0])?.account_id ?? null
  const { quotes, asking, refresh } = useQuotes(quoting, drafts.map((d) => d.symbol.trim().toUpperCase()))
  const resolved = drafts.map((d) => {
    const symbol = d.symbol.trim().toUpperCase()
    return withMarketPrice(d, livePrice(quotes[symbol] ?? null, d.isSell, now))
  })
  const locked = correctionId !== null
  const canSave = !!source.source_id && selected.size > 0 && resolved.length > 0 && resolved.every(isValid)
  const ready = checks.filter((c) => isReady(c.preview) && !outcomes[c.commandId])
  const sent = hasSent(Object.values(outcomes))

  async function check() {
    const id = crypto.randomUUID()
    setCorrectionId(id)
    setChecking(true)
    setError(null)
    const result = await window.copytrading.act.saveManualCorrection({
      correction: {
        correction_id: id,
        source_id: source.source_id!,
        selected_account_ids: [...selected],
        actor: "owner",
        reason: MODE_REASON[mode],
        instructions: resolved.map(toInstruction),
      },
    })
    if (!result.ok) {
      setError(refusalLine(result.error))
      setChecking(false)
      return
    }
    setSaved(result.value)
    // Saved: go straight on to what the order would be, fresh in each account that recorded the call.
    const entries = result.value.accounts
      .filter((a) => a.status === "recorded")
      .flatMap((a) => resolved.map((_, index) => ({ previewId: crypto.randomUUID(), commandId: crypto.randomUUID(), accountId: a.account_id, index })))
    setChecks(entries.map((e) => ({ ...e, preview: null, error: null })))
    const done = await Promise.all(
      entries.map(async (entry): Promise<Check> => {
        const preview = await window.copytrading.read.previewManualOrder({
          preview: { preview_id: entry.previewId, account_id: entry.accountId, correction_id: id, instruction_index: entry.index },
        })
        return { ...entry, preview: preview.ok ? preview.value : null, error: preview.ok ? null : refusalLine(preview.error) }
      }),
    )
    setChecks(done)
    setChecking(false)
  }

  async function place() {
    setSending(true)
    setError(null)
    const result = await window.copytrading.act.confirmManualOrders({
      commands: ready.map((c) => ({ command_id: c.commandId, preview_id: c.previewId, account_id: c.accountId, actor: "owner" })),
    })
    setSending(false)
    if (result.ok) {
      setOutcomes((o) => ({ ...o, ...Object.fromEntries(result.value.outcomes.map((x) => [x.command_id, { result: x.result, error: x.error }])) }))
    } else if (!result.cancelled) {
      setError(refusalLine(result.error))
    }
  }

  /** Unlocks the choices for another try under a new correction, after the engine refused. */
  function change() {
    setCorrectionId(null)
    setSaved(null)
    setChecks([])
    setError(null)
  }

  const update = (id: string, draft: Draft) => setDrafts((all) => all.map((d) => (d.id === id ? draft : d)))
  const lede = [
    `${guruName ?? source.guru_id}, ${dateTime(source.source_at)}`,
    { approve: "Waiting for your approval.", copy: "Waiting for you to copy it.", enter: guessed ? "Filled in from the post's words. Check it, then send." : "CopyTrading couldn't read a trade in this post." }[mode],
  ].join(". ")

  return (
    <Drawer open onOpenChange={(open) => !open && onClose()}>
      <DrawerContent title={MODE_TITLE[mode]} description={lede} className={styles.sheet}>
        <div className={styles.sections}>
          <fieldset className={styles.group}>
            <legend>Post</legend>
            {/* The post is untrusted Discord text: rendered as text, never as HTML. */}
            <p className={styles.post}>{source.text || "A post with no words"}</p>
          </fieldset>

          <fieldset disabled={locked} className={styles.group} data-locked={locked || undefined}>
            {drafts.map((draft, i) => {
              const symbol = draft.symbol.trim().toUpperCase()
              return (
                <div key={draft.id} className={styles.trade}>
                  <div className={styles.tradeHead}>
                    <span className={styles.groupTitle}>{drafts.length > 1 ? `Trade ${i + 1}` : "Trade"}</span>
                    {drafts.length > 1 && (
                      <Button type="button" size="sm" variant="ghost" onClick={() => setDrafts((all) => all.filter((d) => d.id !== draft.id))}>
                        Remove trade
                      </Button>
                    )}
                  </div>
                  <TradeFields draft={draft} onChange={(next) => update(draft.id, next)} holdings={held} quote={quotes[symbol] ?? null} quoting={asking.has(symbol)} onRefreshQuote={() => refresh(symbol)} now={now} />
                </div>
              )
            })}
            {!locked && drafts.length < MAX_TRADES && (
              <Button type="button" size="sm" variant="ghost" className={styles.addTrade} onClick={() => setDrafts((all) => [...all, newDraft()])}>
                <Add01Icon width={16} height={16} aria-hidden="true" /> Add trade
              </Button>
            )}

            <div className={styles.accounts}>
              <span className={styles.groupTitle}>Accounts</span>
              {accounts.length === 0 && <p className={styles.hint}>No account status is loaded.</p>}
              {accounts.map((account) => (
                <div key={account.account_id} className={styles.accountRow}>
                  <span id={`review-${account.account_id}`} className={styles.accountName}>
                    {account.account_id} {account.environment === "live" && <Badge tone="warning">Live</Badge>}
                  </span>
                  <Switch
                    aria-labelledby={`review-${account.account_id}`}
                    checked={selected.has(account.account_id)}
                    onCheckedChange={(on) =>
                      setSelected((s) => {
                        const next = new Set(s)
                        if (on) next.add(account.account_id)
                        else next.delete(account.account_id)
                        return next
                      })
                    }
                  />
                </div>
              ))}
            </div>
          </fieldset>

          {correctionId && (
            <fieldset className={styles.group}>
              <legend>Checked just now</legend>
              {error && (
                <p role="alert" className={styles.problem}>
                  {error}
                </p>
              )}
              {saved?.accounts
                .filter((a) => a.status !== "recorded")
                .map((a) => (
                  <Alert key={a.account_id} tone={a.status === "unavailable" ? "warning" : "danger"} title={`${a.account_id}: ${refusalReason(a.reason ?? a.status)}`} />
                ))}
              <ul className={styles.previews}>
                {checks.map((c) => (
                  <PreviewRow key={c.previewId} accountId={c.accountId} index={c.index} preview={c.preview} error={c.error} outcome={outcomes[c.commandId]} />
                ))}
              </ul>
              {checking && (
                <p className={styles.hint} role="status">
                  Checking current account and market state
                </p>
              )}
            </fieldset>
          )}
        </div>
        <div className={styles.footer}>
          <Button type="button" variant="secondary" onClick={onClose}>
            {sent ? "Done" : "Close"}
          </Button>
          {!correctionId ? (
            <Button type="button" disabled={!canSave} onClick={check}>
              Check order
            </Button>
          ) : checking || sending ? (
            <Button type="button" loading>
              {sending ? "Placing" : "Checking"}
            </Button>
          ) : ready.length > 0 ? (
            <Button type="button" onClick={place}>
              Place {ready.length} {ready.length === 1 ? "order" : "orders"}
            </Button>
          ) : !sent ? (
            <Button type="button" onClick={change}>
              Change it
            </Button>
          ) : null}
        </div>
      </DrawerContent>
    </Drawer>
  )
}
