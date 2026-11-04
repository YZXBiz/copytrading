import { useEffect, useSyncExternalStore } from "react"
import type {
  AccountOverviewPage,
  AccountPolicy,
  CapabilityCheck,
  ConnectionCheck,
  ProviderName,
  Result,
  SecretStatus,
  SecretUpdate,
  SetupView,
  TradingConfiguration,
  TradingStatus,
  TradingValidation,
} from "../../../shared/contract"
import { PROVIDER_TITLES, acceptsBaseUrl, baseUrlProblem, requiresApiKey, suggestedModel } from "../../../shared/providers"
import { startFailure } from "../../../shared/start-failure"
import {
  type AccountDraft,
  type GuruDraft,
  type SetupDraft,
  SetupProblem,
  buildConfiguration,
  draftFromSetup,
  hasTypedKeys,
  newAccount,
  newGuru,
  effectiveChannel,
  signature,
  split,
  typedSecrets,
} from "./draft"
import { type Checks, type KeyFacts, type Subject, accountSubject, fingerprint, keyFacts, recordChecks, same } from "./state"
import { ENGINE_UNAVAILABLE } from "./words"

// The one place the setup form lives, so edits survive a trip to another screen. Screens read it with `useSetup()`.

type Report = TradingValidation["report"]

export type Start =
  | { phase: "idle" }
  | { phase: "checking" }
  | { phase: "starting" }
  /** The engine has not confirmed the start yet; the saved setup stays the one before it until it does. */
  | { phase: "pending"; activationId: string }
  /** `paused`: accounts the engine holds that are still not buying, which the owner resumes on their page. */
  | { phase: "started"; paused: string[] }
  | { phase: "failed"; message: string; report: Report | null }

export interface Loaded {
  saved: SetupView | null
  secrets: SecretStatus
  trading: TradingStatus | null
}

export interface SetupState {
  load: { status: "loading" } | { status: "error"; error: string } | { status: "ready"; data: Loaded }
  draft: SetupDraft
  /** The form as the engine would see it; null while it cannot be built, with the reason in `problem`. */
  built: TradingConfiguration | null
  problem: string | null
  checks: Checks
  start: Start
  /** What the last Connect could not do, by subject, in the owner's words. */
  notices: Partial<Record<Subject, string>>
}

let state: SetupState = {
  load: { status: "loading" },
  draft: draftFromSetup(null),
  built: null,
  problem: null,
  checks: {},
  start: { phase: "idle" },
  notices: {},
}
const listeners = new Set<() => void>()

function set(next: Partial<SetupState>) {
  state = { ...state, ...next }
  listeners.forEach((listener) => listener())
}

let building = 0
function rebuild() {
  const token = ++building
  const draft = state.draft
  buildConfiguration(draft).then(
    (built) => token === building && set({ built, problem: null }),
    (error: unknown) => token === building && set({ built: null, problem: error instanceof SetupProblem ? error.message : "The setup could not be read." }),
  )
}

export function edit(change: (draft: SetupDraft) => SetupDraft) {
  set({ draft: change(state.draft), notices: {} })
  // Any edit after a start failed or a check passed discards that outcome: it covered a setup that is gone.
  if (state.start.phase === "failed") set({ start: { phase: "idle" } })
  rebuild()
}

/** Changes one account; renaming it keeps every guru that copies into it pointed at it. */
export function editAccount(uid: string, change: (account: AccountDraft) => AccountDraft) {
  edit((draft) => {
    const before = draft.accounts.find((a) => a.uid === uid)
    if (!before) return draft
    const after = change(before)
    const [from, to] = [before.name.trim(), after.name.trim()]
    return {
      ...draft,
      accounts: draft.accounts.map((a) => (a.uid === uid ? after : a)),
      gurus: from && from !== to ? draft.gurus.map((g) => (g.account_id.trim() === from ? { ...g, account_id: to } : g)) : draft.gurus,
    }
  })
}

export const editPolicy = (uid: string, patch: Partial<AccountPolicy>) => editAccount(uid, (a) => ({ ...a, policy: { ...a.policy, ...patch } }))

