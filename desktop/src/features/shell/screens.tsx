import type { ReactNode } from "react"
import type { Icon } from "@/lib/icon"
import { Activity01Icon } from "@/components/icons/Activity01Icon"
import { BankIcon } from "@/components/icons/BankIcon"
import { Rocket01Icon } from "@/components/icons/Rocket01Icon"
import { Settings02Icon } from "@/components/icons/Settings02Icon"
import { UserGroupIcon } from "@/components/icons/UserGroupIcon"
import type { AccountOverviewPage } from "../../../shared/contract"
import { AccountsScreen } from "@/features/account/AccountsScreen"
import { ActivityScreen } from "@/features/activity/ActivityScreen"
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
  icon: Icon
  render: (props: ScreenProps) => ReactNode
}

const placeholder = (title: string) => () => <ScreenPlaceholder title={title} />

/**
 * Every screen, in one table. To port one, replace its `render` with the real component (see README.md);
 * nothing else in the shell changes. The sidebar, the top bar and ⌘K read `title` and `icon` from here.
 */
export const SCREENS: Record<ScreenId, Screen> = {
  accounts: {
    title: "Accounts",
    icon: BankIcon,
    render: ({ route, accounts }) => (
      <AccountsScreen
        accounts={accounts}
        selectedAccountId={route.id}
        onRefresh={accounts.retry}
        onOpenConnections={() => navigate("settings", "connections")}
      />
    ),
  },
  gurus: { title: "Gurus", icon: UserGroupIcon, render: ({ route, accounts }) => <GurusScreen guruId={route.id} accounts={accounts} /> },
  activity: {
    title: "Activity",
    icon: Activity01Icon,
    render: ({ route, accounts }) => <ActivityScreen selectedSequence={route.id === null ? null : Number(route.id)} accounts={accounts} />,
  },
  "getting-started": { title: "Getting Started", icon: Rocket01Icon, render: () => <GettingStartedScreen /> },
  settings: { title: "Settings", icon: Settings02Icon, render: ({ route, accounts }) => <SettingsScreen page={route.id} sheet={route.sub} accounts={accounts} /> },
}
