import { MessageScroller, MessageScrollerContent, MessageScrollerItem, MessageScrollerProvider, MessageScrollerViewport, useMessageScrollerScrollable } from "@/components/ui/message-scroller"
import { AssistantMessageRow } from "./AssistantMessageRow"
import type { Message } from "./conversation"

/** The scroller skips rendering off-screen items, so a long answer reports a 10rem placeholder and bottom following lands short. */
const MEASURED_ITEM = "[content-visibility:visible]"

/** Opacity only: a transform entrance mismeasures the item's extent. */
const ITEM_ENTRANCE = `${MEASURED_ITEM} animate-in fade-in-0 duration-300 ease-out motion-reduce:animate-none`

/** Softens whichever edge has more thread behind it, and only that edge. */
function ScrollFades() {
  const { start, end } = useMessageScrollerScrollable()
  return (
    <>
      <div aria-hidden="true" data-active={start} className="from-sidebar pointer-events-none absolute inset-x-0 top-0 h-6 bg-linear-to-b to-transparent opacity-0 transition-opacity duration-200 ease-out data-[active=true]:opacity-100 motion-reduce:transition-none" />
      <div aria-hidden="true" data-active={end} className="from-sidebar pointer-events-none absolute inset-x-0 bottom-0 h-8 bg-linear-to-t to-transparent opacity-0 transition-opacity duration-200 ease-out data-[active=true]:opacity-100 motion-reduce:transition-none" />
    </>
  )
}

/** ai-chat-8's thread: the newest turn stays in view while an answer is written, and each turn fades in. */
export function AssistantTranscript({ messages, answering }: { messages: Message[]; answering: boolean }) {
  return (
    <div className="relative flex min-h-0 flex-1 flex-col">
      <MessageScrollerProvider autoScroll>
        <MessageScroller className="min-h-0 flex-1">
          <MessageScrollerViewport className="scrollbar" aria-label="Conversation with the assistant">
            <MessageScrollerContent aria-busy={answering} className="flex w-full min-w-0 flex-col gap-4 px-4 py-4">
              {messages.map((message, index) => (
                <MessageScrollerItem key={message.id} messageId={message.id} scrollAnchor={false} className={ITEM_ENTRANCE}>
                  <AssistantMessageRow message={message} writing={answering && index === messages.length - 1} />
                </MessageScrollerItem>
              ))}
            </MessageScrollerContent>
          </MessageScrollerViewport>
        </MessageScroller>
        <ScrollFades />
      </MessageScrollerProvider>
    </div>
  )
}
