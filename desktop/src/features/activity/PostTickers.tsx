import type { SourceActivity } from "../../../shared/contract"
import { TickerLink } from "@/features/stock/TickerLink"

/** The stocks a post names or traded, each once, in the order the post gives them. */
export const postTickers = (post: SourceActivity): string[] => [
  ...new Set([...post.instructions.map((i) => i.symbol), ...(post.stops ?? []).map((s) => s.symbol), ...post.destinations.flatMap((d) => d.orders ?? []).map((o) => o.symbol)].filter((s): s is string => Boolean(s))),
]

/** A link to each stock a post names; nothing for a post with none. */
export function PostTickers({ post }: { post: SourceActivity }) {
  const tickers = postTickers(post)
  if (tickers.length === 0) return null
  return (
    <>
      {tickers.map((symbol) => (
        <TickerLink key={symbol} symbol={symbol} />
      ))}
    </>
  )
}
