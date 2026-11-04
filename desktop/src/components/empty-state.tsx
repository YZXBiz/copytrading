import type { LucideIcon } from "lucide-react"
import { IconStack } from "@/components/reui/icon-stack"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"

/** An empty list, as ReUI draws one: the icon-stack with one glyph, a title, a line that adds a fact, and at most one action. */
export function EmptyState({ icon: Icon, title, description, action, className }: { icon: LucideIcon; title: string; description?: string; action?: { label: string; onClick: () => void }; className?: string }) {
  return (
    <Empty className={className}>
      <EmptyHeader>
        <EmptyMedia className="mb-0">
          <IconStack aria-hidden="true" className="h-16 w-14">
            <Icon strokeWidth="1.9" className="size-3.5" aria-hidden="true" />
          </IconStack>
        </EmptyMedia>
        <EmptyTitle>{title}</EmptyTitle>
        {description && <EmptyDescription>{description}</EmptyDescription>}
      </EmptyHeader>
      {action && (
        <EmptyContent>
          <Button type="button" size="sm" variant="outline" onClick={action.onClick}>
            {action.label}
          </Button>
        </EmptyContent>
      )}
    </Empty>
  )
}
