import { ArrowDownIcon, ArrowUpIcon } from "lucide-react"
import { Badge } from "@/components/reui/badge"
import { FramePanel } from "@/components/reui/frame"
import { Separator } from "@/components/ui/separator"
import { signedPercent } from "@/lib/format"

interface Delta {
  fraction: number
  /** What the change is measured against, e.g. "Yesterday's close: $2,715.27". */
  against: string
}

/** One KPI: the number leads; a change shows as an arrow badge, as in the stat-card example. */
export function Stat({ label, value, note, delta }: { label: string; value: string; note?: string; delta?: Delta }) {
  const up = delta ? delta.fraction >= 0 : true
  return (
    <FramePanel className="flex flex-col gap-2.5">
      <h3 className="text-muted-foreground text-sm font-medium">{label}</h3>
      <div className="flex items-center gap-2.5">
        <span className="text-foreground text-2xl font-medium tracking-tight tabular-nums">{value}</span>
        {delta && (
          <Badge variant={up ? "success-light" : "destructive-light"}>
            {up ? <ArrowUpIcon aria-hidden="true" /> : <ArrowDownIcon aria-hidden="true" />}
            {signedPercent(delta.fraction, 2)}
          </Badge>
        )}
      </div>
      {(delta || note) && (
        <>
          <Separator />
          <div className="text-muted-foreground text-xs tabular-nums">{delta ? delta.against : note}</div>
        </>
      )}
    </FramePanel>
  )
}
