import type { AssistantTurnPage, Result } from "../../../shared/contract"

export type Event = AssistantTurnPage["events"][number]

export interface PollOptions {
  readTurn: (after: number) => Promise<Result<AssistantTurnPage>>
  /** False once a reset or unmount has made this turn no longer the one on screen. */
  isCurrent: () => boolean
  onEvents: (events: Event[]) => void
  sleep: () => Promise<void>
}

/**
 * Reads a turn's events as the engine writes them, each page after the last event seen, until the engine says it is done.
 * Returns how it ended: "done", or the error that stopped it; "dropped" when a reset made the pages no longer wanted.
 */
export async function pollTurn({ readTurn, isCurrent, onEvents, sleep }: PollOptions): Promise<"done" | "dropped" | { error: string }> {
  let after = 0
  while (isCurrent()) {
    const page = await readTurn(after)
    if (!isCurrent()) return "dropped"
    if (!page.ok) return { error: page.error }
    for (const event of page.value.events) after = Math.max(after, event.seq)
    if (page.value.events.length) onEvents(page.value.events)
    if (page.value.done || page.value.events.some((e) => e.kind === "done")) return "done"
    await sleep()
  }
  return "dropped"
}
