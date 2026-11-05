import { BUCKETS, BUCKET_LABEL } from "./post-bucket"
import { OUTCOME_CONFIG } from "./chart-config"

/** dashboard-7's legend row: a dot and a word for each outcome. */
export function ChartLegend({ only }: { only?: readonly (typeof BUCKETS)[number][] }) {
  return (
    <div className="text-muted-foreground flex flex-wrap items-center gap-x-3 gap-y-1 text-xs sm:justify-end">
      {(only ?? BUCKETS).map((bucket) => (
        <span key={bucket} className="inline-flex items-center gap-1.5">
          <span className="size-2 rounded-full" style={{ backgroundColor: OUTCOME_CONFIG[bucket].color }} aria-hidden />
          {BUCKET_LABEL[bucket]}
        </span>
      ))}
    </div>
  )
}
