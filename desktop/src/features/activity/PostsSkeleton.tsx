import { Skeleton } from "@/components/arc/skeleton/skeleton"

/** Posts still loading, in the shape of feed rows. */
export function PostsSkeleton() {
  return <Skeleton label="Loading posts" lines={4} avatar />
}
