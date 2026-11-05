import { Children, Fragment, type ReactNode, useEffect, useRef, useState } from "react"
import { LandmarkIcon, MessageSquareIcon, PlusIcon, SparklesIcon, UserIcon, UsersIcon } from "lucide-react"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { ItemGroup, ItemSeparator } from "@/components/ui/item"
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
    <div className="flex w-full flex-col gap-5">
      <Section id="services" title="Services" description="Where the calls come from, and the AI that reads them.">
        <Rows title="Services">
          <ConnectionRow
            icon={MessageSquareIcon}
            label="Discord"
            title="Discord"
            detail={channels.length ? `${plural(channels.length, "channel")}, ${authors.length ? plural(authors.length, "author") : "anyone who posts"}` : undefined}
            status={discord}
            onEdit={() => setOpen({ kind: "discord" })}
            {...connectProps("discord")}
          />
          <ConnectionRow
            icon={SparklesIcon}
            label="Interpreter"
            title={model ? providerShortTitle(draft.provider) : "Interpreter"}
            detail={model || undefined}
            status={interpreter}
            onEdit={() => setOpen({ kind: "interpreter" })}
            {...connectProps("interpreter")}
          />
        </Rows>
      </Section>

      <Section
        id="accounts"
        title="Broker accounts"
        description="Where orders go."
        action={
          <Button type="button" size="sm" variant="outline" onClick={() => setOpen({ kind: "account", uid: addAccount() })}>
            <PlusIcon aria-hidden /> Add account
          </Button>
        }
      >
        {draft.accounts.length ? (
          <Rows title="Broker accounts">
            {draft.accounts.map((account) => {
              const name = account.name.trim()
              const subject = accountSubject(name)
              return (
                <ConnectionRow
                  key={account.uid}
                  icon={LandmarkIcon}
                  label={name || "new account"}
                  title={name || "New account"}
                  detail={account.environment === "live" ? "Live" : "Paper"}
                  status={accountStatus(facts, account)}
                  onEdit={() => setOpen({ kind: "account", uid: account.uid })}
                  {...connectProps(subject)}
                />
              )
            })}
          </Rows>
        ) : (
          <EmptyRegion icon={LandmarkIcon} title="No broker accounts yet" description="Add an Alpaca paper account to start." />
        )}
      </Section>

      <Section
        id="gurus"
        title="Gurus"
        description="Each guru is one Discord channel."
        action={
          <Button type="button" size="sm" variant="outline" onClick={() => setOpen({ kind: "guru", uid: addGuru() })}>
            <PlusIcon aria-hidden /> Add guru
          </Button>
        }
      >
        {draft.gurus.length ? (
          <Rows title="Gurus">
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
          </Rows>
        ) : (
          <EmptyRegion icon={UsersIcon} title="No gurus yet" description="Add one to copy their calls." />
        )}
      </Section>

      <StartBar s={s} derived={derived} />

      {open?.kind === "discord" && <DiscordSheet onClose={close} />}
      {open?.kind === "interpreter" && <InterpreterSheet onClose={close} />}
      {open?.kind === "account" && <AccountSheet uid={open.uid} onClose={close} />}
      {open?.kind === "guru" && <GuruSheet uid={open.uid} onClose={close} />}
    </div>
  )
}

/** A section's heading: the title with a line under it and, when the section can grow, its Add button at the right (settings-16). */
function Section({ id, title, description, action, children }: { id: string; title: string; description: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section aria-labelledby={id} className="flex flex-col gap-3">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div className="flex min-w-0 flex-col gap-1">
          <h2 id={id} className="text-sm font-semibold">
            {title}
          </h2>
          <p className="text-muted-foreground text-sm">{description}</p>
        </div>
        {action}
      </div>
      {children}
    </section>
  )
}

/** One section's connections in a single Frame, a hairline between rows (settings-16's Frame, with its title kept for screen readers). */
function Rows({ title, children }: { title: string; children: ReactNode }) {
  const rows = Children.toArray(children)
  return (
    <Frame>
      <FrameHeader className="sr-only">
        <FrameTitle>{title}</FrameTitle>
        <FrameDescription>Status and actions for each connection.</FrameDescription>
      </FrameHeader>
      <FramePanel className="p-0!">
        <ItemGroup className="gap-0">
          {rows.map((row, index) => (
            <Fragment key={index}>
              {index > 0 && <ItemSeparator className="my-0" />}
              {row}
            </Fragment>
          ))}
        </ItemGroup>
      </FramePanel>
    </Frame>
  )
}

function EmptyRegion({ icon: Icon, title, description }: { icon: typeof UsersIcon; title: string; description: string }) {
  return (
    <Frame>
      <FramePanel>
        <Empty className="py-6">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <Icon />
            </EmptyMedia>
            <EmptyTitle>{title}</EmptyTitle>
            <EmptyDescription>{description}</EmptyDescription>
          </EmptyHeader>
        </Empty>
      </FramePanel>
    </Frame>
  )
}

/** Three sections of rows in the real layout while the setup is read. */
function ConnectionsSkeleton() {
  return (
    <div role="status" aria-label="Loading connections" className="flex w-full flex-col gap-5">
      {[2, 1, 1].map((rows, i) => (
        <div key={i} className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Skeleton className="h-4 w-32" />
            <Skeleton className="h-4 w-56" />
          </div>
          <Frame>
            <FramePanel className="flex flex-col gap-3 p-4!">
              {Array.from({ length: rows }, (_, j) => (
                <div key={j} className="flex items-center gap-3">
                  <Skeleton className="size-10 rounded-md" />
                  <div className="flex flex-1 flex-col gap-1.5">
                    <Skeleton className="h-4 w-40" />
                    <Skeleton className="h-3.5 w-28" />
                  </div>
                  <Skeleton className="h-8 w-20" />
                </div>
              ))}
            </FramePanel>
          </Frame>
        </div>
      ))}
    </div>
  )
}
