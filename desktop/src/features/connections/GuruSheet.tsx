import { useId, useState } from "react"
import { CircleAlertIcon, CircleCheckIcon, SparklesIcon } from "lucide-react"
import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/reui/alert"
import { Button } from "@/components/ui/button"
import { Field, FieldDescription, FieldGroup, FieldLabel, FieldLegend, FieldSet } from "@/components/ui/field"
import { Spinner } from "@/components/ui/spinner"
import { Textarea } from "@/components/ui/textarea"
import { EditorSheet } from "./EditorSheet"
import { SelectField } from "./SelectField"
import { SwitchField } from "./SwitchField"
import { TextField } from "./TextField"
import { DEFAULT_REPEAT_WINDOW_MINUTES, PLAYBOOK_MAX_LENGTH, REPEAT_WINDOW_RANGE, accountChoices, effectiveChannel, policyOf, split } from "./draft"
import { editGuru, isCopying, learnPlaybook, removeGuru, useSetup } from "./setup-store"
import { sizing } from "./sizing"

/** One guru: where they post, how to read their calls, and the account that copies them. */
export function GuruSheet({ uid, onClose }: { uid: string; onClose: () => void }) {
  const s = useSetup()
  const { draft } = s
  const guru = draft.gurus.find((g) => g.uid === uid)
  const playbookId = useId()
  const [confirmsRemove, setConfirmsRemove] = useState(false)
  const [learning, setLearning] = useState(false)
  const [learned, setLearned] = useState<{ ok: boolean; text: string } | null>(null)
  if (!guru) return null
  const locked = isCopying(s)
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
          <Button type="button" variant="ghost" className="text-destructive" disabled={locked} onClick={() => setConfirmsRemove(true)}>
            Remove guru
          </Button>
          <Button type="button" onClick={onClose}>
            Done
          </Button>
        </>
      }
    >
      {confirmsRemove && (
        <Alert variant="warning">
          <CircleAlertIcon aria-hidden />
          <AlertTitle>Remove {guru.display_name.trim() || "this guru"}?</AlertTitle>
          <AlertDescription>Their calls stop being copied once you start copying with this change. Shares they bought stay in the account.</AlertDescription>
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
                removeGuru(uid)
              }}
            >
              Remove guru
            </Button>
          </AlertAction>
        </Alert>
      )}
      <FieldGroup>
        <TextField label="Name" value={guru.display_name} onChange={(display_name) => editGuru(uid, { display_name })} placeholder="How you refer to this guru" disabled={locked} />
        {channelChoices.length ? (
          <SelectField
            label="Discord channel"
            value={channel}
            groups={[{ choices: channelChoices.map((c) => ({ value: c, label: c })) }]}
            onChange={(channel_id) => editGuru(uid, { channel_id })}
            disabled={locked}
          />
        ) : (
          <Field>
            <FieldLabel>Discord channel</FieldLabel>
            <FieldDescription>Add the channel they post in under Discord in Connections first.</FieldDescription>
          </Field>
        )}
        <TextField
          label="Discord user ID"
          hint="Optional. Only needed when others post in the channel."
          value={guru.author_id}
          onChange={(author_id) => editGuru(uid, { author_id })}
          placeholder="Any poster"
          inputMode="numeric"
          disabled={locked}
        />
      </FieldGroup>

      <FieldSet>
        <FieldLegend>Copies into</FieldLegend>
        <FieldGroup>
          {accountList.length ? (
            <SelectField
              label="Account"
              hint="Each account copies one guru."
              value={guru.account_id}
              placeholder="Choose an account"
              groups={[{ choices: accountList.map((a) => ({ value: a, label: a })) }]}
              onChange={(account_id) => editGuru(uid, { account_id })}
              disabled={locked}
            />
          ) : (
            <Field>
              <FieldLabel>Account</FieldLabel>
              <FieldDescription>Every account already copies a guru. Add a broker account in Connections first.</FieldDescription>
            </Field>
          )}
          {guru.account_id && (
            <TextField
              label="Full position"
              hint="The guru's whole position, in dollars. A 1/6 call buys a sixth."
              value={guru.full_position_usd}
              onChange={(full_position_usd) => editGuru(uid, { full_position_usd })}
              placeholder={policy?.max_symbol_usd.trim() || "Required"}
              inputMode="decimal"
              disabled={locked}
            />
          )}
        </FieldGroup>
        {sized ? (
          <dl className="flex flex-col gap-1.5 text-sm" aria-label="What this guru's calls buy">
            {sized.figures.map((figure) => (
              <div key={figure.label} className="flex justify-between gap-4">
                <dt className="text-muted-foreground">{figure.label}</dt>
                <dd className="tabular-nums">
                  {figure.cutFrom && <span className="text-muted-foreground mr-2 text-xs">cut from {figure.cutFrom}</span>}
                  {figure.amount}
                </dd>
              </div>
            ))}
          </dl>
        ) : (
          guru.account_id && <p className="text-muted-foreground text-xs">Set the guru's full position, or this account's max per stock.</p>
        )}
        {(sized?.warning ?? sized?.note) && <p className="text-muted-foreground text-xs">{sized?.warning ?? sized?.note}</p>}
      </FieldSet>

      <FieldSet>
        <FieldLegend>Playbook</FieldLegend>
        <Field>
          <div className="flex items-center justify-between gap-2">
            <FieldLabel htmlFor={playbookId}>How the model should read this guru</FieldLabel>
            <Button type="button" size="xs" variant="outline" disabled={locked || learning} onClick={() => void learn()}>
              {learning ? <Spinner className="size-3" /> : <SparklesIcon aria-hidden />}
              {guru.playbook.trim() ? "Learn again" : "Learn from channel"}
            </Button>
          </div>
          <Textarea id={playbookId} value={guru.playbook} onChange={(event) => editGuru(uid, { playbook: event.target.value })} className="min-h-40" disabled={locked} spellCheck={false} />
          <div className="text-muted-foreground flex justify-between gap-4 text-xs">
            <span>One rule per line, such as “英伟达 means NVDA”.</span>
            <span className={length > PLAYBOOK_MAX_LENGTH ? "text-destructive tabular-nums" : "tabular-nums"}>
              {length.toLocaleString("en-US")} of {PLAYBOOK_MAX_LENGTH.toLocaleString("en-US")} characters
            </span>
          </div>
        </Field>
        {learned && (
          <Alert variant={learned.ok ? "success" : "destructive"}>
            {learned.ok ? <CircleCheckIcon aria-hidden /> : <CircleAlertIcon aria-hidden />}
            <AlertTitle>{learned.ok ? "Playbook drafted" : "Couldn't learn"}</AlertTitle>
            <AlertDescription>{learned.text}</AlertDescription>
          </Alert>
        )}
      </FieldSet>

      <FieldSet>
        <FieldLegend>Re-posted calls</FieldLegend>
        <FieldGroup>
          <SwitchField
            title="Skip re-posted calls"
            hint={guru.repeat_window_minutes === null ? "Every post is copied, even a repeat." : "Same stock, price, and size counts once. A repeated sell counts once a day."}
            checked={guru.repeat_window_minutes !== null}
            onChange={(on) => editGuru(uid, { repeat_window_minutes: on ? (guru.repeat_window_minutes ?? DEFAULT_REPEAT_WINDOW_MINUTES) : null })}
            disabled={locked}
          />
          {guru.repeat_window_minutes !== null && (
            <TextField
              label="Re-post window (minutes)"
              hint={`From ${REPEAT_WINDOW_RANGE[0]} minute to a day (${REPEAT_WINDOW_RANGE[1].toLocaleString("en-US")}).`}
              value={String(guru.repeat_window_minutes)}
              onChange={(value) => {
                const minutes = Number(value)
                // A typed value outside a minute to a day is held to the nearest end.
                if (Number.isFinite(minutes)) editGuru(uid, { repeat_window_minutes: Math.min(Math.max(Math.round(minutes), REPEAT_WINDOW_RANGE[0]), REPEAT_WINDOW_RANGE[1]) })
              }}
              inputMode="numeric"
              disabled={locked}
            />
          )}
        </FieldGroup>
      </FieldSet>
    </EditorSheet>
  )
}
