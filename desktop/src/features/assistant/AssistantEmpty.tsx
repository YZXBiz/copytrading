import { SparklesIcon } from "lucide-react"
import { IconStack } from "@/components/reui/icon-stack"
import { Button } from "@/components/ui/button"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"

/** ai-chat-8's zero state. Every chip sends a real question, so it is a way in rather than a poster; before a model is set up it says where to choose one. */
export function AssistantEmpty({ hasModel, suggestions, onAsk, onOpenConnections }: { hasModel: boolean; suggestions: string[]; onAsk: (text: string) => void; onOpenConnections: () => void }) {
  return (
    // Centred while it fits, scrollable once the chips outgrow a short panel. `m-auto` centres without clipping the way justify-center does.
    <div className="scrollbar flex min-h-0 flex-1 flex-col overflow-y-auto px-4 py-4">
      <div className="m-auto flex w-full flex-col gap-6">
        <Empty className="flex-none p-0">
          <EmptyHeader>
            <EmptyMedia className="mb-0">
              <IconStack aria-hidden="true" className="h-16 w-14">
                <SparklesIcon strokeWidth="1.9" className="size-3.5" aria-hidden="true" />
              </IconStack>
            </EmptyMedia>
            <EmptyTitle>Ask about your trading</EmptyTitle>
            {!hasModel && <EmptyDescription>Choose a model in Connections to begin.</EmptyDescription>}
          </EmptyHeader>
        </Empty>

        {hasModel ? (
          <div className="flex flex-wrap justify-center gap-2">
            {suggestions.map((suggestion) => (
              <Button key={suggestion} type="button" variant="outline" size="sm" onClick={() => onAsk(suggestion)} className="text-muted-foreground hover:text-foreground h-auto min-h-8 gap-1.5 py-1 font-normal whitespace-normal">
                {suggestion}
              </Button>
            ))}
          </div>
        ) : (
          <div className="flex justify-center">
            <Button type="button" variant="outline" size="sm" onClick={onOpenConnections}>
              Open Connections
            </Button>
          </div>
        )}
      </div>
    </div>
  )
}
