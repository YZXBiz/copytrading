import { BUCKETS, BUCKET_LABEL, type Bucket } from "./post-bucket"

/** One colour per way a post can end: the accent for the data that matters, the status colour for a call that waits, quiet steps for the rest. */
export const OUTCOME_COLOR: Record<Bucket, string> = {
  traded: "var(--accent)",
  waiting: "var(--warning)",
  skipped: "var(--series-3)",
  ignored: "var(--text-muted)",
}

export const OUTCOME_SERIES = BUCKETS.map((bucket) => ({ key: bucket, label: BUCKET_LABEL[bucket], color: OUTCOME_COLOR[bucket], area: false }))
