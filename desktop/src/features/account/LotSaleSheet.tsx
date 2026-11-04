import { useState } from "react"
import { CircleAlertIcon, CircleCheckIcon, CircleDashedIcon } from "lucide-react"
import type { LotSalePreview, LotSaleResult, PositionLot, TradingEnvironment } from "../../../shared/contract"
import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert"
import { Badge } from "@/components/reui/badge"
import { Button } from "@/components/ui/button"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { Spinner } from "@/components/ui/spinner"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { dateTime, signedMoney } from "@/lib/format"
import { decMul, decText, parseDec } from "./decimal"
import { reviewLabel, saleChoices, saleOutcome, saleSentence, sharesLine } from "./lot-sale"
import { usd } from "@/lib/quantity"
import { reasonText } from "@/lib/reasons"

/** The lot a Sell sheet is open for, in the account it belongs to. */
export interface LotSaleTarget {
  accountId: string
  environment: TradingEnvironment
  symbol: string
  lot: PositionLot
  /** Whose post bought it, for the sheet's line on where the shares came from. */
  guruName: string | null
  /** Today's price of the symbol, for the live line before the broker is asked. */
  currentPrice: string | null
}

type Phase =
  | { name: "choosing" }
  | { name: "checking" }
  | { name: "reviewing"; preview: LotSalePreview }
  | { name: "selling"; preview: LotSalePreview }
  | { name: "finished"; result: LotSaleResult }

const TONE = { success: "success", neutral: "info", warning: "warning", destructive: "destructive" } as const
const ICON = { success: CircleCheckIcon, neutral: CircleDashedIcon, warning: CircleAlertIcon, destructive: CircleAlertIcon } as const

/**
 * Selling shares from one lot: choose how much of it, review a fresh preview, confirm once (the main process asks
 * the owner, from the plan the engine returned). The same command id is reused if the owner retries after the
 * engine could not be reached, so a sale is never placed twice; it is new only after Back.
 */
