import { useState, type ReactNode } from "react"

import { Button } from "@/components/ui/button"
import { ButtonGroup } from "@/components/ui/button-group"
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Spinner } from "@/components/ui/spinner"
import {
  ToggleGroup,
  ToggleGroupItem,
} from "@/components/ui/toggle-group"
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip"

import { RANGES, type RangeKey, type ViewState } from "./data"
import { UI_ICONS } from "./icons"
import { useTriggerTooltip } from "./use-trigger-tooltip"

export interface ChartActions {
  refresh: () => void
  resetView: () => void
}

/** Pressed lifts to the card surface: the stock muted fill is the header
 *  band's own tone and would vanish on it. */
const PRESSED_LIFT =
  "text-muted-foreground data-pressed:bg-card dark:data-pressed:bg-muted data-pressed:text-foreground"

/** The layers the menu shows or hides. */
const LAYERS = [
  { key: "markers", label: "High and Low", icon: UI_ICONS.markers },
  { key: "average", label: "Average Line", icon: UI_ICONS.average },
] as const satisfies readonly {
  key: Exclude<keyof ViewState, "range">
  label: string
  icon: ReactNode
}[]

/** The header toolbar: the range, then one group of actions: refresh and
 *  more. It wraps between groups, never inside. */
export function ChartToolbar({
  view,
  onRangeChange,
  onViewChange,
  refreshing,
  canReset,
  actions,
}: {
  view: ViewState
  onRangeChange: (range: RangeKey) => void
  onViewChange: (patch: Partial<ViewState>) => void
  refreshing: boolean
  canReset: boolean
  actions: ChartActions
}) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      {/* Re-clicking the pressed item sends an empty array; the guard
          keeps a range selected. */}
      <ToggleGroup
        multiple={false}
        value={[view.range]}
        onValueChange={(value) => {
          const next = RANGES.find((range) => range.value === value[0])
          if (next) onRangeChange(next.value)
        }}
        variant="outline"
        size="sm"
        spacing={0}
        aria-label="Range"
      >
        {RANGES.map((range) => (
          <ToggleGroupItem
            key={range.value}
            value={range.value}
            className={PRESSED_LIFT}
          >
            {range.label}
          </ToggleGroupItem>
        ))}
      </ToggleGroup>
      <ButtonGroup aria-label="Chart actions">
        <Tooltip>
          <TooltipTrigger
            render={
              <Button
                type="button"
                variant="outline"
                size="icon-sm"
                aria-label={
                  refreshing ? "Refreshing balance" : "Refresh balance"
                }
                aria-busy={refreshing}
                disabled={refreshing}
                focusableWhenDisabled
                className="aria-disabled:pointer-events-none aria-disabled:opacity-50"
                onClick={actions.refresh}
              />
            }
          >
            {refreshing ? <Spinner /> : UI_ICONS.refresh}
          </TooltipTrigger>
          <TooltipContent>Refresh balance</TooltipContent>
        </Tooltip>
        <MoreMenu
          view={view}
          onViewChange={onViewChange}
          canReset={canReset}
          actions={actions}
        />
      </ButtonGroup>
    </div>
  )
}

// Layer toggles keep the menu open, so several change in one visit.
function MoreMenu({
  view,
  onViewChange,
  canReset,
  actions,
}: {
  view: ViewState
  onViewChange: (patch: Partial<ViewState>) => void
  canReset: boolean
  actions: ChartActions
}) {
  const [open, setOpen] = useState(false)
  const hint = useTriggerTooltip(open)
  return (
    <DropdownMenu open={open} onOpenChange={(next: boolean) => setOpen(next)}>
      <Tooltip {...hint.tooltip}>
        <TooltipTrigger
          render={
            <DropdownMenuTrigger
              render={
                <Button
                  type="button"
                  variant="outline"
                  size="icon-sm"
                  aria-label="More actions"
                  {...hint.triggerProps}
                />
              }
            />
          }
        >
          {UI_ICONS.more}
        </TooltipTrigger>
        <TooltipContent>More actions</TooltipContent>
      </Tooltip>
      <DropdownMenuContent align="end" className="w-auto">
        <DropdownMenuGroup>
          <DropdownMenuLabel>Show</DropdownMenuLabel>
          {LAYERS.map((layer) => (
            <DropdownMenuCheckboxItem
              key={layer.key}
              checked={view[layer.key]}
              onCheckedChange={(next: boolean) => {
                const patch: Partial<ViewState> = {}
                patch[layer.key] = next
                onViewChange(patch)
              }}
              closeOnClick={false}
            >
              {layer.icon}
              {layer.label}
            </DropdownMenuCheckboxItem>
          ))}
        </DropdownMenuGroup>
        <DropdownMenuSeparator />
        <DropdownMenuGroup>
          <DropdownMenuItem disabled={!canReset} onClick={actions.resetView}>
            {UI_ICONS.reset}
            Reset View
          </DropdownMenuItem>
        </DropdownMenuGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
