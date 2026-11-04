import type {
  AccountLimits,
  AccountOverviewPage,
  EquityHistory,
  HistoryRange,
  Result,
  SourceActivityPage,
  TradingStatus,
} from "../../shared/contract"
import { EngineBridge, EngineError } from "./engine/bridge"

const ENGINE_WORDS: Record<string, string> = {
  unavailable: "The engine is not ready to answer yet.",
  not_found: "The engine has no record of this account.",
  invalid_request: "The engine did not accept the request.",
  identity_conflict: "The engine belongs to a different installation.",
}

async function call<T>(run: () => Promise<T>): Promise<Result<T>> {
  try {
    return { ok: true, value: await run() }
  } catch (error) {
    const text = error instanceof Error ? error.message : String(error)
    return { ok: false, error: error instanceof EngineError && error.code === "engine" ? (ENGINE_WORDS[text] ?? text) : text }
  }
}

const field = <T>(reply: unknown, key: string) => (reply as Record<string, T>)[key] as T

/** The reads the renderer may make, each one a single engine operation. */
export const engineApi = (bridge: EngineBridge) => ({
  getStatus: () => call(async () => field<TradingStatus>(await bridge.request("get_trading_status"), "trading")),
  getAccounts: () =>
    call(async () => field<AccountOverviewPage>(await bridge.request("get_accounts", { limit: 100 }), "accounts")),
  getEquityHistory: (accountId: string, range: HistoryRange) =>
    call(async () =>
      field<EquityHistory | null>(
        await bridge.request("get_equity_history", { account_id: accountId, window: { range } }),
        "history",
      ),
    ),
  getSourceActivity: () =>
    call(async () => field<SourceActivityPage>(await bridge.request("get_source_activity", { limit: 50 }), "activity")),
  // Limits live in the setup the app saves, which the React app does not own yet.
  getLimits: (_accountId: string) => call(async (): Promise<AccountLimits | null> => null),
})

export type EngineApi = ReturnType<typeof engineApi>
