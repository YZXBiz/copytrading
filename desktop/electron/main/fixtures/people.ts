import { createHash } from "node:crypto"
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { crc32, deflateSync } from "node:zlib"
import type {
  DestinationActivity,
  GuruDayStats,
  OrderActivity,
  ReadCall,
  Result,
  SetupView,
  SourceActivity,
  SourceActivityPage,
  SourceInstruction,
} from "../../../shared/contract"
import activity from "./activity.json"

// Posts, gurus and a captured picture for the Activity and Gurus screens. The texts are the real posts
// captured Nov 3; the orders and readings around them are written in the engine's wire shape.

const ACCOUNT = "zhap-account-2"
const ZHAO = "赵哥"
const CRYPTO = "赵哥-加密"
const REVISION = "3f5a0c9d1e7b24a86c0d9e1f4a7b3c52d8e6f0a1b2c3d4e5f60718293a4b5c6d"
const CRYPTO_REVISION = "9a8b7c6d5e4f30211203f4e5d6c7b8a99a8b7c6d5e4f30211203f4e5d6c7b8a9"

const policy = {
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
  // COPYTRADING_FIXTURE_SCENE=stops is an account that follows the guru's stops.
  follow_stops: process.env.COPYTRADING_FIXTURE_SCENE === "stops",
  max_above_signal_pct: "0",
  max_below_signal_pct: "1",
  recovery_preference: "manual",
} as const

const setup: SetupView = {
  configuration: {
    version: 10,
    source: { channel_ids: ["1100000000000000001", "1100000000000000002"], author_ids: [] },
    provider: { name: "deepseek", model: "deepseek-flash" },
    accounts: [{ id: ACCOUNT, environment: "paper", policy }],
    profiles: [
      { guru_id: ZHAO, display_name: ZHAO, playbook: "", profile_revision: REVISION },
      { guru_id: CRYPTO, display_name: CRYPTO, playbook: "", profile_revision: CRYPTO_REVISION },
    ],
    routes: [ZHAO, CRYPTO].map((guru, index) => ({
      source: "discord",
      channel_id: `110000000000000000${index + 1}`,
      guru_id: guru,
      profile_revision: guru === ZHAO ? REVISION : CRYPTO_REVISION,
      connections: [{ account_id: ACCOUNT, full_position_usd: "1000" }],
      repeat_window_minutes: 10,
    })),
  },
  revision: "a".repeat(64),
  keys_present: true,
  pending_activation: null,
}

// ── The captured picture: a small chart-like PNG, written where the engine keeps attachments ──

function png(width: number, height: number, pixel: (x: number, y: number) => [number, number, number]): Buffer {
  const chunk = (type: string, data: Buffer) => {
    const body = Buffer.concat([Buffer.from(type, "latin1"), data])
    const out = Buffer.alloc(data.length + 12)
    out.writeUInt32BE(data.length, 0)
    body.copy(out, 4)
    out.writeUInt32BE(crc32(body), data.length + 8)
    return out
  }
  const header = Buffer.alloc(13)
  header.writeUInt32BE(width, 0)
  header.writeUInt32BE(height, 4)
  header.set([8, 2, 0, 0, 0], 8)
  const rows = Buffer.alloc((width * 3 + 1) * height)
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) rows.set(pixel(x, y), y * (width * 3 + 1) + 1 + x * 3)
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0)),
  ])
}

const PICTURE = png(360, 180, (x, y) => {
  const line = 150 - x * 0.28 - 14 * Math.sin(x / 18)
  if (Math.abs(y - line) < 2.2) return [74, 190, 120]
  return y > line ? [34, 42, 56] : [26, 32, 44]
})
const PICTURE_SHA = createHash("sha256").update(PICTURE).digest("hex")
const PICTURE_ID = "a1b2c3d4e5f60718293a4b5c6d7e8f90"

/** Writes the fixture picture as the engine stores one; returns the attachments folder. */
export function seedFixturePictures(): string {
  const dir = join(mkdtempSync(join(tmpdir(), "copytrading-fixture-")), "attachments")
  mkdirSync(join(dir, PICTURE_SHA.slice(0, 2)), { recursive: true })
  writeFileSync(join(dir, PICTURE_SHA.slice(0, 2), PICTURE_SHA), PICTURE)
  return dir
}

// ── Posts ──

