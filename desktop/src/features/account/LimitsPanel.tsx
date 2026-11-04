import { GaugeIcon } from "lucide-react"
import type { AccountLimits, AccountOverview } from "../../../shared/contract"
import { Frame, FramePanel } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Progress, ProgressLabel, ProgressValue } from "@/components/ui/progress"
import { Skeleton } from "@/components/ui/skeleton"
import { money } from "@/lib/format"
import { type Loaded } from "@/lib/use-result"

function Meter({ label, used, cap }: { label: string; used: number; cap: number }) {
  return (
    <Progress value={Math.min(100, (used / cap) * 100)}>
      <ProgressLabel className="text-muted-foreground font-normal">{label}</ProgressLabel>
      <ProgressValue>{() => `${money(used)} of ${money(cap)}`}</ProgressValue>
    </Progress>
  )
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className="tabular-nums">{value}</span>
    </div>
  )
}

export function LimitsPanel({
  account,
  limits,
  onOpenConnections,
  onEdit,
}: {
  account: AccountOverview
  limits: Loaded<AccountLimits | null> & { retry: () => void }
  onOpenConnections: () => void
  onEdit: () => void
}) {
  const lossToday = Math.max(0, -Number(account.balance?.day_change_usd ?? 0))
  return (
    <Frame stacked className="@container w-full">
      <FramePanel className="flex items-center justify-between gap-4 p-3.5!">
        {/* Header */}
        <h2 className="text-foreground text-base font-medium">Limits</h2>
        {limits.status === "ready" && limits.data && (
          <Button type="button" size="sm" variant="outline" onClick={onEdit}>
            Edit Limits
          </Button>
        )}
      </FramePanel>
      <FramePanel className="flex flex-col gap-4 p-5!">
        {limits.status === "loading" && (
          <div role="status" aria-label="Loading limits" className="flex flex-col gap-4">
            {Array.from({ length: 5 }, (_, i) => (
              <Skeleton key={i} className="h-5 w-full" />
            ))}
          </div>
        )}
        {limits.status === "error" && <RegionError title="Limits did not load" message={limits.error} onRetry={limits.retry} />}
        {limits.status === "ready" && !limits.data && (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <GaugeIcon />
              </EmptyMedia>
              <EmptyTitle>No limits to show</EmptyTitle>
              <EmptyDescription>Save the account in Connections first.</EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Button type="button" size="sm" variant="outline" onClick={onOpenConnections}>
                Open Connections
              </Button>
            </EmptyContent>
          </Empty>
        )}
        {limits.status === "ready" && limits.data && (
          <>
            <Meter label="Loss today" used={lossToday} cap={limits.data.daily_loss_cap_usd} />
            <Meter label="Invested" used={Number(account.total_exposure_usd ?? 0)} cap={limits.data.max_total_usd} />
            <Fact label="Each order" value={money(limits.data.max_order_usd)} />
            <Fact label="Each stock" value={money(limits.data.max_symbol_usd)} />
            <Fact label="Buys per day" value={String(limits.data.max_entries_per_day)} />
          </>
        )}
      </FramePanel>
    </Frame>
  )
}
