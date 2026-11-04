import type { AssistantTurnPage } from "../../../shared/contract"

// The owner's conversation with the assistant as data: AssistantModel.swift's `apply`, without the polling.

export type Event = AssistantTurnPage["events"][number]

export interface Link {
  kind: string
  id: string
  title: string
}

export interface Message {
  id: string
  author: "owner" | "assistant"
  text: string
  steps: string[]
  links: Link[]
  proposalIds: string[]
  errorText: string | null
}

export interface Conversation {
  messages: Message[]
  /** Set when a step line interrupts written text, so the words after it start a new paragraph. */
  breakBeforeText: boolean
}

export const empty: Conversation = { messages: [], breakBeforeText: false }

const message = (author: Message["author"], id: string, text = ""): Message => ({ id, author, text, steps: [], links: [], proposalIds: [], errorText: null })

/** The question and the empty answer it will fill. */
export function ask(conversation: Conversation, text: string, id: string): Conversation {
  return { messages: [...conversation.messages, message("owner", `${id}-q`, text), message("assistant", `${id}-a`)], breakBeforeText: false }
}

const patchLast = (c: Conversation, change: (m: Message) => Message): Conversation => {
  const last = c.messages.at(-1)
  return last?.author === "assistant" ? { ...c, messages: [...c.messages.slice(0, -1), change(last)] } : c
}

/** One event from the engine, applied to the answer being written. `done` changes nothing: the caller stops polling on it. */
export function apply(conversation: Conversation, event: Event): Conversation {
  switch (event.kind) {
    case "text": {
      if (!event.text) return conversation
      const text = event.text
      const next = patchLast(conversation, (m) => ({ ...m, text: m.text + (conversation.breakBeforeText && m.text ? "\n\n" : "") + text }))
      return { ...next, breakBeforeText: false }
    }
    case "step":
      return { ...patchLast(conversation, (m) => (event.text ? { ...m, steps: [...m.steps, event.text] } : m)), breakBeforeText: true }
    case "link":
      return event.link ? patchLast(conversation, (m) => ({ ...m, links: [...m.links, event.link!] })) : conversation
    case "proposal":
      return event.proposal_id ? patchLast(conversation, (m) => ({ ...m, proposalIds: [...m.proposalIds, event.proposal_id!] })) : conversation
    case "error":
      return patchLast(conversation, (m) => ({ ...m, errorText: event.text ?? "The assistant could not answer." }))
    default:
      return conversation
  }
}

/** Marks the answer being written as failed, so the panel shows why instead of waiting. */
export const fail = (conversation: Conversation, text: string): Conversation => patchLast(conversation, (m) => ({ ...m, errorText: text }))

/** Each place once, however often the assistant pointed at it. */
export const uniqueLinks = (links: Link[]): Link[] => links.filter((link, i) => links.findIndex((l) => l.kind === link.kind && l.id === link.id) === i)

/** The engine starts every step line for a refused request with "Couldn't". */
export const isRefusal = (step: string): boolean => step.startsWith("Couldn't ")
