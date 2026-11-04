import { HammerIcon } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"

/** Gurus, Connections and Settings arrive with the screens that own them. */
export function ScreenPlaceholder({ title, onBack }: { title: string; onBack: () => void }) {
  return (
    <Empty className="min-h-[60vh]">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <HammerIcon />
        </EmptyMedia>
        <EmptyTitle>{title} is not built yet</EmptyTitle>
        <EmptyDescription>This screen comes in a later step of the move to the new desktop app.</EmptyDescription>
      </EmptyHeader>
      <EmptyContent>
        <Button type="button" size="sm" variant="outline" onClick={onBack}>
          Back to accounts
        </Button>
      </EmptyContent>
    </Empty>
  )
}
