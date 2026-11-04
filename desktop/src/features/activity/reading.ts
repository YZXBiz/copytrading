import type { PostReading, ReadCall, ReadPrice, ReadShare, ReadSize, SourceActivity, SourceInstruction } from "../../../shared/contract"
import { dollars, fraction, num } from "./amounts"
import { codeWords } from "./reasons"

// How the reader read a post, in plain words (ReadAsText.swift, SourceActivity+Display.swift).

const capitalize = (text: string) => text.charAt(0).toUpperCase() + text.slice(1)

/** A share as a person says it: "half", "a third", "a sixth", else "1/5". */
export function portion(value: string): string {
  switch (fraction(value)) {
    case "1": return "all"
    case "1/2": return "half"
    case "1/3": return "a third"
    case "1/4": return "a quarter"
    case "1/6": return "a sixth"
    default: return fraction(value)
  }
}

const price = (p: ReadPrice): string => {
  switch (p.kind) {
    case "exact": return `at ${dollars(p.value)}`
    case "range": return `between ${dollars(p.low)} and ${dollars(p.high)}`
    case "at_market": return "at the market price"
    case "not_given": return "with no price given"
  }
}

const size = (s: ReadSize): string => {
  switch (s.kind) {
    case "fraction": return `, ${portion(s.value)} of a full position`
    case "batch": return `, batch ${s.number}`
    case "dollars": return `, ${dollars(s.value)} worth`
    case "not_given": return ""
  }
}

const share = (s: ReadShare): string => (s.kind === "all" ? "all" : s.kind === "fraction" ? portion(s.value) : "some")

export function kindText(reading: PostReading): string {
  switch (reading.kind) {
    case "trade_made": return "a trade the guru made"
    case "instruction": return "an instruction"
    case "conditional": return "a condition"
    case "suggestion": return "a suggestion"
    case "commentary": return "talk, nothing to trade"
    case "chatter": return "just chat"
    case "unclear": return "unclear"
  }
}

export const callsOf = (reading: PostReading): ReadCall[] => ("calls" in reading ? reading.calls : [])

/** A call as its headline and the phrase under it: "Buy WMT at $110" and "A sixth of a full position". */
export function callHeadline(call: ReadCall): { title: string; detail: string | null } {
  if (call.action === "buy") {
    const title = `Buy ${call.stock.ticker} ${price(call.price)}`
    switch (call.size.kind) {
      case "fraction": return { title, detail: capitalize(`${portion(call.size.value)} of a full position`) }
      case "batch": return { title, detail: `Batch ${call.size.number}` }
      case "dollars": return { title: `Buy ${dollars(call.size.value)} of ${call.stock.ticker} ${price(call.price)}`, detail: null }
      case "not_given": return { title, detail: null }
    }
  }
  const from = call.sell_from.kind === "lot" ? ` of the ${call.stock.ticker} bought at ${dollars(call.sell_from.buy_price)}` : ` of ${call.stock.ticker}`
  return { title: `Sell ${share(call.share)}${from}`, detail: capitalize(price(call.price)) }
}

/** What a call's sentence leaves implicit: a buy with no size buys a full position, a sell naming no buy sells from every buy. */
export function callNote(call: ReadCall): string | null {
  if (call.action === "buy") return call.size.kind === "not_given" ? "no size given, so a full position" : null
  return call.sell_from.kind === "lot" ? null : "from every buy of it"
}

export const isRepost = (call: ReadCall) => Boolean(call.repeats)

/** The sentence a post with no calls gets: the reader's own summary, or what kind of post it was. */
export function noCallLine(reading: PostReading): string {
  switch (reading.kind) {
    case "commentary": return reading.summary
    case "chatter": return "Just chat, nothing to trade"
    case "unclear": return "The reader couldn't tell what this post means."
    default: return reading.summary
  }
}

// ── What the post asked for, in one phrase ──

/** "Buy ABC at $12.34", "Sell half of ABC at $14", "Sell all ABC at the market price". */
export function instructionPhrase(i: SourceInstruction): string {
  const at = num(i.price) === null ? "the market price" : dollars(i.price)
  if (i.action === "buy") return `Buy ${i.symbol} at ${at}`
  if (i.action === "close") return `Sell all ${i.symbol} at ${at}`
  return `Sell ${i.fraction ? portion(i.fraction) : "some"} of ${i.symbol} at ${at}`
}

/** The post's own words with only mass mentions and outer whitespace removed; line breaks stay. */
export function readingText(post: SourceActivity): string {
  const event = post.source_event
  const source = event?.capture_status === "complete" ? event.content : post.text
  return source.replaceAll("@everyone", "").replaceAll("@here", "").trim()
}

/** A relay's name label with nothing after it, such as "赵哥-股票：": one short word ending in a colon. */
export function isLabelOnly(text: string): boolean {
  const last = text.slice(-1)
  if (last !== ":" && last !== "：") return false
  const label = text.slice(0, -1)
  return label.length > 0 && [...label].length <= 24 && !/\s/.test(label)
}

const hasText = (text: string | null | undefined): text is string => Boolean(text?.trim())

/** Captured embeds that carry readable content of their own. */
export function readableEmbeds(post: SourceActivity) {
  const event = post.source_event
  if (event?.capture_status !== "complete") return []
  return event.embeds.filter(
    (e) =>
      (hasText(e.title) || hasText(e.description) || e.fields.some((f) => hasText(f.name) || hasText(f.value))) &&
      !(e.fields.length === 0 && !hasText(e.title) && isLabelOnly((e.description ?? "").trim())),
  )
}

/** A compact one-line excerpt for a list: whitespace folded, and empty for a post that is only a label or a picture. */
export function readableText(post: SourceActivity): string {
  let source = readingText(post)
  const embed = readableEmbeds(post)[0]
  if (!source && embed) {
    source = [embed.title, embed.description, ...embed.fields.flatMap((f) => [f.name, f.value])].filter(hasText).join(" ")
  }
  const words = source.split(/\s+/).filter(Boolean).join(" ")
  return isLabelOnly(words) ? "" : words
}

export const enteredByOwner = (post: SourceActivity) => post.destinations.some((d) => (d.orders ?? []).some((o) => o.client_id.startsWith("manual-")))

/** What the interpreter decided, in the words a trader would use. */
export function decisionTitle(post: SourceActivity): string {
  switch (post.decision) {
    case "trade": return "Trade"
    case "review": return "Needs review"
    case "ignore": return "Ignored"
    case null: return post.capture_status === "historical" ? "Historical" : codeWords(post.parse_status)
  }
}

/** What the post asked for, in plain words: "Buy ABC at $12.34 and 1 more". */
export function headline(post: SourceActivity): string {
  const first = post.instructions[0]
  if (!first) {
    if (enteredByOwner(post)) return "You entered the trade"
    if (post.reading?.kind === "chatter") return "Just chat, nothing to trade"
    switch (post.decision) {
      case "ignore": return "Not a trade"
      case "review": return "Needs your review"
      case "trade": return "Trade with no instructions"
      default: return post.capture_status === "historical" ? "Earlier message" : "Reading the message…"
    }
  }
  const rest = post.instructions.length > 1 ? ` and ${post.instructions.length - 1} more` : ""
  return instructionPhrase(first) + rest
}

/** How the reader took the post, in one line: "Buy PM at $201 · Full position". */
export function readAsLine(post: SourceActivity): string {
  const calls = post.reading ? callsOf(post.reading) : []
  if (calls.length === 0) return headline(post)
  return calls
    .map((call) => {
      const { title, detail } = callHeadline(call)
      return detail ? `${title} · ${detail}` : title
    })
    .join("; ")
}