const exact = (value: string, words: string) => ({ kind: "exact", value, words }) as const

function order(client_id: string, o: Partial<OrderActivity> & Pick<OrderActivity, "symbol" | "side" | "status" | "created_at">): OrderActivity {
  return {
    client_id,
    quantity: "0",
    filled_quantity: "0",
    limit_price: null,
    average_fill_price: null,
    broker_id: null,
    instruction_index: 0,
    ...o,
  }
}

const destination = (status: string, instruction_outcomes: string[], orders: OrderActivity[] = [], timeline?: DestinationActivity["timeline"]): DestinationActivity => ({
  account_id: ACCOUNT,
  environment: "paper",
  status,
  instruction_outcomes,
  orders,
  ...(timeline && { timeline }),
})

type Step = NonNullable<DestinationActivity["timeline"]>[number]
/** The account's steps as the engine writes them: each a name and the seconds after the post, with the order it belongs to. */
const steps = (posted: string, rows: [step: string, seconds: number, extra?: Partial<Step>][]): Step[] =>
  rows.map(([step, seconds, extra]) => ({ step, at: new Date(Date.parse(posted) + seconds * 1000).toISOString(), client_id: null, reason: null, quantity: null, price: null, ...extra }))

type Draft = Omit<SourceActivity, "sequence" | "source_id" | "decision" | "guru_id" | "instructions" | "destinations"> &
  Partial<Pick<SourceActivity, "decision" | "guru_id" | "instructions" | "destinations">>

