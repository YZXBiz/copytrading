import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart"
import { ChartLegend } from "./ChartLegend"
import { COUNT_CONFIG, OUTCOME_CONFIG } from "./chart-config"
import { BUCKETS, BUCKET_LABEL, type GuruMix } from "./post-bucket"

/** dashboard-7's four bar fills: a diagonal, dots, vertical and horizontal lines over the outcome's colour. */
const FILLS: Record<(typeof BUCKETS)[number], React.ReactNode> = {
  traded: <path d="M-1 8L8 -1M3 9L9 3" stroke="var(--color-background)" strokeOpacity={0.2} strokeWidth={1} />,
  waiting: (
    <>
      <circle cx="2" cy="2" r="0.9" fill="var(--color-background)" fillOpacity={0.22} />
      <circle cx="6" cy="6" r="0.9" fill="var(--color-background)" fillOpacity={0.22} />
    </>
  ),
  skipped: <path d="M2 0V8M6 0V8" stroke="var(--color-background)" strokeOpacity={0.18} strokeWidth={1} />,
  ignored: <path d="M0 2H8M0 6H8" stroke="var(--color-background)" strokeOpacity={0.18} strokeWidth={1} />,
}

function Patterns() {
  return (
    <>
      {BUCKETS.map((bucket) => (
        <pattern key={bucket} id={`activity-mix-${bucket}`} width="8" height="8" patternUnits="userSpaceOnUse">
          <rect width="8" height="8" fill={`var(--color-${bucket})`} />
          {FILLS[bucket]}
        </pattern>
      ))}
    </>
  )
}

const lines = (text: string, width: number): string[] => {
  const out: string[] = []
  let line = ""
  for (const word of text.split(" ")) {
    if (line && `${line} ${word}`.length > width) {
      out.push(line)
      line = word
    } else line = line ? `${line} ${word}` : word
  }
  if (line) out.push(line)
  return out.length > 2 ? [out[0]!, `${out[1]!.slice(0, width - 1)}…`] : out
}

/** A reason in words, on up to two lines to the left of its bar. */
function ReasonTick({ x, y, payload }: { x?: number; y?: number; payload?: { value: string } }) {
  const [first, second] = lines(payload?.value ?? "", 24)
  return (
    <text x={(x ?? 0) - 4} y={y} textAnchor="end" className="fill-muted-foreground text-xs">
      <tspan x={(x ?? 0) - 4} dy={second ? "-0.35em" : "0.35em"}>{first}</tspan>
      {second && <tspan x={(x ?? 0) - 4} dy="1.2em">{second}</tspan>}
    </text>
  )
}

export type Mix = { kind: "gurus"; rows: GuruMix[] } | { kind: "reasons"; rows: { reason: string; count: number }[] }

/** dashboard-7's Channel Mix chart: how each guru's posts ended, or, with one guru, the top reasons posts were skipped. */
export function MixChart({ mix }: { mix: Mix }) {
  const gurus = mix.kind === "gurus"
  return (
    <Frame className="flex h-full min-w-0 flex-col">
      <FrameHeader className="flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-col gap-px">
          <FrameTitle>{gurus ? "Outcome mix" : "Why posts were skipped"}</FrameTitle>
          <FrameDescription>{gurus ? "Share of each guru's posts, last 30 days" : "Top reasons, last 30 days"}</FrameDescription>
        </div>
      </FrameHeader>
      <FramePanel className="flex min-h-[360px] flex-1 flex-col gap-4">
        {gurus ? <GuruBars rows={mix.rows} /> : <ReasonBars rows={mix.rows} />}
      </FramePanel>
    </Frame>
  )
}

const percentRows = (rows: GuruMix[]) =>
  rows.map((row) => {
    const share = Object.fromEntries(BUCKETS.map((b) => [b, Math.round((row[b] / row.total) * 100)])) as Record<(typeof BUCKETS)[number], number>
    // Rounding can leave the stack at 99 or 101: the last outcome takes the difference.
    const last = [...BUCKETS].reverse().find((b) => row[b] > 0) ?? "ignored"
    share[last] = Math.max(share[last] + 100 - BUCKETS.reduce((n, b) => n + share[b], 0), 0)
    return { ...share, guru: row.guru, counts: row }
  })

