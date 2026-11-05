import { type FormEvent, type KeyboardEvent, useEffect, useRef, useState } from "react"
import { ArrowUp02Icon } from "@/components/icons/ArrowUp02Icon"
import { Key01Icon } from "@/components/icons/Key01Icon"
import { Button } from "@/components/ui/button"
import { Field, FieldLabel } from "@/components/ui/field"
import { InputGroup, InputGroupAddon, InputGroupTextarea } from "@/components/ui/input-group"
import { Kbd } from "@/components/ui/kbd"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"

const COMPOSER_ID = "assistant-composer"

/** Every shortcut the panel actually binds, and nothing it does not. */
const SHORTCUTS: { keys: string[]; label: string }[] = [
  { keys: ["Enter"], label: "Send" },
  { keys: ["Shift", "Enter"], label: "New line" },
  { keys: ["⌘", "J"], label: "Show or hide" },
  { keys: ["Esc"], label: "Hide" },
]

/**
 * ai-chat-8's composer: one box that grows with the text, Enter to send, and a quiet bar under it. The bar names the model that
 * answers on the left and lists the shortcuts on the right. While an answer is written the button stops it.
 */
export function AssistantComposer({ open, answering, enabled, provider, onSend, onStop }: { open: boolean; answering: boolean; enabled: boolean; provider: { name: string; model: string } | null; onSend: (text: string) => void; onStop: () => void }) {
  const [value, setValue] = useState("")
  const box = useRef<HTMLTextAreaElement>(null)
  const canSend = value.trim().length > 0

  // The caret is in the box each time the panel opens.
  useEffect(() => {
    if (open && enabled) box.current?.focus()
  }, [open, enabled])

  function send(text: string) {
    // While an answer is written the only primary action is Stop, so Enter must not slip a second send past it.
    if (answering || !enabled) return
    const trimmed = text.trim()
    if (!trimmed) return
    setValue("")
    onSend(trimmed)
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    send(value)
  }

  function onKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    // Enter sends, Shift+Enter breaks the line. An IME candidate window also fires Enter, and committing a word there must not post the message.
    if (event.key !== "Enter" || event.shiftKey || event.nativeEvent.isComposing) return
    event.preventDefault()
    send(value)
  }

  return (
    <div className="flex flex-col gap-2">
      <form onSubmit={submit}>
        <Field>
          <FieldLabel htmlFor={COMPOSER_ID} className="sr-only">
            Ask the assistant
          </FieldLabel>
          <InputGroup className="min-h-10">
            <InputGroupTextarea
              id={COMPOSER_ID}
              ref={box}
              value={value}
              disabled={!enabled}
              maxLength={2000}
              onChange={(event) => setValue(event.target.value)}
              onKeyDown={onKeyDown}
              placeholder="Ask about your trading"
              // Starts one line and grows with the text, capped so the transcript never loses the panel.
              className="field-sizing-content max-h-32 min-h-9"
            />
            <InputGroupAddon align="inline-end" className="self-end pb-1">
              {answering ? (
                <Button type="button" size="sm" variant="outline" onClick={onStop}>
                  Stop
                </Button>
              ) : (
                <Tooltip>
                  <TooltipTrigger render={<Button type="submit" size="icon-sm" aria-label="Send message" disabled={!enabled || !canSend} className="rounded-full" />}>
                    <ArrowUp02Icon className="size-4" aria-hidden="true" />
                  </TooltipTrigger>
                  <TooltipContent className="flex items-center gap-1.5">
                    Send
                    <Kbd>Enter</Kbd>
                  </TooltipContent>
                </Tooltip>
              )}
            </InputGroupAddon>
          </InputGroup>
        </Field>
      </form>

      <div className="flex items-center justify-between gap-2 px-1">
        <span className="text-muted-foreground flex min-w-0 items-center gap-1.5 px-1 text-xs">
          {provider ? (
            <>
              <span className="shrink-0">{provider.name}</span>
              <span aria-hidden="true" className="bg-muted-foreground/40 size-1 shrink-0 rounded-full" />
              <span className="min-w-0 truncate">{provider.model}</span>
            </>
          ) : (
            "No model chosen"
          )}
        </span>
        <Popover>
          <PopoverTrigger render={<Button type="button" variant="ghost" size="sm" aria-label="Keyboard shortcuts" className="text-muted-foreground hover:text-foreground h-7 shrink-0 gap-1.5 px-2 font-normal" />}>
            <Key01Icon className="size-3.5 shrink-0" aria-hidden="true" />
            <span className="text-xs">Shortcuts</span>
          </PopoverTrigger>
          <PopoverContent align="end" className="w-64 p-2">
            <div className="flex flex-col gap-2">
              {SHORTCUTS.map((shortcut) => (
                <div key={shortcut.label} className="flex items-center justify-between gap-3">
                  <span className="text-sm">{shortcut.label}</span>
                  <span className="flex shrink-0 items-center gap-1">
                    {shortcut.keys.map((key) => (
                      <Kbd key={key}>{key}</Kbd>
                    ))}
                  </span>
                </div>
              ))}
            </div>
          </PopoverContent>
        </Popover>
      </div>
    </div>
  )
}
