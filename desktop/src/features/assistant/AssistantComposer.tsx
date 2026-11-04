import { useState } from "react"
import { ArrowUpIcon, SquareIcon } from "lucide-react"
import { InputGroup, InputGroupAddon, InputGroupButton, InputGroupInput } from "@/components/ui/input-group"

/** The question field: Enter sends, and while an answer is being written the button stops it. */
export function AssistantComposer({ answering, enabled, onSend, onStop }: { answering: boolean; enabled: boolean; onSend: (text: string) => void; onStop: () => void }) {
  const [draft, setDraft] = useState("")
  return (
    <form
      className="shrink-0 border-t p-4"
      onSubmit={(event) => {
        event.preventDefault()
        const text = draft.trim()
        if (!text || answering || !enabled) return
        setDraft("")
        onSend(text)
      }}
    >
      <InputGroup>
        <InputGroupInput aria-label="Ask the assistant" placeholder="Ask about your trading" maxLength={2000} disabled={!enabled} autoFocus value={draft} onChange={(event) => setDraft(event.target.value)} />
        <InputGroupAddon align="inline-end">
          {answering ? (
            <InputGroupButton type="button" size="icon-sm" variant="default" onClick={onStop}>
              <SquareIcon aria-hidden />
              <span className="sr-only">Stop</span>
            </InputGroupButton>
          ) : (
            <InputGroupButton type="submit" size="icon-sm" variant="default" disabled={!enabled || !draft.trim()}>
              <ArrowUpIcon aria-hidden />
              <span className="sr-only">Send</span>
            </InputGroupButton>
          )}
        </InputGroupAddon>
      </InputGroup>
    </form>
  )
}
