import { HammerIcon } from "@/components/icons/HammerIcon"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"

/** What a screen shows until the worker who ports it replaces its entry in screens.tsx. */
export function ScreenPlaceholder({ title }: { title: string }) {
  return (
    <Empty className="min-h-[60vh]">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <HammerIcon />
        </EmptyMedia>
        <EmptyTitle>{title}</EmptyTitle>
        <EmptyDescription>This screen is not ported to the new app yet.</EmptyDescription>
      </EmptyHeader>
    </Empty>
  )
}
