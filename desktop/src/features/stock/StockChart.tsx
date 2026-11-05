import { useRef, useState } from "react"
import { useReducedMotion } from "motion/react"
import { MaximizeScreenIcon } from "@/components/icons/MaximizeScreenIcon"
import { ZoomInAreaIcon } from "@/components/icons/ZoomInAreaIcon"
import { ZoomOutAreaIcon } from "@/components/icons/ZoomOutAreaIcon"
import type { DailyRange } from "../../../shared/contract"
import { PriceChart } from "@/components/arc/blocks/market-terminal/market-terminal"
import { AVERAGES, type AverageId, type Candle } from "@/components/arc/blocks/market-terminal/market-terminal-data"
import terminal from "@/components/arc/blocks/market-terminal/market-terminal.module.css"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { RegionNote } from "@/features/account/RegionNote"
import { STOCK_RANGES } from "./candles"
import styles from "./stock.module.css"

export type ChartData = { status: "loading" } | { status: "error"; error: string; retry: () => void } | { status: "ready"; candles: Candle[]; lastAt: string }

/**
 * A stock's daily candles with volume, its 20 and 50 day averages, a crosshair that reads each day's open, high, low
 * and close, and zoom: scroll or pinch to zoom, drag to pan, plus and minus on the keyboard.
 */
export function StockChart({ symbol, data, range, onRangeChange, live }: { symbol: string; data: ChartData; range: DailyRange; onRangeChange: (range: DailyRange) => void; live: number | null }) {
  const reduced = !!useReducedMotion()
  const [averages, setAverages] = useState<AverageId[]>(["ma20", "ma50"])
  const zoomRef = useRef<{ zoom: (factor: number) => void; reset: () => void } | null>(null)
  const spec = STOCK_RANGES.find((r) => r.value === range)!.spec
  const candles = data.status === "ready" ? data.candles : []
  const last = candles[candles.length - 1]
  // A refresh with the same bars keeps the view; a new day, range or stock starts a fresh one.
  const seriesId = `${symbol}:${spec.id}:${data.status === "ready" ? data.lastAt : ""}:${candles.length}`

  return (
    <div className={terminal.root}>
      <div className={terminal.toolbar}>
        <div className={terminal.seg}>
          <SegmentedControl label="Time range" value={range} onValueChange={(value) => onRangeChange(value as DailyRange)} options={STOCK_RANGES.map((r) => ({ value: r.value, label: r.spec.label }))} />
        </div>
        <div className={terminal.tools}>
          <div className={terminal.toggles} role="group" aria-label="Moving averages">
            {AVERAGES.map((average) => (
              <button
                key={average.id}
                type="button"
                className={terminal.toggle}
                data-average={average.id}
                aria-pressed={averages.includes(average.id)}
                onClick={() => setAverages((list) => (list.includes(average.id) ? list.filter((item) => item !== average.id) : [...list, average.id]))}
              >
                <span className={terminal.swatch} aria-hidden="true" />
                {average.label}
              </button>
            ))}
          </div>
          <div className={terminal.zoom} role="group" aria-label="Zoom">
            <button type="button" className={terminal.iconButton} onClick={() => zoomRef.current?.zoom(0.7)} aria-label="Zoom in">
              <ZoomInAreaIcon width={16} height={16} aria-hidden="true" />
            </button>
            <button type="button" className={terminal.iconButton} onClick={() => zoomRef.current?.zoom(1.45)} aria-label="Zoom out">
              <ZoomOutAreaIcon width={16} height={16} aria-hidden="true" />
            </button>
            <button type="button" className={terminal.iconButton} onClick={() => zoomRef.current?.reset()} aria-label="Reset view">
              <MaximizeScreenIcon width={16} height={16} aria-hidden="true" />
            </button>
          </div>
        </div>
      </div>

      {data.status === "loading" && <Skeleton label={`Loading ${symbol} prices`} lines={6} className={styles.chartSlot} />}
      {data.status === "error" && <RegionNote title={`${symbol} prices did not load`} message={data.error} onRetry={data.retry} />}
      {data.status === "ready" && candles.length < 2 && (
        <EmptyState title={`No daily prices for ${symbol}`} description="The broker has none for this stock in the last year, so there is nothing to chart." />
      )}
      {data.status === "ready" && candles.length >= 2 && last && (
        <PriceChart
          bars={candles}
          seriesId={seriesId}
          range={spec}
          symbol={{ ticker: symbol, name: symbol, exchange: "", price: last.c, prevClose: candles[candles.length - 2]!.c, vol: 0, avgVolume: 0 }}
          live={live ?? last.c}
          averages={averages}
          limit={null}
          reduced={reduced}
          zoomRef={zoomRef}
        />
      )}
    </div>
  )
}
