import type { ReactNode } from "react"
import { ArchiveIcon, BotIcon, ClockIcon, ScrollTextIcon, type LucideIcon } from "lucide-react"
import type { AccountOverviewPage } from "../../../shared/contract"
import { Item, ItemContent, ItemGroup, ItemMedia, ItemTitle } from "@/components/ui/item"
import { href } from "@/features/shell/route"
import type { Loaded } from "@/lib/use-result"
import { AgentsPage } from "./AgentsPage"
import { BackupsPage } from "./BackupsPage"
import { GeneralPage } from "./GeneralPage"
import { LogsPage } from "./LogsPage"

type Accounts = Loaded<AccountOverviewPage> & { retry: () => void }

const PAGES: { id: string; title: string; icon: LucideIcon; render: (accounts: Accounts) => ReactNode }[] = [
  { id: "general", title: "General", icon: ClockIcon, render: () => <GeneralPage /> },
  { id: "agents", title: "Agent Access", icon: BotIcon, render: () => <AgentsPage /> },
  { id: "backups", title: "Backups", icon: ArchiveIcon, render: (accounts) => <BackupsPage accounts={accounts} /> },
  { id: "logs", title: "Logs", icon: ScrollTextIcon, render: () => <LogsPage /> },
]

/** Settings: its pages listed on the left, the selected page (the route's second segment) on the right. */
export function SettingsScreen({ page, accounts }: { page: string | null; accounts: Accounts }) {
  const current = PAGES.find((p) => p.id === page) ?? PAGES[0]!
  return (
    <div className="mx-auto grid max-w-5xl grid-cols-[12rem_minmax(0,1fr)] items-start gap-8">
      <nav aria-label="Settings pages">
        <ItemGroup className="gap-0.5">
          {PAGES.map(({ id, title, icon: Icon }) => (
            <Item key={id} size="xs" render={<a href={href("settings", id)} aria-current={id === current.id ? "page" : undefined} />} className={id === current.id ? "bg-muted" : undefined}>
              <ItemMedia variant="icon">
                <Icon aria-hidden />
              </ItemMedia>
              <ItemContent>
                <ItemTitle>{title}</ItemTitle>
              </ItemContent>
            </Item>
          ))}
        </ItemGroup>
      </nav>
      <div key={current.id} className="min-w-0">
        <h1 className="mb-4 text-lg font-semibold tracking-tight">{current.title}</h1>
        {current.render(accounts)}
      </div>
    </div>
  )
}
