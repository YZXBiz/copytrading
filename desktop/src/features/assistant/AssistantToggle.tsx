import { Button } from "@/components/arc/button/button"
import { Kbd } from "@/components/arc/kbd/kbd"
import { Tooltip } from "@/components/arc/tooltip/tooltip"
import { SparklesIcon } from "@/components/icons/SparklesIcon"
import { useAssistantPanel } from "./AssistantFrame"

/** The header's one control for the Assistant: shows the panel, and presses in while it is open. */
export function AssistantToggle() {
  const { open, toggle } = useAssistantPanel()
  return (
    <Tooltip
      content={
        <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
          {open ? "Hide" : "Show"}
          <Kbd size="sm">mod+j</Kbd>
        </span>
      }
    >
      <Button type="button" variant={open ? "secondary" : "primary"} size="sm" aria-pressed={open} onClick={toggle}>
        <SparklesIcon width={16} height={16} aria-hidden="true" />
        Assistant
      </Button>
    </Tooltip>
  )
}
