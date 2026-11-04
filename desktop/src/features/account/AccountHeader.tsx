import type { AccountOverview } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"

const COPYING = {
  enabled: { label: "Copying", variant: "success-light" },
  paused: { label: "Paused", variant: "warning-light" },
  disabled: { label: "Not copying", variant: "outline" },
} as const

export function AccountHeader({ account, guru }: { account: AccountOverview; guru: string | null }) {
  const state = COPYING[account.entry_permission as keyof typeof COPYING] ?? COPYING.disabled
  return (
    <div className="flex flex-col gap-1.5">
      <h1 className="text-2xl font-semibold tracking-tight">{account.account_id}</h1>
      <div className="flex items-center gap-2">
        <Badge variant="outline">{account.environment === "paper" ? "Paper" : "Live"}</Badge>
        <Badge variant={state.variant}>{state.label}</Badge>
        {guru && <span className="text-muted-foreground text-xs">Copies {guru}</span>}
      </div>
    </div>
  )
}
