import { Skeleton } from "@/components/ui/skeleton"

/** Posts still loading, in the shape of a timeline event: its title, then the frame under it. */
export function PostsSkeleton() {
  return (
    <div role="status" aria-label="Loading posts" className="space-y-6">
      {Array.from({ length: 4 }, (_, i) => (
        <div key={i} className="ms-10 space-y-2">
          <Skeleton className="h-4 w-1/3" />
          <Skeleton className="h-9 w-full" />
        </div>
      ))}
    </div>
  )
}
