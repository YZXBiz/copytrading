import { Button } from "@/components/arc/button/button"
import styles from "./assistant.module.css"

/** The zero state. Every chip sends a real question, so it is a way in rather than a poster; before a model is set up it says where to choose one. */
export function AssistantEmpty({ hasModel, suggestions, onAsk, onOpenConnections }: { hasModel: boolean; suggestions: string[]; onAsk: (text: string) => void; onOpenConnections: () => void }) {
  return (
    <div className={styles.thread}>
      <div className={styles.threadInner}>
        <div className={styles.empty}>
          <h3 className={styles.emptyTitle}>Ask about your trading</h3>
          {hasModel ? (
            <ul className={styles.suggestions}>
              {suggestions.map((suggestion) => (
                <li key={suggestion}>
                  <button type="button" className={styles.suggestion} onClick={() => onAsk(suggestion)}>
                    {suggestion}
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <>
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
