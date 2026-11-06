import { AgentAccess } from "./AgentAccess"
import { AgentRequests } from "./AgentRequests"
import styles from "./settings.module.css"

/** Requests from the assistant and from agents, and what happened to them. */
export function AgentsPage() {
  return (
    <div className={styles.page}>
      <AgentAccess />
      <AgentRequests />
    </div>
  )
}
