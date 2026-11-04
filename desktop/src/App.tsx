import { MotionConfig } from "motion/react"
import { TooltipProvider } from "@/components/ui/tooltip"
import { AppFrame } from "@/features/shell/AppFrame"
import { useEngineState } from "@/features/shell/engine-state"
import { splitRecords } from "@/features/shell/records"
import { useRoute } from "@/features/shell/route"
import { SCREENS } from "@/features/shell/screens"
import { useResult } from "@/lib/use-result"

export default function App() {
  const route = useRoute()
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
          {SCREENS[route.screen].render({ route, accounts })}
        </AppFrame>
      </TooltipProvider>
    </MotionConfig>
  )
}
