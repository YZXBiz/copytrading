import { ArrowUpRightIcon, SparklesIcon } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Item, ItemActions, ItemContent, ItemGroup, ItemSeparator, ItemTitle } from "@/components/ui/item"

/** Before the first question: four to start with, or, before a model is set up, where to choose one. */
export function AssistantEmpty({ hasModel, suggestions, onAsk, onOpenConnections }: { hasModel: boolean; suggestions: string[]; onAsk: (text: string) => void; onOpenConnections: () => void }) {
  return (
    <Empty className="flex-1 justify-start gap-6 pt-10">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <SparklesIcon />
        </EmptyMedia>
        <EmptyTitle>Ask about your trading</EmptyTitle>
        {!hasModel && <EmptyDescription>Choose a model in Connections to begin.</EmptyDescription>}
      </EmptyHeader>
      <EmptyContent className="max-w-none">
        {hasModel ? (
          <ItemGroup className="w-full gap-0">
            {suggestions.map((suggestion, index) => (
              <div key={suggestion}>
                {index > 0 && <ItemSeparator className="my-0!" />}
                <Item size="xs" render={<button type="button" onClick={() => onAsk(suggestion)} />} className="text-left">
                  <ItemContent>
                    <ItemTitle>{suggestion}</ItemTitle>
                  </ItemContent>
                  <ItemActions>
                    <ArrowUpRightIcon className="text-muted-foreground size-4" aria-hidden />
                  </ItemActions>
                </Item>
              </div>
            ))}
          </ItemGroup>
        ) : (
          <Button type="button" variant="outline" size="sm" onClick={onOpenConnections}>
            Open Connections
          </Button>
        )}
      </EmptyContent>
    </Empty>
  )
}
