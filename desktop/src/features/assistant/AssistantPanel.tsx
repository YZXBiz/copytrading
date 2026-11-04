import { type KeyboardEvent } from "react"
import { ChevronsLeftRightIcon, SparklesIcon, SquarePenIcon, XIcon } from "lucide-react"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Sidebar, SidebarContent, SidebarFooter, SidebarHeader, useSidebar } from "@/components/ui/sidebar"
import { Skeleton } from "@/components/ui/skeleton"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { type Loaded } from "@/lib/use-result"
import { AssistantComposer } from "./AssistantComposer"
import { AssistantEmpty } from "./AssistantEmpty"
import { AssistantTranscript } from "./AssistantTranscript"
import type { useAssistant } from "./use-assistant"

const MUTED_ICON_BUTTON = "text-muted-foreground hover:text-foreground"

interface Props {
  model: Loaded<unknown> & { retry: () => void }
  ready: boolean
  /** The model that answers. */
  provider: { name: string; model: string } | null
  suggestions: string[]
  assistant: ReturnType<typeof useAssistant>
  wide: boolean
  onWide: (wide: boolean) => void
  onAsk: (text: string) => void
  onOpenConnections: () => void
}

/** ai-chat-8's docked panel: a floating right sidebar with a quiet header, the conversation, and a composer pinned under it. */
export function AssistantPanel({ model, ready, provider, suggestions, assistant, wide, onWide, onAsk, onOpenConnections }: Props) {
  const { isMobile, open, setOpen, toggleSidebar } = useSidebar()
  // Off canvas leaves the composer and its buttons focusable behind the page.
  const offscreen = !isMobile && !open

  return (
    <Sidebar
      side="right"
      variant="floating"
      collapsible="offcanvas"
      aria-label="Assistant"
      aria-hidden={offscreen || undefined}
      inert={offscreen || undefined}
      onKeyDown={(event: KeyboardEvent) => {
        if (event.key === "Escape") setOpen(false)
      }}
    >
      <SidebarHeader className="shrink-0 gap-0 border-b p-0">
        <div className="flex min-h-12 items-center gap-1 px-3">
          <span className="text-primary">
            <SparklesIcon className="size-4 shrink-0" aria-hidden="true" />
          </span>
          <span className="min-w-0 truncate ps-2 text-start text-sm font-medium">Assistant</span>
          <div className="ms-auto flex shrink-0 items-center gap-0.5">
            <Tooltip>
              <TooltipTrigger
                render={<Button type="button" variant="ghost" size="icon-sm" aria-label="Widen the panel" aria-pressed={wide} onClick={() => onWide(!wide)} className={`${MUTED_ICON_BUTTON} aria-pressed:text-foreground`} />}
              >
                <ChevronsLeftRightIcon className="size-3.5" aria-hidden="true" />
              </TooltipTrigger>
              <TooltipContent>{wide ? "Narrow" : "Widen"}</TooltipContent>
            </Tooltip>
            {assistant.messages.length > 0 && (
              <Tooltip>
                <TooltipTrigger
                  render={<Button type="button" variant="ghost" size="icon-sm" aria-label="New conversation" onClick={() => void assistant.reset()} className={MUTED_ICON_BUTTON} />}
                >
                  <SquarePenIcon className="size-3.5" aria-hidden="true" />
                </TooltipTrigger>
                <TooltipContent>New chat</TooltipContent>
              </Tooltip>
            )}
            <Tooltip>
              <TooltipTrigger render={<Button type="button" variant="ghost" size="icon-sm" aria-label="Hide assistant" onClick={toggleSidebar} className={MUTED_ICON_BUTTON} />}>
                <XIcon aria-hidden="true" />
              </TooltipTrigger>
              <TooltipContent>Hide</TooltipContent>
            </Tooltip>
          </div>
        </div>
      </SidebarHeader>

      {/* The slot ships overflow-auto, which would nest a second scroll container inside the transcript's own viewport. */}
      <SidebarContent className="overflow-hidden">
        {model.status === "error" ? (
          <div className="p-4">
            <RegionError title="The assistant's model did not load" message={model.error} onRetry={model.retry} />
          </div>
        ) : model.status === "loading" ? (
          <div role="status" aria-label="Loading the assistant" className="flex flex-1 flex-col gap-3 p-4">
            <Skeleton className="h-6 w-2/3" />
            <Skeleton className="h-12 w-full" />
          </div>
        ) : assistant.messages.length === 0 ? (
          <AssistantEmpty hasModel={ready} suggestions={suggestions} onAsk={onAsk} onOpenConnections={onOpenConnections} />
        ) : (
          <AssistantTranscript messages={assistant.messages} answering={assistant.answering} />
        )}
      </SidebarContent>

      {/* The transcript's bottom fade is absolutely positioned, so it paints above anything in normal flow until the composer is raised past it. */}
      <SidebarFooter className="relative z-10 mt-2 shrink-0 gap-2 px-4 pt-2 pb-4">
        <AssistantComposer open={open} answering={assistant.answering} enabled={ready} provider={provider} onSend={onAsk} onStop={() => void assistant.stop()} />
      </SidebarFooter>
    </Sidebar>
  )
}
