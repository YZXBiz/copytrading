import { useMemo, useState } from "react"
import { ArrowDownRight01Icon } from "@/components/icons/ArrowDownRight01Icon"
import { ArrowLeft01Icon } from "@/components/icons/ArrowLeft01Icon"
import { ArrowUpRight01Icon } from "@/components/icons/ArrowUpRight01Icon"
import type { AccountOverview, AccountOverviewPage, DailyRange, Position } from "../../../shared/contract"
import { AnimatedCounter } from "@/components/arc/animated-counter/animated-counter"
import { formatPercent, formatPrice, formatSigned, formatVolume } from "@/components/arc/blocks/market-terminal/market-terminal-data"
import terminal from "@/components/arc/blocks/market-terminal/market-terminal.module.css"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { RegionNote } from "@/features/account/RegionNote"
import { type LotSaleTarget, LotSaleSheet } from "@/features/account/LotSaleSheet"
import { sourceKey } from "@/features/account/post-rows"
import { useSkippedCalls } from "@/features/account/skipped-calls"
import { useLivePrices } from "@/features/live/use-live-prices"
import { href } from "@/features/shell/route"
import { readClock } from "@/lib/clock"
import { type Loaded, useResult } from "@/lib/use-result"
import { type ChartData, StockChart } from "./StockChart"
import { StockCalls } from "./StockCalls"
import { StockLots } from "./StockLots"
import { SymbolMark } from "./TickerLink"
import { accountOfHash } from "./stock-link"
import { sessionOf, toCandles } from "./candles"
import styles from "./stock.module.css"

/** The engine caches daily bars for five minutes, so asking more often only repeats its answer. */
const BARS_MS = 300_000

function StockPage({ symbol, account, onRefresh }: { symbol: string; account: AccountOverview; onRefresh: () => void }) {
  const accountId = account.account_id
  const [range, setRange] = useState<DailyRange>("six_months")
  const [sale, setSale] = useState<LotSaleTarget | null>(null)
  const [now] = useState(readClock)
  const skipped = useSkippedCalls()
  const bars = useResult(() => window.copytrading.read.getDailyBars({ account_id: accountId, symbol, range }), `${accountId}:${symbol}:${range}`, BARS_MS)
  const posts = useResult(() => window.copytrading.read.getSourceActivity(), accountId, 15_000)
  const limits = useResult(() => window.copytrading.read.getLimits({ account_id: accountId }), accountId, 60_000)
  const prices = useLivePrices(accountId, [symbol])

  const candles = useMemo(() => (bars.status === "ready" ? toCandles(bars.data) : []), [bars])
  const data: ChartData = bars.status === "ready" ? { status: "ready", candles, lastAt: bars.data[bars.data.length - 1]?.at ?? "" } : bars.status === "error" ? { status: "error", error: bars.error, retry: bars.retry } : { status: "loading" }
  const session = sessionOf(candles)
  const position: Position | undefined = account.positions.find((p) => p.symbol === symbol)
  const live = prices[symbol] ?? null
  const price = live ?? session?.close ?? (position?.current_price ? Number(position.current_price) : null)
  const change = price !== null && session ? price - session.previousClose : null
  const up = (change ?? 0) >= 0
  const guru = limits.status === "ready" && limits.data ? limits.data.guru : null

  return (
    <div className={styles.page}>
      <a className={styles.back} href={href("accounts", accountId)}>
        <ArrowLeft01Icon width={16} height={16} aria-hidden="true" />
        {accountId}
      </a>
      <div className={terminal.root}>
      <section className={terminal.main} aria-labelledby="stock-title">
        <header className={terminal.header}>
          <div className={terminal.identity}>
            <h1 id="stock-title" className={terminal.title}>
              <SymbolMark symbol={symbol} size={28} />
              <span className={terminal.ticker}>{symbol}</span>
            </h1>
            <p className={terminal.exchange}>{`${accountId}, ${account.environment === "live" ? "live" : "paper"}, USD`}</p>
          </div>
          <div className={terminal.quote}>
            <span className={terminal.price}>{price === null ? <span className={styles.muted}>No price</span> : <AnimatedCounter value={Number(price.toFixed(2))} prefix="$" decimals={2} />}</span>
            {change !== null && session && (
              <span className={terminal.change} data-direction={up ? "up" : "down"}>
                {up ? <ArrowUpRight01Icon width={16} height={16} aria-hidden="true" /> : <ArrowDownRight01Icon width={16} height={16} aria-hidden="true" />}
                <span className={terminal.num}>
                  {formatSigned(change)} ({formatPercent((change / session.previousClose) * 100)})
                </span>
                <span className={terminal.changeLabel}>today</span>
              </span>
            )}
          </div>
          {session && (
            <dl className={terminal.stats}>
              <div className={terminal.stat}>
                <dt>Open</dt>
                <dd className={terminal.num}>{formatPrice(session.open)}</dd>
              </div>
              <div className={terminal.stat}>
                <dt>High</dt>
                <dd className={terminal.num}>{formatPrice(session.high)}</dd>
              </div>
              <div className={terminal.stat}>
                <dt>Low</dt>
                <dd className={terminal.num}>{formatPrice(session.low)}</dd>
              </div>
              <div className={terminal.stat}>
                <dt>Volume</dt>
                <dd className={terminal.num}>{formatVolume(session.volume)}</dd>
              </div>
            </dl>
          )}
        </header>
        <StockChart symbol={symbol} data={data} range={range} onRangeChange={setRange} live={live} />
      </section>
      </div>

      <div className={styles.stack}>
        <StockLots
          symbol={symbol}
          position={position}
          price={price}
          onSell={(lot) => setSale({ accountId, environment: account.environment, symbol, lot, guruName: guru, currentPrice: position?.current_price ?? null })}
        />
        <StockCalls symbol={symbol} accountId={accountId} posts={posts} now={now} skipped={(id) => skipped.has(id)} />
      </div>
      {sale && (
        <LotSaleSheet
          target={sale}
          onClose={() => {
            setSale(null)
            onRefresh()
          }}
        />
      )}
    </div>
  )
}

/** A stock's page, `#/stock/<SYMBOL>`: its price and daily chart, what you hold of it and what the guru said about it, through one account. */
export function StockScreen({ symbol, accounts, onRefresh }: { symbol: string | null; accounts: Loaded<AccountOverviewPage> & { retry: () => void }; onRefresh: () => void }) {
  if (!symbol) return <div className={styles.page}><EmptyState title="No stock chosen" description="Press a holding or a ticker to open its page." /></div>
  if (accounts.status === "loading") return <div className={styles.page}><Skeleton label={`Loading ${symbol}`} lines={6} /></div>
  if (accounts.status === "error") return <div className={styles.page}><RegionNote title="Accounts did not load" message={accounts.error} onRetry={accounts.retry} /></div>
  const items = accounts.data.items
  const named = accountOfHash(window.location.hash)
  // The account the link names, else the one that holds the stock, else the first.
  const account = items.find((a) => a.account_id === named) ?? items.find((a) => a.positions.some((p) => p.symbol === symbol)) ?? items[0]
  if (!account) {
    return (
      <div className={styles.page}>
        <EmptyState
          title="No accounts yet"
          description="A stock's prices are read through an account."
          action={
            <Button type="button" onClick={() => (window.location.hash = href("settings", "connections"))}>
              Open Connections
            </Button>
          }
        />
      </div>
    )
  }
  return <StockPage key={`${account.account_id}:${symbol}`} symbol={symbol} account={account} onRefresh={onRefresh} />
}