/** A new account; the first guru that copies into nothing yet copies into it, since an account copies one guru. Returns its id. */
export function addAccount(): string {
  const account = newAccount(state.draft.accounts)
  edit((draft) => {
    const free = draft.gurus.findIndex((g) => !g.account_id)
    return {
      ...draft,
      accounts: [...draft.accounts, account],
      gurus: draft.gurus.map((g, i) => (i === free ? { ...g, account_id: account.name } : g)),
    }
  })
  return account.uid
}

export const removeAccount = (uid: string) => edit((d) => ({ ...d, accounts: d.accounts.filter((a) => a.uid !== uid) }))

export function addGuru(): string {
  const guru = newGuru(state.draft)
  edit((draft) => ({ ...draft, gurus: [...draft.gurus, guru] }))
  return guru.uid
}

export const editGuru = (uid: string, patch: Partial<GuruDraft>) =>
  edit((d) => ({ ...d, gurus: d.gurus.map((g) => (g.uid === uid ? { ...g, ...patch } : g)) }))

export const removeGuru = (uid: string) => edit((d) => ({ ...d, gurus: d.gurus.filter((g) => g.uid !== uid) }))

/** Gives copying the account's new limits at once (after a confirmation in main). Returns why it could not, null when it did or the owner said no. */
export async function applyLimits(uid: string): Promise<string | null> {
  if (state.load.status !== "ready" || !state.load.data.saved) return "There is no saved setup to change yet."
  const account = state.draft.accounts.find((a) => a.uid === uid)
  const configuration = structuredClone(state.load.data.saved.configuration)
  const target = configuration.accounts.find((a) => a.id === account?.name.trim())
  if (!account || !target) return "This account is not in the saved setup yet."
  target.policy = account.policy
  const applied = await window.copytrading.act.updateAccountLimits({ configuration })
  if (!applied.ok && !applied.cancelled) return applied.error
  await reload({ keepDraft: true })
  return null
}

/** Picks an interpreter: a key belongs to its provider, so another pick empties the key field, and the model field shows that provider's model unless the owner typed one. */
export function pickProvider(provider: ProviderName) {
  edit((draft) => {
    const changed = provider !== draft.provider
    const model = draft.model.trim()
    const replaceable = !model || model === suggestedModel(draft.provider)
    return {
      ...draft,
      provider,
      provider_api_key: changed ? "" : draft.provider_api_key,
      base_url: acceptsBaseUrl(provider) ? draft.base_url : "",
      model: replaceable ? suggestedModel(provider) : draft.model,
    }
  })
}

const failure = (error: string): Extract<Start, { phase: "failed" }> => ({ phase: "failed", message: error, report: null })

/** Reads the saved setup, the saved keys and the engine's status; the form is refilled from the saved setup unless `keepDraft`. */
export async function reload({ keepDraft = false }: { keepDraft?: boolean } = {}) {
  const api = window.copytrading.read
  const [saved, secrets, trading] = await Promise.all([api.getSetup(), api.getSecretStatus(), api.getStatus()])
  const error = !saved.ok ? saved.error : !secrets.ok ? secrets.error : null
  if (error !== null || !saved.ok || !secrets.ok) {
    set({ load: { status: "error", error: error ?? "The saved setup could not be read." } })
    return
  }
  const data: Loaded = { saved: saved.value, secrets: secrets.value, trading: trading.ok ? trading.value : null }
  set({ load: { status: "ready", data }, ...(keepDraft ? {} : { draft: draftFromSetup(saved.value?.configuration ?? null), checks: {}, notices: {} }) })
  if (!keepDraft) rebuild()
}

/** Forgets the form's edits and typed keys, and shows the saved setup again. */
export async function discard() {
  set({ start: { phase: "idle" } })
  // Keys typed for a Connect are held in main until a start saves them; discarding the form drops them there too.
  await window.copytrading.act.discardSecrets()
  await reload()
}

