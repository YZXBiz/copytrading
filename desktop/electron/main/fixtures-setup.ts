import type { Result, SecretStatus, SetupView, TradingConfiguration, TradingStatus } from "../../shared/contract"

// The setup the Connections and Getting Started screens read in fixture mode. The guru's id and profile revision are the
// engine's own digests (guru-927e2da2 = sha256("discord:1100000000000000001")[:8]), so the form reads this setup as saved.
// COPYTRADING_FIXTURE_SETUP=none shows a first run; COPYTRADING_FIXTURE_TRADING=paused|running|degraded sets copying.

const CHANNEL = "1100000000000000001"
const REVISION = "658cae5cd6e59b372cad69696b464021d78c388f4cb79741821213e39a3c498e"

const configuration: TradingConfiguration = {
  version: 10,
  source: { channel_ids: [CHANNEL], author_ids: [] },
  provider: { name: "deepseek", model: "deepseek-flash" },
  accounts: [
    {
      id: "zhap-account-2",
      environment: "paper",
      policy: {
        max_order_usd: "200",
        max_symbol_usd: "1000",
        max_total_usd: "3000",
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
      },
    },
  ],
  profiles: [
    {
      guru_id: "guru-927e2da2",
      display_name: "赵哥",
      playbook: '买入 "BUY SOXS 40.45" 这样的消息才是下单。闲聊和图表忽略。',
      profile_revision: REVISION,
    },
  ],
  routes: [
    {
      source: "discord",
      channel_id: CHANNEL,
      guru_id: "guru-927e2da2",
      profile_revision: REVISION,
      connections: [{ account_id: "zhap-account-2", full_position_usd: "1000" }],
      repeat_window_minutes: 10,
    },
  ],
}

const first = process.env.COPYTRADING_FIXTURE_SETUP === "none"
const saved: SetupView = { configuration, revision: "c0ffee".repeat(10) + "c0ff", keys_present: true, pending_activation: null }
const keys = (on: boolean): SecretStatus => ({ discord_token: on, provider_api_key: on, notification_token: false, brokers: on ? { "zhap-account-2": true } : {} })
const trading = (): TradingStatus => {
  const state = process.env.COPYTRADING_FIXTURE_TRADING
  const degraded = state === "degraded"
  return {
    state: state === "paused" ? "paused" : degraded ? "degraded" : "running",
    configured_accounts: first ? 0 : 1,
    active_accounts: state === "paused" || degraded ? 0 : 1,
    source_connected: true,
    model_ready: true,
    error_code: degraded ? "broker_unreachable" : null,
    ...(degraded ? { accounts: [{ id: "zhap-account-2", state: "failed", error_code: "broker_unreachable" }] } : {}),
  }
}

const ok = async <T>(value: T): Promise<Result<T>> => ({ ok: true, value })

export const setupReads: Record<string, () => Promise<Result<unknown>>> = {
  // The people fixtures (Gurus, Activity) have their own getSetup; this one answers only the setup captures that ask for it.
  ...(process.env.COPYTRADING_FIXTURE_SETUP ? { getSetup: () => ok(first ? null : saved) } : {}),
  getSecretStatus: () => ok(keys(!first)),
  getStatus: () => ok(trading()),
}
