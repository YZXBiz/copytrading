import { useState } from "react"
import { Breadcrumb, BreadcrumbItem, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator } from "@/components/ui/breadcrumb"
import { SidebarInset, SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar"
import { TooltipProvider } from "@/components/ui/tooltip"
import { AccountsScreen } from "@/features/account/AccountsScreen"
import { AppSidebar, type Screen } from "@/features/shell/AppSidebar"
import { ScreenPlaceholder } from "@/features/shell/ScreenPlaceholder"
import { useResult } from "@/lib/use-result"

const TITLES: Record<Screen, string> = { accounts: "Accounts", gurus: "Gurus", connections: "Connections", settings: "Settings" }

export default function App() {
  const [screen, setScreen] = useState<Screen>("accounts")
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const accounts = useResult(() => window.copytrading.getAccounts(), "accounts")
  const shown = accounts.status === "ready" ? (accounts.data.items.find((a) => a.account_id === selectedId) ?? accounts.data.items[0]) : null

  return (
    <TooltipProvider>
      <SidebarProvider>
        <AppSidebar
          screen={screen}
          onScreen={setScreen}
          accounts={accounts}
          selectedAccountId={shown?.account_id ?? null}
          onSelectAccount={(id) => {
            setSelectedId(id)
            setScreen("accounts")
          }}
        />
        <SidebarInset className="min-w-0 overflow-hidden">
          <header className="flex h-12 shrink-0 items-center gap-2 border-b px-4">
            <SidebarTrigger className="-ml-1" />
            <Breadcrumb className="min-w-0">
              <BreadcrumbList className="flex-nowrap">
                {screen === "accounts" && shown && (
                  <>
                    <BreadcrumbItem>Accounts</BreadcrumbItem>
                    <BreadcrumbSeparator />
                  </>
                )}
                <BreadcrumbItem className="min-w-0">
                  <BreadcrumbPage className="truncate">{screen === "accounts" ? (shown?.account_id ?? "Accounts") : TITLES[screen]}</BreadcrumbPage>
                </BreadcrumbItem>
              </BreadcrumbList>
            </Breadcrumb>
          </header>
          <main className="flex-1 overflow-auto p-6">
            {screen === "accounts" ? (
              <AccountsScreen
                accounts={accounts}
                selectedAccountId={shown?.account_id ?? null}
                onRefresh={accounts.retry}
                onOpenConnections={() => setScreen("connections")}
              />
            ) : (
              <ScreenPlaceholder title={TITLES[screen]} onBack={() => setScreen("accounts")} />
            )}
          </main>
        </SidebarInset>
      </SidebarProvider>
    </TooltipProvider>
  )
}
