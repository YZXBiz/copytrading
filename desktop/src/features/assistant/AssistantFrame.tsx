import { type ReactNode, createContext, useCallback, useContext, useEffect, useRef, useState, useSyncExternalStore } from "react"
import type { TradingConfiguration } from "../../../shared/contract"
import { ASSISTANT_EVENT } from "../../../shared/shortcuts"
import { navigate, useRoute } from "@/features/shell/route"
import { useResult } from "@/lib/use-result"
import { AssistantPanel } from "./AssistantPanel"
import { assistantContext, assistantGurus, hasModel, suggestions } from "./context"
import { useAssistant } from "./use-assistant"
import styles from "./assistant.module.css"

interface PanelState {
  open: boolean
  setOpen: (open: boolean) => void
  toggle: () => void
}
const PanelContext = createContext<PanelState | null>(null)

/** Whether the Assistant is docked open, and the controls to change it (the header's button and ⌘J use these). */
export function useAssistantPanel(): PanelState {
  const state = useContext(PanelContext)
  if (!state) throw new Error("useAssistantPanel needs the AssistantFrame")
  return state
}

const subscribeWidth = (onChange: () => void) => {
  window.addEventListener("resize", onChange)
  return () => window.removeEventListener("resize", onChange)
}
const windowWidth = () => window.innerWidth

/** 28rem where there is room, a share of the window where there is not; wide is 40rem. */
const dockWidth = (wide: boolean, viewport: number) => Math.round(Math.min(wide ? 640 : 448, viewport * (wide ? 0.6 : 0.45)))

/**
 * The page and the Assistant docked beside it: closed until ⌘J or the header's Assistant button opens it, and the page
 * narrows to make room. The conversation lives here, so closing the panel keeps it.
 */
export function AssistantFrame({ onOpen, children }: { onOpen: () => void; children: ReactNode }) {
  const [open, setOpenState] = useState(false)
  const [wide, setWide] = useState(false)
  const viewport = useSyncExternalStore(subscribeWidth, windowWidth, () => 1280)
  const width = dockWidth(wide, viewport)
  const setOpen = useCallback((next: boolean) => setOpenState(next), [])
  const toggle = useCallback(() => setOpenState((was) => !was), [])
  const state: PanelState = { open, setOpen, toggle }

  return (
    <PanelContext.Provider value={state}>
      <div className={styles.frame}>
        <AssistantBody onOpen={onOpen} wide={wide} onWide={setWide} width={width}>
          {children}
        </AssistantBody>
      </div>
    </PanelContext.Provider>
  )
}

function AssistantBody({ onOpen, wide, onWide, width, children }: { onOpen: () => void; wide: boolean; onWide: (wide: boolean) => void; width: number; children: ReactNode }) {
  const { open, setOpen, toggle } = useAssistantPanel()
  const route = useRoute()
  const assistant = useAssistant()

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.metaKey && event.key.toLowerCase() === "j") {
        event.preventDefault()
        toggle()
      }
    }
    window.addEventListener("keydown", onKey)
    // The app menu's ⌘J reaches the page as this event instead of a key press, so one or the other fires, never both.
    window.addEventListener(ASSISTANT_EVENT, toggle)
    return () => {
      window.removeEventListener("keydown", onKey)
      window.removeEventListener(ASSISTANT_EVENT, toggle)
    }
  }, [toggle])

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
      <div className={styles.page}>{children}</div>
      <AssistantPanel
        model={model}
        ready={ready}
        provider={configuration?.provider ?? null}
        suggestions={suggestions(route.screen, guru, configuration !== null)}
        assistant={assistant}
        open={open}
        width={width}
        wide={wide}
        onWide={onWide}
        onOpenChange={setOpen}
        onAsk={ask}
        onOpenConnections={() => (setOpen(false), navigate("settings", "connections"))}
      />
    </>
  )
}
