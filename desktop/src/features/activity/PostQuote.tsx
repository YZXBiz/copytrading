import type { SourceActivity } from "../../../shared/contract"
import { PostImage } from "./PostImage"
import { isLabelOnly, readableEmbeds, readingText } from "./reading"
import styles from "./post-detail.module.css"

/** The guru's own words, with what else came with them: embeds and pictures. Untrusted Discord content: React renders it as text only. */
export function PostQuote({ post }: { post: SourceActivity }) {
  // A relay's bare label ("赵哥-股票：") is not words: the pictures that came with it show instead.
  const text = readingText(post)
  const said = isLabelOnly(text) ? "" : text
  const embeds = readableEmbeds(post)
  const attachments = post.source_event?.attachments ?? []
  const omitted = post.source_event?.attachments_omitted ?? 0
  return (
    <div className={styles.quote}>
      {said ? <blockquote className={styles.words}>“{said}”</blockquote> : embeds.length === 0 && attachments.length === 0 && <p className={styles.muted}>No message text was captured.</p>}
      {embeds.map((embed, index) => (
        <div key={index} className={styles.embed}>
          {embed.title?.trim() && <strong>{embed.title}</strong>}
          {embed.description?.trim() && <p>{embed.description}</p>}
          {embed.fields.map((field, i) => (
            <div key={i} className={styles.field}>
              {field.name.trim() && <span>{field.name}</span>}
              {field.value.trim() && <div>{field.value}</div>}
            </div>
          ))}
        </div>
      ))}
      {(attachments.length > 0 || omitted > 0) && (
        <div className={styles.pictures}>
          {attachments.map((attachment) => (
            <PostImage key={attachment.evidence_id} attachment={attachment} />
          ))}
          {omitted > 0 && <p className={styles.note}>{omitted === 1 ? "1 attachment omitted" : `${omitted} attachments omitted`}</p>}
        </div>
      )}
    </div>
  )
}
