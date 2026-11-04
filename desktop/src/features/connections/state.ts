import type { CapabilityCheck, SecretStatus, TradingConfiguration, TradingStatus } from "../../../shared/contract"
import {
  type AccountDraft,
  type GuruDraft,
  type SetupDraft,
  accountNameProblem,
  accountIds,
  effectiveChannel,
  split,
} from "./draft"
import { baseUrlProblem, requiresApiKey } from "../../../shared/providers"

// How far a setup has come and how each connection is doing (SetupProgress.swift, ConnectionStatus.swift),
// read from the form, the saved setup and the latest checks, so the screens tick themselves as the owner types.

export type StepId = "discord" | "interpreter" | "account" | "guru" | "start"

export const STEPS: { id: StepId; title: string; detail: string }[] = [
  { id: "discord", title: "Connect Discord", detail: "The channels your gurus post in, and the token CopyTrading reads them with." },
  { id: "interpreter", title: "Choose an interpreter", detail: "The AI model that turns each post into an exact order." },
  {
    id: "account",
    title: "Add a broker account",
    detail: "Where orders go. Start with an Alpaca paper account: it trades pretend money at real prices.",
  },
  { id: "guru", title: "Pick who to copy", detail: "Each guru's channel, how to read their calls, and the account that copies them." },
  { id: "start", title: "Check and start copying", detail: "CopyTrading tests every connection while you watch. Nothing is saved or traded before this." },
]

/** One connection Connections checks on its own: a service, or a broker account by its name. */
export type Subject = "discord" | "interpreter" | `account:${string}`
export const accountSubject = (name: string): Subject => `account:${name.trim()}`

/** Which keys are already saved, as far as this setup may use them. */
export interface KeyFacts {
  discord: boolean
  /** The saved model key belongs to the provider the form names, so a blank key field keeps it. */
  providerKey: boolean
  brokers: Record<string, boolean>
}

export function keyFacts(secrets: SecretStatus | null, saved: TradingConfiguration | null, draft: SetupDraft): KeyFacts {
  return {
    discord: Boolean(secrets?.discord_token),
    providerKey: Boolean(secrets?.provider_api_key) && saved?.provider.name === draft.provider,
    brokers: secrets?.brokers ?? {},
  }
}

export interface Progress {
  done: ReadonlySet<StepId>
  /** The first step still to do. */
  next: StepId | null
  /** Everything a check needs is in place. */
  isReadyToCheck: boolean
}

export function setupProgress(draft: SetupDraft, facts: KeyFacts, isSetUp: boolean, failed: ReadonlySet<Subject> = new Set()): Progress {
  const done = new Set<StepId>()
  if (split(draft.channels).length && (draft.discord_token || facts.discord) && !failed.has("discord")) done.add("discord")
  const hasModelKey = !requiresApiKey(draft.provider) || Boolean(draft.provider_api_key) || facts.providerKey
  if (draft.model.trim() && hasModelKey && !baseUrlProblem(draft.provider, draft.base_url) && !failed.has("interpreter")) done.add("interpreter")
  const hasAccount = draft.accounts.some((a) => {
    const name = a.name.trim()
    return !accountNameProblem(name) && !failed.has(accountSubject(name)) && ((a.key && a.secret) || facts.brokers[name])
  })
  if (hasAccount) done.add("account")
  const ids = new Set(accountIds(draft))
  if (draft.gurus.some((g) => g.display_name.trim() && effectiveChannel(draft, g) && ids.has(g.account_id.trim()))) done.add("guru")
  if (isSetUp) done.add("start")
  return {
    done,
    next: STEPS.find((s) => !done.has(s.id))?.id ?? null,
    isReadyToCheck: (["discord", "interpreter", "account", "guru"] as const).every((s) => done.has(s)),
  }
}

// ── Checks ──────────────────────────────────────────────────────────────────

export interface CheckResult {
  fingerprint: string
  /** Null while the check is still running. */
  check: CapabilityCheck | null
  /** Why the check could not run at all, in the app's words; shown in place of the engine's reason. */
  error?: string
}
export type Checks = Partial<Record<Subject, CheckResult>>

/** A digest of every field the connection's check covers: once any of it is edited the result no longer counts. */
export function fingerprint(draft: SetupDraft, subject: Subject): string {
  if (subject === "discord") return JSON.stringify([split(draft.channels), split(draft.authors), draft.discord_token])
  if (subject === "interpreter") return JSON.stringify([draft.provider, draft.model.trim(), draft.base_url.trim(), draft.provider_api_key])
  const account = draft.accounts.find((a) => accountSubject(a.name) === subject)
  return JSON.stringify([subject, account?.environment, account?.key, account?.secret])
}

/** The connection's latest check, unless something it checked has been edited since. */
export function resultFor(checks: Checks, draft: SetupDraft, subject: Subject): CheckResult | undefined {
  const result = checks[subject]
  return result && result.fingerprint === fingerprint(draft, subject) ? result : undefined
}

/** The subjects whose latest check failed. */
export function failedSubjects(checks: Checks, draft: SetupDraft): Set<Subject> {
  return new Set((Object.keys(checks) as Subject[]).filter((s) => resultFor(checks, draft, s)?.check?.state === "failed"))
}

