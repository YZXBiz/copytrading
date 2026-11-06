import { useEffect, useRef, useState } from "react"
import { Add01Icon } from "@/components/icons/Add01Icon"
import { BankIcon } from "@/components/icons/BankIcon"
import { Message01Icon } from "@/components/icons/Message01Icon"
import { SparklesIcon } from "@/components/icons/SparklesIcon"
import { UserGroupIcon } from "@/components/icons/UserGroupIcon"
import { UserIcon } from "@/components/icons/UserIcon"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { ProviderStatus, type ProviderStatusItem } from "@/components/arc/provider-status/provider-status"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import type { Icon } from "@/lib/icon"
import { SectionError } from "@/features/settings/SectionError"
import { providerShortTitle, requiresApiKey } from "../../../shared/providers"
import { AccountSheet } from "./AccountSheet"
import { CheckResults } from "./CheckResults"
import { ConnectionActions } from "./ConnectionActions"
import { DiscordSheet } from "./DiscordSheet"
import { GuruSheet } from "./GuruSheet"
import { InterpreterSheet } from "./InterpreterSheet"
import { derive } from "./derive"
import { split } from "./draft"
import { healthOf } from "./health"
import { addAccount, addGuru, connect, refreshStatus, useSetup } from "./setup-store"
import { type Status, type Subject, accountStatus, accountSubject, discordStatus, draftStatus, guruStatus, interpreterStatus, resultFor } from "./state"
import { connectionProblem } from "./words"
import styles from "./connections.module.css"

