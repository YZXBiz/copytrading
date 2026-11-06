import { Button } from "@/components/arc/button/button"
import { StarterPrompts } from "@/components/arc/starter-prompts/starter-prompts"
import styles from "./assistant.module.css"

/** The zero state. Every card sends a real question, so it is a way in rather than a poster; before a model is set up it says where to choose one. */
export function AssistantEmpty({ hasModel, suggestions, onAsk, onOpenConnections }: { hasModel: boolean; suggestions: string[]; onAsk: (text: string) => void; onOpenConnections: () => void }) {
  return (
    <div className={styles.thread}>
      <div className={styles.threadInner}>
        <div className={styles.empty}>
          {hasModel ? (
            <StarterPrompts
              greeting="Ask about your trading"
              description="Pick a question or write your own below."
              prompts={suggestions.map((suggestion) => ({ id: suggestion, title: suggestion }))}
              onSelect={(prompt) => onAsk(prompt.title)}
            />
          ) : (
            <>
              <h3 className={styles.emptyTitle}>Ask about your trading</h3>
              <p className={styles.emptyText}>Choose a model in Connections to begin.</p>
              <div>
                <Button type="button" variant="secondary" size="sm" onClick={onOpenConnections}>
                  Open Connections
                </Button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
