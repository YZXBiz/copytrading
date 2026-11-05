import type { AssistantAskContext, SecretStatus, TradingConfiguration } from "../../../shared/contract"
import type { Route, ScreenId } from "@/features/shell/route"

// What the assistant is told about the screen the owner is on (AppModel+Assistant.swift), and what it offers to be asked.

/** The names the engine's `AskContext.screen` accepts. */
const SCREEN: Record<ScreenId, AssistantAskContext["screen"]> = {
  accounts: "accounts",
  gurus: "people",
  activity: "activity",
  "getting-started": "gettingStarted",
  settings: "settings",
  stock: "accounts",
}

/** Ids as the engine reads them: letters, digits, `_` and `-`, up to 64; a name has up to 100 characters. */
const GURU_ID = /^[A-Za-z0-9_-]{1,64}$/

/** Every guru by the name the owner gave them, each once; one the engine would reject is left out. */
export function assistantGurus(setup: TradingConfiguration | null): { id: string; name: string }[] {
  const seen = new Set<string>()
  const named = (setup?.routes ?? []).flatMap((route) => {
    const profile = setup!.profiles.find((p) => p.guru_id === route.guru_id && p.profile_revision === route.profile_revision)
    return profile ? [{ id: profile.guru_id, name: profile.display_name.trim().slice(0, 100) }] : []
  })
  return named.filter(({ id, name }) => GURU_ID.test(id) && name !== "" && !seen.has(id) && !!seen.add(id))
}

export function assistantContext(route: Route, setup: TradingConfiguration | null): AssistantAskContext {
  return {
    screen: route.screen === "settings" && (route.id ?? "connections") === "connections" ? "connections" : SCREEN[route.screen],
    selected_account_id: route.screen === "accounts" ? route.id : null,
    selected_guru_id: route.screen === "gurus" ? route.id : null,
    language: "en",
    gurus: assistantGurus(setup),
  }
}

/** Whether a model is set up to answer: a saved setup naming one, and its key where the provider needs one. */
export function hasModel(setup: { configuration: TradingConfiguration } | null, secrets: Pick<SecretStatus, "provider_api_key">): boolean {
  const provider = setup?.configuration.provider
  return !!provider && provider.model.trim() !== "" && (provider.name === "ollama" || secrets.provider_api_key)
}

/** Four questions to start with, the first about the screen the owner is on. Before a setup is saved there is nothing to ask about but setting up. */
export function suggestions(screen: ScreenId, guru: string | null, isSetUp: boolean): string[] {
  const alerts = "How do I add Telegram alerts?"
  if (!isSetUp) return ["Where do I find a channel ID?", "Which AI model should I choose?", "What is a paper account?", alerts]
  const skipped = "Why was the last post skipped?"
  const record = guru ? `How did ${guru} do this week?` : "How did my gurus do this week?"
  const account = "What's in my paper account?"
  switch (screen) {
    case "gurus":
      return [record, skipped, account, alerts]
    case "accounts":
      return [account, record, skipped, alerts]
    default:
      return [alerts, record, account, skipped]
  }
}
