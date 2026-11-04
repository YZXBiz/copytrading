import type { ReactNode } from "react"
import { ActivityIcon, LandmarkIcon, PlugIcon, RocketIcon, SettingsIcon, UsersIcon, type LucideIcon } from "lucide-react"
import type { AccountOverviewPage } from "../../../shared/contract"
import { AccountsScreen } from "@/features/account/AccountsScreen"
import { ActivityScreen } from "@/features/activity/ActivityScreen"
import { ConnectionsScreen } from "@/features/connections/ConnectionsScreen"
import { GettingStartedScreen } from "@/features/getting-started/GettingStartedScreen"
import { GurusScreen } from "@/features/gurus/GurusScreen"
import { SettingsScreen } from "@/features/settings/SettingsScreen"
import { type Loaded } from "@/lib/use-result"
import { ScreenPlaceholder } from "./ScreenPlaceholder"
import { type Route, type ScreenId, navigate } from "./route"

export interface ScreenProps {
  route: Route
  accounts: Loaded<AccountOverviewPage> & { retry: () => void }
}

interface Screen {
  title: string
  icon: LucideIcon
  render: (props: ScreenProps) => ReactNode
}

const placeholder = (title: string) => () => <ScreenPlaceholder title={title} />

/**
 * Every screen, in one table. To port one, replace its `render` with the real component (see README.md);
 * nothing else in the shell changes. The sidebar and the breadcrumb read `title` and `icon` from here.
 */
export const SCREENS: Record<ScreenId, Screen> = {
  accounts: {
    title: "Accounts",
    icon: LandmarkIcon,
    render: ({ route, accounts }) => (
      <AccountsScreen
        accounts={accounts}
        selectedAccountId={route.id}
        onRefresh={accounts.retry}
        onOpenConnections={() => navigate("connections")}
      />
    ),
  },
  gurus: { title: "Gurus", icon: UsersIcon, render: ({ route, accounts }) => <GurusScreen guruId={route.id} accounts={accounts} /> },
  activity: {
    title: "Activity",
    icon: ActivityIcon,
    render: ({ route, accounts }) => <ActivityScreen selectedSequence={route.id === null ? null : Number(route.id)} accounts={accounts} />,
  },
  "getting-started": { title: "Getting Started", icon: RocketIcon, render: () => <GettingStartedScreen /> },
  connections: { title: "Connections", icon: PlugIcon, render: ({ route }) => <ConnectionsScreen routeId={route.id} /> },
  settings: { title: "Settings", icon: SettingsIcon, render: ({ route, accounts }) => <SettingsScreen page={route.id} accounts={accounts} /> },
}