/** Which keys are already saved, as far as the form's setup may use them; null until the setup is loaded. */
export const keysOf = (s: SetupState): KeyFacts | null =>
  s.load.status === "ready" ? keyFacts(s.load.data.secrets, s.load.data.saved?.configuration ?? null, s.draft) : null

const facts = () => keysOf(state)

/** Copying is on or on its way: the setup is the engine's to run, so the form can change limits only. */
export const isCopying = (s: SetupState): boolean =>
  s.load.status === "ready" && ["running", "degraded", "starting", "pausing"].includes(s.load.data.trading?.state ?? "")

/** What Connect says when a panel has nothing it could check, in the owner's words; null when there is something to check. */
export function missingToConnect(subject: Subject, draft: SetupDraft, keys: KeyFacts): string | null {
  if (subject === "discord") {
    return split(draft.channels).length && (draft.discord_token || keys.discord) ? null : "Enter a channel ID and your Discord token to connect."
  }
  if (subject === "interpreter") {
    if (!draft.model.trim()) return "Enter the model's name to connect."
    const address = baseUrlProblem(draft.provider, draft.base_url)
    if (address) return address
    return !requiresApiKey(draft.provider) || draft.provider_api_key || keys.providerKey ? null : "Enter the API key to connect."
  }
  const account = draft.accounts.find((a) => accountSubject(a.name) === subject)
  const typed = Boolean(account?.key && account.secret)
  if (account && (Boolean(account.key) !== Boolean(account.secret))) return "Enter both the API key and the secret to connect."
  return typed || keys.brokers[account?.name.trim() ?? ""] ? null : "Enter the Alpaca API key and secret to connect."
}

/** What the engine checks for one subject, from the form. */
function connectionFor(subject: Subject, draft: SetupDraft): ConnectionCheck | null {
  if (subject === "discord") return { kind: "source", source: { channel_ids: split(draft.channels), author_ids: split(draft.authors) } }
  if (subject === "interpreter") {
    const base = draft.base_url.trim()
    return { kind: "model", provider: { name: draft.provider, model: draft.model.trim(), ...(acceptsBaseUrl(draft.provider) && base ? { base_url: base } : {}) } }
  }
  const account = draft.accounts.find((a) => accountSubject(a.name) === subject)
  return account ? { kind: "broker", account: { id: account.name.trim(), environment: account.environment, policy: account.policy } } : null
}

/** The keys typed for one subject, which main needs before it can check them. */
function secretsFor(subject: Subject, draft: SetupDraft): SecretUpdate | null {
  const all = typedSecrets(draft)
  if (!all) return null
  if (subject === "discord") return all.discord_token ? { discord_token: all.discord_token } : null
  if (subject === "interpreter") return all.provider_api_key ? { provider_api_key: all.provider_api_key, provider_name: draft.provider } : null
  const mine = all.brokers?.find((b) => accountSubject(b.account_id) === subject)
  return mine ? { brokers: [mine] } : null
}

const unavailable = (subject: Subject, draft: SetupDraft): CapabilityCheck => ({
  name: subject === "discord" ? "source" : subject === "interpreter" ? "model" : "broker",
  state: "failed",
  subject: subject.startsWith("account:") ? subject.slice(8) : null,
  environment: null,
  identity: null,
  adapter: draft.provider,
  reason_code: ENGINE_UNAVAILABLE,
  suggestion: null,
  symbols: [],
})

const refreshSecrets = async () => {
  const secrets = await window.copytrading.read.getSecretStatus()
  if (secrets.ok && state.load.status === "ready") set({ load: { status: "ready", data: { ...state.load.data, secrets: secrets.value } } })
}

