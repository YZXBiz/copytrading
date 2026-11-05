import { type ReactNode, useCallback, useState } from "react"
import { BankIcon } from "@/components/icons/BankIcon"
import { Search01Icon } from "@/components/icons/Search01Icon"
import { TrendingUpIcon } from "@/components/icons/TrendingUpIcon"
import type { AccountOverview, AccountOverviewPage, EngineState, TradingConfiguration } from "../../../shared/contract"
import { SidebarRail, useSidebarRail, type RailEntry, type RailSection } from "@/components/arc/blocks/sidebar-rail/sidebar-rail"
import { USD_WHOLE_OPTIONS } from "@/features/account/balance-panel/format"
import { AssistantFrame } from "@/features/assistant/AssistantFrame"
import { derive } from "@/features/connections/derive"
import { useSetup } from "@/features/connections/setup-store"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { type Loaded } from "@/lib/use-result"
import { AppHeader } from "./AppHeader"
import { type Route, type ScreenId, href } from "./route"
import { SearchPalette, useSearchShortcut } from "./SearchPalette"
import { SCREENS } from "./screens"
import { useCopyingStatus } from "./use-copying-status"

interface Props {
  route: Route
  accounts: Loaded<AccountOverviewPage> & { retry: () => void }
  live: AccountOverview[]
  old: AccountOverview[]
  setup: TradingConfiguration | null | undefined
  selectedAccountId: string | null
  engine: EngineState
  children: ReactNode
}

/** Below this width the rail folds to icons when the Assistant opens, so the page keeps its room. */
const ROOMY = 1280

const USD_WHOLE = new Intl.NumberFormat("en-US", USD_WHOLE_OPTIONS)

const screenEntry = (id: ScreenId): RailEntry => ({ id, label: SCREENS[id].title, href: href(id), icon: SCREENS[id].icon })

/** The live accounts with their balances, in place of the list while it loads, fails or is empty. */
function accountsSection(accounts: Props["accounts"], live: AccountOverview[]): RailSection {
  const section: RailSection = { id: "accounts", heading: "Accounts", items: [] }
  if (accounts.status === "loading") return { ...section, note: <Skeleton label="Loading accounts" /> }
  if (accounts.status === "error") {
    return {
      ...section,
      note: (
        <span title={accounts.error}>
          Accounts did not load.{" "}
          <button type="button" onClick={accounts.retry}>
            Retry
          </button>
        </span>
      ),
    }
  }
  if (live.length === 0) return { ...section, note: "No accounts yet." }
  return {
    ...section,
    items: live.map((account) => ({
      id: `account:${account.account_id}`,
      label: account.account_id,
      href: href("accounts", account.account_id),
      icon: BankIcon,
      value: account.balance ? USD_WHOLE.format(Number(account.balance.equity)) : undefined,
    })),
  }
}

function Frame({ route, selectedAccountId, children }: Pick<Props, "route" | "selectedAccountId" | "children">) {
  const { fold } = useSidebarRail()
  const makeRoom = useCallback(() => {
    if (window.innerWidth < ROOMY) fold()
  }, [fold])
  return (
    <AssistantFrame onOpen={makeRoom}>
      <AppHeader route={route} selectedAccountId={selectedAccountId} />
      <main className="min-h-0 flex-1 overflow-auto px-4 pb-4">{children}</main>
    </AssistantFrame>
  )
}

/** The app's frame: a rail that folds to icons beside the page, with search above the nav and the copying status below it. */
export function AppFrame({ children, ...props }: Props) {
  const { route, accounts, live, old, setup, selectedAccountId, engine } = props
  const [searching, setSearching] = useState(false)
  useSearchShortcut(useCallback(() => setSearching(true), []))
  const status = useCopyingStatus(engine)

  // Settings, with Getting Started above it until setup is complete: every step of its checklist done, which includes
  // copying started once (the setup saved). It stays while its own page is open, and #/getting-started and ⌘K reach it after.
  const progress = derive(useSetup())
  const settingUp = progress !== null && progress.progress.next !== null
  const footer = (settingUp || route.screen === "getting-started" ? (["getting-started", "settings"] as const) : (["settings"] as const)).map(screenEntry)

  const sections: RailSection[] = [
    { id: "search", items: [{ id: "search", label: "Search", icon: Search01Icon, value: "⌘K", onSelect: () => setSearching(true) }] },
    accountsSection(accounts, live),
    { id: "screens", items: [screenEntry("gurus"), screenEntry("activity")] },
  ]
  const active = route.screen === "accounts" ? (selectedAccountId ? `account:${selectedAccountId}` : null) : route.screen

  return (
    <>
      <SidebarRail
        label="Main"
        brand={{ name: "CopyTrading", mark: <TrendingUpIcon width={16} height={16} /> }}
        sections={sections}
        footer={footer}
        active={active}
        status={status}
      >
        <Frame route={route} selectedAccountId={selectedAccountId}>
          {children}
        </Frame>
      </SidebarRail>
      <SearchPalette open={searching} onOpenChange={setSearching} live={live} old={old} setup={setup} />
    </>
  )
}
