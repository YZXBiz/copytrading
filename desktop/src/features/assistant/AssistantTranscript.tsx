import { useEffect, useRef } from "react"
import { AssistantMessageRow } from "./AssistantMessageRow"
import type { Message } from "./conversation"
import styles from "./assistant.module.css"

/** How close to the end the thread counts as following it: a reader who scrolled up is left where they are. */
const FOLLOW_PX = 80

/** The thread: the newest turn stays in view while an answer is written, unless the reader scrolled up. */
export function AssistantTranscript({ messages, answering }: { messages: Message[]; answering: boolean }) {
  const viewport = useRef<HTMLDivElement>(null)
  const following = useRef(true)
  const last = messages[messages.length - 1]
  const size = (last?.text.length ?? 0) + (last?.steps.length ?? 0) + (last?.proposalIds.length ?? 0)

  useEffect(() => {
    const node = viewport.current
    if (node && following.current) node.scrollTo({ top: node.scrollHeight })
  }, [messages.length, size, answering])

  return (
    <div
      ref={viewport}
      className={styles.thread}
      role="region"
      aria-label="Conversation with the assistant"
      aria-busy={answering}
      tabIndex={0}
      onScroll={(event) => {
        const node = event.currentTarget
        following.current = node.scrollHeight - node.scrollTop - node.clientHeight < FOLLOW_PX
      }}
    >
      <ol className={`${styles.threadInner} ${styles.turns}`}>
        {messages.map((message, index) => (
          <li key={message.id} className={styles.turn}>
            <AssistantMessageRow message={message} writing={answering && index === messages.length - 1} />
          </li>
        ))}
      </ol>
    </div>
  )
}
