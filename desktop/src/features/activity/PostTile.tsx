import { useState } from "react"
import { Message01Icon } from "@/components/icons/Message01Icon"

/** Tickers the logo cache can fetch; anything else gets the letter. */
const HAS_LOGO = /^[A-Z][A-Z0-9.]{0,9}$/

/**
 * The one tile every post row starts with: the stock's logo inset in a bordered square, its letter when there is no
 * logo, and a neutral chat glyph in the same square for a post that names no stock.
 */
export function PostTile({ symbol }: { symbol: string | null }) {
  const ticker = symbol?.toUpperCase() ?? null
  const [missing, setMissing] = useState(false)
  return (
    <span aria-hidden="true" className="bg-background text-muted-foreground flex size-8 shrink-0 items-center justify-center overflow-hidden rounded-md border p-1.5 text-xs font-medium">
      {ticker === null ? (
        <Message01Icon className="size-4" />
      ) : HAS_LOGO.test(ticker) && !missing ? (
        <img src={`ct-logo://${ticker}`} alt="" className="size-full object-contain" onError={() => setMissing(true)} />
      ) : (
        ticker.charAt(0)
      )}
    </span>
  )
}
