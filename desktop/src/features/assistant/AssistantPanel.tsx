import { Cancel01Icon } from "@/components/icons/Cancel01Icon"
import { ChevronsLeftRightIcon } from "@/components/icons/ChevronsLeftRightIcon"
import { SparklesIcon } from "@/components/icons/SparklesIcon"
import { SquarePenIcon } from "@/components/icons/SquarePenIcon"
import { Button } from "@/components/arc/button/button"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { Tooltip } from "@/components/arc/tooltip/tooltip"
import { SectionError } from "@/features/settings/SectionError"
import { type Loaded } from "@/lib/use-result"
import { AssistantComposer } from "./AssistantComposer"
import { AssistantEmpty } from "./AssistantEmpty"
import { AssistantTranscript } from "./AssistantTranscript"
import type { useAssistant } from "./use-assistant"
import styles from "./assistant.module.css"

interface Props {
  model: Loaded<unknown> & { retry: () => void }
  ready: boolean
  /** The model that answers. */
  provider: { name: string; model: string } | null
  suggestions: string[]
  assistant: ReturnType<typeof useAssistant>
  open: boolean
  wide: boolean
  onWide: (wide: boolean) => void
  onHide: () => void
  onAsk: (text: string) => void
  onOpenConnections: () => void
}

/** The docked panel: a quiet header, the conversation, and a composer pinned under it. */
export function AssistantPanel({ model, ready, provider, suggestions, assistant, open, wide, onWide, onHide, onAsk, onOpenConnections }: Props) {
  return (
    <div className={styles.panel}>
      <header className={styles.head}>
        <span className={styles.identity}>
          <SparklesIcon width={16} height={16} aria-hidden="true" />
          <span className={styles.name}>Assistant</span>
        </span>
        <div className={styles.headActions}>
          <Tooltip content={wide ? "Narrow" : "Widen"}>
            <Button type="button" variant="ghost" size="sm" aria-label="Widen the panel" aria-pressed={wide} onClick={() => onWide(!wide)}>
              <ChevronsLeftRightIcon width={16} height={16} aria-hidden="true" />
            </Button>
          </Tooltip>
          {assistant.messages.length > 0 && (
            <Tooltip content="New chat">
              <Button type="button" variant="ghost" size="sm" aria-label="New conversation" onClick={() => void assistant.reset()}>
                <SquarePenIcon width={16} height={16} aria-hidden="true" />
              </Button>
            </Tooltip>
          )}
          <Tooltip content="Hide">
            <Button type="button" variant="ghost" size="sm" aria-label="Hide assistant" onClick={onHide}>
              <Cancel01Icon width={16} height={16} aria-hidden="true" />
            </Button>
          </Tooltip>
        </div>
      </header>

      {model.status === "error" ? (
        <div className={styles.state}>
          <SectionError title="The assistant's model did not load" message={model.error} onRetry={model.retry} />
        </div>
      ) : model.status === "loading" ? (
        <div className={styles.state}>
          <Skeleton label="Loading the assistant" lines={2} />
        </div>
      ) : assistant.messages.length === 0 ? (
        <AssistantEmpty hasModel={ready} suggestions={suggestions} onAsk={onAsk} onOpenConnections={onOpenConnections} />
      ) : (
        <AssistantTranscript messages={assistant.messages} answering={assistant.answering} />
      )}

      <AssistantComposer open={open} answering={assistant.answering} enabled={ready} provider={provider} onSend={onAsk} onStop={() => void assistant.stop()} />
    </div>
  )
}
