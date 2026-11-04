import { useEffect, useRef, useState } from "react"
import { LandmarkIcon, MessageSquareIcon, PlusIcon, SparklesIcon, UserIcon, UsersIcon } from "lucide-react"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { ItemGroup } from "@/components/ui/item"
import { Skeleton } from "@/components/ui/skeleton"
import { providerShortTitle, requiresApiKey } from "../../../shared/providers"
import { AccountSheet } from "./AccountSheet"
import { ConnectionRow } from "./ConnectionRow"
import { DiscordSheet } from "./DiscordSheet"
import { GuruSheet } from "./GuruSheet"
import { InterpreterSheet } from "./InterpreterSheet"
import { StartBar } from "./StartBar"
import { derive } from "./derive"
import { split } from "./draft"
import { addAccount, addGuru, connect, refreshStatus, useSetup } from "./setup-store"
import { type Status, type Subject, accountStatus, accountSubject, discordStatus, draftStatus, guruStatus, interpreterStatus, resultFor } from "./state"
import { connectionProblem } from "./words"

type Open = { kind: "discord" } | { kind: "interpreter" } | { kind: "account"; uid: string } | { kind: "guru"; uid: string }

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`

/** Connections: Discord, the interpreter, each broker account and each guru, and the one Start copying. */
export function ConnectionsScreen({ routeId }: { routeId: string | null }) {
  const s = useSetup()
  const derived = derive(s)
  const [open, setOpen] = useState<Open | null>(null)
  const opened = useRef(false)

  // A route such as #/connections/account:0 opens that editor (how capture reaches each sheet).
  useEffect(() => {
    if (opened.current || !derived || !routeId) return
    opened.current = true
    const [kind, index] = routeId.split(":")
    if (kind === "discord" || kind === "interpreter") setOpen({ kind })
    const target = kind === "account" ? s.draft.accounts[Number(index)] : kind === "guru" ? s.draft.gurus[Number(index)] : undefined
    if (target) setOpen({ kind: kind as "account" | "guru", uid: target.uid })
  }, [derived, routeId, s.draft])

  // The engine's reading decides whether the form can change, so keep it fresh while the owner is here.
  useEffect(() => {
    const timer = setInterval(() => void refreshStatus(), 5000)
    return () => clearInterval(timer)
  }, [])

  if (s.load.status === "loading" || (s.load.status === "ready" && !derived)) return <ConnectionsSkeleton />
  if (s.load.status === "error") return <RegionError title="Connections did not load" message={s.load.error} onRetry={s.retry} />
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
    return { onConnect: () => void connect(subject), connectLabel: result ? "Check" : "Connect", checking: result?.check === null, problem: problemOf(subject) }
  }

  const channels = split(draft.channels)
  const authors = split(draft.authors)
  const discord: Status =
    discordStatus(facts) ?? (channels.length ? draftStatus(Boolean(draft.discord_token || facts.keys.discord), "Needs a token") : { text: "Not set up", tone: "caution" })
  const model = draft.model.trim()
  const interpreter: Status =
    interpreterStatus(facts) ??
    (model ? draftStatus(!requiresApiKey(draft.provider) || Boolean(draft.provider_api_key) || facts.keys.providerKey, "Needs an API key") : { text: "Not set up", tone: "caution" })

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-8">
      <header className="flex flex-col gap-1">
        <h1 className="text-xl font-semibold tracking-tight">Connections</h1>
        <p className="text-muted-foreground text-sm">Where posts come from, the AI model that reads them, and the broker account that copies them.</p>
      </header>

      <section aria-labelledby="services" className="flex flex-col gap-3">
        <h2 id="services" className="text-sm font-medium">
          Services
        </h2>
        <ItemGroup>
          <ConnectionRow
            icon={MessageSquareIcon}
            label="Discord"
            title="Discord"
            detail={channels.length ? `${plural(channels.length, "channel")}, ${authors.length ? plural(authors.length, "author") : "anyone who posts"}` : "Where your gurus post their calls"}
            status={discord}
            onEdit={() => setOpen({ kind: "discord" })}
            {...connectProps("discord")}
          />
          <ConnectionRow
            icon={SparklesIcon}
            label="Interpreter"
            title={model ? providerShortTitle(draft.provider) : "Interpreter"}
            detail={model || "The AI model that reads each post"}
            status={interpreter}
            onEdit={() => setOpen({ kind: "interpreter" })}
            {...connectProps("interpreter")}
          />
        </ItemGroup>
      </section>

      <section aria-labelledby="accounts" className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 id="accounts" className="text-sm font-medium">
            Broker accounts
          </h2>
          <Button type="button" size="xs" variant="outline" disabled={derived.copying} onClick={() => setOpen({ kind: "account", uid: addAccount() })}>
            <PlusIcon aria-hidden /> Add account
          </Button>
        </div>
        {draft.accounts.length ? (
          <ItemGroup>
            {draft.accounts.map((account) => {
              const name = account.name.trim()
              const subject = accountSubject(name)
              const guru = draft.gurus.find((g) => g.account_id.trim() === name)
              return (
                <ConnectionRow
                  key={account.uid}
                  icon={LandmarkIcon}
                  label={name || "new account"}
                  title={name || "New account"}
                  detail={`${account.environment === "live" ? "Live" : "Paper"}${guru?.display_name.trim() ? ` · copies ${guru.display_name.trim()}` : ""}`}
                  status={accountStatus(facts, account)}
                  onEdit={() => setOpen({ kind: "account", uid: account.uid })}
                  {...connectProps(subject)}
                />
              )
            })}
          </ItemGroup>
        ) : (
          <EmptyRegion icon={LandmarkIcon} title="No broker accounts yet" description="Add an Alpaca paper account to start: it trades pretend money at real prices." />
        )}
      </section>

      <section aria-labelledby="gurus" className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 id="gurus" className="text-sm font-medium">
            Gurus
          </h2>
          <Button type="button" size="xs" variant="outline" disabled={derived.copying} onClick={() => setOpen({ kind: "guru", uid: addGuru() })}>
            <PlusIcon aria-hidden /> Add guru
          </Button>
        </div>
        {draft.gurus.length ? (
          <ItemGroup>
            {draft.gurus.map((guru) => {
              const channel = guru.channel_id.trim() || channels[0] || ""
              return (
                <ConnectionRow
                  key={guru.uid}
                  icon={UserIcon}
                  label={guru.display_name.trim() || "new guru"}
                  title={guru.display_name.trim() || "New guru"}
                  detail={channel && guru.account_id ? `Channel ${channel.length > 10 ? `${channel.slice(0, 4)}…${channel.slice(-4)}` : channel} into ${guru.account_id}` : "Needs a channel and an account"}
                  status={guruStatus(facts, guru)}
                  onEdit={() => setOpen({ kind: "guru", uid: guru.uid })}
                />
              )
            })}
          </ItemGroup>
        ) : (
          <EmptyRegion icon={UsersIcon} title="No gurus yet" description="Each guru is one Discord channel, copied into one account." />
        )}
      </section>

      <StartBar s={s} derived={derived} />

      {open?.kind === "discord" && <DiscordSheet onClose={close} />}
      {open?.kind === "interpreter" && <InterpreterSheet onClose={close} />}
      {open?.kind === "account" && <AccountSheet uid={open.uid} onClose={close} />}
      {open?.kind === "guru" && <GuruSheet uid={open.uid} onClose={close} />}
    </div>
  )
}

function EmptyRegion({ icon: Icon, title, description }: { icon: typeof UsersIcon; title: string; description: string }) {
  return (
    <Empty className="border border-dashed py-8">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <Icon />
        </EmptyMedia>
        <EmptyTitle>{title}</EmptyTitle>
        <EmptyDescription>{description}</EmptyDescription>
      </EmptyHeader>
    </Empty>
  )
}

function ConnectionsSkeleton() {
  return (
    <div role="status" aria-label="Loading connections" className="mx-auto flex w-full max-w-2xl flex-col gap-8">
      <Skeleton className="h-12 w-64" />
      {[2, 1, 1].map((rows, i) => (
        <div key={i} className="flex flex-col gap-3">
          <Skeleton className="h-4 w-32" />
          {Array.from({ length: rows }, (_, j) => (
            <Skeleton key={j} className="h-14 w-full" />
          ))}
        </div>
      ))}
    </div>
  )
}
