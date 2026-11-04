import { describe, expect, it } from "vitest"
import type { TradingConfiguration } from "../../../shared/contract"
import { assistantContext, assistantGurus, hasModel, suggestions } from "./context"

const profile = (id: string, name: string) => ({ guru_id: id, display_name: name, playbook: "", profile_revision: "r1" })
const route = (id: string) => ({ source: "discord", channel_id: "c", guru_id: id, profile_revision: "r1", connections: [], repeat_window_minutes: null })
const setup = (profiles: ReturnType<typeof profile>[], ids = profiles.map((p) => p.guru_id)) =>
  ({ profiles, routes: ids.map(route), provider: { name: "deepseek", model: "m" } }) as unknown as TradingConfiguration

describe("assistantGurus", () => {
  it("names each guru once, as the owner did", () => {
    expect(assistantGurus(setup([profile("zhao", "Zhao"), profile("li", " Li ")], ["zhao", "li", "zhao"]))).toEqual([{ id: "zhao", name: "Zhao" }, { id: "li", name: "Li" }])
  })
  it("leaves out an id the engine would reject, which would fail the whole question", () => {
    expect(assistantGurus(setup([profile("赵哥", "赵哥"), profile("ok", "Ok"), profile("x".repeat(65), "Long")]))).toEqual([{ id: "ok", name: "Ok" }])
  })
  it("leaves out a guru with no name and a route whose profile is gone", () => {
    expect(assistantGurus(setup([profile("a", "  ")]))).toEqual([])
    expect(assistantGurus(setup([], ["ghost"]))).toEqual([])
    expect(assistantGurus(null)).toEqual([])
  })
})

describe("assistantContext", () => {
  it("names the screen the way the engine does, and the selected account or guru", () => {
    expect(assistantContext({ screen: "gurus", id: "zhao" }, null)).toEqual({ screen: "people", selected_account_id: null, selected_guru_id: "zhao", language: "en", gurus: [] })
    expect(assistantContext({ screen: "accounts", id: "a1" }, null)).toMatchObject({ screen: "accounts", selected_account_id: "a1", selected_guru_id: null })
    expect(assistantContext({ screen: "getting-started", id: null }, null).screen).toBe("gettingStarted")
  })
})

describe("hasModel", () => {
  const withProvider = (name: string, model: string) => ({ configuration: { provider: { name, model } } as unknown as TradingConfiguration })
  it("needs a saved setup naming a model, and its key unless the model runs on this Mac", () => {
    expect(hasModel(null, { provider_api_key: true })).toBe(false)
    expect(hasModel(withProvider("deepseek", "m"), { provider_api_key: true })).toBe(true)
    expect(hasModel(withProvider("deepseek", "m"), { provider_api_key: false })).toBe(false)
    expect(hasModel(withProvider("deepseek", " "), { provider_api_key: true })).toBe(false)
    expect(hasModel(withProvider("ollama", "llama"), { provider_api_key: false })).toBe(true)
  })
})

describe("suggestions", () => {
  it("asks about setting up before a setup is saved", () => {
    expect(suggestions("accounts", "Zhao", false)[0]).toBe("Where do I find a channel ID?")
  })
  it("leads with a question about the screen, naming the guru when there is one", () => {
    expect(suggestions("accounts", null, true)[0]).toBe("What's in my paper account?")
    expect(suggestions("gurus", "Zhao", true)[0]).toBe("How did Zhao do this week?")
    expect(suggestions("settings", null, true)).toHaveLength(4)
  })
})
