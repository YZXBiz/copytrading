import type { SourceActivity } from "../../../shared/contract"
import { Meta } from "@/components/meta"
import { reasonText } from "@/lib/reasons"
import { callHeadline, callNote, callsOf, enteredByOwner, headline, isRepost, kindText, noCallLine } from "./reading"

const capitalize = (text: string) => text.charAt(0).toUpperCase() + text.slice(1)

/** How the reader read the post: one plain line per call, what the call leaves out, then what kind of post it was and who read it. */
export function ReadAs({ post }: { post: SourceActivity }) {
  const reading = post.reading
  const calls = reading ? callsOf(reading) : []
  const by = post.interpreted_by ? `read by ${post.interpreted_by}` : null
  return (
    <section aria-label="Read as" className="flex flex-col gap-1">
      {reading && calls.length === 0 && (
        <>
          <p className="font-medium">{noCallLine(reading)}</p>
          {enteredByOwner(post) && <p className="text-muted-foreground text-sm">You entered the trade yourself.</p>}
        </>
      )}
      {calls.map((call, index) => {
        const { title, detail } = callHeadline(call)
        const parts = [detail, callNote(call), isRepost(call) ? "a re-post of an earlier call" : null].filter(Boolean) as string[]
        return (
          <div key={index} className={index === 0 ? undefined : "mt-2"}>
            <p className="font-medium tabular-nums">{title}</p>
            {parts.length > 0 && <Meta className="text-muted-foreground text-sm" items={parts.map(capitalize)} />}
          </div>
        )
      })}
      {reading && <Meta className="text-muted-foreground mt-1 text-xs" items={([kindText(reading), by].filter(Boolean) as string[]).map(capitalize)} />}
      {!reading && (
        <>
          <p className="font-medium">{headline(post)}</p>
          {post.parser_reason && <p className="text-muted-foreground text-sm">{reasonText(post.parser_reason)}</p>}
        </>
      )}
    </section>
  )
}
