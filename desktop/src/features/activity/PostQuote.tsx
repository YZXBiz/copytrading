import type { SourceActivity } from "../../../shared/contract"
import { PostPicture } from "./PostPicture"
import { isLabelOnly, readableEmbeds, readingText } from "./reading"

/** The guru's own words, with what else came with them: embeds and pictures. Untrusted Discord content: React renders it as text only. */
export function PostQuote({ post }: { post: SourceActivity }) {
  // A relay's bare label ("赵哥-股票：") is not words: the pictures that came with it show instead.
  const text = readingText(post)
  const said = isLabelOnly(text) ? "" : text
  const embeds = readableEmbeds(post)
  const attachments = post.source_event?.attachments ?? []
  const omitted = post.source_event?.attachments_omitted ?? 0
  return (
    <div className="flex flex-col gap-4">
      {said ? (
        <blockquote className="text-base leading-relaxed whitespace-pre-wrap break-words">“{said}”</blockquote>
      ) : (
        embeds.length === 0 &&
        attachments.length === 0 && <p className="text-muted-foreground">No message text was captured.</p>
      )}
      {embeds.map((embed, index) => (
        <div key={index} className="border-border flex flex-col gap-1.5 border-l-2 pl-3 text-sm">
          {embed.title?.trim() && <div className="font-medium break-words">{embed.title}</div>}
          {embed.description?.trim() && <div className="break-words whitespace-pre-wrap">{embed.description}</div>}
          {embed.fields.map((field, i) => (
            <div key={i}>
              {field.name.trim() && <div className="text-muted-foreground text-xs">{field.name}</div>}
              {field.value.trim() && <div className="break-words">{field.value}</div>}
            </div>
          ))}
        </div>
      ))}
      {(attachments.length > 0 || omitted > 0) && (
        <div className="flex flex-col gap-2">
          {attachments.map((attachment) => (
            <PostPicture key={attachment.evidence_id} attachment={attachment} />
          ))}
          {omitted > 0 && <p className="text-muted-foreground text-xs">{omitted === 1 ? "1 attachment omitted" : `${omitted} attachments omitted`}</p>}
        </div>
      )}
    </div>
  )
}
