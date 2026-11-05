import { Fragment } from "react"
import { parseMarkdown } from "./light-markdown"
import styles from "./assistant.module.css"

/** An answer's light Markdown as text runs. React escapes every string, so nothing here can be HTML or a live link. */
export function Markdown({ text }: { text: string }) {
  return (
    <p className={styles.answerText}>
      {parseMarkdown(text).map((runs, line) => (
        <Fragment key={line}>
          {line > 0 && "\n"}
          {runs.map((run, i) =>
            run.code ? (
              <code key={i}>{run.text}</code>
            ) : run.bold ? (
              <strong key={i}>{run.text}</strong>
            ) : run.italic ? (
              <em key={i}>{run.text}</em>
            ) : (
              <Fragment key={i}>{run.text}</Fragment>
            ),
          )}
        </Fragment>
      ))}
    </p>
  )
}