const drafts: Draft[] = [
  // Newest first.
  { ...real(0), reading: { kind: "chatter" } },
  {
    ...real(1),
    decision: "review",
    parser_reason: "suggestion",
    reading: {
      kind: "suggestion",
      summary: "Suggests trimming a tenth of CIFR near $7.95",
      calls: [
        { action: "sell", action_words: "出", stock: { ticker: "CIFR", words: "cifr" }, price: { kind: "exact", value: "7.95", words: "7.95" }, share: { kind: "fraction", value: "0.1", words: "10%" }, sell_from: { kind: "not_said" } },
      ],
    },
    instructions: [{ action: "reduce", symbol: "CIFR", price: "7.95", fraction: "0.1" }],
    suggested: [{ action: "reduce", symbol: "CIFR", price: "7.95", fraction: "0.1" }],
    destinations: [destination("review_required", [])],
  },
  {
    source_at: "2026-11-03T17:20:08Z",
    text: "SOXL 89.37 进一成仓",
    decision: "trade",
    interpreted_by: "deepseek-flash",
    reading: {
      kind: "trade_made",
      summary: "Bought SOXL at $89.37",
      calls: [{ action: "buy", action_words: "进", stock: { ticker: "SOXL", words: "SOXL" }, price: exact("89.37", "89.37"), size: { kind: "fraction", value: "0.1", words: "一成仓" } }],
    },
    instructions: [{ action: "buy", symbol: "SOXL", price: "89.37" }],
    destinations: [
      destination(
        "delivered",
        ["order_linked"],
        [
          order("sig-soxl-1", {
            symbol: "SOXL",
            side: "buy",
            status: "filled",
            quantity: "1.119",
            filled_quantity: "1.119",
            limit_price: "89.37",
            average_fill_price: "89.31",
            created_at: "2026-11-03T17:20:10Z",
            requested_usd: "100",
            budget_usd: "100",
          }),
        ],
        steps("2026-11-03T17:20:08Z", [
          ["received", 4.2],
          ["sized", 4.4, { client_id: "sig-soxl-1", quantity: "1.119", price: "89.37" }],
          ["sent", 4.6, { client_id: "sig-soxl-1" }],
          ["accepted", 5.1, { client_id: "sig-soxl-1" }],
          ["filled", 6.3, { client_id: "sig-soxl-1", quantity: "1.119", price: "89.31" }],
        ]),
      ),
    ],
  },
  { ...real(2), reading: { kind: "chatter" } },
  {
    source_at: "2026-11-03T15:05:44Z",
    text: "赵哥-股票：",
    decision: "ignore",
    reading: { kind: "chatter" },
    source_event: {
      event_type: "message_create",
      message_id: "1300000000000000001",
      channel_id: "1100000000000000001",
      author_id: "1200000000000000001",
      timestamp: "2026-11-03T15:05:44Z",
      content: "赵哥-股票：",
      embeds: [],
      attachments: [
        { evidence_id: PICTURE_ID, attachment_id: "1400000000000000001", filename: "chart.png", content_type: "image/png", declared_size: PICTURE.length, status: "available", byte_size: PICTURE.length, sha256: PICTURE_SHA, omitted_count: 0 },
      ],
      attachments_omitted: 0,
      capture_status: "complete",
      payload_bytes: 600,
    },
  },
  {
    source_at: "2026-11-03T14:30:02Z",
    text: "BUY SOXS 40.45",
    decision: "trade",
    interpreted_by: "deepseek-flash",
    reading: {
      kind: "trade_made",
      summary: "Bought SOXS at $40.45",
      calls: [{ action: "buy", action_words: "BUY", stock: { ticker: "SOXS", words: "SOXS" }, price: exact("40.45", "40.45"), size: { kind: "not_given" } }],
    },
    instructions: [{ action: "buy", symbol: "SOXS", price: "40.45" }],
    destinations: [
      destination(
        "delivered",
        ["order_linked"],
        [
          order("sig-soxs-1", {
            symbol: "SOXS",
            side: "buy",
            status: "canceled",
            cancel_reason: "timeout",
            quantity: "2.469",
            limit_price: "40.45",
            created_at: "2026-11-03T14:30:05Z",
            submitted_at: "2026-11-03T14:30:05Z",
            ended_at: "2026-11-03T14:31:05Z",
            requested_usd: "200",
            budget_usd: "100",
            limited_by: "largest_single_buy",
            source_price: "40.45",
            entry_tolerance_pct: "0",
            quote_ask: "40.62",
          }),
        ],
        steps("2026-11-03T14:30:02Z", [
          ["received", 4.2],
          ["sized", 4.5, { client_id: "sig-soxs-1", quantity: "2.469", price: "40.45" }],
          ["sent", 4.7, { client_id: "sig-soxs-1" }],
          ["accepted", 5.1, { client_id: "sig-soxs-1" }],
          ["cancel_requested", 65.1, { client_id: "sig-soxs-1", reason: "timeout" }],
          ["cancelled", 65.8, { client_id: "sig-soxs-1" }],
        ]),
      ),
    ],
  },
  { ...real(3), decision: "review", parser_reason: "unclear", reading: { kind: "unclear", summary: "Talks about premarket trims without naming one trade" }, destinations: [destination("review_required", [])] },
  {
    ...real(4),
    interpreted_by: "deepseek-flash",
    reading: {
      kind: "trade_made",
      summary: "Sold all AEHR at $61.50",
      calls: [{ action: "sell", action_words: "出了", stock: { ticker: "AEHR", words: "aehr" }, price: exact("61.5", "61.5"), share: { kind: "all", words: "出了" }, sell_from: { kind: "not_said" } }],
    },
    instructions: [{ action: "close", symbol: "AEHR", price: "61.50" }],
    destinations: [destination("delivered", ["no_open_lot"], [], steps("2026-11-02T21:13:43Z", [["received", 4.2], ["skipped", 4.4, { reason: "no_open_lot" }]]))],
  },
  { ...real(5), reading: { kind: "chatter" } },
]

/** The real captured post `index` of activity.json, as a draft. */
function real(index: number): Draft & { decision: SourceActivity["decision"] } {
  const post = activity[index]!
  return { source_at: post.at, text: post.text, decision: post.decision as SourceActivity["decision"] }
}

// Real captured posts come in time order newest first, with the written ones between: sort once.
const crypto: Draft = {
  source_at: "2026-11-02T15:00:12Z",
  text: "SOL 142 进",
  guru_id: CRYPTO,
  decision: "trade",
  reading: {
    kind: "trade_made",
    summary: "Bought $100 of SOL",
    calls: [{ action: "buy", action_words: "进", stock: { ticker: "SOL/USD", words: "SOL" }, price: exact("142", "142"), size: { kind: "dollars", value: "100", words: "100" } }],
  },
  instructions: [{ action: "buy", symbol: "SOL/USD", price: "142", usd_amount: "100" }],
  destinations: [
    destination("delivered", ["order_linked"], [
      order("sig-sol-1", { symbol: "SOL/USD", side: "buy", status: "filled", quantity: "0.704", filled_quantity: "0.704", limit_price: "142", average_fill_price: "141.9", created_at: "2026-11-02T15:00:14Z", requested_usd: "100", budget_usd: "100" }),
    ], steps("2026-11-02T15:00:12Z", [
      ["received", 4.2],
      ["held", 4.2, { reason: "waiting_for_resume" }],
      ["resumed", 1325.4],
      ["sized", 1325.7, { client_id: "sig-sol-1", quantity: "0.704", price: "142" }],
      ["sent", 1325.9, { client_id: "sig-sol-1" }],
      ["accepted", 1326.3, { client_id: "sig-sol-1" }],
      ["partially_filled", 1327.1, { client_id: "sig-sol-1", quantity: "0.3", price: "141.9" }],
      ["filled", 1329.8, { client_id: "sig-sol-1", quantity: "0.704", price: "141.9" }],
    ])),
  ],
}

