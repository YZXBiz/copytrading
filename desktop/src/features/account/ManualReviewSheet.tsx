import { useState } from "react"
import { PlusIcon } from "lucide-react"
import type { AccountOverview, ManualCorrectionOutcome, ManualOrderPreview, SourceActivity } from "../../../shared/contract"
import { Alert, AlertDescription } from "@/components/reui/alert"
import { Badge } from "@/components/reui/badge"
import { Button } from "@/components/ui/button"
import { Field, FieldDescription, FieldGroup, FieldLabel, FieldLegend, FieldSet, FieldTitle, FieldContent } from "@/components/ui/field"
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { Spinner } from "@/components/ui/spinner"
import { Switch } from "@/components/ui/switch"
import { dateTime } from "@/lib/format"
import { type Draft, MODE_REASON, MODE_TITLE, draftFromCall, guessDraft, isValid, newDraft, reviewMode, toInstruction, withMarketPrice } from "./manual-draft"
import { type Outcome, hasSent, isReady } from "./manual-preview"
import { PreviewRow } from "./PreviewRow"
import { holdings as heldBy, livePrice } from "./quote"
import { refusalLine, refusalReason } from "@/lib/reasons"
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
  const lede = [guruName ?? source.guru_id, dateTime(source.source_at), { approve: "Waiting for your approval.", copy: "Waiting for you to copy it.", enter: guessed ? "Filled in from the post's words. Check it, then send." : "CopyTrading couldn't read a trade in this post." }[mode]]
    .filter(Boolean)
    .join(" · ")

  return (
    <Sheet open onOpenChange={(open) => !open && onClose()}>
      <SheetContent className="w-full sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>{MODE_TITLE[mode]}</SheetTitle>
          <SheetDescription>{lede}</SheetDescription>
        </SheetHeader>
        <div className="flex-1 overflow-y-auto px-4">
          <FieldGroup className="gap-6">
            <FieldSet>
              <FieldLegend variant="label">Post</FieldLegend>
              {/* The post is untrusted Discord text: rendered as text, never as HTML. */}
              <p className="bg-muted/50 rounded-md border px-3 py-2 text-sm whitespace-pre-wrap select-text">{source.text || "A post with no words"}</p>
            </FieldSet>

            <fieldset disabled={locked} className="flex flex-col gap-6 disabled:opacity-60">
              {drafts.map((draft, i) => {
                const symbol = draft.symbol.trim().toUpperCase()
                return (
                  <FieldSet key={draft.id}>
                    <div className="flex items-center justify-between">
                      <FieldLegend variant="label">{drafts.length > 1 ? `Trade ${i + 1}` : "Trade"}</FieldLegend>
                      {drafts.length > 1 && (
                        <Button type="button" size="xs" variant="ghost" onClick={() => setDrafts((all) => all.filter((d) => d.id !== draft.id))}>
                          Remove
                        </Button>
                      )}
                    </div>
                    <TradeFields draft={draft} onChange={(next) => update(draft.id, next)} holdings={held} quote={quotes[symbol] ?? null} quoting={asking.has(symbol)} onRefreshQuote={() => refresh(symbol)} now={now} />
                  </FieldSet>
                )
              })}
              {!locked && drafts.length < MAX_TRADES && (
                <Button type="button" size="sm" variant="ghost" className="self-start" onClick={() => setDrafts((all) => [...all, newDraft()])}>
                  <PlusIcon aria-hidden /> Add Trade
                </Button>
              )}

              <FieldSet>
                <FieldLegend variant="label">Accounts</FieldLegend>
                {accounts.length === 0 && <FieldDescription>No account status is loaded.</FieldDescription>}
                {accounts.map((account) => (
                  <Field key={account.account_id} orientation="horizontal">
                    <FieldContent>
                      <FieldTitle>
                        {account.account_id} {account.environment === "live" && <Badge variant="warning-light">Live</Badge>}
                      </FieldTitle>
                    </FieldContent>
                    <Switch
                      aria-label={account.account_id}
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
                  </Field>
                ))}
              </FieldSet>
            </fieldset>

            {correctionId && (
              <FieldSet>
                <FieldLegend variant="label">Checked just now</FieldLegend>
                {error && (
                  <p role="alert" className="text-destructive text-sm">
                    {error}
                  </p>
                )}
                {saved?.accounts
                  .filter((a) => a.status !== "recorded")
                  .map((a) => (
                    <Alert key={a.account_id} variant={a.status === "unavailable" ? "warning" : "destructive"}>
                      <AlertDescription className="text-foreground">
                        {a.account_id}: {refusalReason(a.reason ?? a.status)}
                      </AlertDescription>
                    </Alert>
                  ))}
                <ul className="divide-y">
                  {checks.map((c) => (
                    <PreviewRow key={c.previewId} accountId={c.accountId} index={c.index} preview={c.preview} error={c.error} outcome={outcomes[c.commandId]} />
                  ))}
                </ul>
                {checking && (
                  <p className="text-muted-foreground flex items-center gap-2 text-sm">
                    <Spinner /> Checking current account and market state…
                  </p>
                )}
              </FieldSet>
            )}
          </FieldGroup>
        </div>
        <SheetFooter className="flex-row justify-end">
          <Button type="button" variant="outline" onClick={onClose}>
            {sent ? "Done" : "Close"}
          </Button>
          {!correctionId ? (
            <Button type="button" disabled={!canSave} onClick={check}>
              Check Order
            </Button>
          ) : checking || sending ? (
            <Button type="button" disabled>
              {sending ? "Placing…" : "Checking…"}
            </Button>
          ) : ready.length > 0 ? (
            <Button type="button" onClick={place}>
              Place {ready.length} {ready.length === 1 ? "Order" : "Orders"}…
            </Button>
          ) : !sent ? (
            <Button type="button" onClick={change}>
              Change It
            </Button>
          ) : null}
        </SheetFooter>
      </SheetContent>
    </Sheet>
  )
}
