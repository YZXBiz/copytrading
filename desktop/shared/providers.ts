import type { ProviderName } from "./contract"

// The interpreters the owner can pick, grouped as Connections shows them
// (ProviderGroup.swift, TradingProviderName+Title.swift, SetupHelp+Interpreters.swift).

export const PROVIDER_TITLES: Record<ProviderName, string> = {
  anthropic: "Anthropic",
  openai: "OpenAI",
  google: "Google Gemini",
  deepseek: "DeepSeek",
  openrouter: "OpenRouter",
  groq: "Groq",
  xai: "xAI",
  mistral: "Mistral",
  together: "Together AI",
  fireworks: "Fireworks AI",
  cerebras: "Cerebras",
  moonshotai: "Moonshot AI (Kimi)",
  ollama: "Ollama (on this Mac)",
  openai_compatible: "Other (OpenAI-compatible)",
}

/** The name where space is short: a row or a panel's title. */
export const providerShortTitle = (name: ProviderName): string =>
  name === "moonshotai" ? "Moonshot AI" : name === "ollama" ? "Ollama" : name === "openai_compatible" ? "OpenAI-compatible" : PROVIDER_TITLES[name]

export const PROVIDER_GROUPS: { title: string; providers: ProviderName[] }[] = [
  { title: "Popular", providers: ["anthropic", "openai", "google", "deepseek"] },
  { title: "More providers", providers: ["openrouter", "groq", "xai", "mistral", "together", "fireworks", "cerebras", "moonshotai"] },
  { title: "Your own model", providers: ["ollama", "openai_compatible"] },
]

/** A service on this Mac or a custom server takes no key. */
export const requiresApiKey = (name: ProviderName): boolean => name !== "ollama" && name !== "openai_compatible"

/** Only a model on this Mac or a custom server is served at an address the owner gives. */
export const acceptsBaseUrl = (name: ProviderName): boolean => name === "ollama" || name === "openai_compatible"

const SUGGESTED_MODEL: Record<ProviderName, string> = {
  anthropic: "claude-sonnet-5-5",
  openai: "gpt-5.5-mini",
  google: "gemini-2.5-flash",
  deepseek: "deepseek-flash",
  openrouter: "anthropic/claude-sonnet-5.5",
  groq: "llama-3.3-70b-versatile",
  xai: "grok-4",
  mistral: "mistral-large-latest",
  together: "meta-llama/Llama-3.3-70B-Instruct-Turbo",
  fireworks: "accounts/fireworks/models/llama-v3p3-70b-instruct",
  cerebras: "llama-3.3-70b",
  moonshotai: "kimi-k2",
  ollama: "llama3.2",
  openai_compatible: "",
}

/** The model the field fills in when the owner picks a provider; a custom server has none to suggest. */
export const suggestedModel = (name: ProviderName): string => SUGGESTED_MODEL[name]

const LOCAL_HOSTS = ["localhost", "127.0.0.1", "[::1]"]

/** https anywhere, or http only to this Mac. */
function isAllowedBaseUrl(value: string): boolean {
  let url: URL
  try {
    url = new URL(value)
  } catch {
    return false
  }
  if (url.username || url.password) return false
  if (url.protocol === "https:") return Boolean(url.hostname)
  return url.protocol === "http:" && LOCAL_HOSTS.includes(url.hostname)
}

/** Why the engine would refuse this address, in the owner's words; null when it is fine or blank for a service that has its own. */
export function baseUrlProblem(name: ProviderName, baseUrl: string): string | null {
  const address = baseUrl.trim()
  if (!address) return name === "openai_compatible" ? "Enter the base URL your model is served at." : null
  if (!acceptsBaseUrl(name)) return `${name} is served at a fixed address.`
  return isAllowedBaseUrl(address) ? null : "The base URL must start with https://, or http:// for a model on this Mac."
}
