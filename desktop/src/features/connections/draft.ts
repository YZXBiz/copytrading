import type {
  AccountPolicy,
  ProviderName,
  SecretUpdate,
  TradingConfiguration,
  TradingEnvironment,
  TradingProvider,
  TradingRoute,
} from "../../../shared/contract"
import { acceptsBaseUrl, baseUrlProblem } from "../../../shared/providers"

// The setup as the owner edits it: text fields, typed keys, nothing saved. `buildConfiguration` turns it into the
// configuration the engine validates, the way ConnectionsDraft.submission() and AppModel.validateTradingConfiguration do.

export const DEFAULT_POLICY: AccountPolicy = {
  max_order_usd: "100",
  max_symbol_usd: "600",
  max_total_usd: "2500",
  daily_loss_cap_usd: "250",
  max_entries_per_day: 30,
  max_signal_age_seconds: 600,
  order_timeout_seconds: 60,
  poll_seconds: 2,
  extended_hours: true,
  overnight: false,
  copy_exits: true,
  approve_orders: false,
  max_above_signal_pct: "0",
  max_below_signal_pct: "1",
  recovery_preference: "manual",
}

export const DEFAULT_REPEAT_WINDOW_MINUTES = 10
export const REPEAT_WINDOW_RANGE = [1, 1440] as const
export const PLAYBOOK_MAX_LENGTH = 8_000

export interface AccountDraft {
  /** Stays the same while the owner renames the account, so an open editor keeps its place. */
  uid: string
  name: string
  environment: TradingEnvironment
  policy: AccountPolicy
  key: string
  secret: string
}

export interface GuruDraft {
  uid: string
  channel_id: string
  author_id: string
  display_name: string
  playbook: string
  /** Minutes within which the same call again is a re-post; null copies every post. */
  repeat_window_minutes: number | null
  /** The one account this guru copies into; empty until chosen. */
  account_id: string
  /** The guru's whole position in dollars; empty follows the account's maximum per stock. */
  full_position_usd: string
}

export interface SetupDraft {
  channels: string
  authors: string
  discord_token: string
  provider: ProviderName
  model: string
  base_url: string
  provider_api_key: string
  accounts: AccountDraft[]
  gurus: GuruDraft[]
  /** Alerts are not edited here: a saved setup's carry through untouched. */
  notification: TradingConfiguration["notification"]
}

export const EMPTY_DRAFT: SetupDraft = {
  channels: "",
  authors: "",
  discord_token: "",
  provider: "anthropic",
  model: "",
  base_url: "",
  provider_api_key: "",
  accounts: [],
  gurus: [],
  notification: undefined,
}

/** A message for the owner: what is wrong with the setup and where to fix it. */
export class SetupProblem extends Error {}

const uid = () => crypto.randomUUID()

/** Splits on ASCII and full-width commas, so a list typed with any keyboard works. */
export const split = (value: string): string[] =>
  value
    .split(/[,，]/)
    .map((part) => part.trim())
    .filter(Boolean)

const trimLines = (value: string) => value.trim()
const length = (value: string) => [...value].length

/** "primary" for the first account, then "account-2", "account-3", … skipping names in use. */
export function nextAccountName(accounts: AccountDraft[]): string {
  const used = new Set(accounts.map((a) => a.name.trim()))
  if (!used.has("primary")) return "primary"
  let number = 2
  while (used.has(`account-${number}`)) number += 1
  return `account-${number}`
}

export const newAccount = (accounts: AccountDraft[]): AccountDraft => ({
  uid: uid(),
  name: nextAccountName(accounts),
  environment: "paper",
  policy: { ...DEFAULT_POLICY },
  key: "",
  secret: "",
})

export const newGuru = (draft: SetupDraft): GuruDraft => ({
  uid: uid(),
  channel_id: "",
  author_id: "",
  display_name: "",
  playbook: "",
  repeat_window_minutes: DEFAULT_REPEAT_WINDOW_MINUTES,
  // A new guru copies into the first account no other guru copies into.
  account_id: accountChoices(draft, null)[0] ?? "",
  full_position_usd: "",
})

/** Why the engine would refuse the name, in the owner's words; null when it is fine. */
export function accountNameProblem(name: string): string | null {
  const trimmed = name.trim()
  if (!trimmed) return "Give the account a name."
  if (/^[A-Za-z0-9_-]{1,64}$/.test(trimmed)) return null
  return [...trimmed].length > 64 ? "Keep the name to 64 characters." : "Use only letters, digits, “-” and “_” in the name: no spaces."
}

