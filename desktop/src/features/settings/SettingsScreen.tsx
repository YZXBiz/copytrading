import type { ReactNode } from "react"
import type { Icon } from "@/lib/icon"
import { ArchiveIcon } from "@/components/icons/ArchiveIcon"
import { BotIcon } from "@/components/icons/BotIcon"
import { Clock01Icon } from "@/components/icons/Clock01Icon"
import { HistoryIcon } from "@/components/icons/HistoryIcon"
import { Plug01Icon } from "@/components/icons/Plug01Icon"
import { ScrollTextIcon } from "@/components/icons/ScrollTextIcon"
import type { AccountOverviewPage } from "../../../shared/contract"
import { Item, ItemContent, ItemGroup, ItemMedia, ItemTitle } from "@/components/ui/item"
import { href } from "@/features/shell/route"
import type { Loaded } from "@/lib/use-result"
import { ConnectionsScreen } from "@/features/connections/ConnectionsScreen"
import { AgentsPage } from "./AgentsPage"
import { BackupsPage } from "./BackupsPage"
import { GeneralPage } from "./GeneralPage"
import { LogsPage } from "./LogsPage"
import { OldRecordsPage } from "./OldRecordsPage"

type Accounts = Loaded<AccountOverviewPage> & { retry: () => void }

const PAGES: { id: string; title: string; subtitle: string; icon: Icon; render: (accounts: Accounts, sheet: string | null) => ReactNode }[] = [
  { id: "connections", title: "Connections", subtitle: "Each Connect checks its service before anything is saved.", icon: Plug01Icon, render: (_, sheet) => <ConnectionsScreen sheet={sheet} /> },
  { id: "general", title: "General", subtitle: "How times show, and what tells you about trades.", icon: Clock01Icon, render: () => <GeneralPage /> },
  { id: "agents", title: "Agent Access", subtitle: "What agents may do, and what they asked for.", icon: BotIcon, render: () => <AgentsPage /> },
  { id: "backups", title: "Backups", subtitle: "Back up your records, or restore from a backup.", icon: ArchiveIcon, render: () => <BackupsPage /> },
  { id: "logs", title: "Logs", subtitle: "What the engine recorded on this Mac.", icon: ScrollTextIcon, render: () => <LogsPage /> },
  { id: "old-records", title: "Old records", subtitle: "Records of accounts no longer in your setup.", icon: HistoryIcon, render: (accounts) => <OldRecordsPage accounts={accounts} /> },
]

/** Settings: its pages listed on the left, the selected page (the route's second segment) on the right. */
export function SettingsScreen({ page, sheet, accounts }: { page: string | null; sheet: string | null; accounts: Accounts }) {
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
        <header className="mb-5 flex flex-col gap-0.5">
          <h1 className="text-xl font-semibold tracking-tight">{current.title}</h1>
          <p className="text-muted-foreground text-sm">{current.subtitle}</p>
        </header>
        {current.render(accounts, sheet)}
      </div>
    </div>
  )
}
