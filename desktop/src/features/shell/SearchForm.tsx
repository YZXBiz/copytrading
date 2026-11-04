import { useEffect, useState } from "react"
import { FileTextIcon, LandmarkIcon, SearchIcon, UsersIcon } from "lucide-react"
import type { AccountOverview, TradingConfiguration } from "../../../shared/contract"
import { Button } from "@/components/ui/button"
import { Command, CommandDialog, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList, CommandShortcut } from "@/components/ui/command"
import { Kbd } from "@/components/ui/kbd"
import { SidebarGroup, SidebarGroupContent } from "@/components/ui/sidebar"
import { Skeleton } from "@/components/ui/skeleton"
import { quoteOf } from "@/features/activity/PostListItem"
import { guruDirectory, guruName } from "@/features/gurus/model"
import { readClock } from "@/lib/clock"
import { ago } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { SCREEN_IDS, navigate } from "./route"
import { SCREENS } from "./screens"

interface Props {
  live: AccountOverview[]
  old: AccountOverview[]
  setup: TradingConfiguration | null | undefined
}

const POSTS = 20

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
  // The newest posts are read each time the dialog opens, so a post that arrived while it was shut is there.
  const posts = useResult(async () => (open ? window.copytrading.read.getSourceActivity({ limit: POSTS }) : { ok: true as const, value: { items: [] } }), `search:${open}`)
  const now = readClock()
  const go = (screen: Parameters<typeof navigate>[0], id?: string) => () => {
    close()
    navigate(screen, id)
  }

  return (
    <Command>
      <CommandInput placeholder="Search accounts, gurus, posts..." />
      <CommandList>
        <CommandEmpty>Nothing matches.</CommandEmpty>
        <CommandGroup heading="Screens">
          {SCREEN_IDS.filter((id) => id !== "accounts").map((id) => {
            const { title, icon: Icon } = SCREENS[id]
            return (
              <CommandItem key={id} value={`screen ${title}`} onSelect={go(id)}>
                <Icon aria-hidden="true" />
                {title}
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
            posts.data.items.map((post) => (
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