export const accountIds = (draft: SetupDraft) => draft.accounts.map((a) => a.name.trim()).filter(Boolean)

/** A guru without its own channel follows the first source channel, so a one-channel setup needs it entered once. */
export const effectiveChannel = (draft: SetupDraft, guru: GuruDraft): string =>
  guru.channel_id.trim() || split(draft.channels)[0] || ""

/** The accounts a guru may copy into: those no other guru copies into, and its own. */
export function accountChoices(draft: SetupDraft, guru: GuruDraft | null): string[] {
  const taken = new Set(draft.gurus.filter((g) => g.uid !== guru?.uid && g.account_id).map((g) => g.account_id.trim()))
  return accountIds(draft).filter((id) => !taken.has(id))
}

export const policyOf = (draft: SetupDraft, accountId: string): AccountPolicy | undefined =>
  draft.accounts.find((a) => a.name.trim() === accountId.trim())?.policy

/** The guru's full position: their own, or the account's maximum per stock when none is set. */
export const fullPosition = (draft: SetupDraft, guru: GuruDraft): string =>
  guru.full_position_usd.trim() || policyOf(draft, guru.account_id)?.max_symbol_usd.trim() || ""

/** The setup as the form shows it: a saved setup's fields, or an empty first run. */
export function draftFromSetup(saved: TradingConfiguration | null): SetupDraft {
  if (!saved) return { ...EMPTY_DRAFT, accounts: [], gurus: [] }
  const profiles = new Map(saved.profiles.map((p) => [p.profile_revision, p]))
  return {
    ...EMPTY_DRAFT,
    channels: saved.source.channel_ids.join(", "),
    authors: saved.source.author_ids.join(", "),
    provider: saved.provider.name,
    model: saved.provider.model,
    base_url: saved.provider.base_url ?? "",
    accounts: saved.accounts.map((a) => ({ uid: uid(), name: a.id, environment: a.environment, policy: { ...a.policy }, key: "", secret: "" })),
    gurus: saved.routes.map((route) => {
      const profile = profiles.get(route.profile_revision)
      const connection = route.connections[0]
      return {
        uid: uid(),
        channel_id: route.channel_id,
        author_id: route.author_id ?? "",
        display_name: profile?.display_name ?? route.guru_id,
        playbook: profile?.playbook ?? "",
        repeat_window_minutes: route.repeat_window_minutes,
        account_id: connection?.account_id ?? "",
        // A saved full position is the guru's own, even one equal to the account's maximum per stock.
        full_position_usd: connection?.full_position_usd ?? "",
      }
    }),
    notification: saved.notification,
  }
}

const hex = (bytes: ArrayBuffer) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("")
const sha256 = async (text: string) => crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))

/** A guru's id: each channel has one guru, so the channel names them (GuruIdentity.swift, route_keys.guru_for_channel). */
export async function guruId(channelId: string): Promise<string> {
  return `guru-${hex(await sha256(`discord:${channelId}`)).slice(0, 8)}`
}

/** The engine's digest of a profile (profiles.py `_profile_digest`): sorted keys, compact, non-ASCII kept. */
export async function profileRevision(guru_id: string, display_name: string, playbook: string): Promise<string> {
  return hex(await sha256(JSON.stringify({ display_name, guru_id, playbook })))
}

const POSITIVE_DECIMAL = /^\d+(\.\d+)?$/
const isPositive = (value: string) => POSITIVE_DECIMAL.test(value) && Number(value) > 0

