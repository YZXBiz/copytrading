import type { OwnershipIncident, OwnershipResolutionRequest, Position } from "../../../shared/contract"
import { decText, parseDec } from "./decimal"
import { isCoin, sharesOf, sharesText } from "./quantity"

/**
 * The one answer that settles a holdings question (OwnershipFix.swift), worked out from what the broker holds
 * now and what CopyTrading bought. Copied shares the broker still holds stay copied; the rest of the broker's
 * shares count as the owner's own. A shortfall beside copied shares means some were sold outside the app,
 * oldest first, the way a sell takes them.
 */
export interface OwnershipFix {
  request: OwnershipResolutionRequest
  /** What doesn't add up, as one plain sentence. */
  headline: string
  /** What waits on the owner until it is settled. */
  detail: string
  /** The owner's answer, as a short word on the row. */
  action: string
  /** What the answer does, shown in the row before it is sent. */
  confirmation: string
  /** The button that sends it. */
  confirm: string
}

export function ownershipFix(incident: OwnershipIncident, position: Position | undefined, accountId: string): OwnershipFix {
  const symbol = incident.symbol
  const broker = parseDec(position?.broker_qty ?? "0") ?? 0n
  const lots = position?.lots ?? []
  const copied = lots.reduce((sum, lot) => sum + (parseDec(lot.remaining_qty) ?? 0n), 0n)
  const remaining: Record<string, string> = {}
  let external = 0n
  let words: Pick<OwnershipFix, "headline" | "detail" | "action" | "confirmation" | "confirm">

  if (broker >= copied) {
    external = broker - copied
    for (const lot of lots) remaining[lot.lot_id] = lot.remaining_qty
    words =
      external === 0n
        ? {
            headline: `CopyTrading's count of ${symbol} is out of date`,
            detail: `It counted ${sharesText(parseDec(incident.expected_qty) ?? 0n, symbol)}; the broker holds ${sharesText(broker, symbol)}. ${symbol} calls wait until you update it.`,
            action: "Update the Count",
            confirmation: "CopyTrading will use the broker's count. Nothing is bought or sold.",
            confirm: "Update the Count",
          }
        : {
            headline: `${sharesOf(external, symbol)} of ${symbol} that CopyTrading didn't buy`,
            detail: `${symbol} calls wait until you say whose they are.`,
            action: "They're Mine",
            confirmation: `CopyTrading will leave these shares alone and copy ${symbol} calls again. Nothing is bought or sold.`,
            confirm: "Count as Mine",
          }
  } else {
    let missing = copied - broker
    for (const lot of lots) {
      const held = parseDec(lot.remaining_qty) ?? 0n
      const taken = held < missing ? held : missing
      missing -= taken
      remaining[lot.lot_id] = decText(held - taken)
    }
    words = {
      headline: isCoin(symbol) ? `Less ${symbol.split("/")[0]} at the broker than CopyTrading copied` : `Fewer ${symbol} shares at the broker than CopyTrading copied`,
      detail: `${sharesText(copied - broker, symbol)} are missing, likely sold outside CopyTrading. ${symbol} calls wait until you confirm.`,
      action: "They Were Sold",
      confirmation: `CopyTrading will count its oldest copied shares as sold first and copy ${symbol} calls again. Nothing is bought or sold.`,
      confirm: "Count as Sold",
    }
  }

  return {
    ...words,
    request: {
      resolution_id: `owner-${incident.incident_id}`,
      incident_id: incident.incident_id,
      account_id: accountId,
      symbol,
      actor: "owner",
      reason: broker >= copied ? "owner_counted_broker_shares" : "owner_marked_copied_sold",
      broker_qty: decText(broker),
      external_qty: decText(external),
      lot_remaining: remaining,
    },
  }
}