export function LotSaleSheet({ target, onClose }: { target: LotSaleTarget; onClose: () => void }) {
  const { lot, symbol, accountId } = target
  const remaining = parseDec(lot.remaining_qty) ?? 0n
  const [shares, setShares] = useState(remaining)
  const [phase, setPhase] = useState<Phase>({ name: "choosing" })
  const [problem, setProblem] = useState<string | null>(null)
  const [commandId, setCommandId] = useState(() => `lot-sale-${crypto.randomUUID()}`)

  const choices = saleChoices(remaining, symbol)
  const chosen = choices.find((c) => c.amount === shares)
  const bought = parseDec(lot.average_price)
  const price = parseDec(target.currentPrice)

  async function review() {
    setProblem(null)
    setPhase({ name: "checking" })
    const result = await window.copytrading.read.previewLotSale({
      preview: { preview_id: `lot-sale-preview-${crypto.randomUUID()}`, account_id: accountId, lot_id: lot.lot_id, qty: decText(shares) },
    })
    if (result.ok) setPhase({ name: "reviewing", preview: result.value })
    else {
      setPhase({ name: "choosing" })
      setProblem(`${accountId}: ${result.error}`)
    }
  }

  async function sell(preview: LotSalePreview) {
    setProblem(null)
    setPhase({ name: "selling", preview })
    const result = await window.copytrading.act.confirmLotSale({
      sale: { command_id: commandId, preview_id: preview.request.preview_id, account_id: accountId, actor: "owner" },
    })
    if (result.ok) setPhase({ name: "finished", result: result.value })
    else {
      setPhase({ name: "reviewing", preview })
      // The owner said no in the dialog: nothing to say. Anything else may have gone out, so say to check first.
      if (!result.cancelled) setProblem(`${result.error} Your sale may not have been sent; check Accounts before trying again.`)
    }
  }

  /** After a rejected or expired review, start over with a new sale identity. */
  function startOver() {
    setCommandId(`lot-sale-${crypto.randomUUID()}`)
    setProblem(null)
    setPhase({ name: "choosing" })
  }

  const buys = lot.bought_at ?? lot.posted_at
  const origin = `${target.guruName ? `From ${target.guruName}'s post` : "From a post"}${buys ? `, ${dateTime(buys)}` : ""}`
  const busy = phase.name === "checking" || phase.name === "selling"
  const outcome = phase.name === "finished" ? saleOutcome(phase.result, symbol) : null
  const OutcomeIcon = outcome ? ICON[outcome.tone] : null

  return (
    <Sheet open onOpenChange={(open) => !open && !busy && onClose()}>
      <SheetContent className="w-full sm:max-w-md">
        <SheetHeader>
          <SheetTitle>Sell {symbol}</SheetTitle>
          <SheetDescription className="flex items-center gap-2">
            {accountId}
            <Badge variant={target.environment === "live" ? "warning-light" : "outline"}>{target.environment === "live" ? "Live" : "Paper"}</Badge>
          </SheetDescription>
        </SheetHeader>
        <div className="flex-1 overflow-y-auto px-4">
          <FieldGroup className="gap-6">
            <Field>
              <FieldLabel>Lot</FieldLabel>
              <div className="flex items-baseline justify-between gap-3 text-sm">
                <span>{origin}</span>
                {bought !== null && <span className="text-muted-foreground tabular-nums">Bought at {usd(lot.average_price)}</span>}
              </div>
            </Field>

            {(phase.name === "choosing" || phase.name === "checking") && (
              <Field>
                <FieldLabel>Amount</FieldLabel>
                <ToggleGroup aria-label="Sell" variant="outline" size="sm" value={chosen ? [chosen.title] : []} disabled={phase.name === "checking"} onValueChange={(next) => { const c = choices.find((x) => x.title === next[0]); if (c) setShares(c.amount) }}>
                  {choices.map((c) => (
                    <ToggleGroupItem key={c.title} value={c.title}>
                      {c.title}
                    </ToggleGroupItem>
                  ))}
                </ToggleGroup>
                <div className="flex items-baseline justify-between gap-3 text-sm tabular-nums">
                  <span>{sharesLine(shares, remaining, symbol)}</span>
                  {price !== null && bought !== null && (
                    <Badge variant={price >= bought ? "success-light" : "destructive-light"}>{signedMoney(decText(decMul(shares, price - bought)))}</Badge>
                  )}
                </div>
                {price !== null && <FieldDescription>About {usd(decText(decMul(shares, price)))} at {usd(target.currentPrice)}</FieldDescription>}
                <FieldDescription>The price, market session, and account are checked before anything is sent.</FieldDescription>
              </Field>
            )}

            {(phase.name === "reviewing" || phase.name === "selling") &&
              (phase.preview.plan ? (
                <Field>
                  <FieldLabel>Review</FieldLabel>
                  <p className="text-sm">{saleSentence(phase.preview.plan, phase.preview)}</p>
                  <FieldDescription>Prices are checked again the moment you press Sell. If anything changed, nothing is sent.</FieldDescription>
                </Field>
              ) : (
                <Field>
                  <FieldLabel>This sale can’t go out right now</FieldLabel>
                  <ul className="text-sm">
                    {phase.preview.reasons.map((reason) => (
                      <li key={reason}>{reasonText(reason)}</li>
                    ))}
                  </ul>
                </Field>
              ))}

            {outcome && OutcomeIcon && (
              <Alert variant={TONE[outcome.tone]} aria-label="Result">
                <OutcomeIcon aria-hidden />
                <AlertTitle>{outcome.title}</AlertTitle>
                <AlertDescription>{outcome.detail}</AlertDescription>
              </Alert>
            )}
            {problem && (
              <Alert variant="warning">
                <CircleAlertIcon aria-hidden />
                <AlertTitle>{problem}</AlertTitle>
              </Alert>
            )}
          </FieldGroup>
        </div>
        <SheetFooter className="flex-row items-center justify-end">
          {busy && <Spinner aria-label={phase.name === "selling" ? "Sending" : "Checking"} />}
          {phase.name === "finished" ? (
            <>
              {phase.result.status === "rejected" && (
                <Button type="button" variant="outline" onClick={startOver}>
                  Review Again
                </Button>
              )}
              <Button type="button" onClick={onClose}>
                Done
              </Button>
            </>
          ) : (
            <>
              <Button type="button" variant="outline" disabled={busy} onClick={phase.name === "reviewing" ? startOver : onClose}>
                {phase.name === "reviewing" ? "Back" : "Cancel"}
              </Button>
              {(phase.name === "choosing" || phase.name === "checking") && (
                <Button type="button" disabled={busy || !(shares > 0n && shares <= remaining)} onClick={review}>
                  {phase.name === "checking" ? "Checking…" : reviewLabel(shares, symbol)}
                </Button>
              )}
              {phase.name === "reviewing" && phase.preview.plan && (
                <Button type="button" onClick={() => sell(phase.preview)}>
                  Sell {decText(parseDec(phase.preview.plan.qty) ?? shares)} {symbol}
                </Button>
              )}
            </>
          )}
        </SheetFooter>
      </SheetContent>
    </Sheet>
  )
}
