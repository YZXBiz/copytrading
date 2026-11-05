import type { SourceActivity } from "../../../shared/contract"
import { reasonText } from "@/lib/reasons"
import { callHeadline, callNote, callsOf, enteredByOwner, headline, isRepost, kindText, noCallLine } from "./reading"
import styles from "./post-detail.module.css"

const capitalize = (text: string) => text.charAt(0).toUpperCase() + text.slice(1)

/** How the reader read the post: one plain line per call, what the call leaves out, then what kind of post it was and who read it. */
export function ReadAs({ post }: { post: SourceActivity }) {
  const reading = post.reading
  const calls = reading ? callsOf(reading) : []
  const by = post.interpreted_by ? `read by ${post.interpreted_by}` : null
  const kind = reading ? ([kindText(reading), by].filter(Boolean) as string[]).map(capitalize) : []
  return (
    <section aria-label="Read as" className={styles.section}>
      {reading && calls.length === 0 && (
        <>
          <p className={styles.headline}>{noCallLine(reading)}</p>
          {enteredByOwner(post) && <p className={styles.muted}>You entered the trade yourself.</p>}
        </>
      )}
      {calls.map((call, index) => {
        const { title, detail } = callHeadline(call)
        const parts = [detail, callNote(call), isRepost(call) ? "a re-post of an earlier call" : null].filter(Boolean) as string[]
        return (
          <div key={index}>
            <p className={styles.headline}>{title}</p>
            <div className={styles.facts}>
              {parts.map((part, i) => (
                <span key={i}>{capitalize(part)}</span>
              ))}
            </div>
          </div>
        )
      })}
      {kind.length > 0 && (
        <div className={styles.kind}>
          {kind.map((part, i) => (
            <span key={i}>{part}</span>
          ))}
        </div>
      )}
      {!reading && (
        <>
          <p className={styles.headline}>{headline(post)}</p>
          {post.parser_reason && <p className={styles.muted}>{reasonText(post.parser_reason)}</p>}
        </>
      )}
    </section>
  )
}
