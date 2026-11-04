import { Children, Fragment, type ReactNode } from "react"
import { Frame, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { ItemGroup, ItemSeparator } from "@/components/ui/item"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"

/** A titled group of settings: its rows in one bordered frame, a hairline between each. What the group is for is a tooltip on the title. */
export function SettingsSection({ title, hint, children }: { title?: string; hint?: string; children: ReactNode }) {
  const rows = Children.toArray(children)
  if (rows.length === 0) return null
  return (
    <Frame spacing="sm">
      {title && (
        <FrameHeader>
          <FrameTitle>
            {hint ? (
              <Tooltip>
                <TooltipTrigger type="button" className="cursor-help text-left">
                  {title}
                </TooltipTrigger>
                <TooltipContent>{hint}</TooltipContent>
              </Tooltip>
            ) : (
              title
            )}
          </FrameTitle>
        </FrameHeader>
      )}
      <FramePanel className="p-0">
        <ItemGroup className="gap-0">
          {rows.map((row, index) => (
            <Fragment key={index}>
              {index > 0 && <ItemSeparator className="my-0!" />}
              {row}
            </Fragment>
          ))}
        </ItemGroup>
      </FramePanel>
    </Frame>
  )
}