/** Checks one connection with what is typed for it, filling a blank key from the saved ones, and remembers the answer while those fields stay as they are. */
export async function connect(subject: Subject) {
  const keys = facts()
  if (!keys) return
  const draft = state.draft
  const missing = missingToConnect(subject, draft, keys)
  if (missing) return set({ notices: { ...state.notices, [subject]: missing } })
  const connection = connectionFor(subject, draft)
  if (!connection) return
  const print = fingerprint(draft, subject)
  set({ notices: { ...state.notices, [subject]: undefined }, checks: { ...state.checks, [subject]: { fingerprint: print, check: null } } })
  const finish = (check: CapabilityCheck, error?: string) =>
    set({ checks: { ...state.checks, [subject]: { fingerprint: print, check, ...(error ? { error } : {}) } } })
  const typed = secretsFor(subject, draft)
  if (typed) {
    const saved = await window.copytrading.act.setSecrets(typed)
    if (!saved.ok) return finish(unavailable(subject, draft), saved.error)
    await refreshSecrets()
  }
  const answer = await window.copytrading.act.checkConnection({ connection })
  if (answer.ok) finish(answer.value)
  else finish(unavailable(subject, draft), answer.error)
}

/** Drafts a guru's playbook from their channel's recent posts; the owner reads it over before it is used. */
export async function learnPlaybook(uid: string): Promise<{ ok: boolean; text: string }> {
  const keys = facts()
  const draft = state.draft
  const guru = draft.gurus.find((g) => g.uid === uid)
  if (!keys || !guru) return { ok: false, text: "The setup is not loaded yet." }
  const channel = effectiveChannel(draft, guru)
  if (!channel) return { ok: false, text: "Choose the guru's Discord channel first." }
  const missing = missingToConnect("discord", draft, keys) ?? missingToConnect("interpreter", draft, keys)
  if (missing) return { ok: false, text: `${missing.replace(/ to connect\.$/, "")} first, under Discord and Interpreter.` }
  for (const subject of ["discord", "interpreter"] as const) {
    const typed = secretsFor(subject, draft)
    const saved = typed && (await window.copytrading.act.setSecrets(typed))
    if (saved && !saved.ok) return { ok: false, text: saved.error }
  }
  await refreshSecrets()
  const base = draft.base_url.trim()
  const provider = { name: draft.provider, model: draft.model.trim(), ...(acceptsBaseUrl(draft.provider) && base ? { base_url: base } : {}) }
  const author = guru.author_id.trim()
  const learned = await window.copytrading.act.learnGuruPlaybook({ channel_id: channel, ...(author ? { author_id: author } : {}), provider })
  if (!learned.ok) return { ok: false, text: learned.error }
  editGuru(uid, { playbook: learned.value.playbook })
  const sentences = [`Read ${learned.value.posts_read} posts with ${learned.value.model}.`, learned.value.summary.trim(), "The playbook is drafted; read it over before you start copying."]
  return { ok: true, text: sentences.filter(Boolean).join(" ") }
}

/** Whether every typed key is complete: a key without its secret cannot be saved. */
function incompleteKey(draft: SetupDraft): string | null {
  const half = draft.accounts.find((a) => Boolean(a.key) !== Boolean(a.secret))
  return half ? `Enter both the API key and the secret for “${half.name.trim()}”.` : null
}

/** The start committed: main already turned on each account it could, so the owner is told of any still not buying. */
async function finishStarted(ids: string[]) {
  const page: Result<AccountOverviewPage> = await window.copytrading.read.getAccounts()
  const paused = page.ok ? page.value.items.filter((a) => ids.includes(a.account_id) && a.entry_permission !== "enabled").map((a) => a.account_id) : []
  set({ start: { phase: "started", paused } })
}

/**
 * A start the engine had not confirmed when main stopped waiting. Reading the setup lets main settle it; once it is no
 * longer pending, the engine's own record of this activation says whether it took (`reconcilePendingTradingActivation`).
 */
async function settlePending(activationId: string) {
  await reload({ keepDraft: true })
  if (state.load.status !== "ready" || state.load.data.saved?.pending_activation) return
  const read = window.copytrading.read
  const [activation, status] = await Promise.all([read.getTradingActivation({ activation_id: activationId }), read.getStatus()])
  if (!activation.ok) return
  const record = activation.value
  const ended = ["failed", "stopped", "interrupted", "not_found"].includes(record.phase) && ["paused", "failed"].includes(record.runtime_state)
  const accounts = state.load.data.saved?.configuration.accounts.map((a) => a.id) ?? []
  if (ended && record.committed_activation_id !== activationId) {
    const provider = state.load.data.saved?.configuration.provider.name ?? "anthropic"
    const why = startFailure(record.error_code, (status.ok && status.value.accounts) || [], PROVIDER_TITLES[provider])
    return set({ start: failure(`The new setup didn't start. ${why}`) })
  }
  await finishStarted(accounts)
}