type Open = { kind: "discord" } | { kind: "interpreter" } | { kind: "account"; uid: string } | { kind: "guru"; uid: string }

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`

/** Connections: Discord, the interpreter, each broker account and each guru, and the one Start copying. */
export function ConnectionsScreen({ sheet }: { sheet: string | null }) {
  const s = useSetup()
  const derived = derive(s)
  const [open, setOpen] = useState<Open | null>(null)
  const opened = useRef(false)

  // A route such as #/settings/connections/account:0 opens that editor (how capture reaches each sheet).
  useEffect(() => {
    if (opened.current || !derived || !sheet) return
    opened.current = true
    const [kind, index] = sheet.split(":")
    if (kind === "discord" || kind === "interpreter") setOpen({ kind })
    const target = kind === "account" ? s.draft.accounts[Number(index)] : kind === "guru" ? s.draft.gurus[Number(index)] : undefined
    if (target) setOpen({ kind: kind as "account" | "guru", uid: target.uid })
  }, [derived, sheet, s.draft])

  // The engine's reading decides whether the form can change, so keep it fresh while the owner is here.
  useEffect(() => {
    const timer = setInterval(() => void refreshStatus(), 5000)
    return () => clearInterval(timer)
  }, [])

  if (s.load.status === "loading" || (s.load.status === "ready" && !derived)) return <ConnectionsSkeleton />
  if (s.load.status === "error") return <SectionError title="Connections did not load" message={s.load.error} onRetry={s.retry} />
  if (!derived) return null

  const { draft } = s
  const { facts } = derived
  const close = () => setOpen(null)

  const problemOf = (subject: Subject): string | null => {
    const result = resultFor(s.checks, draft, subject)
    if (result?.check && result.check.state === "failed") return result.error ?? connectionProblem(result.check, draft.model)
    return s.notices[subject] ?? null
  }
  const connectProps = (subject: Subject) => {
    const result = resultFor(s.checks, draft, subject)
    const connection = result?.check === null ? "connecting" : result?.check?.state === "ready" ? "connected" : "idle"
    return { onConnect: () => void connect(subject), connectLabel: result ? "Check" : "Connect", connection: connection as "idle" | "connecting" | "connected", problem: problemOf(subject) }
  }

  const channels = split(draft.channels)
  const authors = split(draft.authors)
  const discord: Status =
    discordStatus(facts) ?? (channels.length ? draftStatus(Boolean(draft.discord_token || facts.keys.discord), "Needs a token") : { text: "Not set up", tone: "caution" })
  const model = draft.model.trim()
  const interpreter: Status =
    interpreterStatus(facts) ??
    (model ? draftStatus(!requiresApiKey(draft.provider) || Boolean(draft.provider_api_key) || facts.keys.providerKey, "Needs an API key") : { text: "Not set up", tone: "caution" })

  /** One connection as a status row: its mark, name, state in words, the reason when it failed, and Connect and Edit. */
  const row = (o: { id: string; icon: Icon; label: string; title: string; detail?: string; status: Status; onEdit: () => void; subject?: Subject }): ProviderStatusItem => {
    const check = o.subject ? connectProps(o.subject) : null
    const problem = check?.problem ?? null
    const Mark = o.icon
    return {
      id: o.id,
      name: o.title,
      mark: <Mark width={16} height={16} />,
      detail: o.detail,
      problem,
      status: healthOf(o.status, check?.connection, problem),
      statusLabel: o.status.text,
      actions: <ConnectionActions label={o.label} onEdit={o.onEdit} onConnect={check?.onConnect} connectLabel={check?.connectLabel} connection={check?.connection} />,
    }
  }
  const add = (label: string, make: () => Open) => (
    <Button type="button" size="sm" variant="secondary" onClick={() => setOpen(make())}>
      <Add01Icon width={16} height={16} aria-hidden="true" />
      {label}
    </Button>
  )

  return (
    <div className={styles.page}>
      <ProviderStatus
        title="Services"
        description="Where the calls come from, and the AI that reads them."
        providers={[
          row({
            id: "discord",
            icon: Message01Icon,
            label: "Discord",
            title: "Discord",
            detail: channels.length ? `${plural(channels.length, "channel")}, ${authors.length ? plural(authors.length, "author") : "anyone who posts"}` : undefined,
            status: discord,
            onEdit: () => setOpen({ kind: "discord" }),
            subject: "discord",
          }),
          row({
            id: "interpreter",
            icon: SparklesIcon,
            label: "Interpreter",
            title: model ? providerShortTitle(draft.provider) : "Interpreter",
            detail: model || undefined,
            status: interpreter,
            onEdit: () => setOpen({ kind: "interpreter" }),
            subject: "interpreter",
          }),
        ]}
      />

      <ProviderStatus
        title="Broker accounts"
        description="Where orders go."
        action={add("Add account", () => ({ kind: "account", uid: addAccount() }))}
        empty={<EmptyState title="No broker accounts yet" description="Add an Alpaca paper account to start." icon={<BankIcon width={24} height={24} aria-hidden="true" />} />}
        providers={draft.accounts.map((account) => {
          const name = account.name.trim()
          return row({
            id: account.uid,
            icon: BankIcon,
            label: name || "new account",
            title: name || "New account",
            detail: account.environment === "live" ? "Live" : "Paper",
            status: accountStatus(facts, account),
            onEdit: () => setOpen({ kind: "account", uid: account.uid }),
            subject: accountSubject(name),
          })
        })}
      />

      <ProviderStatus
        title="Gurus"
        description="Each guru is one Discord channel."
        action={add("Add guru", () => ({ kind: "guru", uid: addGuru() }))}
        empty={<EmptyState title="No gurus yet" description="Add one to copy their calls." icon={<UserGroupIcon width={24} height={24} aria-hidden="true" />} />}
        providers={draft.gurus.map((guru) => {
          const channel = guru.channel_id.trim() || channels[0] || ""
          return row({
            id: guru.uid,
            icon: UserIcon,
            label: guru.display_name.trim() || "new guru",
            title: guru.display_name.trim() || "New guru",
            detail: channel && guru.account_id ? `Channel ${channel.length > 10 ? `${channel.slice(0, 4)}…${channel.slice(-4)}` : channel} into ${guru.account_id}` : "Needs a channel and an account",
            status: guruStatus(facts, guru),
            onEdit: () => setOpen({ kind: "guru", uid: guru.uid }),
          })
        })}
      />

      {s.start.phase === "failed" && s.start.report && <CheckResults report={s.start.report} modelName={s.draft.model} />}

      {open?.kind === "discord" && <DiscordSheet onClose={close} />}
      {open?.kind === "interpreter" && <InterpreterSheet onClose={close} />}
      {open?.kind === "account" && <AccountSheet uid={open.uid} onClose={close} />}
      {open?.kind === "guru" && <GuruSheet uid={open.uid} onClose={close} />}
    </div>
  )
}

/** Three sections in the real layout while the setup is read. */
function ConnectionsSkeleton() {
  return (
    <div className={styles.skeletons}>
      <Skeleton label="Loading connections" lines={3} />
    </div>
  )
}
