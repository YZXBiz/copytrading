import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame"
import { Skeleton } from "@/components/ui/skeleton"

/** The account page's layout with every number still to come: header, stats, chart, limits, positions. */
export function AccountPageSkeleton() {
  return (
    <div role="status" aria-label="Loading account" className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <Skeleton className="h-8 w-56" />
        <Skeleton className="h-5 w-48" />
      </div>
      <Frame spacing="sm" className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }, (_, i) => (
          <FramePanel key={i} className="flex flex-col gap-2.5">
            <Skeleton className="h-4 w-20" />
            <Skeleton className="h-8 w-28" />
            <Skeleton className="h-3 w-32" />
          </FramePanel>
        ))}
      </Frame>
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
        <Frame spacing="sm">
          <FrameHeader>
            <Skeleton className="h-5 w-24" />
          </FrameHeader>
          <FramePanel>
            <Skeleton className="h-[240px] w-full" />
          </FramePanel>
        </Frame>
        <Frame spacing="sm">
          <FrameHeader>
            <Skeleton className="h-5 w-16" />
          </FrameHeader>
          <FramePanel className="flex flex-col gap-4">
            {Array.from({ length: 5 }, (_, i) => (
              <Skeleton key={i} className="h-5 w-full" />
            ))}
          </FramePanel>
        </Frame>
      </div>
      <Frame spacing="sm">
        <FrameHeader>
          <Skeleton className="h-5 w-24" />
        </FrameHeader>
        <FramePanel className="flex flex-col gap-3">
          {Array.from({ length: 3 }, (_, i) => (
            <Skeleton key={i} className="h-8 w-full" />
          ))}
        </FramePanel>
      </Frame>
    </div>
  )
}
