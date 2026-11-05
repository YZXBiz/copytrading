import { Cancel01Icon } from "@/components/icons/Cancel01Icon"
import { Copy01Icon } from "@/components/icons/Copy01Icon"
import { File01Icon } from "@/components/icons/File01Icon"
import { Tick02Icon } from "@/components/icons/Tick02Icon"
import { Alert } from "@/components/arc/alert/alert"
import { Button } from "@/components/arc/button/button"
import { Tooltip } from "@/components/arc/tooltip/tooltip"
import { navigate } from "@/features/shell/route"
import { AssistantProposalCard } from "./AssistantProposalCard"
import { type Link, type Message as Turn, isRefusal, uniqueLinks } from "./conversation"
import { Markdown } from "./Markdown"
import styles from "./assistant.module.css"

/** Opens what an answer points at: the account, the guru, or the post's screen. */
function open(link: Link) {
  if (link.kind === "account") navigate("accounts", link.id)
  else if (link.kind === "guru") navigate("gurus", link.id)
  else if (link.kind === "post") navigate("activity")
}

const KIND: Record<string, string> = { account: "Account", guru: "Guru", post: "Post" }

/**
 * One turn, in the shape the engine returns it. The owner's question is a bubble at the trailing edge. The answer is what it
 * looked at (steps), its words, the places it points to (chips), a request waiting for approval, or why it stopped.
 */
export function AssistantMessageRow({ message, writing }: { message: Turn; writing: boolean }) {
  if (message.author === "owner") {
    return (
      <div className={styles.ask}>
        <p className={styles.askBubble}>{message.text}</p>
      </div>
    )
  }
  const working = writing && message.text === "" && message.errorText === null
  const links = uniqueLinks(message.links)
  return (
    <div className={styles.answer}>
      {message.steps.length > 0 && (
        <ul className={styles.steps}>
          {message.steps.map((step, i) => (
            <li key={i} className={styles.step} data-refusal={isRefusal(step) || undefined}>
              {isRefusal(step) ? <Cancel01Icon width={16} height={16} aria-hidden="true" /> : <Tick02Icon width={16} height={16} aria-hidden="true" />}
              <span>{step}</span>
            </li>
          ))}
        </ul>
      )}
      {message.text && <Markdown text={message.text} />}
      {working && <div className={styles.thinking}>{message.steps.length === 0 ? "Looking into it…" : "Still looking…"}</div>}
      {message.proposalIds.map((id) => (
        <AssistantProposalCard key={id} proposalId={id} />
      ))}
      {links.length > 0 && (
        <ul className={styles.links}>
          {links.map((link) => (
            <li key={`${link.kind}:${link.id}`}>
              <button type="button" className={styles.link} onClick={() => open(link)}>
                <File01Icon width={16} height={16} aria-hidden="true" />
                <span>{link.title}</span>
                <small>{KIND[link.kind] ?? "Link"}</small>
              </button>
            </li>
          ))}
        </ul>
      )}
      {message.errorText && <Alert tone="warning" title={message.errorText} />}
      {message.text && !writing && (
        <div className={styles.turnActions}>
          <Tooltip content="Copy">
            <Button type="button" size="sm" variant="ghost" aria-label="Copy answer" onClick={() => void navigator.clipboard?.writeText(message.text)}>
              <Copy01Icon width={16} height={16} aria-hidden="true" />
            </Button>
          </Tooltip>
        </div>
      )}
    </div>
  )
}
