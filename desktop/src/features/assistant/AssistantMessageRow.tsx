import { CheckIcon, CircleAlertIcon, XIcon } from "lucide-react"
import { Bubble, BubbleContent } from "@/components/ui/bubble"
import { Button } from "@/components/ui/button"
import { Message, MessageContent } from "@/components/ui/message"
import { Spinner } from "@/components/ui/spinner"
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

const linkTitle = (link: Link) => (link.kind === "account" ? `${link.title} in Accounts` : link.kind === "guru" ? `${link.title} in Gurus` : link.title)

/** One turn. The owner's question is a soft bubble at the trailing edge; the answer is plain text at the leading edge, with what was looked at, approvals, and links. */
export function AssistantMessageRow({ message, writing, onNavigate }: { message: Turn; writing: boolean; onNavigate: () => void }) {
  if (message.author === "owner") {
    return (
      <Message align="end">
        <MessageContent>
          <Bubble variant="muted" align="end">
            <BubbleContent className="whitespace-pre-wrap">{message.text}</BubbleContent>
          </Bubble>
        </MessageContent>
      </Message>
    )
  }
  const working = writing && message.text === "" && message.errorText === null
  const links = uniqueLinks(message.links)
  return (
    <Message align="start">
      <MessageContent>
        {(message.steps.length > 0 || working) && (
          <ul className="text-muted-foreground flex flex-col gap-1 text-xs">
            {message.steps.map((step, i) => (
              <li key={i} className="flex items-baseline gap-1.5">
                {isRefusal(step) ? <XIcon className="text-warning-foreground dark:text-warning size-3 shrink-0" aria-hidden /> : <CheckIcon className="size-3 shrink-0" aria-hidden />}
                {step}
              </li>
            ))}
            {working && (
              <li className="flex items-center gap-1.5">
                <Spinner className="size-3" />
                {message.steps.length === 0 ? "Looking into it…" : "Still looking…"}
              </li>
            )}
          </ul>
        )}
        {message.text && <Markdown text={message.text} />}
        {message.proposalIds.map((id) => (
          <AssistantProposalCard key={id} proposalId={id} />
        ))}
        {links.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {links.map((link) => (
              <Button
                key={`${link.kind}:${link.id}`}
                type="button"
                size="xs"
                variant="outline"
                onClick={() => {
                  open(link)
                  onNavigate()
                }}
              >
                {linkTitle(link)}
              </Button>
            ))}
          </div>
        )}
        {message.errorText && (
          <p role="alert" className="text-muted-foreground flex items-start gap-1.5 text-xs">
            <CircleAlertIcon className="text-warning-foreground dark:text-warning mt-0.5 size-3.5 shrink-0" aria-hidden />
            {message.errorText}
          </p>
        )}
      </MessageContent>
    </Message>
  )
}
