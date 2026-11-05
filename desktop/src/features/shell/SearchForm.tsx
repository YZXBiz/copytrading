import { useEffect, useState } from "react"
import { FileTextIcon, LandmarkIcon, MonitorIcon, MoonIcon, PauseIcon, PlayIcon, PlugIcon, SearchIcon, SparklesIcon, SkipForwardIcon, SunIcon, UsersIcon, type LucideIcon } from "lucide-react"
import type { AccountOverview, Theme, TradingConfiguration } from "../../../shared/contract"
import { ASSISTANT_EVENT, ASSISTANT_SHORTCUT, shortcutOf } from "../../../shared/shortcuts"
import { Button } from "@/components/ui/button"
import { Command, CommandDialog, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList, CommandShortcut } from "@/components/ui/command"
import { Kbd } from "@/components/ui/kbd"
import { SidebarGroup, SidebarGroupContent } from "@/components/ui/sidebar"
import { Skeleton } from "@/components/ui/skeleton"
import { skipCalls, useSkippedCalls } from "@/features/account/skipped-calls"
import { openCall } from "@/features/account/waiting"
import { quoteOf, readableText } from "@/features/activity/reading"
import { guruDirectory, guruName } from "@/features/gurus/model"
import { readClock } from "@/lib/clock"
import { ago } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { SCREEN_IDS, type ScreenId, href, navigate } from "./route"
import { SCREENS } from "./screens"

interface Props {
  live: AccountOverview[]
  old: AccountOverview[]
  setup: TradingConfiguration | null | undefined
}

const POSTS = 20

const THEME_ACTIONS = [
  { theme: "dark", label: "Dark", icon: MoonIcon },
  { theme: "light", label: "Light", icon: SunIcon },
  { theme: "system", label: "System", icon: MonitorIcon },
] as const satisfies { theme: Theme; label: string; icon: unknown }[]

const SCREEN_ENTRIES: { title: string; icon: LucideIcon; route: [ScreenId, string?] }[] = [
  ...SCREEN_IDS.map((id) => ({ title: SCREENS[id].title, icon: SCREENS[id].icon, route: [id] as [ScreenId] })),
  { title: "Connections", icon: PlugIcon, route: ["settings", "connections"] },
]

/** app-shell-2's search: a button in the sidebar and ⌘K open a dialog. It finds screens, accounts, gurus and the latest posts. */
export function SearchForm({ live, old, setup }: Props) {
  const [open, setOpen] = useState(false)

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key.toLowerCase() === "k" && (event.metaKey || event.ctrlKey)) {
        event.preventDefault()
        setOpen((was) => !was)
      }
    }
    window.addEventListener("keydown", onKeyDown)
    return () => window.removeEventListener("keydown", onKeyDown)
  }, [])

  return (
    <form onSubmit={(event) => event.preventDefault()}>
      <SidebarGroup className="py-0">
        <SidebarGroupContent className="relative">
          <Button
            size="sm"
            id="search"
            type="button"
            variant="outline"
            className="hover:bg-background h-8 w-full justify-start pl-7 font-normal transition-[width] duration-200 ease-linear in-data-[state=collapsed]:w-8! in-data-[state=collapsed]:pl-4! in-data-[state=collapsed]:text-transparent"
            onClick={() => setOpen(true)}
          >
            Search...
          </Button>
          <SearchIcon aria-hidden="true" className="pointer-events-none absolute top-1/2 left-2 size-3.5 -translate-y-1/2 opacity-50 select-none" />
          <Kbd className="absolute top-1/2 right-2 -translate-y-1/2 in-data-[state=collapsed]:hidden">⌘K</Kbd>
        </SidebarGroupContent>
      </SidebarGroup>
      <CommandDialog open={open} onOpenChange={setOpen} title="Search" description="Find a screen, account, guru or post." className="max-w-md">
        <SearchResults open={open} live={live} old={old} setup={setup} close={() => setOpen(false)} />
      </CommandDialog>
    </form>
  )
}