// COPYTRADING_FIXTURE_SCENE=calls puts six calls in front of the owner, quiet none, empty no posts and no holdings, for `npm run capture`.
const scene = process.env.COPYTRADING_FIXTURE_SCENE

const suggestion = (source_at: string, text: string, call: SourceInstruction): Draft => ({
  source_at,
  text,
  decision: "review",
  parser_reason: "suggestion",
  reading: { kind: "suggestion", summary: text, calls: [] },
  instructions: [call],
  suggested: [call],
  destinations: [destination("review_required", [])],
})

const extraCalls: Draft[] =
  scene === "calls"
    ? [
        suggestion("2026-11-03T16:42:10Z", "AMD 168.2 进一成仓", { action: "buy", symbol: "AMD", price: "168.20" }),
        suggestion("2026-11-03T15:58:30Z", "NVDA 188.5 出一半", { action: "reduce", symbol: "NVDA", price: "188.50", entry_price: "150.00", fraction: "0.5" }),
        suggestion("2026-11-03T17:05:44Z", "SOFI 24.6 进", { action: "buy", symbol: "SOFI", price: "24.60" }),
        suggestion(
          "2026-11-03T18:30:19Z",
          "今天先观察 TSLA，如果回踩 410 附近可以考虑少量进，注意仓位控制，不要一次打满，下午再看一次量能和大盘的方向再决定要不要加",
          { action: "buy", symbol: "TSLA", price: "410.00" },
        ),
      ]
    : []

// COPYTRADING_FIXTURE_SCENE=reasons adds one call for each reason a call waits for besides a suggestion: a sell whose named buy never
// filled, a sell whose named buy never reached the account, a condition, and an account that approves each order.
const heldSell = (source_at: string, text: string, symbol: string, price: string, entry_price: string, named: { posted_at: string | null; outcome: string | null }): Draft => ({
  source_at,
  text,
  decision: "trade",
  reading: { kind: "trade_made", summary: text, calls: [] },
  instructions: [{ action: "close", symbol, price, entry_price }],
  destinations: [{ ...destination("delivered", ["named_buy_not_held"]), named_buys: [{ part: 0, ...named }] }],
})

const reasonCalls: Draft[] =
  scene === "reasons"
    ? [
        heldSell("2026-11-03T16:10:00Z", "NVDA 188.5 出 150进的", "NVDA", "188.50", "150.00", { posted_at: "2026-11-03T14:10:00Z", outcome: "not_filled" }),
        heldSell("2026-11-03T15:30:00Z", "AEHR 61.5 出 44.1进的", "AEHR", "61.50", "44.10", { posted_at: null, outcome: null }),
        {
          source_at: "2026-11-03T17:35:00Z",
          text: "如果 TSLA 站上 420 就进",
          decision: "review",
          parser_reason: "conditional",
          reading: { kind: "conditional", summary: "Would buy TSLA if it holds above $420", condition: "TSLA holds above $420", calls: [] },
          instructions: [{ action: "buy", symbol: "TSLA", price: "420.00" }],
          destinations: [destination("review_required", [])],
        },
        {
          source_at: "2026-11-03T18:00:00Z",
          text: "AMD 168.2 进",
          decision: "trade",
          reading: { kind: "trade_made", summary: "Bought AMD at $168.20", calls: [] },
          instructions: [{ action: "buy", symbol: "AMD", price: "168.20" }],
          destinations: [destination("delivered", ["approval_required"])],
        },
      ]
    : []

