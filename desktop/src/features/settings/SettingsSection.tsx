import { Children, Fragment, type ReactNode } from "react"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { ItemGroup, ItemSeparator } from "@/components/ui/item"
import { Skeleton } from "@/components/ui/skeleton"

/** A titled group of settings, as in ReUI's settings-9: a Frame with its title in a slim header, one line on what it is for, and the rows in one panel with a hairline between each. */
export function SettingsSection({ title, hint, children }: { title?: string; hint?: string; children: ReactNode }) {
  const rows = Children.toArray(children)
  if (rows.length === 0) return null
  return (
    <Frame stacked dense spacing="sm">
      {title && (
        <FrameHeader className="gap-0.5 px-4 py-2">
          <FrameTitle>{title}</FrameTitle>
          {hint && <FrameDescription className="truncate">{hint}</FrameDescription>}
        </FrameHeader>
      )}
      <FramePanel className="p-0!">
        <ItemGroup className="gap-0">
          {rows.map((row, index) => (
            <Fragment key={index}>
              {index > 0 && <ItemSeparator className="my-0" />}
              {row}
            </Fragment>
          ))}
        </ItemGroup>
      </FramePanel>
    </Frame>
  )
}

/** A section's title and `rows` rows while they load, in the shape they will have (so nothing jumps when they arrive). */
export function SectionSkeleton({ rows = 1 }: { rows?: number }) {
  return (
    <Frame stacked dense spacing="sm" role="status" aria-label="Loading">
      <FrameHeader className="px-4 py-2">
        <Skeleton className="h-4 w-32" />
      </FrameHeader>
      <FramePanel className="p-0!">
        <ItemGroup className="gap-0">
          {Array.from({ length: rows }, (_, index) => (
            <Fragment key={index}>
              {index > 0 && <ItemSeparator className="my-0" />}
              <div className="flex items-center justify-between gap-4 px-4 py-3">
                <div className="flex flex-col gap-1.5">
                  <Skeleton className="h-4 w-40" />
                  <Skeleton className="h-3.5 w-56" />
                </div>
                <Skeleton className="h-8 w-28" />
              </div>
            </Fragment>
          ))}
        </ItemGroup>
      </FramePanel>
    </Frame>
  )
}