function SearchResults({ open, live, old, setup, close }: Props & { open: boolean; close: () => void }) {
  const gurus = guruDirectory(setup)
  // The posts are read each time the dialog opens, so a post that arrived while it was shut is there. The same read says which calls wait.
  const posts = useResult(async () => (open ? window.copytrading.read.getSourceActivity() : { ok: true as const, value: { items: [] } }), `search:${open}`)
  const status = useResult(async () => (open ? window.copytrading.read.getStatus() : { ok: false as const, error: "closed" }), `search-status:${open}`)
  const skipped = useSkippedCalls()
  const now = readClock()
  const waiting = posts.status === "ready" ? posts.data.items.flatMap((post) => openCall(post, { skipped: skipped.has(post.source_id ?? String(post.sequence)), now }) ?? []) : []
  const state = status.status === "ready" ? status.data.state : null
  const copying = state === "running" || state === "degraded"
  const go = (screen: Parameters<typeof navigate>[0], id?: string) => () => {
    close()
    navigate(screen, id)
  }

  /** Runs an action: the confirmations are main's own, the same ones the window's buttons show. */
  const act = (run: () => void) => () => {
    close()
    run()
  }
  const startCopying = () => void window.copytrading.act.startCopying()
  const setTheme = (theme: Theme) => void window.copytrading.act.setTheme({ theme })

  return (
    <Command>
      <CommandInput placeholder="Search accounts, gurus, posts..." />
      <CommandList>
        <CommandEmpty>Nothing matches.</CommandEmpty>
        <CommandGroup heading="Actions">
          {state !== null && !copying && state !== "pausing" && state !== "starting" ? (
            <CommandItem value="action Start Copying" onSelect={act(startCopying)}>
              <PlayIcon aria-hidden="true" />
              Start Copying
            </CommandItem>
          ) : null}
          {state === null || copying ? (
            <CommandItem value="action Pause Copying" onSelect={act(() => void window.copytrading.act.pauseTrading())}>
              <PauseIcon aria-hidden="true" />
              Pause Copying
            </CommandItem>
          ) : null}
          {waiting.length > 0 && (
            <CommandItem
              value="action Skip all waiting calls"
              onSelect={act(() => skipCalls(waiting.map((call) => ({ sourceId: call.source.source_id ?? String(call.source.sequence), text: readableText(call.source) }))))}
            >
              <SkipForwardIcon aria-hidden="true" />
              Skip all waiting calls
              <CommandShortcut className="tracking-normal tabular-nums">{waiting.length}</CommandShortcut>
            </CommandItem>
          )}
          {THEME_ACTIONS.map(({ theme, label, icon: Icon }) => (
            <CommandItem key={theme} value={`action theme ${label}`} onSelect={act(() => setTheme(theme))}>
              <Icon aria-hidden="true" />
              {label} theme
            </CommandItem>
          ))}
        </CommandGroup>
        <CommandGroup heading="Screens">
          <CommandItem value="screen Assistant" onSelect={act(() => window.dispatchEvent(new CustomEvent(ASSISTANT_EVENT)))}>
            <SparklesIcon aria-hidden="true" />
            Assistant
            <CommandShortcut className="tracking-normal">⌘{ASSISTANT_SHORTCUT.toUpperCase()}</CommandShortcut>
          </CommandItem>
          {/* Getting Started stays here after the sidebar drops it, and Connections is Settings' first page. */}
          {SCREEN_ENTRIES.map(({ title, icon: Icon, route }) => {
            const keys = shortcutOf(href(...route))
            return (
              <CommandItem key={title} value={`screen ${title}`} onSelect={go(...route)}>
                <Icon aria-hidden="true" />
                {title}
                {keys && <CommandShortcut className="tracking-normal">{keys}</CommandShortcut>}
              </CommandItem>
            )
          })}
        </CommandGroup>
        {live.length + old.length > 0 && (
          <CommandGroup heading="Accounts">
            {[...live, ...old.map((a) => ({ ...a, old: true }))].map((a) => (
              <CommandItem key={a.account_id} value={`account ${a.account_id}`} onSelect={go("accounts", a.account_id)}>
                <LandmarkIcon aria-hidden="true" />
                {a.account_id}
                {"old" in a && <CommandShortcut className="tracking-normal">Old record</CommandShortcut>}
              </CommandItem>
            ))}
          </CommandGroup>
        )}
        {gurus.length > 0 && (
          <CommandGroup heading="Gurus">
            {gurus.map((g) => (
              <CommandItem key={g.id} value={`guru ${g.name}`} onSelect={go("gurus", g.id)}>
                <UsersIcon aria-hidden="true" />
                {g.name}
              </CommandItem>
            ))}
          </CommandGroup>
        )}
        <CommandGroup heading="Recent posts">
          {posts.status === "loading" ? (
            <div role="status" aria-label="Loading posts" className="flex flex-col gap-2 p-2">
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-2/3" />
            </div>
          ) : posts.status === "error" ? (
            <div className="text-muted-foreground flex items-center gap-1 px-2 py-1.5 text-sm">
              <span className="min-w-0 truncate">Posts did not load.</span>
              <Button type="button" variant="link" size="xs" onClick={posts.retry}>
                Retry
              </Button>
            </div>
          ) : (
            posts.data.items.slice(0, POSTS).map((post) => (
              <CommandItem key={post.sequence} value={`post ${post.sequence} ${guruName(gurus, post.guru_id)} ${quoteOf(post)}`} onSelect={go("activity", String(post.sequence))}>
                <FileTextIcon aria-hidden="true" />
                <span className="min-w-0 flex-1 truncate">{quoteOf(post)}</span>
                <CommandShortcut className="tracking-normal tabular-nums">
                  {guruName(gurus, post.guru_id)} · {ago(post.source_at, now)}
                </CommandShortcut>
              </CommandItem>
            ))
          )}
        </CommandGroup>
      </CommandList>
    </Command>
  )
}
