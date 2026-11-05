import type { ReactNode } from "react"
import { ArchiveIcon } from "@/components/icons/ArchiveIcon"
import { BotIcon } from "@/components/icons/BotIcon"
import { Clock01Icon } from "@/components/icons/Clock01Icon"
import { HistoryIcon } from "@/components/icons/HistoryIcon"
import { Plug01Icon } from "@/components/icons/Plug01Icon"
import { ScrollTextIcon } from "@/components/icons/ScrollTextIcon"
import type { AccountOverviewPage } from "../../../shared/contract"
import { SettingsFrame, type SettingsSection } from "@/components/arc/blocks/settings-page/settings-page"
import { ConnectionsScreen } from "@/features/connections/ConnectionsScreen"
import { ConnectionsBar } from "@/features/connections/StartBar"
import { derive } from "@/features/connections/derive"
import { useSetup } from "@/features/connections/setup-store"
import { navigate } from "@/features/shell/route"
import type { Loaded } from "@/lib/use-result"
import { AgentsPage } from "./AgentsPage"
import { BackupsPage } from "./BackupsPage"
import { GeneralPage } from "./GeneralPage"
import { LogsPage } from "./LogsPage"
import { OldRecordsPage } from "./OldRecordsPage"

type Accounts = Loaded<AccountOverviewPage> & { retry: () => void }

const PAGES: (SettingsSection & { render: (accounts: Accounts, sheet: string | null) => ReactNode })[] = [
  { id: "connections", label: "Connections", description: "Each Connect checks its service before anything is saved.", icon: Plug01Icon, render: (_, sheet) => <ConnectionsScreen sheet={sheet} /> },
  { id: "general", label: "General", description: "How times show, and what tells you about trades.", icon: Clock01Icon, render: () => <GeneralPage /> },
  { id: "agents", label: "Agent access", description: "What agents may do, and what they asked for.", icon: BotIcon, render: () => <AgentsPage /> },
  { id: "backups", label: "Backups", description: "Back up your records, or restore from a backup.", icon: ArchiveIcon, render: () => <BackupsPage /> },
  { id: "logs", label: "Logs", description: "What the engine recorded on this Mac.", icon: ScrollTextIcon, render: () => <LogsPage /> },
  { id: "old-records", label: "Old records", description: "Records of accounts no longer in your setup.", icon: HistoryIcon, render: (accounts) => <OldRecordsPage accounts={accounts} /> },
]

/** Settings: its sections listed on the left, the selected one (the route's second segment) on the right, and the setup bar floating over Connections. */
export function SettingsScreen({ page, sheet, accounts }: { page: string | null; sheet: string | null; accounts: Accounts }) {
  const setup = useSetup()
  const derived = derive(setup)
  const current = PAGES.find((p) => p.id === page) ?? PAGES[0]!
  const sections = PAGES.map(({ id, label, description, icon }) => ({ id, label, description, icon, pending: id === "connections" && derived?.hasUnsaved ? 1 : 0 }))
  const bar = current.id === "connections" && derived ? <ConnectionsBar key="bar" s={setup} derived={derived} /> : null
  return (
    <SettingsFrame sections={sections} section={current.id} onSectionChange={(id) => navigate("settings", id)} bar={bar}>
      {current.render(accounts, sheet)}
    </SettingsFrame>
  )
}
