import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame"
import { Skeleton } from "@/components/ui/skeleton"

/** The page's layout with every number still to come: header, four cards, two charts, the table. */
export function ActivitySkeleton() {
  return (
    <div role="status" aria-label="Loading posts" className="mx-auto flex w-full max-w-7xl flex-col gap-4">
      <div className="flex min-h-9 items-center justify-between pb-1">
        <Skeleton className="h-4 w-64" />
        <Skeleton className="h-8 w-44" />
      </div>
      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4 xl:gap-3">
        {Array.from({ length: 4 }, (_, i) => (
          <Skeleton key={i} className="h-28 w-full" />
        ))}
      </div>
      <div className="grid min-w-0 gap-3 lg:grid-cols-[minmax(0,1.5fr)_minmax(300px,1fr)]">
        <Skeleton className="h-[440px] w-full" />
        <Skeleton className="h-[440px] w-full" />
      </div>
      <Frame>
        <FrameHeader>
          <Skeleton className="h-8 w-64" />
        </FrameHeader>
        <FramePanel className="flex flex-col gap-3">
          {Array.from({ length: 5 }, (_, i) => (
            <Skeleton key={i} className="h-10 w-full" />
          ))}
        </FramePanel>
      </Frame>
    </div>
  )
}
