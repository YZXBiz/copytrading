import { useEffect } from "react"
import { MotionConfig } from "motion/react"
import { announceSkipped } from "@/features/account/skipped-calls"
import { TooltipProvider } from "@/components/ui/tooltip"
import { AppFrame } from "@/features/shell/AppFrame"
import { FillToasts } from "@/features/shell/FillToasts"
import { useEngineState } from "@/features/shell/engine-state"
import { splitRecords } from "@/features/shell/records"
import { useRoute } from "@/features/shell/route"
import { SCREENS } from "@/features/shell/screens"
import { useResult } from "@/lib/use-result"

export default function App() {
  const route = useRoute()
  useEffect(announceSkipped, [])
  const engine = useEngineState()
  // Reads again when the engine finishes starting, then every 5 s: balance, holdings and copying state move on their own.
  const accounts = useResult(() => window.copytrading.read.getAccounts(), `accounts:${engine.state}`, 5000)
  // The saved setup says which accounts are live; the rest are records left from earlier runs.
  const setup = useResult(() => window.copytrading.read.getSetup(), `setup:${engine.state}`, 5000)
  const config = setup.status === "ready" ? (setup.data?.configuration ?? null) : undefined
  const { live, old } = splitRecords(accounts.status === "ready" ? accounts.data.items : [], config)
  const selectedAccountId = route.screen === "accounts" ? (route.id ?? live[0]?.account_id ?? null) : null

  return (
    <MotionConfig reducedMotion="user">
      <TooltipProvider>
        <AppFrame route={route} accounts={accounts} live={live} old={old} setup={config} selectedAccountId={selectedAccountId} engine={engine}>
          {SCREENS[route.screen].render({ route: route.screen === "accounts" && !route.id ? { ...route, id: selectedAccountId } : route, accounts })}
        </AppFrame>
        <FillToasts />
      </TooltipProvider>
    </MotionConfig>
  )
}
