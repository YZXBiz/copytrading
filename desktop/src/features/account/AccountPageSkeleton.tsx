import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame"
import { Skeleton } from "@/components/ui/skeleton"

/** The account page's layout with every number still to come: navbar, command band, chart beside limits, posts. */
export function AccountPageSkeleton() {
  return (
    <div role="status" aria-label="Loading account" className="mx-auto flex w-full max-w-7xl flex-col gap-5">
      <div className="flex min-h-9 items-center justify-between pb-1">
        <Skeleton className="h-5 w-48" />
        <Skeleton className="h-8 w-40" />
      </div>
      <Frame>
        <FramePanel className="flex flex-col gap-4">
          <div className="flex items-start justify-between gap-4">
            <div className="flex flex-col gap-3">
              <Skeleton className="h-5 w-40" />
              <Skeleton className="h-8 w-56" />
              <Skeleton className="h-5 w-32" />
            </div>
            <Skeleton className="h-24 w-72" />
          </div>
          <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
            {Array.from({ length: 4 }, (_, i) => (
              <Skeleton key={i} className="h-14 w-full" />
            ))}
          </div>
        </FramePanel>
      </Frame>
      <div className="grid min-w-0 items-stretch gap-4 lg:grid-cols-[minmax(0,1.6fr)_minmax(320px,1fr)]">
        <Frame>
          <FrameHeader>
            <Skeleton className="h-5 w-24" />
          </FrameHeader>
          <FramePanel>
            <Skeleton className="h-80 w-full" />
          </FramePanel>
        </Frame>
        <Frame>
          <FrameHeader>
            <Skeleton className="h-5 w-40" />
          </FrameHeader>
          <FramePanel className="flex flex-col gap-4">
            {Array.from({ length: 5 }, (_, i) => (
              <Skeleton key={i} className="h-10 w-full" />
            ))}
          </FramePanel>
        </Frame>
      </div>
      <Frame>
        <FrameHeader>
          <Skeleton className="h-5 w-32" />
        </FrameHeader>
        <FramePanel className="flex flex-col gap-3">
          {Array.from({ length: 4 }, (_, i) => (
            <Skeleton key={i} className="h-9 w-full" />
          ))}
        </FramePanel>
      </Frame>
    </div>
  )
}
