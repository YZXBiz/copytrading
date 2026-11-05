import { type FormEvent, type KeyboardEvent, useEffect, useRef, useState } from "react"
import { ArrowUp02Icon } from "@/components/icons/ArrowUp02Icon"
import { Key01Icon } from "@/components/icons/Key01Icon"
import { Button } from "@/components/arc/button/button"
import { Kbd } from "@/components/arc/kbd/kbd"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/arc/popover/popover"
import { Tooltip } from "@/components/arc/tooltip/tooltip"
import styles from "./assistant.module.css"

const COMPOSER_ID = "assistant-composer"

/** Every shortcut the panel actually binds, and nothing it does not. */
const SHORTCUTS: { keys: string[]; label: string }[] = [
  { keys: ["Enter"], label: "Send" },
  { keys: ["Shift", "Enter"], label: "New line" },
  { keys: ["⌘", "J"], label: "Show or hide" },
  { keys: ["Esc"], label: "Hide" },
]

/**
 * One box that grows with the text, Enter to send, and a quiet bar under it. The bar names the model that answers on the
 * left and lists the shortcuts on the right. While an answer is written the button stops it.
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
    <div className={styles.composerArea}>
      <form onSubmit={submit}>
        <label htmlFor={COMPOSER_ID} style={{ position: "absolute", width: 1, height: 1, overflow: "hidden", clipPath: "inset(50%)" }}>
          Ask the assistant
        </label>
        <div className={styles.composer} data-disabled={!enabled || undefined}>
          <textarea
            id={COMPOSER_ID}
            ref={box}
            className={styles.input}
            rows={1}
            value={value}
            disabled={!enabled}
            maxLength={2000}
            onChange={(event) => setValue(event.target.value)}
            onKeyDown={onKeyDown}
            placeholder="Ask about your trading"
          />
          {answering ? (
            <Button type="button" size="sm" variant="secondary" onClick={onStop}>
              Stop
            </Button>
          ) : (
            <Tooltip
              content={
                <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                  Send
                  <Kbd size="sm">Enter</Kbd>
                </span>
              }
            >
              <button type="submit" className={styles.send} aria-label="Send message" disabled={!enabled || !canSend}>
                <ArrowUp02Icon width={16} height={16} aria-hidden="true" />
              </button>
            </Tooltip>
          )}
        </div>
      </form>

      <div className={styles.meta}>
        <span className={styles.model}>
          {provider ? (
            <>
              <span>{provider.name}</span>
              <span aria-hidden="true" className={styles.dot} />
              <span>{provider.model}</span>
            </>
          ) : (
            "No model chosen"
          )}
        </span>
        <Popover>
          <PopoverTrigger asChild>
            <Button type="button" variant="ghost" size="sm" aria-label="Keyboard shortcuts">
              <Key01Icon width={16} height={16} aria-hidden="true" />
              Shortcuts
            </Button>
          </PopoverTrigger>
          <PopoverContent align="end">
            <div className={styles.shortcuts}>
              {SHORTCUTS.map((shortcut) => (
                <div key={shortcut.label}>
                  <span>{shortcut.label}</span>
                  <span>
                    {shortcut.keys.map((key) => (
                      <Kbd key={key} size="sm">
                        {key}
                      </Kbd>
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
