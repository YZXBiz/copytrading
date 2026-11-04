import {
  MessageScroller,
  MessageScrollerButton,
  MessageScrollerContent,
  MessageScrollerItem,
  MessageScrollerProvider,
  MessageScrollerViewport,
} from "@/components/ui/message-scroller"
import { AssistantMessageRow } from "./AssistantMessageRow"
import type { Message } from "./conversation"

/** The conversation, pinned to the newest turn while an answer is written; a question lifts near the top. */
export function AssistantTranscript({ messages, answering, onNavigate }: { messages: Message[]; answering: boolean; onNavigate: () => void }) {
  return (
    <MessageScrollerProvider scrollPreviousItemPeek={64} scrollMargin={16}>
      <MessageScroller>
        <MessageScrollerViewport aria-label="Conversation with the assistant">
          <MessageScrollerContent className="gap-5 p-4">
            {messages.map((message, index) => (
              <MessageScrollerItem key={message.id} messageId={message.id} scrollAnchor={message.author === "owner"}>
                <AssistantMessageRow message={message} writing={answering && index === messages.length - 1} onNavigate={onNavigate} />
              </MessageScrollerItem>
            ))}
          </MessageScrollerContent>
        </MessageScrollerViewport>
        <MessageScrollerButton variant="outline" className="rounded-full shadow-sm" />
      </MessageScroller>
    </MessageScrollerProvider>
  )
}
