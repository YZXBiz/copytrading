import { useState } from "react"
import { Message01Icon } from "@/components/icons/Message01Icon"

/** Tickers the logo cache can fetch; anything else gets its first letter. */
const HAS_LOGO = /^[A-Z][A-Z0-9.]{0,9}$/

/** The mark on a post's avatar: the stock's real logo (main's ct-logo:// cache), its letter when there is none, a chat glyph for a post that names no stock. */
export function PostMark({ symbol }: { symbol: string | null }) {
  const ticker = symbol?.toUpperCase() ?? null
  const [missing, setMissing] = useState(false)
  if (ticker === null) return <Message01Icon width={16} height={16} aria-hidden="true" />
  if (HAS_LOGO.test(ticker) && !missing) return <img src={`ct-logo://${ticker}`} alt="" onError={() => setMissing(true)} />
  return <span aria-hidden="true">{ticker.charAt(0)}</span>
}