// COPYTRADING_FIXTURE_SCENE=busy adds a day of fills and chat to Nov 3; empty has no posts at all.
const filled = (source_at: string, text: string, symbol: string, price: string, quantity: string): Draft => ({
  source_at,
  text,
  decision: "trade",
  interpreted_by: "deepseek-flash",
  reading: {
    kind: "trade_made",
    summary: `Bought ${symbol} at $${price}`,
    calls: [{ action: "buy", action_words: "进", stock: { ticker: symbol, words: symbol }, price: exact(price, price), size: { kind: "not_given" } }],
  },
  instructions: [{ action: "buy", symbol, price }],
  destinations: [
    destination("delivered", ["order_linked"], [
      order(`sig-${symbol}-${source_at}`, { symbol, side: "buy", status: "filled", quantity, filled_quantity: quantity, limit_price: price, average_fill_price: price, created_at: source_at, requested_usd: "100", budget_usd: "100" }),
    ]),
  ],
})
const chat = (source_at: string, text: string): Draft => ({ source_at, text, decision: "ignore", reading: { kind: "chatter" } })

const busyDay: Draft[] =
  scene === "busy"
    ? [
        chat("2026-11-03T13:02:11Z", "早上好各位，今天关注科技股"),
        filled("2026-11-03T13:31:40Z", "AMD 167.4 进", "AMD", "167.40", "0.597"),
        chat("2026-11-03T13:48:02Z", "大盘高开，别追"),
        filled("2026-11-03T14:05:19Z", "PLTR 71.2 进", "PLTR", "71.20", "1.404"),
        chat("2026-11-03T14:12:55Z", "看到这个量能我就放心了"),
        filled("2026-11-03T15:21:07Z", "NVDA 186.9 进", "NVDA", "186.90", "0.535"),
        chat("2026-11-03T15:40:30Z", "午饭时间，下午再看"),
        filled("2026-11-03T16:02:48Z", "TSLA 405.5 进", "TSLA", "405.50", "0.247"),
        chat("2026-11-03T16:15:12Z", "都冷静点，没到位置"),
        filled("2026-11-03T16:50:33Z", "SOFI 24.3 进", "SOFI", "24.30", "4.115"),
        chat("2026-11-03T18:04:21Z", "收盘前不动"),
        filled("2026-11-03T18:45:09Z", "INTC 36.8 进", "INTC", "36.80", "2.717"),
      ]
    : []

// COPYTRADING_FIXTURE_SCENE=stops is an account that follows the guru's stops: one stop resting on its SOXL, one that filled.
// stops-off is an account that does not (the default setting): the same TQQQ post, skipped.
const stopOrder = (client_id: string, o: Partial<OrderActivity> & Pick<OrderActivity, "symbol" | "status" | "created_at">): OrderActivity =>
  order(client_id, { side: "sell", order_type: "stop", ...o })
const stopPost = (source_at: string, text: string, symbol: string, price: string, entry: string | null, outcome: string, orders: OrderActivity[]): Draft => ({
  source_at,
  text,
  decision: "trade",
  interpreted_by: "deepseek-flash",
  reading: {
    kind: "trade_made",
    summary: `A stop on ${symbol} at $${price}`,
    calls: [
      {
        action: "stop",
        action_words: "跌破",
        stock: { ticker: symbol, words: symbol.toLowerCase() },
        price: exact(price, price),
        protects: entry ? { kind: "lot", buy_price: entry, words: entry } : { kind: "not_said" },
      },
    ],
  },
  stops: [{ symbol, stop_price: price, entry_price: entry }],
  destinations: [{ ...destination("done", [], orders, orders.length > 0 ? stopSteps(source_at, orders[0]!) : steps(source_at, [["received", 4.2], ["skipped", 4.4, { reason: outcome }]])), stop_outcomes: [outcome] }],
})
/** A stop's steps: placed a few seconds after the post, and when it filled, hours later. */
const stopSteps = (posted: string, o: OrderActivity): Step[] =>
  steps(posted, [
    ["received", 4.2],
    ["sized", 4.6, { client_id: o.client_id, quantity: o.quantity, price: o.stop_price }],
    ["sent", 4.8, { client_id: o.client_id }],
    ["accepted", 9.2, { client_id: o.client_id }],
    ...(o.status === "filled" ? ([["filled", 7_380, { client_id: o.client_id, quantity: o.filled_quantity, price: o.average_fill_price }]] as [string, number, Partial<Step>][]) : []),
  ])
