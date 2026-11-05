import { RotateClockwiseIcon } from "@/components/icons/RotateClockwiseIcon"
import { TrendingDownIcon } from "@/components/icons/TrendingDownIcon"
import { TrendingUpIcon } from "@/components/icons/TrendingUpIcon"
import type { MarketQuote } from "../../../shared/contract"
import { Button } from "@/components/ui/button"
import { ButtonGroup } from "@/components/ui/button-group"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { Input } from "@/components/ui/input"
import { Spinner } from "@/components/ui/spinner"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { BUY_SIZES, type Draft, type PriceChoice, SELL_SHARES, defaultChoice, sameShare, shareTitle } from "./manual-draft"
import { dollars, sharesText, usd } from "@/lib/quantity"
import { type Holding, canQuote, livePrice, quoteDetail, quoteProblem } from "./quote"

/** One choice among a few, as a row of toggles. */
function Choices({ label, value, options, onPick }: { label: string; value: string | null; options: { value: string; title: string; detail?: string | null }[]; onPick: (value: string) => void }) {
  return (
    <ToggleGroup aria-label={label} variant="outline" size="sm" value={value === null ? [] : [value]} onValueChange={(next) => next[0] !== undefined && onPick(next[0])} className="flex-wrap">
      {options.map((o) => (
        <ToggleGroupItem key={o.value} value={o.value} aria-label={o.detail ? `${o.title}, ${o.detail}` : o.title}>
          {o.title}
          {o.detail && <span className="text-muted-foreground text-xs font-normal">{o.detail}</span>}
        </ToggleGroupItem>
      ))}
    </ToggleGroup>
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
  // A buy with no size is the empty string, which a toggle cannot hold as its value.
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

  return (
    <FieldGroup className="gap-4">
      <Field>
        <FieldLabel>Side</FieldLabel>
        <ButtonGroup aria-label="Side">
          <Button size="sm" type="button" variant={!draft.isSell ? "default" : "outline"} aria-pressed={!draft.isSell} onClick={() => setSell(false)}>
            <TrendingUpIcon aria-hidden /> Buy
          </Button>
          <Button size="sm" type="button" variant={draft.isSell ? "default" : "outline"} aria-pressed={draft.isSell} onClick={() => setSell(true)}>
            <TrendingDownIcon aria-hidden /> Sell
          </Button>
        </ButtonGroup>
      </Field>

      <Field>
        <FieldLabel htmlFor={`stock-${draft.id}`}>Stock</FieldLabel>
        {draft.isSell ? (
          holdings.length === 0 && !named ? (
            <FieldDescription>Nothing CopyTrading bought is held in these accounts.</FieldDescription>
          ) : (
            <Choices
              label="Stock"
              value={symbol || null}
              options={[...holdings.map((h) => ({ value: h.symbol, title: h.symbol })), ...(named ? [{ value: symbol, title: symbol, detail: "Not held" }] : [])]}
              onPick={(next) => set({ symbol: next, entryPrice: "" })}
            />
          )
        ) : (
          <Input id={`stock-${draft.id}`} className="w-40" placeholder="Type a ticker" value={draft.symbol} onChange={(e) => set({ symbol: e.target.value })} autoCapitalize="characters" />
        )}
        {draft.isSell && holding && (
          <FieldDescription>
            You hold {sharesText(holding.shares, holding.symbol)}
            {holding.price ? ` at ${usd(holding.price)} each` : ""}
          </FieldDescription>
        )}
        {draft.isSell && draft.entryPrice.trim() !== "" && <FieldDescription>Sells from the buy at {dollars(draft.entryPrice)}.</FieldDescription>}
      </Field>

      <Field>
        <FieldLabel>How much</FieldLabel>
        <Choices label="How much" value={sizeValue} options={sizeOptions} onPick={(next) => set({ fraction: next === NONE ? "" : next, usdAmount: "" })} />
        {!draft.isSell && draft.usdAmount !== "" && <FieldDescription>The post named {dollars(draft.usdAmount)}.</FieldDescription>}
      </Field>

      <Field>
        <FieldLabel>Price</FieldLabel>
        <div className="flex flex-wrap items-center gap-2">
          <Choices
            label="Price"
            value={draft.priceChoice}
            options={priceOptions}
            onPick={(next) => choosePrice(next as PriceChoice)}
          />
          {canQuote(symbol) && (
            <Button type="button" size="icon-sm" variant="ghost" aria-label="Get the latest price" disabled={quoting} onClick={onRefreshQuote}>
              {quoting ? <Spinner /> : <RotateClockwiseIcon aria-hidden />}
            </Button>
          )}
          {draft.priceChoice === "limit" && (
            <div className="flex items-center gap-1">
              <span className="text-muted-foreground text-sm">$</span>
              <Input aria-label="Limit price" inputMode="decimal" className="w-24 tabular-nums" value={draft.price} onChange={(e) => set({ price: e.target.value })} />
            </div>
          )}
        </div>
        {canQuote(symbol) && quoteProblem(symbol, quote, draft.isSell, now) && <FieldDescription>{quoteProblem(symbol, quote, draft.isSell, now)}</FieldDescription>}
      </Field>
    </FieldGroup>
  )
}
