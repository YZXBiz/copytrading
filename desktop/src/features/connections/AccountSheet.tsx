import { useState } from "react"
import { Alert } from "@/components/arc/alert/alert"
import { Button } from "@/components/arc/button/button"
import type { AccountPolicy } from "../../../shared/contract"
import { CheckNotice } from "./CheckNotice"
import { ChoiceField } from "./ChoiceField"
import { EditorSheet } from "./EditorSheet"
import { MoneyField } from "./MoneyField"
import { NumberInput } from "./NumberInput"
import { SwitchField } from "./SwitchField"
import { TextField } from "./TextField"
import { FOLLOW_STOPS_HINT, FOLLOW_STOPS_TITLE } from "@/features/account/limits"
import { accountNameProblem } from "./draft"
import { applyLimits, connect, editAccount, editPolicy, isCopying, keysOf, removeAccount, useSetup } from "./setup-store"
import { accountSubject, resultFor, same } from "./state"
import styles from "./connections.module.css"

type Text = { [K in keyof AccountPolicy]: AccountPolicy[K] extends string ? K : never }[keyof AccountPolicy]
type Count = { [K in keyof AccountPolicy]: AccountPolicy[K] extends number ? K : never }[keyof AccountPolicy]

const LIMITS: { key: Text; label: string; hint: string; kind: "usd" | "pct" }[] = [
  { key: "max_order_usd", label: "Largest single buy", hint: "The most one buy spends, and what a call with no size buys.", kind: "usd" },
  { key: "max_symbol_usd", label: "Maximum per stock", hint: "Shares CopyTrading bought. Your own aren't counted.", kind: "usd" },
  { key: "max_total_usd", label: "Maximum total exposure", hint: "Every stock CopyTrading bought. Your own aren't counted.", kind: "usd" },
  { key: "daily_loss_cap_usd", label: "Daily loss cap", hint: "Stops buying for the day. Still sells.", kind: "usd" },
  { key: "max_above_signal_pct", label: "Maximum above signal price (%)", hint: "0 means never more than the guru paid.", kind: "pct" },
  { key: "max_below_signal_pct", label: "Lowest sell price (% under the guru's)", hint: "A sell waits at this price or better until it fills.", kind: "pct" },
]

const TIMING: { key: Count; label: string; hint: string }[] = [
  { key: "max_entries_per_day", label: "Entries per day", hint: "Sells don't count." },
  { key: "max_signal_age_seconds", label: "Maximum signal age (seconds)", hint: "Older buys aren't copied. A sell always is." },
  { key: "order_timeout_seconds", label: "Order timeout (seconds)", hint: "An unfilled buy is cancelled. A sell keeps waiting." },
]