const stopDrafts: Draft[] =
  scene === "stops"
    ? [
        stopPost("2026-11-03T19:05:12Z", "剩下的一点soxl做个跌破44.5全出的保护 或者不想博弈全出都可以 扛不住要休息下了", "SOXL", "44.5", null, "order_linked", [
          stopOrder("stp-soxl-1", { symbol: "SOXL", status: "accepted", quantity: "6.679793", stop_price: "44.5", created_at: "2026-11-03T19:05:20Z" }),
        ]),
        stopPost("2026-11-03T18:20:41Z", "剩下一半49.5的tqqq 设置下 跌破50.95出剩下的保护", "TQQQ", "50.95", "49.5", "order_linked", [
          stopOrder("stp-tqqq-1", { symbol: "TQQQ", status: "filled", quantity: "12.5", filled_quantity: "12.5", stop_price: "50.95", average_fill_price: "50.9", created_at: "2026-11-03T18:20:50Z" }),
        ]),
      ]
    : scene === "stops-off"
      ? [stopPost("2026-11-03T18:20:41Z", "剩下一半49.5的tqqq 设置下 跌破50.95出剩下的保护", "TQQQ", "50.95", "49.5", "follow_stops_off", [])]
      : []

const sorted = (scene === "empty" ? [] : [...drafts, ...extraCalls, ...reasonCalls, ...busyDay, ...stopDrafts, crypto])
  .filter((draft) => scene !== "quiet" || !draft.destinations?.some((d) => d.status === "review_required"))
  .sort((a, b) => Date.parse(a.source_at) - Date.parse(b.source_at))

export const posts: SourceActivity[] = sorted
  .map((draft, index) => ({
    guru_id: ZHAO,
    decision: null,
    instructions: [],
    destinations: [],
    ...draft,
    sequence: index + 1,
    // The channel of the guru's route, as the engine writes it: Activity shows only the channels the setup follows.
    source_id: `discord:110000000000000000${(draft.guru_id ?? ZHAO) === CRYPTO ? 2 : 1}:${index + 1}`,
    captured_at: new Date(Date.parse(draft.source_at) + 500).toISOString(),
    capture_status: "delivered",
    delivery_status: "delivered",
    read_started_at: new Date(Date.parse(draft.source_at) + 1000).toISOString(),
    read_at: new Date(Date.parse(draft.source_at) + 4000).toISOString(),
  }))
  .reverse()

// ── The reads ──

type Params = Record<string, unknown> | undefined
const ok = async <T>(value: T): Promise<Result<T>> => ({ ok: true, value })

function page(items: SourceActivity[], params: Params): SourceActivityPage {
  const before = typeof params?.before_seq === "number" ? params.before_seq : Infinity
  const limit = typeof params?.limit === "number" ? params.limit : 50
  const older = items.filter((p) => p.sequence < before)
  const shown = older.slice(0, limit)
  return { items: shown, next_before_seq: older.length > shown.length ? shown[shown.length - 1]!.sequence : null }
}

const isWaiting = (p: SourceActivity) => p.destinations.some((d) => d.status === "review_required")

function dayStats(params: Params): GuruDayStats[] {
  const [start, end] = [Date.parse(String(params?.day_start)), Date.parse(String(params?.day_end))]
  return [ZHAO, CRYPTO].map((guru) => {
    const mine = posts.filter((p) => p.guru_id === guru)
    const today = mine.filter((p) => Date.parse(p.source_at) >= start && Date.parse(p.source_at) < end)
    return {
      guru_id: guru,
      posts: today.length,
      traded: today.filter((p) => p.destinations.some((d) => (d.orders ?? []).some((o) => o.filled_quantity !== "0"))).length,
      read_seconds: today.length ? 3.2 : null,
      waiting: mine.filter(isWaiting),
    }
  })
}

export const peopleReads: Record<string, (params: Params) => Promise<Result<unknown>>> = {
  getSetup: () => ok(setup),
  getSourceActivity: (params) => ok(page(posts, params)),
  getGuruActivity: (params) => ok(page(posts.filter((p) => p.guru_id === params?.guru_id), params)),
  getGuruDayStats: (params) => ok({ day_start: params?.day_start ?? "", day_end: params?.day_end ?? "", gurus: dayStats(params) }),
}
