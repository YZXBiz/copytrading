import { type CSSProperties, type ReactNode, useEffect, useRef } from "react"
import type { TradingConfiguration } from "../../../shared/contract"
import { SidebarProvider, useSidebar } from "@/components/ui/sidebar"
import { navigate, useRoute } from "@/features/shell/route"
import { useResult } from "@/lib/use-result"
import { AssistantPanel } from "./AssistantPanel"
import { assistantContext, assistantGurus, hasModel, suggestions } from "./context"
import { useAssistant } from "./use-assistant"

/** ai-chat-8's width: 28rem where there is room, a share of the window where there is not. The sidebar token paints the panel as a card. */
const PANEL = { "--sidebar-width": "min(28rem, 45vw)", "--sidebar": "var(--card)" } as CSSProperties

/**
 * The page and the Assistant docked beside it (ai-chat-8): a second sidebar on the right, closed until ⌘J or the header's
 * Assistant button opens it, whose flow gap narrows the page. The conversation lives here, so closing the panel keeps it.
 */
export function AssistantFrame({ onOpen, children }: { onOpen: () => void; children: ReactNode }) {
  return (
    <SidebarProvider defaultOpen={false} shortcut={false} className="min-h-0 flex-1" style={PANEL}>
      <AssistantBody onOpen={onOpen}>{children}</AssistantBody>
    </SidebarProvider>
  )
}

function AssistantBody({ onOpen, children }: { onOpen: () => void; children: ReactNode }) {
  const { open, setOpen, toggleSidebar } = useSidebar()
  const route = useRoute()
  const assistant = useAssistant()

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.metaKey && event.key.toLowerCase() === "j") {
        event.preventDefault()
        toggleSidebar()
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [toggleSidebar])

  // The shell may fold its own sidebar when the panel opens; a ref keeps that to the moment of opening.
  const opened = useRef(onOpen)
  opened.current = onOpen
  useEffect(() => {
    if (open) opened.current()
  }, [open])

  // Read again each time the panel opens, so a model set up in Connections is seen.
  const model = useResult(async () => {
    const { read } = window.copytrading
    const [setup, secrets] = await Promise.all([read.getSetup(), read.getSecretStatus()])
    if (!setup.ok) return setup
    if (!secrets.ok) return secrets
    return { ok: true as const, value: { setup: setup.value?.configuration ?? null, hasModel: hasModel(setup.value, secrets.value) } }
  }, `model:${open}`)

  const configuration: TradingConfiguration | null = model.status === "ready" ? model.data.setup : null
  const gurus = assistantGurus(configuration)
  const guru = (route.screen === "gurus" && gurus.find((g) => g.id === route.id)?.name) || gurus[0]?.name || null
  const ready = model.status === "ready" && model.data.hasModel
  const ask = (text: string) => void assistant.ask(text, assistantContext(route, configuration), ready)

  return (
    <>
      <div className="flex min-w-0 flex-1 flex-col">{children}</div>
      <AssistantPanel
        model={model}
        ready={ready}
        provider={configuration?.provider ?? null}
        suggestions={suggestions(route.screen, guru, configuration !== null)}
        assistant={assistant}
        onAsk={ask}
        onOpenConnections={() => (setOpen(false), navigate("connections"))}
      />
    </>
  )
}