function GuruBars({ rows }: { rows: GuruMix[] }) {
  const data = percentRows(rows)
  const posts = rows.reduce((n, r) => n + r.total, 0)
  const traded = rows.reduce((n, r) => n + r.traded, 0)
  return (
    <>
      <div className="grid grid-cols-2 gap-3">
        <div className="min-w-0">
          <div className="text-muted-foreground text-xs">Gurus</div>
          <div className="text-lg font-semibold tabular-nums">{rows.length}</div>
        </div>
        <div className="min-w-0">
          <div className="text-muted-foreground text-xs">Traded</div>
          <div className="text-lg font-semibold tabular-nums">{posts > 0 ? `${Math.round((traded / posts) * 100)}%` : "—"}</div>
        </div>
      </div>
      <ChartLegend />
      <ChartContainer config={OUTCOME_CONFIG} className="mt-auto h-64 w-full min-w-0">
        <BarChart accessibilityLayer data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
          <defs>
            <Patterns />
          </defs>
          <CartesianGrid vertical={false} strokeDasharray="3 3" />
          <XAxis dataKey="guru" tickLine={false} axisLine={false} tickMargin={10} />
          <ChartTooltip
            cursor={false}
            content={
              <ChartTooltipContent
                indicator="dot"
                formatter={(value, name, item) => {
                  const bucket = String(name) as (typeof BUCKETS)[number]
                  const count = item.payload?.counts?.[bucket] ?? 0
                  return (
                    <div className="flex flex-1 items-center justify-between gap-6">
                      <span className="text-muted-foreground">{BUCKET_LABEL[bucket]}</span>
                      <span className="font-mono font-medium tabular-nums">
                        {count} {count === 1 ? "post" : "posts"}, {String(value)}%
                      </span>
                    </div>
                  )
                }}
              />
            }
          />
          {BUCKETS.map((bucket, i) => (
            <Bar key={bucket} dataKey={bucket} stackId="posts" fill={`url(#activity-mix-${bucket})`} maxBarSize={72} radius={i === 0 ? [0, 0, 4, 4] : i === BUCKETS.length - 1 ? [4, 4, 0, 0] : 0} />
          ))}
        </BarChart>
      </ChartContainer>
    </>
  )
}

function ReasonBars({ rows }: { rows: { reason: string; count: number }[] }) {
  if (rows.length === 0) return <p className="text-muted-foreground m-auto text-sm">No post was skipped in the last 30 days.</p>
  const total = rows.reduce((n, r) => n + r.count, 0)
  return (
    <>
      <div className="grid grid-cols-2 gap-3">
        <div className="min-w-0">
          <div className="text-muted-foreground text-xs">Skipped</div>
          <div className="text-lg font-semibold tabular-nums">{total}</div>
        </div>
        <div className="min-w-0">
          <div className="text-muted-foreground text-xs">Most common</div>
          <div className="truncate text-lg font-semibold tabular-nums">{rows[0]!.count}×</div>
        </div>
      </div>
      <ChartContainer config={COUNT_CONFIG} className="mt-auto h-64 w-full min-w-0">
        <BarChart accessibilityLayer layout="vertical" data={rows} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
          <defs>
            <pattern id="activity-mix-reasons" width="8" height="8" patternUnits="userSpaceOnUse">
              <rect width="8" height="8" fill="var(--color-count)" />
              {FILLS.skipped}
            </pattern>
          </defs>
          <CartesianGrid horizontal={false} strokeDasharray="3 3" />
          <XAxis type="number" hide allowDecimals={false} />
          <YAxis type="category" dataKey="reason" width={170} tickLine={false} axisLine={false} tick={<ReasonTick />} interval={0} />
          <ChartTooltip cursor={false} content={<ChartTooltipContent indicator="dot" labelFormatter={(_, items) => String(items?.[0]?.payload?.reason ?? "")} />} />
          <Bar dataKey="count" fill="url(#activity-mix-reasons)" radius={4} maxBarSize={28} />
        </BarChart>
      </ChartContainer>
    </>
  )
}
