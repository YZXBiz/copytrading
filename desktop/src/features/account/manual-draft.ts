import type { ManualInstruction, SourceInstruction } from "../../../shared/contract"
import { parseDec } from "./decimal"
import type { WaitingCall } from "./waiting"

// One trade the owner is about to send by hand, as plain choices (ManualInstructionDraft.swift), and the
// likeliest trade in a post the reader could not read (ManualInstructionGuess.swift). Nothing here reaches the
// engine until the owner sends it.

export type PriceChoice = "guru" | "market" | "limit"

export interface Draft {
  id: string
  isSell: boolean
  symbol: string
  /** The price the post named; empty when it named none. */
  postPrice: string
  priceChoice: PriceChoice
  /** The price sent: the post's, the market's, or one the owner typed. Empty on a sell sells at the market. */
  price: string
  /** A sell's buy price; empty sells from every buy of the stock (ADR-0010). */
  entryPrice: string
  /** A buy's share of the full position (empty buys the full position), or the share to sell ("1" sells all). */
  fraction: string
  /** A buy's dollar amount, as the post named it; empty sizes by `fraction`. */
  usdAmount: string
  exitBasis: string | null
}

const SIXTH = "0.1666666666666666666666666666666666666667"
const THIRD = "0.3333333333333333333333333333333333333333"
const TWO_THIRDS = "0.6666666666666666666666666666666666666667"

/** A sell's share of what is held, and a buy's share of the full position (empty buys the full position). */
export const SELL_SHARES = ["0.25", THIRD, "0.5", "0.75", "1"]
export const BUY_SIZES = [SIXTH, "0.25", THIRD, "0.5", ""]

const GLYPHS: Record<string, string> = { "1/6": "⅙", "1/4": "¼", "1/3": "⅓", "1/2": "½", "2/3": "⅔", "3/4": "¾" }

/** "⅙", "All", "Full", or "No size" for a buy that names none. */
export function shareTitle(share: string, isSell: boolean): string {
  if (share === "") return "No size"
  const value = Number(share)
  if (value === 1) return isSell ? "All" : "Full"
  for (let denominator = 2; denominator <= 100; denominator++) {
    const numerator = Math.round(value * denominator)
    if (numerator > 0 && Math.abs(numerator / denominator - value) < 1e-9) {
      const fraction = `${numerator}/${denominator}`
      return GLYPHS[fraction] ?? fraction
    }
  }
  return `${Math.round(value * 100)}%`
}

/** Two share strings name the same amount: "0.5" and "0.50", or a third written two ways. */
export function sameShare(a: string, b: string): boolean {
  const left = parseDec(a)
  const right = parseDec(b)
  return left === null || right === null ? a.trim() === b.trim() : left === right
}

/** The guru's price whenever the post names one, so a copy never pays the market above it; the market otherwise. */
export const defaultChoice = (postPrice: string): PriceChoice => (postPrice.trim() === "" ? "market" : "guru")

export function newDraft(): Draft {
  return { id: crypto.randomUUID(), isSell: false, symbol: "", postPrice: "", priceChoice: "market", price: "", entryPrice: "", fraction: "", usdAmount: "", exitBasis: null }
}

/** A call the engine read or held back, ready for the owner to copy (ADR-0007). */
export function draftFromCall(call: SourceInstruction): Draft {
  const postPrice = call.price ?? ""
  return {
    ...newDraft(),
    isSell: call.action !== "buy",
    symbol: call.symbol,
    postPrice,
    priceChoice: defaultChoice(postPrice),
    price: postPrice,
    entryPrice: call.entry_price ?? "",
    fraction: call.action === "close" ? "1" : (call.fraction ?? ""),
    usdAmount: call.usd_amount ?? "",
    exitBasis: call.exit_basis ?? null,
  }
}

export const draftAction = (d: Draft): ManualInstruction["action"] => (!d.isSell ? "buy" : parseDec(d.fraction) === parseDec("1") && parseDec(d.fraction) !== null ? "close" : "reduce")

/** A sell with no price sells at the market, just under the live bid (ADR-0007). */
export const sellsAtMarket = (d: Draft) => d.isSell && d.price.trim() === ""

/**
 * The draft with the price it would send. At the market a buy pays the live ask and is not ready without one;
 * a sell sends no price.
 */
export const withMarketPrice = (d: Draft, ask: string | null): Draft =>
  d.priceChoice === "market" ? { ...d, price: d.isSell ? "" : (ask ?? "") } : d

export function isValid(d: Draft): boolean {
  if (d.symbol.trim() === "") return false
  if (!sellsAtMarket(d) && !((parseDec(d.price) ?? 0n) > 0n)) return false
  const fraction = parseDec(d.fraction)
  return !d.isSell || (fraction !== null && fraction > 0n && fraction <= parseDec("1")!)
}

const orNull = (text: string) => (text.trim() === "" ? null : text.trim())

/** The engine's manual instruction for a draft. */
export function toInstruction(d: Draft): ManualInstruction {
  const action = draftAction(d)
  return {
    action,
    symbol: d.symbol.trim().toUpperCase(),
    price: sellsAtMarket(d) ? null : d.price.trim(),
    entry_price: d.isSell ? orNull(d.entryPrice) : null,
    fraction: action === "close" ? "1" : orNull(d.fraction),
    usd_amount: d.isSell ? null : orNull(d.usdAmount),
    exit_basis: d.isSell ? d.exitBasis : null,
  }
}

// ── Why the sheet is open ───────────────────────────────────────────────────

/** To approve a call an account held for approval, to copy calls the post waits on, or to say what an unreadable post should do. */
export type ReviewMode = "approve" | "copy" | "enter"

export const reviewMode = (call: WaitingCall | null): ReviewMode => (!call || call.calls.length === 0 ? "enter" : call.awaitsApproval ? "approve" : "copy")

