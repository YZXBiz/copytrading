import { CheckIcon, CopyIcon, FileTextIcon, TriangleAlertIcon, XIcon } from "lucide-react"
import { Alert, AlertTitle } from "@/components/reui/alert"
import { Attachment, AttachmentContent, AttachmentDescription, AttachmentGroup, AttachmentTitle } from "@/components/ui/attachment"
import { Bubble, BubbleContent } from "@/components/ui/bubble"
import { Button } from "@/components/ui/button"
import { Marker, MarkerContent, MarkerIcon } from "@/components/ui/marker"
import { Spinner } from "@/components/ui/spinner"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { navigate } from "@/features/shell/route"
import { AssistantProposalCard } from "./AssistantProposalCard"
import { type Link, type Message as Turn, isRefusal, uniqueLinks } from "./conversation"
import { Markdown } from "./Markdown"

/** Opens what an answer points at: the account, the guru, or the post's screen. */
function open(link: Link) {
  if (link.kind === "account") navigate("accounts", link.id)
  else if (link.kind === "guru") navigate("gurus", link.id)
  else if (link.kind === "post") navigate("activity")
}

const KIND: Record<string, string> = { account: "Account", guru: "Guru", post: "Post" }

/** Copy, on an answer that has words; it shows when the turn is hovered or focused, and keeps its space so nothing shifts. */
const TURN_ACTIONS =
  "pointer-events-none flex items-center gap-0.5 opacity-0 transition-opacity group-hover/turn:pointer-events-auto group-hover/turn:opacity-100 focus-within:pointer-events-auto focus-within:opacity-100"

/**
 * One turn, in the shape the engine returns it. The owner's question is a bubble at the trailing edge. The answer is what it
 * looked at (steps), its words, the places it points to (chips), a request waiting for approval, or why it stopped.
 */
export function AssistantMessageRow({ message, writing }: { message: Turn; writing: boolean }) {
  if (message.author === "owner") {
    return (
      <div className="flex flex-col items-end gap-1">
        <Bubble variant="default" align="end">
          <BubbleContent className="text-sm leading-relaxed whitespace-pre-wrap">{message.text}</BubbleContent>
        </Bubble>
      </div>
    )
  }
  const working = writing && message.text === "" && message.errorText === null
  const links = uniqueLinks(message.links)
  const hasBubble = message.steps.length > 0 || message.text !== ""
  return (
    <div className="group/turn flex min-w-0 flex-col gap-2">
      {hasBubble && (
        <Bubble variant="outline" className="max-w-full">
          <BubbleContent className="flex flex-col gap-2.5">
            {message.steps.length > 0 && (
              <div className="flex flex-col gap-1.5">
                {message.steps.map((step, i) => (
                  <Marker key={i} className="items-start">
                    <MarkerIcon className={isRefusal(step) ? "text-warning-foreground dark:text-warning" : "text-success"}>
                      {isRefusal(step) ? <XIcon className="size-3.5" aria-hidden="true" /> : <CheckIcon className="size-3.5" aria-hidden="true" />}
                    </MarkerIcon>
                    <MarkerContent className="text-foreground">{step}</MarkerContent>
                  </Marker>
                ))}
              </div>
            )}
            {message.text && (
              <div className="text-sm">
                <Markdown text={message.text} />
              </div>
            )}
          </BubbleContent>
        </Bubble>
      )}
      {working && (
        <div className="text-muted-foreground flex items-center gap-2 text-sm">
          <Spinner className="size-3.5" />
          {message.steps.length === 0 ? "Looking into it…" : "Still looking…"}
        </div>
      )}
      {message.proposalIds.map((id) => (
        <AssistantProposalCard key={id} proposalId={id} />
      ))}
      {links.length > 0 && (
        <AttachmentGroup className="flex-wrap gap-1.5">
          {links.map((link) => (
            <Attachment key={`${link.kind}:${link.id}`} size="xs" className="max-w-56 gap-2">
              <button type="button" onClick={() => open(link)} className="flex min-w-0 items-center gap-2 rounded-lg px-1.5 py-1 text-left outline-none focus-visible:ring-2 focus-visible:ring-ring/50">
                <span className="text-muted-foreground">
                  <FileTextIcon className="size-3.5 shrink-0" aria-hidden="true" />
                </span>
                <AttachmentContent>
                  <AttachmentTitle>{link.title}</AttachmentTitle>
                  <AttachmentDescription>{KIND[link.kind] ?? "Link"}</AttachmentDescription>
                </AttachmentContent>
              </button>
            </Attachment>
          ))}
        </AttachmentGroup>
      )}
      {message.errorText && (
        <Alert variant="warning" role="alert">
          <TriangleAlertIcon aria-hidden="true" />
          <AlertTitle className="line-clamp-none">{message.errorText}</AlertTitle>
        </Alert>
      )}
      {message.text && !writing && (
        <div className={TURN_ACTIONS}>
          <Tooltip>
            <TooltipTrigger
              render={
                <Button
                  type="button"
                  size="icon-sm"
                  variant="ghost"
                  aria-label="Copy answer"
                  onClick={() => void navigator.clipboard?.writeText(message.text)}
                  className="text-muted-foreground hover:text-foreground"
                />
              }
            >
              <CopyIcon className="size-3.5" aria-hidden="true" />
            </TooltipTrigger>
            <TooltipContent>Copy</TooltipContent>
          </Tooltip>
        </div>
      )}
    </div>
  )
}
