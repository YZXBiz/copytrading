import { describe, expect, it } from "vitest"
import type { TradingStatus } from "../../../shared/contract"
import { copyingProblem } from "./copying-problem"

const status = (changes: Partial<TradingStatus>): TradingStatus => ({
  state: "degraded",
  configured_accounts: 2,
  active_accounts: 2,
  source_connected: true,
  model_ready: true,
  error_code: null,
  ...changes,
})

describe("copyingProblem", () => {
  it("names a stopped account, what happened and where to look", () => {
    const accounts = [
      { id: "zhap-account-2", state: "failed", error_code: "broker_keys_rejected" },
      { id: "zhap-account-3", state: "running", error_code: null },
    ]
    expect(copyingProblem(status({ accounts, active_accounts: 1 }))).toBe(
      "zhap-account-2 stopped copying. Alpaca didn't accept the API keys. Open Accounts to see what to do.",
    )
  })

  it("names every stopped account, and says when their reasons differ", () => {
    const accounts = [
      { id: "a", state: "failed", error_code: "broker_unreachable" },
      { id: "b", state: "failed", error_code: "account_in_use" },
    ]
    expect(copyingProblem(status({ accounts }))).toBe("a and b stopped copying. They stopped for different reasons. Open Accounts to see what to do.")
  })

  it("never shows a missing code as a dash", () => {
    const accounts = [{ id: "a", state: "failed", error_code: null }]
    expect(copyingProblem(status({ accounts }))).toBe("a stopped copying. The account could not be reached. Open Accounts to see what to do.")
  })

  it("says Discord's token was refused, can't be reached, or is still connecting", () => {
    expect(copyingProblem(status({ source_connected: false, error_code: "source_unauthorized" }))).toContain("Paste a new one in Connections")
    expect(copyingProblem(status({ source_connected: false, error_code: "source_unavailable" }))).toContain("Discord can't be reached")
    expect(copyingProblem(status({ source_connected: false }))).toBe("Still connecting to Discord, so new posts aren't being read yet.")
  })

  it("says the model service is not answering and alerts are not sent, and never shows a raw code", () => {
    expect(copyingProblem(status({ model_ready: false }))).toContain("model service isn't answering")
    expect(copyingProblem(status({ error_code: "notification_unavailable" }))).toContain("notification channel")
    expect(copyingProblem(status({ error_code: "something_new" }))).not.toContain("something_new")
  })
})
