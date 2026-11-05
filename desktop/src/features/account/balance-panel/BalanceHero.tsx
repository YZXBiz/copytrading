import { useMemo, useRef, useState } from "react"
import { motion, useReducedMotion } from "motion/react"
import { ArrowDownRight01Icon } from "@/components/icons/ArrowDownRight01Icon"
import { ArrowUpRight01Icon } from "@/components/icons/ArrowUpRight01Icon"
import type { AccountOverview, HistoryRange } from "../../../../shared/contract"
import { AnimatedCounter } from "@/components/arc/animated-counter/animated-counter"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { motionTokens } from "@/components/arc/lib/motion-tokens"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { monthDay, timeOfDay } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { balanceAxis } from "../balance-axis"
import { RegionNote } from "../RegionNote"
import { dayChange } from "../model"
import styles from "../account.module.css"
import { DEFAULT_RANGE, RANGES } from "./data"
import { formatSignedPercent, formatSignedUsd, formatUsd, formatWeekday } from "./format"
import { type BalanceRow, balanceRows, rangeStats } from "./range-view"

const W = 560
const H = 120

/** The account's balance: the figure, today's change, and its history as one line you can scrub, over a range choice. */
export function BalanceHero({
  account,
  version,
  onRefresh,
}: {
  account: AccountOverview
  /** Changes when the page was told to read again. */
  version: number
  onRefresh: () => void
}) {
  const accountId = account.account_id
  const [selected, setSelected] = useState<HistoryRange>(DEFAULT_RANGE)
  const [point, setPoint] = useState<number | null>(null)
  const reduced = useReducedMotion()
  // The line glides only when the owner picked another range, never when a read brings new points.
  const picked = useRef(false)

  // The reply carries its own range: a change of range renders once with the old reply still in hand.
  const history = useResult(
    async () => {
      const result = await window.copytrading.read.getEquityHistory({ account_id: accountId, range: selected })
      return result.ok ? { ok: true as const, value: { range: selected, history: result.value } } : result
    },
    `${accountId}:${selected}:${version}`,
    60_000,
  )
  const data = history.status === "ready" ? history.data : null
  // Stable between the page's own re-renders: new rows would redraw the line.
  const read = useMemo(() => (data?.history ? { range: data.range, rows: balanceRows(data.history.points.map((p) => ({ at: p.at, equity: Number(p.equity) }))) } : null), [data])
  // A new range keeps drawing the last one until its points land, so the line morphs instead of being redrawn.
  const last = useRef(read)
  if (read) last.current = read
  const pending = history.status === "loading" || (data !== null && data.range !== selected)
  const shown = pending ? last.current : read
  const rows: BalanceRow[] = shown?.rows ?? []
  const switching = pending && shown !== null
  const stats = rows.length >= 2 ? rangeStats(rows) : null
  const range = RANGES.find((r) => r.value === (shown?.range ?? selected))!
  const axis = useMemo(() => (rows.length >= 2 ? balanceAxis(rows.map((r) => r.balance)) : null), [rows])
  const tick = (key: string) => (shown?.range === "day" ? timeOfDay(key) : monthDay(key))

  const balance = account.balance
  const change = dayChange(account)
  const scrubbed = point !== null ? rows[point] : undefined
  const figure = scrubbed ? scrubbed.balance : balance ? Number(balance.equity) : null

  const x = (i: number) => (i / (rows.length - 1)) * W
  const y = (value: number) => 104 - ((value - axis!.domain[0]) / Math.max(1e-9, axis!.domain[1] - axis!.domain[0])) * 88
  const points = stats && axis ? rows.map((row, i) => `${x(i).toFixed(1)},${y(row.balance).toFixed(1)}`).join(" ") : ""
  const gliding = picked.current && !reduced
  const showChart = stats && axis && (!pending || switching) && history.status !== "error"
  const moved = scrubbed ? scrubbed.sinceStart : (change?.amount ?? 0)

  return (
    <section className={styles.balance} aria-labelledby="balance-title">
      <div className={styles.balanceTop}>
        <div className={styles.balanceFigure}>
          <h2 id="balance-title" className={styles.balanceLabel}>
            {scrubbed ? formatWeekday(scrubbed.time) : "Balance"}
          </h2>
          <div className={styles.balanceValue} aria-live="polite">
            {figure === null ? <span className={styles.muted}>No balance yet</span> : <AnimatedCounter value={Number(figure.toFixed(2))} prefix="$" decimals={2} />}
          </div>
          <div className={styles.changeLine}>
            {(scrubbed || change) && (
              <span className={styles.change} data-direction={moved < 0 ? "down" : moved > 0 ? "up" : "flat"}>
                {moved < 0 ? <ArrowDownRight01Icon width={16} height={16} aria-hidden="true" /> : moved > 0 ? <ArrowUpRight01Icon width={16} height={16} aria-hidden="true" /> : null}
                {formatSignedUsd(moved)}
              </span>
            )}
            <span className={styles.muted}>{scrubbed ? "since the start of the range" : change ? "today" : ""}</span>
          </div>
        </div>
        <SegmentedControl
          label="Balance range"
          value={selected}
          onValueChange={(value) => {
            picked.current = true
            setPoint(null)
            setSelected(value as HistoryRange)
          }}
          options={RANGES.map((r) => ({ value: r.value, label: r.label }))}
        />
      </div>

      {pending && !switching && <Skeleton label="Loading balance history" lines={3} className={styles.chartSlot} />}
      {history.status === "error" && <RegionNote title="Balance history did not load" message={history.error} onRetry={history.retry} />}
      {!pending && history.status === "ready" && rows.length < 2 && (
        <EmptyState
          title="No balance history for this range"
          description="The broker has not reported a balance for it yet."
          action={
            <Button type="button" variant="secondary" size="sm" onClick={() => (selected === DEFAULT_RANGE ? onRefresh() : setSelected(DEFAULT_RANGE))}>
              {selected === DEFAULT_RANGE ? "Try again" : "Show 1 month"}
            </Button>
          }
        />
      )}
      {showChart && (
        <>
          <div className={styles.chart} onPointerLeave={() => setPoint(null)}>
            <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden="true">
              <path className={styles.chartGuide} d="M0 30H560 M0 70H560 M0 110H560" />
              <motion.polyline
                points={points}
                fill="none"
                stroke="var(--accent)"
                strokeWidth="2"
                vectorEffect="non-scaling-stroke"
                strokeLinejoin="round"
                strokeLinecap="round"
                initial={false}
                animate={{ points }}
                transition={gliding ? motionTokens.spring.smooth : { duration: 0 }}
                onAnimationComplete={() => {
                  picked.current = false
                }}
              />
              {scrubbed && point !== null && <line x1={x(point)} x2={x(point)} y1="0" y2={H} stroke="var(--border-strong)" strokeDasharray="3 4" vectorEffect="non-scaling-stroke" />}
            </svg>
            {scrubbed && point !== null && <span className={styles.chartDot} style={{ left: `${(point / (rows.length - 1)) * 100}%`, top: `${(y(scrubbed.balance) / H) * 100}%` }} aria-hidden="true" />}
            <input
              className={styles.chartScrubber}
              type="range"
              min="0"
              max={rows.length - 1}
              value={point ?? rows.length - 1}
              aria-label={`Explore the balance history, ${range.name}`}
              aria-valuetext={`${formatUsd(rows[point ?? rows.length - 1]!.balance)}, ${formatWeekday(rows[point ?? rows.length - 1]!.time)}`}
              onChange={(event) => setPoint(Number(event.target.value))}
              onBlur={() => setPoint(null)}
              onPointerMove={(event) => {
                if (event.pointerType !== "mouse") return
                const bounds = event.currentTarget.getBoundingClientRect()
                setPoint(Math.max(0, Math.min(rows.length - 1, Math.round(((event.clientX - bounds.left) / bounds.width) * (rows.length - 1)))))
              }}
            />
          </div>
          <div className={styles.chartFoot}>
            <span>{tick(rows[0]!.key)}</span>
            <span className={styles.chartSummary}>{`${formatSignedUsd(stats.change)} (${formatSignedPercent(stats.changeRatio)}) ${range.name}`}</span>
            <span>{tick(rows[rows.length - 1]!.key)}</span>
          </div>
        </>
      )}
    </section>
  )
}