/** The one Start Copying: checks every connection, saves exactly what was checked, then starts. */
export async function startCopying() {
  if (state.start.phase === "checking" || state.start.phase === "starting" || state.start.phase === "pending" || state.load.status !== "ready") return
  const draft = state.draft
  const keys = facts()!
  const problem = incompleteKey(draft)
  if (problem) return set({ start: failure(problem) })
  if (!draft.discord_token && !keys.discord) return set({ start: failure("Enter your Discord token in Connections first.") })
  let configuration: TradingConfiguration
  try {
    configuration = await buildConfiguration(draft)
  } catch (error) {
    return set({ start: failure(error instanceof SetupProblem ? error.message : "The setup could not be read.") })
  }
  const act = window.copytrading.act
  set({ start: { phase: "checking" } })
  const typed = typedSecrets(draft)
  if (typed) {
    const saved = await act.setSecrets({ ...typed, ...(typed.provider_api_key ? { provider_name: draft.provider } : {}) })
    if (!saved.ok) return set({ start: failure(saved.error) })
    await refreshSecrets()
  }
  const checked = await act.validateTrading({ configuration })
  if (!checked.ok) return set({ start: failure(checked.error) })
  const { report, activation_token } = checked.value
  set({ checks: { ...state.checks, ...recordChecks(draft, report.checks) } })
  if (!report.activatable || !activation_token) {
    return set({ start: { phase: "failed", message: "Some connections need attention. Nothing was saved.", report } })
  }
  if (signature(state.draft) !== signature(draft)) return set({ start: failure("The setup changed after it was checked. Check it again.") })
  set({ start: { phase: "starting" } })
  const saved = await act.saveSetup({ configuration, revision: report.configuration_revision })
  if (!saved.ok) return set({ start: failure(saved.error) })
  const activationId = crypto.randomUUID()
  const started = await act.startTrading({ activation_id: activationId, validation_token: activation_token })
  if (!started.ok) {
    set({ start: started.cancelled ? { phase: "idle" } : failure(started.error) })
    return void (await reload({ keepDraft: true }))
  }
  await reload()
  const after = state.load.status === "ready" ? state.load.data : null
  if (after?.saved?.pending_activation) return set({ start: { phase: "pending", activationId } })
  await finishStarted(configuration.accounts.map((a) => a.id))
}

/** The form differs from what is saved: typed keys, edits, or a first setup in progress. */
export function hasUnsavedChanges({ load, built, draft }: SetupState): boolean {
  if (hasTypedKeys(draft)) return true
  const saved = load.status === "ready" ? load.data.saved : null
  if (!saved) return Boolean(draft.accounts.length || draft.gurus.length || draft.channels.trim() || draft.authors.trim() || draft.model.trim())
  return !built || !same(built, saved.configuration)
}

/** Reads the engine's status again, for the screens that show it while the owner edits. */
export async function refreshStatus() {
  if (state.start.phase === "pending") return settlePending(state.start.activationId)
  const trading = await window.copytrading.read.getStatus()
  if (state.load.status === "ready" && trading.ok) set({ load: { status: "ready", data: { ...state.load.data, trading: trading.value } } })
}

/** The form's state right now, for code that is not a component. */
export const setupState = (): SetupState => state

let requested = false

/** The setup form and everything around it; the first screen to ask loads it. */
export function useSetup(): SetupState & { retry: () => void } {
  const current = useSyncExternalStore(
    (listener) => {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    () => state,
  )
  useEffect(() => {
    if (!requested) {
      requested = true
      void reload()
    }
  }, [])
  return { ...current, retry: () => void reload() }
}
