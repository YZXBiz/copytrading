import { useState } from "react"
import { CircleAlertIcon, LandmarkIcon } from "lucide-react"
import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/reui/alert"
import { Button } from "@/components/ui/button"
import { FieldGroup, FieldLegend, FieldSet } from "@/components/ui/field"
import { Spinner } from "@/components/ui/spinner"
import type { AccountPolicy } from "../../../shared/contract"
import { CheckNotice } from "./CheckNotice"
import { ChoiceField } from "./ChoiceField"
import { EditorSheet } from "./EditorSheet"
import { SwitchField } from "./SwitchField"
import { TextField } from "./TextField"
import { accountNameProblem } from "./draft"
import { applyLimits, connect, editAccount, editPolicy, isCopying, keysOf, removeAccount, useSetup } from "./setup-store"
import { accountSubject, resultFor, same } from "./state"

type Text = { [K in keyof AccountPolicy]: AccountPolicy[K] extends string ? K : never }[keyof AccountPolicy]
type Count = { [K in keyof AccountPolicy]: AccountPolicy[K] extends number ? K : never }[keyof AccountPolicy]

const LIMITS: { key: Text; label: string; hint: string }[] = [
  { key: "max_order_usd", label: "Largest single buy", hint: "The most one buy spends, and what a call with no size buys." },
  { key: "max_symbol_usd", label: "Maximum per stock", hint: "Shares CopyTrading bought. Your own aren't counted." },
  { key: "max_total_usd", label: "Maximum total exposure", hint: "Every stock CopyTrading bought. Your own aren't counted." },
  { key: "daily_loss_cap_usd", label: "Daily loss cap", hint: "Stops buying for the day. Still sells." },
  { key: "max_above_signal_pct", label: "Maximum above signal price (%)", hint: "0 means never more than the guru paid." },
  { key: "max_below_signal_pct", label: "Lowest sell price (% under the guru's)", hint: "A sell waits at this price or better until it fills." },
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
      icon={LandmarkIcon}
      title={name || "New account"}
      description={account.environment === "live" ? "Live: real orders, real money" : "Paper: pretend money, real prices"}
      onClose={onClose}
      footer={
        <>
          <Button type="button" variant="ghost" className="text-destructive" onClick={() => setConfirmsRemove(true)}>
            Remove account
          </Button>
          <div className="flex gap-2">
            {copying && (
              <Button type="button" variant="outline" disabled={applying || !savedPolicy || same(savedPolicy, account.policy)} onClick={() => void apply()}>
                {applying && <Spinner />}
                Apply limits now
              </Button>
            )}
            <Button type="button" variant="outline" disabled={result?.check === null} onClick={() => void connect(subject)}>
              {result?.check === null && <Spinner />}
              Connect
            </Button>
            <Button type="button" onClick={onClose}>
              Done
            </Button>
          </div>
        </>
      }
    >
      {confirmsRemove && (
        <Alert variant="warning">
          <CircleAlertIcon aria-hidden />
          <AlertTitle>Remove {name || "this account"}?</AlertTitle>
          <AlertDescription>Its guru stops being copied once you start copying with this change. Shares in it stay with Alpaca.</AlertDescription>
          <AlertAction>
            <Button type="button" size="xs" variant="outline" onClick={() => setConfirmsRemove(false)}>
              Keep
            </Button>
            <Button
              type="button"
              size="xs"
              variant="destructive"
              onClick={() => {
                onClose()
                removeAccount(uid)
              }}
            >
              Remove account
            </Button>
          </AlertAction>
        </Alert>
      )}
      {copying && (
        <Alert variant="info">
          <CircleAlertIcon aria-hidden />
          <AlertTitle>Copying is running</AlertTitle>
          <AlertDescription>Apply limits now changes only this account’s limits, from the next order. Any other change is applied from the start bar, which restarts copying for a few seconds.</AlertDescription>
        </Alert>
      )}
      <FieldGroup>
        <TextField
          label="Name"
          hint="Letters, digits, “-” and “_”."
          error={nameProblem}
          value={account.name}
          onChange={(value) => editAccount(uid, (a) => ({ ...a, name: value }))}
          placeholder="e.g. primary"
        />
        <ChoiceField
          label="Environment"
          value={account.environment}
          choices={[
            { value: "paper", label: "Paper" },
            { value: "live", label: "Live" },
          ]}
          onChange={(environment) => editAccount(uid, (a) => ({ ...a, environment }))}
        />
        {account.environment === "live" && (
          <Alert variant="warning">
            <CircleAlertIcon aria-hidden />
            <AlertTitle>Live accounts place real orders with real money.</AlertTitle>
          </Alert>
        )}
      </FieldGroup>

      <FieldSet>
        <FieldLegend>Alpaca keys</FieldLegend>
        <FieldGroup>
          <TextField
            label="API key"
            hint={savedKeys ? "Kept encrypted on this Mac. Leave blank to keep the saved keys." : "Kept encrypted on this Mac, never in the setup file."}
            value={account.key}
            onChange={(key) => editAccount(uid, (a) => ({ ...a, key }))}
            type="password"
            placeholder={savedKeys ? "Saved" : "Required"}          />
          <TextField
            label="API secret"
            value={account.secret}
            onChange={(secret) => editAccount(uid, (a) => ({ ...a, secret }))}
            type="password"
            placeholder={savedKeys ? "Saved" : "Required"}          />
        </FieldGroup>
        <CheckNotice subject={subject} result={result} notice={s.notices[subject]} />
      </FieldSet>

      <FieldSet>
        <FieldLegend>Position limits (USD)</FieldLegend>
        <FieldGroup>
          {LIMITS.map(({ key, label, hint }) => (
            <TextField key={key} label={label} hint={hint} value={account.policy[key]} onChange={(value) => editPolicy(uid, { [key]: value })} inputMode="decimal" />
          ))}
        </FieldGroup>
      </FieldSet>

      <FieldSet>
        <FieldLegend>Timing</FieldLegend>
        <FieldGroup>
          {TIMING.map(({ key, label, hint }) => (
            <TextField
              key={key}
              label={label}
              hint={hint}
              value={String(account.policy[key])}
              onChange={(value) => Number.isFinite(Number(value)) && editPolicy(uid, { [key]: Number(value) })}
              inputMode="numeric"
            />
          ))}
        </FieldGroup>
      </FieldSet>

      <FieldSet>
        <FieldLegend>Behavior</FieldLegend>
        <FieldGroup>
          <SwitchField
            title="Trade in extended hours"
            hint="4:00–9:30 AM and 4:00–8:00 PM New York time, with limit orders."
            checked={account.policy.extended_hours}
            // Overnight runs only with extended hours, so turning those off ends it too.
            onChange={(on) => editPolicy(uid, on ? { extended_hours: true } : { extended_hours: false, overnight: false })}
          />
          <SwitchField
            title="Trade overnight"
            hint="8:00 PM–4:00 AM New York time. Needs extended hours."
            checked={account.policy.overnight}
            onChange={(on) => editPolicy(uid, on ? { overnight: true, extended_hours: true } : { overnight: false })}
          />
          <SwitchField
            title="Copy exits"
            hint="Off means you sell copied shares yourself."
            checked={account.policy.copy_exits}
            onChange={(copy_exits) => editPolicy(uid, { copy_exits })}
          />
          <SwitchField
            title="Ask me before sending orders"
            hint="No order goes out by itself: each waits for you to approve it from its post in Activity."
            checked={account.policy.approve_orders}
            onChange={(approve_orders) => editPolicy(uid, { approve_orders })}
          />
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
        </FieldGroup>
        <p className="text-muted-foreground text-xs">Only shares CopyTrading bought are ever sold. Your own shares are never touched.</p>
      </FieldSet>
      {applyError && (
        <Alert variant="destructive">
          <CircleAlertIcon aria-hidden />
          <AlertTitle>Limits not applied</AlertTitle>
          <AlertDescription>{applyError}</AlertDescription>
        </Alert>
      )}
    </EditorSheet>
  )
}