/** The configuration to validate, built from the form; throws a `SetupProblem` in the owner's words. */
export async function buildConfiguration(draft: SetupDraft): Promise<TradingConfiguration> {
  const channels = split(draft.channels)
  if (!channels.length) throw new SetupProblem("Enter at least one Discord channel ID in Connections.")
  const model = draft.model.trim()
  if (!model) throw new SetupProblem("Enter a model name under Interpreter in Connections.")
  const addressProblem = baseUrlProblem(draft.provider, draft.base_url)
  if (addressProblem) throw new SetupProblem(`${addressProblem} Fix it under Interpreter in Connections.`)
  if (!draft.accounts.length) throw new SetupProblem("Add a broker account in Connections.")
  if (!draft.gurus.length) throw new SetupProblem("Add a guru to copy in Connections.")

  const ids = accountIds(draft)
  for (const id of ids) {
    if (accountNameProblem(id)) throw new SetupProblem(`The account name “${id}” may only use letters, digits, “-” and “_”.`)
  }
  if (new Set(ids).size !== ids.length || ids.length !== draft.accounts.length) {
    throw new SetupProblem("Each broker account needs a different name.")
  }

  const profiles = new Map<string, TradingConfiguration["profiles"][number]>()
  const routes: TradingRoute[] = []
  const copiedInto = new Map<string, string>()
  const reading = new Map<string, string>()
  for (const guru of draft.gurus) {
    const channel = effectiveChannel(draft, guru)
    const name = guru.display_name.trim()
    const playbook = trimLines(guru.playbook)
    if (!name || length(name) > 100 || length(playbook) > PLAYBOOK_MAX_LENGTH) {
      throw new SetupProblem(
        name
          ? `Each guru needs a name of up to 100 characters and a playbook under ${PLAYBOOK_MAX_LENGTH.toLocaleString("en-US")} characters.`
          : "Each guru needs a name.",
      )
    }
    if (!channel) throw new SetupProblem(`“${name}” needs a Discord channel.`)
    if (!channels.includes(channel)) {
      throw new SetupProblem(`“${name}” uses channel ${channel}, which is not listed under Discord in Connections.`)
    }
    const accountId = guru.account_id.trim()
    if (!accountId) throw new SetupProblem(`“${name}” needs an account to copy into.`)
    if (!ids.includes(accountId)) throw new SetupProblem(`“${name}” copies into “${accountId}”, which isn't one of your broker accounts.`)
    const full = fullPosition(draft, guru)
    if (!isPositive(full)) {
      throw new SetupProblem(`Set ${name}'s full position, or a max per stock for “${accountId}”: a 1/6 call buys a sixth of it.`)
    }
    const other = copiedInto.get(accountId)
    if (other) throw new SetupProblem(`“${accountId}” already copies “${other}”. Each account copies one guru.`)
    copiedInto.set(accountId, name)
    const sharing = reading.get(channel)
    if (sharing) {
      throw new SetupProblem(
        `“${sharing}” and “${name}” both read channel ${channel}. Each channel copies one guru: remove one of them, or give it its own channel.`,
      )
    }
    reading.set(channel, name)

    const guru_id = await guruId(channel)
    const profile_revision = await profileRevision(guru_id, name, playbook)
    profiles.set(profile_revision, { guru_id, display_name: name, playbook, profile_revision })
    const author = guru.author_id.trim()
    routes.push({
      source: "discord",
      channel_id: channel,
      ...(author ? { author_id: author } : {}),
      guru_id,
      profile_revision,
      connections: [{ account_id: accountId, full_position_usd: full }],
      repeat_window_minutes: guru.repeat_window_minutes,
    })
  }

  const provider: TradingProvider = {
    name: draft.provider,
    model,
    ...(acceptsBaseUrl(draft.provider) && draft.base_url.trim() ? { base_url: draft.base_url.trim() } : {}),
  }
  return {
    version: 10,
    source: { channel_ids: channels, author_ids: split(draft.authors) },
    provider,
    accounts: draft.accounts.map((a) => ({ id: a.name.trim(), environment: a.environment, policy: a.policy })),
    profiles: [...profiles.values()].sort((a, b) => (a.profile_revision < b.profile_revision ? -1 : 1)),
    routes,
    ...(draft.notification ? { notification: draft.notification } : {}),
  }
}

/** Keys the owner typed and has not saved yet, in the form `act.setSecrets` takes; null when there are none. */
export function typedSecrets(draft: SetupDraft): SecretUpdate | null {
  const brokers = draft.accounts.filter((a) => a.key && a.secret).map((a) => ({ account_id: a.name.trim(), key: a.key, secret: a.secret }))
  const update: SecretUpdate = {
    ...(draft.discord_token ? { discord_token: draft.discord_token } : {}),
    ...(draft.provider_api_key ? { provider_api_key: draft.provider_api_key } : {}),
    ...(brokers.length ? { brokers } : {}),
  }
  return Object.keys(update).length ? update : null
}

export const hasTypedKeys = (draft: SetupDraft) =>
  Boolean(draft.discord_token || draft.provider_api_key || draft.accounts.some((a) => a.key || a.secret))

/** What a check or a start covers: a digest of the setup and the typed keys, so any edit afterwards discards the result. */
export const signature = (draft: SetupDraft): string => JSON.stringify(draft, (key, value) => (key === "uid" ? undefined : value))
