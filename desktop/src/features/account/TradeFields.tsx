import { RotateClockwiseIcon } from "@/components/icons/RotateClockwiseIcon"
import type { MarketQuote } from "../../../shared/contract"
import { Button } from "@/components/arc/button/button"
import { Input } from "@/components/arc/input/input"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { BUY_SIZES, type Draft, type PriceChoice, SELL_SHARES, defaultChoice, sameShare, shareTitle } from "./manual-draft"
import { dollars, sharesText, usd } from "@/lib/quantity"
import { type Holding, canQuote, livePrice, quoteDetail, quoteProblem } from "./quote"
import styles from "./sheet.module.css"

/** One choice among a few, as a row of options; a detail rides after its title. */
function Choices({ label, value, options, onPick }: { label: string; value: string | null; options: { value: string; title: string; detail?: string | null }[]; onPick: (value: string) => void }) {
  return (
    <SegmentedControl
      label={label}
      value={value ?? ""}
      onValueChange={onPick}
      options={options.map((o) => ({ value: o.value, label: o.title, accessory: o.detail ? <span className={styles.detail}>{o.detail}</span> : undefined }))}
    />
  )
}

/**
 * What should happen, as one group of fields: Buy or Sell, then the stock (for a sell, one CopyTrading holds, with
 * what is held as a note), how much, and the price: the guru's, the market's, or a limit.
 */
export function TradeFields({
  draft,
  onChange,
  holdings,
  quote,
  quoting,
  onRefreshQuote,
  now,
}: {
  draft: Draft
  onChange: (draft: Draft) => void
  holdings: Holding[]
  quote: MarketQuote | null
  quoting: boolean
  onRefreshQuote: () => void
  now: Date
}) {
  const symbol = draft.symbol.trim().toUpperCase()
  const holding = holdings.find((h) => h.symbol === symbol)
  const named = symbol !== "" && !holding
  const set = (changes: Partial<Draft>) => onChange({ ...draft, ...changes })

  function setSell(sell: boolean) {
    if (draft.isSell === sell) return
    // The stock stays what the post named, or empty for the owner to pick: choosing Sell never fills one in.
    const next: Draft = { ...draft, isSell: sell, entryPrice: "", usdAmount: "", exitBasis: null }
    if (sell) next.fraction ||= "1"
    else if (draft.fraction === "1") next.fraction = ""
    if (next.priceChoice !== "limit") next.priceChoice = defaultChoice(draft.postPrice)
    onChange(next)
  }

  function choosePrice(choice: PriceChoice) {
    // A limit starts from the price it replaces, ready to edit.
    const price = choice === "guru" ? draft.postPrice : choice === "limit" ? draft.price.trim() || livePrice(quote, draft.isSell, now) || draft.postPrice : draft.price
    set({ priceChoice: choice, price })
  }

  const sizes = draft.isSell ? SELL_SHARES : BUY_SIZES
  const usual = sizes.some((s) => sameShare(s, draft.fraction))
  // A buy with no size is the empty string, which an option cannot hold as its value.
  const NONE = "none"
  const sizeOptions = [
    ...sizes.map((s) => ({ value: s || NONE, title: shareTitle(s, draft.isSell) })),
    // A size the post named that isn't one of the usual ones.
    ...(draft.usdAmount === "" && !usual && (draft.isSell || draft.fraction !== "") ? [{ value: draft.fraction, title: shareTitle(draft.fraction, draft.isSell) }] : []),
  ]
  const sizeValue = draft.isSell || draft.usdAmount === "" ? (sizeOptions.find((o) => sameShare(o.value === NONE ? "" : o.value, draft.fraction))?.value ?? null) : null

  const marketDetail = quoteDetail(quote, draft.isSell, now) ?? (draft.isSell ? "At the bid" : null)
  const priceOptions = [
    ...(draft.postPrice.trim() !== "" ? [{ value: "guru", title: dollars(draft.postPrice), detail: "the guru's price" }] : []),
    { value: "market", title: "Market", detail: marketDetail },
    { value: "limit", title: "Limit" },
  ]
  const problem = canQuote(symbol) ? quoteProblem(symbol, quote, draft.isSell, now) : null

  return (
    <div className={styles.fields}>
      <div className={styles.field}>
        <span className={styles.fieldLabel}>Side</span>
        <SegmentedControl
          label="Side"
          value={draft.isSell ? "sell" : "buy"}
          onValueChange={(next) => setSell(next === "sell")}
          options={[
            { value: "buy", label: "Buy" },
            { value: "sell", label: "Sell" },
          ]}
        />
      </div>

      <div className={styles.field}>
        {draft.isSell ? (
          <>
            <span className={styles.fieldLabel}>Stock</span>
            {holdings.length === 0 && !named ? (
              <p className={styles.hint}>Nothing CopyTrading bought is held in these accounts.</p>
            ) : (
              <Choices
                label="Stock"
                value={symbol || null}
                options={[...holdings.map((h) => ({ value: h.symbol, title: h.symbol })), ...(named ? [{ value: symbol, title: symbol, detail: "Not held" }] : [])]}
                onPick={(next) => set({ symbol: next, entryPrice: "" })}
              />
            )}
          </>
        ) : (
          <Input label="Stock" placeholder="Type a ticker" value={draft.symbol} onChange={(e) => set({ symbol: e.target.value })} autoCapitalize="characters" />
        )}
        {draft.isSell && holding && (
          <p className={styles.hint}>
            You hold {sharesText(holding.shares, holding.symbol)}
            {holding.price ? ` at ${usd(holding.price)} each` : ""}
          </p>
        )}
        {draft.isSell && draft.entryPrice.trim() !== "" && <p className={styles.hint}>Sells from the buy at {dollars(draft.entryPrice)}.</p>}
      </div>

      <div className={styles.field}>
        <span className={styles.fieldLabel}>How much</span>
        <Choices label="How much" value={sizeValue} options={sizeOptions} onPick={(next) => set({ fraction: next === NONE ? "" : next, usdAmount: "" })} />
        {!draft.isSell && draft.usdAmount !== "" && <p className={styles.hint}>The post named {dollars(draft.usdAmount)}.</p>}
      </div>

      <div className={styles.field}>
        <span className={styles.fieldLabel}>Price</span>
        <div className={styles.priceRow}>
          <Choices label="Price" value={draft.priceChoice} options={priceOptions} onPick={(next) => choosePrice(next as PriceChoice)} />
          {canQuote(symbol) && (
            <Button type="button" size="sm" variant="ghost" aria-label="Get the latest price" loading={quoting} onClick={onRefreshQuote}>
              <RotateClockwiseIcon width={16} height={16} aria-hidden="true" />
            </Button>
          )}
        </div>
        {draft.priceChoice === "limit" && <Input label="Limit price" inputMode="decimal" value={draft.price} onChange={(e) => set({ price: e.target.value })} />}
        {problem && <p className={styles.hint}>{problem}</p>}
      </div>
    </div>
  )
}
