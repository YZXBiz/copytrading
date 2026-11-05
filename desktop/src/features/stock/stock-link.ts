import { href } from "@/features/shell/route"

/** A stock's page, `#/stock/SOXL`; with `accountId` the page reads that account's keys and lots (`?account=`). */
export const stockHref = (symbol: string, accountId?: string | null) =>
  `${href("stock", symbol.toUpperCase())}${accountId ? `?account=${encodeURIComponent(accountId)}` : ""}`

/** The account a stock link names, or null. */
export const accountOfHash = (hash: string): string | null => new URLSearchParams(hash.split("?")[1]).get("account")
