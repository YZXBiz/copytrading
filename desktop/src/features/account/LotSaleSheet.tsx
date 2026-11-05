import { useState } from "react"
import type { LotSalePreview, LotSaleResult, PositionLot, TradingEnvironment } from "../../../shared/contract"
import { Alert } from "@/components/arc/alert/alert"
import { Badge } from "@/components/arc/badge/badge"
import { Button } from "@/components/arc/button/button"
import { Drawer, DrawerContent } from "@/components/arc/drawer/drawer"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { dateTime, signedMoney } from "@/lib/format"
import { decMul, decText, parseDec } from "./decimal"
import { reviewLabel, saleChoices, saleOutcome, saleSentence, sharesLine } from "./lot-sale"
import { usd } from "@/lib/quantity"
import { reasonText } from "@/lib/reasons"
import styles from "./sheet.module.css"

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

const TONE = { success: "success", neutral: "info", warning: "warning", destructive: "danger" } as const

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

  return (
    <Drawer open onOpenChange={(open) => !open && !busy && onClose()}>
      <DrawerContent title={`Sell ${symbol}`} description={`${accountId}, ${target.environment === "live" ? "live" : "paper"}`} className={styles.sheet}>
        <div className={styles.sections}>
          <div className={styles.group}>
            <span className={styles.groupTitle}>Lot</span>
            <div className={styles.line}>
              <span>{origin}</span>
              {bought !== null && <span className={styles.muted}>Bought at {usd(lot.average_price)}</span>}
            </div>
          </div>

          {(phase.name === "choosing" || phase.name === "checking") && (
            <fieldset className={styles.group} disabled={phase.name === "checking"}>
              <legend>Amount</legend>
              <SegmentedControl
                label="Sell"
                value={chosen?.title ?? ""}
                onValueChange={(next) => {
                  const c = choices.find((x) => x.title === next)
                  if (c) setShares(c.amount)
                }}
                options={choices.map((c) => ({ value: c.title, label: c.title }))}
              />
              <div className={styles.line}>
                <span>{sharesLine(shares, remaining, symbol)}</span>
                {price !== null && bought !== null && <Badge tone={price >= bought ? "success" : "danger"}>{signedMoney(decText(decMul(shares, price - bought)))}</Badge>}
              </div>
              {price !== null && (
                <p className={styles.hint}>
                  About {usd(decText(decMul(shares, price)))} at {usd(target.currentPrice)}
                </p>
              )}
              <p className={styles.hint}>The price, market session, and account are checked before anything is sent.</p>
            </fieldset>
          )}

          {(phase.name === "reviewing" || phase.name === "selling") &&
            (phase.preview.plan ? (
              <div className={styles.group}>
                <span className={styles.groupTitle}>Review</span>
                <p className={styles.sentence}>{saleSentence(phase.preview.plan, phase.preview)}</p>
                <p className={styles.hint}>Prices are checked again the moment you press Sell. If anything changed, nothing is sent.</p>
              </div>
            ) : (
              <div className={styles.group}>
                <span className={styles.groupTitle}>This sale can’t go out right now</span>
                <ul className={styles.reasons}>
                  {phase.preview.reasons.map((reason) => (
                    <li key={reason}>{reasonText(reason)}</li>
                  ))}
                </ul>
              </div>
            ))}

          {outcome && (
            <Alert tone={TONE[outcome.tone]} title={outcome.title}>
              <p className={styles.alertText}>{outcome.detail}</p>
            </Alert>
          )}
          {problem && <Alert tone="warning" title={problem} />}
        </div>
        <div className={styles.footer}>
          {phase.name === "finished" ? (
            <>
              {phase.result.status === "rejected" && (
                <Button type="button" variant="secondary" onClick={startOver}>
                  Review again
                </Button>
              )}
              <Button type="button" onClick={onClose}>
                Done
              </Button>
            </>
          ) : (
            <>
              <Button type="button" variant="secondary" disabled={busy} onClick={phase.name === "reviewing" ? startOver : onClose}>
                {phase.name === "reviewing" ? "Back" : "Cancel"}
              </Button>
              {(phase.name === "choosing" || phase.name === "checking") && (
                <Button type="button" loading={phase.name === "checking"} disabled={!(shares > 0n && shares <= remaining)} onClick={review}>
                  {reviewLabel(shares, symbol)}
                </Button>
              )}
              {(phase.name === "reviewing" || phase.name === "selling") && phase.preview.plan && (
                <Button type="button" loading={phase.name === "selling"} onClick={() => sell(phase.preview)}>
                  Sell {decText(parseDec(phase.preview.plan.qty) ?? shares)} {symbol}
                </Button>
              )}
            </>
          )}
        </div>
      </DrawerContent>
    </Drawer>
  )
}
