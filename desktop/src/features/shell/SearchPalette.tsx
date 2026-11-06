import { type ReactNode, useEffect } from "react"
import type { Icon } from "@/lib/icon"
import { BankIcon } from "@/components/icons/BankIcon"
import { File01Icon } from "@/components/icons/File01Icon"
import { MonitorIcon } from "@/components/icons/MonitorIcon"
import { Moon02Icon } from "@/components/icons/Moon02Icon"
import { PauseIcon } from "@/components/icons/PauseIcon"
import { PlayIcon } from "@/components/icons/PlayIcon"
import { Plug01Icon } from "@/components/icons/Plug01Icon"
import { SkipForwardIcon } from "@/components/icons/SkipForwardIcon"
import { SparklesIcon } from "@/components/icons/SparklesIcon"
import { Sun01Icon } from "@/components/icons/Sun01Icon"
import { UserGroupIcon } from "@/components/icons/UserGroupIcon"
import type { AccountOverview, Theme, TradingConfiguration } from "../../../shared/contract"
import { ASSISTANT_EVENT, ASSISTANT_SHORTCUT, shortcutOf } from "../../../shared/shortcuts"
import { CommandPalette, type CommandItem } from "@/components/arc/command-palette/command-palette"
import { Dialog, DialogContent } from "@/components/arc/dialog/dialog"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { useToastStack } from "@/components/arc/toast-stack/toast-stack"
import { sourceKey } from "@/features/account/post-rows"
import { UNDO_MS, skipCalls, unskipCalls, useSkippedCalls } from "@/features/account/skipped-calls"
import { openCall } from "@/features/account/waiting"
import { quoteOf } from "@/features/activity/reading"
import { guruDirectory, guruName } from "@/features/gurus/model"
import { readClock } from "@/lib/clock"
import { ago } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { NAV_SCREEN_IDS, type ScreenId, href, navigate } from "./route"
import { SCREENS } from "./screens"
import styles from "./search-palette.module.css"

interface Props {
  live: AccountOverview[]
  old: AccountOverview[]
  setup: TradingConfiguration | null | undefined
}

const POSTS = 20

const THEME_ACTIONS = [
  { theme: "dark", label: "Dark", icon: Moon02Icon },
  { theme: "light", label: "Light", icon: Sun01Icon },
  { theme: "system", label: "System", icon: MonitorIcon },
] as const satisfies { theme: Theme; label: string; icon: unknown }[]

const SCREEN_ENTRIES: { title: string; icon: Icon; route: [ScreenId, string?] }[] = [
  ...NAV_SCREEN_IDS.map((id) => ({ title: SCREENS[id].title, icon: SCREENS[id].icon, route: [id] as [ScreenId] })),
  { title: "Connections", icon: Plug01Icon, route: ["settings", "connections"] },
]

/** One result: what the palette shows, and what pressing it does. */
type Entry = { item: CommandItem; run: () => void }

const icon = (Glyph: Icon): ReactNode => <Glyph width={16} height={16} aria-hidden="true" />

/** ⌘K opens the search, from anywhere. Pressed again while it is open, it only returns focus to the field. */
export function useSearchShortcut(open: () => void) {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key.toLowerCase() === "k" && (event.metaKey || event.ctrlKey) && !event.defaultPrevented) {
        event.preventDefault()
        open()
      }
    }
    window.addEventListener("keydown", onKeyDown)
    return () => window.removeEventListener("keydown", onKeyDown)
  }, [open])
}

/** The search over screens, accounts, gurus and the latest posts, with the actions the window's buttons have. */
export function SearchPalette({ open, onOpenChange, ...data }: Props & { open: boolean; onOpenChange: (open: boolean) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent title="Search" description="Find a screen, account, guru or post.">
        <SearchResults {...data} close={() => onOpenChange(false)} />
      </DialogContent>
    </Dialog>
  )
}

