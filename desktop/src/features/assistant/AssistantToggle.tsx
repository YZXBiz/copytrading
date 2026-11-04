import { SparklesIcon } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { Kbd } from "@/components/ui/kbd"
import { useSidebar } from "@/components/ui/sidebar"

/** The header's one control for the Assistant: shows the panel, and presses in while it is open. */
export function AssistantToggle() {
  const { open, toggleSidebar } = useSidebar()
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <Button variant={open ? "secondary" : "default"} size="sm" aria-pressed={open} onClick={toggleSidebar} className="gap-1.5">
            <SparklesIcon aria-hidden="true" />
            Assistant
          </Button>
        }
      />
      <TooltipContent className="flex items-center gap-1.5">
        {open ? "Hide" : "Show"}
        <Kbd>⌘J</Kbd>
      </TooltipContent>
    </Tooltip>
  )
}