/** A full check answers for every connection at once, so each row shows its own answer too. */
export function recordChecks(draft: SetupDraft, reports: CapabilityCheck[]): Checks {
  const checks: Checks = {}
  for (const check of reports) {
    const subject: Subject | null =
      check.name === "source" ? "discord" : check.name === "model" ? "interpreter" : check.name === "broker" && check.subject ? accountSubject(check.subject) : null
    if (subject) checks[subject] = { fingerprint: fingerprint(draft, subject), check }
  }
  return checks
}

// ── Statuses ────────────────────────────────────────────────────────────────

export type Tone = "positive" | "caution" | "inactive" | "neutral"
export interface Status {
  text: string
  tone: Tone
}

export interface Facts {
  draft: SetupDraft
  saved: TradingConfiguration | null
  /** The form as the engine would see it; null while it cannot be built. */
  built: TradingConfiguration | null
  keys: KeyFacts
  trading: TradingStatus | null
  checks: Checks
}

const stable = (value: unknown): string =>
  JSON.stringify(value, (_key, v: unknown) =>
    v && typeof v === "object" && !Array.isArray(v) ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => (a < b ? -1 : 1))) : v,
  )
/** Equal as JSON, whatever order the keys came in. */
export const same = (a: unknown, b: unknown): boolean => stable(a) === stable(b)

const positive = (text: string): Status => ({ text, tone: "positive" })
const caution = (text: string): Status => ({ text, tone: "caution" })
const inactive = (text: string): Status => ({ text, tone: "inactive" })

function checked(facts: Facts, subject: Subject): Status | null {
  const result = resultFor(facts.checks, facts.draft, subject)
  if (!result) return null
  if (!result.check) return { text: "Checking…", tone: "neutral" }
  return result.check.state === "ready" ? positive("Connected") : caution("Couldn't connect")
}

/** The engine's own reading while copying runs or starts; nothing while it is paused. */
function running(facts: Facts, reading: (status: TradingStatus) => Status): Status | null {
  const status = facts.trading
  if (!facts.saved || !status) return null
  if (status.state === "running" || status.state === "degraded") return reading(status)
  return status.state === "starting" ? { text: "Connecting", tone: "neutral" } : null
}

function isEdited(facts: Facts, subject: "discord" | "interpreter"): boolean {
  const { saved, built, draft } = facts
  if (!saved || !built) return true
  return subject === "discord" ? Boolean(draft.discord_token) || !same(built.source, saved.source) : Boolean(draft.provider_api_key) || !same(built.provider, saved.provider)
}

/** While copying runs, the engine's own reading; otherwise the latest check, or that the setup is saved. */
function live(facts: Facts, subject: Subject, reading: (status: TradingStatus) => Status): Status | null {
  if ((subject === "discord" || subject === "interpreter") && isEdited(facts, subject)) {
    const result = checked(facts, subject)
    if (result) return result
  }
  return running(facts, reading) ?? checked(facts, subject) ?? (facts.saved && facts.trading ? inactive("Saved") : null)
}

export const discordStatus = (facts: Facts): Status | null =>
  live(facts, "discord", (s) => (s.source_connected ? positive("Connected") : caution("Not connected")))

export const interpreterStatus = (facts: Facts): Status | null =>
  live(facts, "interpreter", (s) => (s.model_ready ? positive("Ready") : caution("Not ready")))

export function accountStatus(facts: Facts, account: AccountDraft): Status {
  const name = account.name.trim()
  if (accountNameProblem(name)) return caution("Needs a valid name")
  const result = checked(facts, accountSubject(name))
  if (result) return result
  const typed = Boolean(account.key && account.secret)
  const hasSavedKeys = Boolean(facts.keys.brokers[name])
  const built = facts.built?.accounts.find((a) => a.id === name)
  const saved = facts.saved?.accounts.find((a) => a.id === name)
  if (saved && built && !typed && hasSavedKeys && saved.environment === account.environment && same(saved.policy, built.policy)) {
    return live(facts, accountSubject(name), () => positive("Connected")) ?? inactive("Saved")
  }
  return typed || hasSavedKeys ? inactive("Not saved yet") : caution("Needs keys")
}

/** Whether this guru reads and copies as saved: their route and profile match the saved ones. */
export function isGuruSaved(facts: Facts, guru: GuruDraft): boolean {
  const channel = effectiveChannel(facts.draft, guru)
  const { saved, built } = facts
  const route = saved?.routes.find((r) => r.channel_id === channel)
  const edited = built?.routes.find((r) => r.channel_id === channel)
  return Boolean(route && edited && same(route, edited))
}

export function guruStatus(facts: Facts, guru: GuruDraft): Status {
  const { draft } = facts
  if (!guru.display_name.trim()) return caution("Needs a name")
  if (!effectiveChannel(draft, guru)) return caution("Needs a channel")
  if (!accountIds(draft).includes(guru.account_id.trim())) return caution("Needs an account to copy into")
  if (!isGuruSaved(facts, guru)) return inactive("Not saved yet")
  return running(facts, () => positive("Copying")) ?? inactive("Saved")
}

/** Before a setup is saved a row can only say whether its key is in. */
export const draftStatus = (hasKey: boolean, missing: string): Status => (hasKey ? inactive("Not saved yet") : caution(missing))
