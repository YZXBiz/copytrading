import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"

/** Tickers the logo cache can fetch; a coin's pair or anything else gets the letter tile alone. */
const HAS_LOGO = /^[A-Z][A-Z0-9.]{0,9}$/

/** A company's logo (main's ct-logo:// cache), or its first letter in a tile when there is none. */
export function SymbolLogo({ symbol, size = "default" }: { symbol: string; size?: "sm" | "default" | "lg" }) {
  const ticker = symbol.toUpperCase()
  return (
    <Avatar size={size} aria-hidden="true">
      {HAS_LOGO.test(ticker) && <AvatarImage src={`ct-logo://${ticker}`} alt="" />}
      <AvatarFallback className="text-xs font-medium">{ticker.charAt(0)}</AvatarFallback>
    </Avatar>
  )
}
