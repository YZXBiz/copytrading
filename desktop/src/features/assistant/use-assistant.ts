import { useCallback, useEffect, useRef, useState } from "react"
import type { AssistantAskContext } from "../../../shared/contract"
import { type Conversation, apply, ask as addQuestion, empty, fail } from "./conversation"
import { pollTurn } from "./poll"

const POLL_MS = 250
const newId = (prefix: string) => `${prefix}-${crypto.randomUUID().replaceAll("-", "").slice(0, 12)}`
const api = () => window.copytrading

/**
 * The owner's conversation: a question goes to the engine, and the answer is read back by polling while it is written
 * (AssistantModel.swift). A reset drops any page that arrives after it, and polling stops when the panel is gone.
 * Nothing outlives a quit.
 */
export function useAssistant() {
  const [conversation, setConversation] = useState<Conversation>(empty)
  const [answering, setAnswering] = useState(false)
  const conversationId = useRef(newId("c"))
  const turn = useRef<string | null>(null)
  const generation = useRef(0)
  const count = useRef(0)

  // Unmounting drops the pages still to come, as a reset does.
  useEffect(
    () => () => {
      generation.current++
    },
    [],
  )

  const finish = () => {
    turn.current = null
    setAnswering(false)
  }

  const follow = useCallback(async (turnId: string, started: number) => {
    const ended = await pollTurn({
      readTurn: (after) => api().read.getAssistantTurn({ turn_id: turnId, after }),
      isCurrent: () => started === generation.current,
      onEvents: (events) => setConversation((c) => events.reduce(apply, c)),
      sleep: () => new Promise((done) => setTimeout(done, POLL_MS)),
    })
    if (ended === "dropped") return
    if (typeof ended === "object") setConversation((c) => fail(c, `The assistant stopped answering: ${ended.error}`))
    finish()
  }, [])

  const ask = useCallback(
    async (text: string, context: AssistantAskContext, hasModel: boolean) => {
      const question = text.trim()
      if (!question || answering) return
      const started = generation.current
      setConversation((c) => addQuestion(c, question, `m${count.current++}`))
      setAnswering(true)
      const setup = await api().read.getSetup()
      const provider = setup.ok ? setup.value?.configuration.provider : undefined
      if (started !== generation.current) return
      if (!hasModel || !provider) {
        setConversation((c) => fail(c, "Set up a model under Connections, then ask again."))
        return finish()
      }
      const result = await api().act.assistantAsk({ conversation_id: conversationId.current, text: question, context, provider })
      if (started !== generation.current) {
        // A reset landed while the engine was starting this turn; stop it so nothing runs unseen.
        if (result.ok) void api().act.assistantCancel({ turn_id: result.value.turn_id })
        return
      }
      if (!result.ok) {
        setConversation((c) => fail(c, `The assistant could not start: ${result.error}`))
        return finish()
      }
      turn.current = result.value.turn_id
      void follow(result.value.turn_id, started)
    },
    [answering, follow],
  )

  /** Asks the engine to stop writing; the answer so far stays, and polling ends on its `done`. */
  const stop = useCallback(async () => {
    if (turn.current) await api().act.assistantCancel({ turn_id: turn.current })
  }, [])

  /** Forgets the conversation here and in the engine. */
  const reset = useCallback(async () => {
    generation.current++
    finish()
    setConversation(empty)
    conversationId.current = newId("c")
    await api().act.assistantReset(undefined)
  }, [])

  return { messages: conversation.messages, answering, ask, stop, reset }
}
