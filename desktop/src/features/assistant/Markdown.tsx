import { Fragment } from "react"
import { parseMarkdown } from "./light-markdown"

/** An answer's light Markdown as text runs. React escapes every string, so nothing here can be HTML or a live link. */
export function Markdown({ text }: { text: string }) {
  return (
    <p className="leading-relaxed break-words whitespace-pre-wrap">
      {parseMarkdown(text).map((runs, line) => (
        <Fragment key={line}>
          {line > 0 && "\n"}
          {runs.map((run, i) =>
            run.code ? (
              <code key={i} className="bg-muted rounded px-1 py-0.5 font-mono text-[0.85em]">
                {run.text}
              </code>
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