/** One broker account: its name, paper or live, its Alpaca keys, and the limits every order into it must stay inside. */
export function AccountSheet({ uid, onClose }: { uid: string; onClose: () => void }) {
  const s = useSetup()
  const account = s.draft.accounts.find((a) => a.uid === uid)
  const [confirmsRemove, setConfirmsRemove] = useState(false)
  const [applying, setApplying] = useState(false)
  const [applyError, setApplyError] = useState<string | null>(null)
  if (!account) return null
  const name = account.name.trim()
  const subject = accountSubject(name)
  const copying = isCopying(s)
  const savedKeys = Boolean(keysOf(s)?.brokers[name])
  const result = resultFor(s.checks, s.draft, subject)
  const savedPolicy = s.load.status === "ready" ? s.load.data.saved?.configuration.accounts.find((a) => a.id === name)?.policy : undefined
  const nameProblem = name || account.name ? accountNameProblem(account.name) : null

  const apply = async () => {
    setApplying(true)
    setApplyError(await applyLimits(uid))
    setApplying(false)
  }

  return (
    <EditorSheet
      title={name || "New account"}
      description={account.environment === "live" ? "Live: real orders, real money" : "Paper: pretend money, real prices"}
      onClose={onClose}
      footer={
        <>
          <Button size="sm" type="button" variant="ghost" onClick={() => setConfirmsRemove(true)}>
            <span className={styles.dangerText}>Remove account</span>
          </Button>
          <div className={styles.footerEnd}>
            {copying && (
              <Button size="sm" type="button" variant="secondary" loading={applying} disabled={!savedPolicy || same(savedPolicy, account.policy)} onClick={() => void apply()}>
                Apply limits now
              </Button>
            )}
            <Button size="sm" type="button" variant="secondary" loading={result?.check === null} onClick={() => void connect(subject)}>
              {result ? "Check again" : "Connect"}
            </Button>
            <Button size="sm" type="button" onClick={onClose}>
              Done
            </Button>
          </div>
        </>
      }
    >
      {confirmsRemove && (
        <Alert tone="warning" title={`Remove ${name || "this account"}?`}>
          Its guru stops being copied once you start copying with this change. Shares in it stay with Alpaca.
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
                removeAccount(uid)
              }}
            >
              Remove account
            </Button>
          </div>
        </Alert>
      )}
      {copying && (
        <Alert tone="info" title="Copying is running">
          Apply limits now changes only this account’s limits, from the next order. Any other change is applied from the bar below, which restarts copying for a few seconds.
        </Alert>
      )}
      <div className={styles.fields}>
        <TextField label="Name" hint="Letters, digits, “-” and “_”." error={nameProblem} value={account.name} onChange={(value) => editAccount(uid, (a) => ({ ...a, name: value }))} placeholder="e.g. primary" />
        <ChoiceField
          label="Environment"
          value={account.environment}
          choices={[
            { value: "paper", label: "Paper" },
            { value: "live", label: "Live" },
          ]}
          onChange={(environment) => editAccount(uid, (a) => ({ ...a, environment }))}
        />
        {account.environment === "live" && <Alert tone="warning" title="Live accounts place real orders with real money." />}
      </div>

      <fieldset className={styles.fieldset}>
        <legend>Alpaca keys</legend>
        <TextField
          label="API key"
          hint={savedKeys ? "Kept encrypted on this Mac. Leave blank to keep the saved keys." : "Kept encrypted on this Mac, never in the setup file."}
          value={account.key}
          onChange={(key) => editAccount(uid, (a) => ({ ...a, key }))}
          type="password"
          placeholder={savedKeys ? "Saved" : "Required"}
        />
        <TextField label="API secret" value={account.secret} onChange={(secret) => editAccount(uid, (a) => ({ ...a, secret }))} type="password" placeholder={savedKeys ? "Saved" : "Required"} />
        <CheckNotice subject={subject} result={result} notice={s.notices[subject]} />
      </fieldset>

      <fieldset className={styles.fieldset}>
        <legend>Position limits</legend>
        {LIMITS.map(({ key, label, hint, kind }) =>
          kind === "usd" ? (
            <MoneyField key={key} label={label} hint={hint} value={account.policy[key]} onChange={(value) => editPolicy(uid, { [key]: value })} />
          ) : (
            <TextField key={key} label={label} hint={hint} value={account.policy[key]} onChange={(value) => editPolicy(uid, { [key]: value })} inputMode="decimal" />
          ),
        )}
      </fieldset>

      <fieldset className={styles.fieldset}>
        <legend>Timing</legend>
        {TIMING.map(({ key, label, hint }) => (
          <NumberInput key={key} label={label} hint={hint} value={account.policy[key]} onChange={(value) => editPolicy(uid, { [key]: value })} />
        ))}
      </fieldset>

      <fieldset className={styles.fieldset}>
        <legend>Behavior</legend>
        <div className={styles.switches}>
          <SwitchField
            title="Trade in extended hours"
            hint="4:00 to 9:30 AM and 4:00 to 8:00 PM New York time, with limit orders."
            checked={account.policy.extended_hours}
            // Overnight runs only with extended hours, so turning those off ends it too.
            onChange={(on) => editPolicy(uid, on ? { extended_hours: true } : { extended_hours: false, overnight: false })}
          />
          <SwitchField
            title="Trade overnight"
            hint="8:00 PM to 4:00 AM New York time. Needs extended hours."
            checked={account.policy.overnight}
            onChange={(on) => editPolicy(uid, on ? { overnight: true, extended_hours: true } : { overnight: false })}
          />
          <SwitchField title="Copy exits" hint="Off means you sell copied shares yourself." checked={account.policy.copy_exits} onChange={(copy_exits) => editPolicy(uid, { copy_exits })} />
          <SwitchField
            title="Ask me before sending orders"
            hint="No order goes out by itself: each waits for you to approve it from its post in Activity."
            checked={account.policy.approve_orders}
            onChange={(approve_orders) => editPolicy(uid, { approve_orders })}
          />
          <SwitchField title={FOLLOW_STOPS_TITLE} hint={FOLLOW_STOPS_HINT} checked={account.policy.follow_stops === true}onChange={(follow_stops) => editPolicy(uid, { follow_stops })} />
        </div>
        <ChoiceField
          label="After a restart"
          hint={account.policy.recovery_preference === "automatic" ? "Buys again once its checks pass." : "Buys wait for your Start copying."}
          value={account.policy.recovery_preference}
          choices={[
            { value: "manual", label: "Wait for me" },
            { value: "automatic", label: "Resume" },
          ]}
          onChange={(recovery_preference) => editPolicy(uid, { recovery_preference })}
        />
        <p className={styles.note}>Only shares CopyTrading bought are ever sold. Your own shares are never touched.</p>
      </fieldset>
      {applyError && (
        <Alert tone="danger" title="Limits not applied">
          {applyError}
        </Alert>
      )}
    </EditorSheet>
  )
}
