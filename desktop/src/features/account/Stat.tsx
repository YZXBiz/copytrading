import { FramePanel } from "@/components/reui/frame"

/** One KPI: the figure leads, its label above it. `note` is only for a fact that changes what the owner does. */
export function Stat({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <FramePanel className="flex flex-col gap-1.5">
      <h3 className="text-muted-foreground text-sm font-medium">{label}</h3>
      <span className="text-foreground text-2xl font-semibold tracking-tight tabular-nums">{value}</span>
      {note && <p className="text-muted-foreground text-xs tabular-nums">{note}</p>}
    </FramePanel>
  )
}
