import { useState } from "react"
import { SparklesIcon } from "@/components/icons/SparklesIcon"
import { Alert } from "@/components/arc/alert/alert"
import { Button } from "@/components/arc/button/button"
import { Textarea } from "@/components/arc/textarea/textarea"
import { EditorSheet } from "./EditorSheet"
import { MoneyField } from "./MoneyField"
import { SelectField } from "./SelectField"
import { SwitchField } from "./SwitchField"
import { TextField } from "./TextField"
import { NumberInput } from "./NumberInput"
import { DEFAULT_REPEAT_WINDOW_MINUTES, PLAYBOOK_MAX_LENGTH, REPEAT_WINDOW_RANGE, accountChoices, effectiveChannel, policyOf, split } from "./draft"
import { editGuru, learnPlaybook, removeGuru, useSetup } from "./setup-store"
import { sizing } from "./sizing"
import styles from "./connections.module.css"

/** One guru: where they post, how to read their calls, and the account that copies them. */
export function GuruSheet({ uid, onClose }: { uid: string; onClose: () => void }) {
  const s = useSetup()
  const { draft } = s
  const guru = draft.gurus.find((g) => g.uid === uid)
  const [confirmsRemove, setConfirmsRemove] = useState(false)
  const [learning, setLearning] = useState(false)
  const [learned, setLearned] = useState<{ ok: boolean; text: string } | null>(null)
  if (!guru) return null
  const channels = split(draft.channels)
  const channel = effectiveChannel(draft, guru)
  const channelChoices = channel && !channels.includes(channel) ? [...channels, channel] : channels
  const accounts = accountChoices(draft, guru)
  const accountList = guru.account_id && !accounts.includes(guru.account_id) ? [...accounts, guru.account_id] : accounts
  const policy = policyOf(draft, guru.account_id)
  const sized = guru.account_id ? sizing(guru.full_position_usd, policy) : null
  const length = [...guru.playbook].length

  const learn = async () => {
    setLearning(true)
    setLearned(null)
    setLearned(await learnPlaybook(uid))
    setLearning(false)
  }

  return (
    <EditorSheet
      title={guru.display_name.trim() || "New guru"}
      description={
        channel && guru.account_id
          ? `Copies channel ${channel.length > 10 ? `${channel.slice(0, 4)}…${channel.slice(-4)}` : channel} into ${guru.account_id}.`
          : "Needs a Discord channel and an account."
      }
      onClose={onClose}
      footer={
        <>
          <Button size="sm" type="button" variant="ghost" onClick={() => setConfirmsRemove(true)}>
            <span className={styles.dangerText}>Remove guru</span>
          </Button>
          <div className={styles.footerEnd}>
            <Button size="sm" type="button" onClick={onClose}>
              Done
            </Button>
          </div>
        </>
      }
    >
      {confirmsRemove && (
        <Alert tone="warning" title={`Remove ${guru.display_name.trim() || "this guru"}?`}>
          Their calls stop being copied once you start copying with this change. Shares they bought stay in the account.
          <div className={styles.footerEnd} style={{ marginTop: 8 }}>
            <Button type="button" size="sm" variant="secondary" onClick={() => setConfirmsRemove(false)}>
              Keep
            </Button>
            <Button
              type="button"
              size="sm"
              variant="danger"
              onClick={() => {
                onClose()
                removeGuru(uid)
              }}
            >
              Remove guru
            </Button>
          </div>
        </Alert>
      )}
      <div className={styles.fields}>
        <TextField label="Name" value={guru.display_name} onChange={(display_name) => editGuru(uid, { display_name })} placeholder="How you refer to this guru" />
        {channelChoices.length ? (
          <SelectField label="Discord channel" value={channel} choices={channelChoices.map((c) => ({ value: c, label: c }))} onChange={(channel_id) => editGuru(uid, { channel_id })} />
        ) : (
          <div className={styles.field}>
            <span className={styles.fieldLabel}>Discord channel</span>
            <p className={styles.fieldHint}>Add the channel they post in under Discord in Connections first.</p>
          </div>
        )}
        <TextField label="Discord user ID" hint="Optional. Only needed when others post in the channel." value={guru.author_id} onChange={(author_id) => editGuru(uid, { author_id })} placeholder="Any poster" inputMode="numeric" />
      </div>

      <fieldset className={styles.fieldset}>
        <legend>Copies into</legend>
        {accountList.length ? (
          <SelectField label="Account" hint="Each account copies one guru." value={guru.account_id} placeholder="Choose an account" choices={accountList.map((a) => ({ value: a, label: a }))} onChange={(account_id) => editGuru(uid, { account_id })} />
        ) : (
          <div className={styles.field}>
            <span className={styles.fieldLabel}>Account</span>
            <p className={styles.fieldHint}>Every account already copies a guru. Add a broker account in Connections first.</p>
          </div>
        )}
        {guru.account_id && (
          <MoneyField
            label="Full position"
            hint={`The guru's whole position, in dollars. A 1/6 call buys a sixth.${policy?.max_symbol_usd.trim() ? ` Blank uses the account's maximum per stock, $${policy.max_symbol_usd.trim()}.` : ""}`}
            value={guru.full_position_usd}
            onChange={(full_position_usd) => editGuru(uid, { full_position_usd })}
          />
        )}
        {sized ? (
          <dl className={styles.figures} aria-label="What this guru's calls buy">
            {sized.figures.map((figure) => (
              <div key={figure.label}>
                <dt>{figure.label}</dt>
                <dd>
                  {figure.cutFrom && <span className={styles.cut}>cut from {figure.cutFrom}</span>}
                  {figure.amount}
                </dd>
              </div>
            ))}
          </dl>
        ) : (
          guru.account_id && <p className={styles.note}>Set the guru’s full position, or this account’s max per stock.</p>
        )}
        {(sized?.warning ?? sized?.note) && <p className={styles.note}>{sized?.warning ?? sized?.note}</p>}
      </fieldset>

      <fieldset className={styles.fieldset}>
        <legend>Playbook</legend>
        <div className={styles.labelRow}>
          <span className={styles.fieldHint}>One rule per line, such as “英伟达 means NVDA”.</span>
          <Button type="button" size="sm" variant="secondary" loading={learning} onClick={() => void learn()}>
            {!learning && <SparklesIcon width={16} height={16} aria-hidden="true" />}
            {guru.playbook.trim() ? "Learn again" : "Learn from channel"}
          </Button>
        </div>
        <Textarea label="How the model should read this guru" value={guru.playbook} onChange={(event) => editGuru(uid, { playbook: event.target.value })} spellCheck={false} rows={8} />
        <div className={styles.counter} data-over={length > PLAYBOOK_MAX_LENGTH || undefined}>
          <span />
          <span>
            {length.toLocaleString("en-US")} of {PLAYBOOK_MAX_LENGTH.toLocaleString("en-US")} characters
          </span>
        </div>
        {learned && (
          <Alert tone={learned.ok ? "info" : "danger"} title={learned.ok ? "Playbook drafted" : "Could not learn"}>
            {learned.text}
          </Alert>
        )}
      </fieldset>

      <fieldset className={styles.fieldset}>
        <legend>Re-posted calls</legend>
        <SwitchField
          title="Skip re-posted calls"
          hint={guru.repeat_window_minutes === null ? "Every post is copied, even a repeat." : "Same stock, price, and size counts once. A repeated sell counts once a day."}
          checked={guru.repeat_window_minutes !== null}
          onChange={(on) => editGuru(uid, { repeat_window_minutes: on ? (guru.repeat_window_minutes ?? DEFAULT_REPEAT_WINDOW_MINUTES) : null })}
        />
        {guru.repeat_window_minutes !== null && (
          <NumberInput
            label="Re-post window (minutes)"
            hint={`From ${REPEAT_WINDOW_RANGE[0]} minute to a day (${REPEAT_WINDOW_RANGE[1].toLocaleString("en-US")}).`}
            value={guru.repeat_window_minutes}
            // A typed value outside a minute to a day is held to the nearest end.
            onChange={(minutes) => editGuru(uid, { repeat_window_minutes: Math.min(Math.max(Math.round(minutes), REPEAT_WINDOW_RANGE[0]), REPEAT_WINDOW_RANGE[1]) })}
          />
        )}
      </fieldset>
    </EditorSheet>
  )
}