export const MODE_TITLE: Record<ReviewMode, string> = { approve: "Approve trade", copy: "Copy trade", enter: "Enter trade" }

/** What the correction records as its reason, in the owner's words. */
export const MODE_REASON: Record<ReviewMode, string> = {
  approve: "Copied a call that was waiting for me",
  copy: "Copied a call that was waiting for me",
  enter: "Entered the trade the post asked for",
}

// ── The likeliest trade in a post's words ───────────────────────────────────

const SELL_WORDS = new Set(["sell", "sold", "selling", "trim", "trimmed", "trimming", "close", "closed", "closing", "cut", "exit", "exited", "dump", "out", "tp"])
/** Words that by themselves mean selling everything. */
const SELL_ALL_WORDS = new Set(["close", "closed", "closing", "exit", "exited", "dump", "out"])
const BUY_WORDS = new Set(["buy", "bought", "buying", "add", "added", "adding", "long", "enter", "entered", "starter", "open", "opened"])
/** Short words that look like tickers in a post written in capitals. */
const NOT_TICKERS = new Set(
  ("I A AT THE AND OR TO OF IN ON FOR IS IT MY ALL HALF BUY SELL TP PT SL OUT ADD CUT NOW USD ETF AM PM EOD LOL IMO ATH GO UP NO SO BE WE ME AN AS BY IF OK SOME MORE BACK THIS THAT HERE MOST FEW AGAIN SHARE BIT").split(" "),
)

const words = (lowered: string) =>
  lowered
    .split(/[\s,!?;:()"“”]+/)
    .map((w) => w.replace(/^\.+|\.+$/g, ""))
    .filter(Boolean)

/** The share a post names: "half", "a third", "1/4", "25%", "all". */
export function share(lowered: string): string | null {
  const joined = ` ${words(lowered).join(" ")} `
  const named: [string, string][] = [
    [" three quarters ", "0.75"], [" 3/4 ", "0.75"], [" 75% ", "0.75"],
    [" two thirds ", TWO_THIRDS], [" 2/3 ", TWO_THIRDS],
    [" half ", "0.5"], [" 1/2 ", "0.5"], [" 50% ", "0.5"],
    [" third ", THIRD], [" 1/3 ", THIRD],
    [" quarter ", "0.25"], [" 1/4 ", "0.25"], [" 25% ", "0.25"],
    [" sixth ", SIXTH], [" 1/6 ", SIXTH],
    [" all ", "1"], [" everything ", "1"], [" rest ", "1"], [" full ", "1"],
  ]
  return named.find(([phrase]) => joined.includes(phrase))?.[1] ?? null
}

/** The first plain number in a post that isn't a share: "wmt 1/6 110" → "110". */
export function priceIn(text: string): string | null {
  for (const word of words(text.toLowerCase())) {
    if (word.includes("/") || word.endsWith("%")) continue
    const digits = word.replace(/^[$@]+|[$@]+$/g, "")
    if (/^\d+(\.\d+)?$/.test(digits) && Number(digits) > 0 && Number(digits) <= 10_000_000) return digits
  }
  return null
}

/** A held stock the post names in any case, else a `$TICKER` or a word in capitals. */
export function symbolIn(text: string, held: string[]): string | null {
  const raw = text.split(/[\s,.!?;:()"“”']+/).filter(Boolean)
  const bare = raw.map((w) => w.replace(/^[$#]+|[$#]+$/g, "").toUpperCase())
  const heldMatch = bare.find((w) => held.includes(w))
  if (heldMatch) return heldMatch
  const cashtag = raw.find((w) => w.startsWith("$") && w.length > 1 && /^\p{L}+$/u.test(w.slice(1)))
  if (cashtag) return cashtag.slice(1).toUpperCase()
  const capitals = raw.find((w) => w.length >= 1 && w.length <= 5 && /^\p{Lu}+$/u.test(w) && !NOT_TICKERS.has(w))
  if (capitals) return capitals
  // A post in lower case: the first short word after "sell" or "buy" that isn't a filler ("buy some nvda").
  const lowered = raw.map((w) => w.toLowerCase())
  for (const [index, word] of lowered.entries()) {
    if (!SELL_WORDS.has(word) && !BUY_WORDS.has(word)) continue
    for (const next of bare.slice(index + 1, index + 4)) {
      if (NOT_TICKERS.has(next) || share(next.toLowerCase()) !== null) continue
      if (next.length >= 1 && next.length <= 5 && /^\p{L}+$/u.test(next)) return next
      break
    }
  }
  return null
}

/** A buy or a sell guessed from `text`, with the stock matched first against `held`; null when the post names neither a direction nor a stock. */
export function guessDraft(text: string, held: string[]): Draft | null {
  const lowered = text.toLowerCase()
  const parts = words(lowered)
  const sells = parts.some((w) => SELL_WORDS.has(w)) || lowered.includes("take profit")
  const buys = parts.some((w) => BUY_WORDS.has(w))
  const symbol = symbolIn(text, held)
  if (!sells && !buys && symbol === null) return null
  const draft = newDraft()
  // A post that both buys and sells reads as a sell when the stock is already held.
  draft.isSell = sells && (!buys || (symbol !== null && held.includes(symbol)))
  draft.symbol = symbol ?? ""
  draft.postPrice = priceIn(text) ?? ""
  draft.priceChoice = defaultChoice(draft.postPrice)
  draft.price = draft.postPrice
  const named = share(lowered)
  if (named) draft.fraction = named
  else if (draft.isSell && parts.some((w) => SELL_ALL_WORDS.has(w))) draft.fraction = "1"
  if (!draft.isSell && draft.fraction === "1") draft.fraction = ""
  return draft
}