function SearchResults({ live, old, setup, close }: Props & { close: () => void }) {
  const gurus = guruDirectory(setup)
  // The posts are read each time the search opens, so a post that arrived while it was shut is there. The same read says which calls wait.
  const posts = useResult(() => window.copytrading.read.getSourceActivity(), "search")
  const status = useResult(() => window.copytrading.read.getStatus(), "search-status")
  const skipped = useSkippedCalls()
  const { toast } = useToastStack()
  const now = readClock()
  const waiting = posts.status === "ready" ? posts.data.items.flatMap((post) => openCall(post, { skipped: skipped.has(sourceKey(post)), now }) ?? []) : []
  const state = status.status === "ready" ? status.data.state : null
  const copying = state === "running" || state === "degraded"

  const go = (screen: Parameters<typeof navigate>[0], id?: string) => () => navigate(screen, id)
  const startCopying = () => void window.copytrading.act.startCopying()
  const setTheme = (theme: Theme) => void window.copytrading.act.setTheme({ theme })

  // The confirmations are main's own, the same ones the window's buttons show.
  const entries: Entry[] = []
  if (state !== null && !copying && state !== "pausing" && state !== "starting")
    entries.push({ item: { id: "action:start", group: "Actions", label: "Start Copying", icon: icon(PlayIcon) }, run: startCopying })
  if (state === null || copying) entries.push({ item: { id: "action:pause", group: "Actions", label: "Pause Copying", icon: icon(PauseIcon) }, run: () => void window.copytrading.act.pauseTrading() })
  if (waiting.length > 0)
    entries.push({
      item: { id: "action:skip", group: "Actions", label: "Skip all waiting calls", description: `${waiting.length} waiting`, icon: icon(SkipForwardIcon) },
      run: () => {
        const ids = waiting.map((call) => sourceKey(call.source))
        skipCalls(ids)
        toast({ type: "info", title: ids.length === 1 ? "Call skipped" : `${ids.length} calls skipped`, duration: UNDO_MS, action: { label: "Undo", onClick: () => unskipCalls(ids) } })
      },
    })
  for (const { theme, label, icon: Glyph } of THEME_ACTIONS) entries.push({ item: { id: `action:theme:${theme}`, group: "Actions", label: `${label} theme`, icon: icon(Glyph) }, run: () => setTheme(theme) })

  entries.push({
    item: { id: "screen:assistant", group: "Screens", label: "Assistant", icon: icon(SparklesIcon), shortcut: `⌘${ASSISTANT_SHORTCUT.toUpperCase()}` },
    run: () => window.dispatchEvent(new CustomEvent(ASSISTANT_EVENT)),
  })
  // Getting Started stays here after the sidebar drops it, and Connections is Settings' first page.
  for (const { title, icon: Glyph, route } of SCREEN_ENTRIES) entries.push({ item: { id: `screen:${title}`, group: "Screens", label: title, icon: icon(Glyph), shortcut: shortcutOf(href(...route)) }, run: go(...route) })

  for (const a of [...live, ...old.map((account) => ({ ...account, old: true }))])
    entries.push({ item: { id: `account:${a.account_id}`, group: "Accounts", label: a.account_id, description: "old" in a ? "Old record" : undefined, icon: icon(BankIcon) }, run: go("accounts", a.account_id) })
  for (const g of gurus) entries.push({ item: { id: `guru:${g.id}`, group: "Gurus", label: g.name, icon: icon(UserGroupIcon) }, run: go("gurus", g.id) })
  if (posts.status === "ready")
    for (const post of posts.data.items.slice(0, POSTS)) {
      const guru = guruName(gurus, post.guru_id)
      entries.push({
        item: { id: `post:${post.sequence}`, group: "Recent posts", label: quoteOf(post), description: `${guru} · ${ago(post.source_at, now)}`, keywords: [guru, String(post.sequence)], icon: icon(File01Icon) },
        run: go("activity", String(post.sequence)),
      })
    }

  return (
    <div className={styles.results}>
      <CommandPalette
        items={entries.map((entry) => entry.item)}
        placeholder="Search accounts, gurus and posts"
        autoFocus
        onClose={close}
        onSelect={(item) => {
          close()
          entries.find((entry) => entry.item.id === item.id)?.run()
        }}
      />
      {/* The posts load after the rest, so their state sits under the results rather than inside them. */}
      {posts.status === "loading" && <Skeleton label="Loading posts" lines={2} />}
      {posts.status === "error" && (
        <p className={styles.note}>
          Posts did not load.{" "}
          <button type="button" onClick={posts.retry}>
            Retry
          </button>
        </p>
      )}
    </div>
  )
}
