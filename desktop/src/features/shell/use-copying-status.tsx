import { useEffect, useState } from "react"
import type { RailStatus } from "@/components/arc/blocks/sidebar-rail/sidebar-rail"
import type { EngineState, TradingStatus } from "../../../shared/contract"
import { COPYING_STATES, type Tone } from "../../../shared/copying-state"
import { ago } from "@/lib/format"
import { copyingProblem } from "./copying-problem"
import styles from "./copying-status.module.css"

const POLL_MS = 10_000

type DotTone = Tone | "checking"

type Read = { status: TradingStatus; at: string } | { error: string } | null

/** Copying status, read from the engine every ten seconds once the engine is running. */
function useCopyingRead(running: boolean) {
  const [read, setRead] = useState<Read>(null)
  const [now, setNow] = useState(() => new Date())

  useEffect(() => {
    if (!running) return
    let current = true
    const load = () =>
      window.copytrading.read.getStatus().then(
        (result) => {
          if (!current) return
          const at = new Date()
          setNow(at)
          setRead(result.ok ? { status: result.value, at: at.toISOString() } : { error: result.error })
        },
        () => current && setRead({ error: "The engine did not answer." }),
      )
    void load()
    const timer = setInterval(load, POLL_MS)
    return () => {
      current = false
      clearInterval(timer)
    }
  }, [running])

  return { read, now }
}

/** The sidebar's status line: the engine starting or stopped (with why), else whether copying is on. */
export function useCopyingStatus(engine: EngineState): RailStatus {
  const { read, now } = useCopyingRead(engine.state === "running")

  let text: string
  // How fresh the reading is, set apart on a second line.
  let note: string | undefined
  let tone: DotTone
  let title: string | undefined
  // Whether the text is the engine's reason or a problem, which runs to a sentence.
  let sentence = false
  if (engine.state === "starting") {
    text = "Engine starting"
    tone = "warning"
  } else if (engine.state === "stopped") {
    text = `Engine stopped: ${engine.reason}`
    tone = "destructive"
    title = engine.reason
    sentence = true
  } else if (!read) {
    text = "Checking the engine"
    tone = "checking"
  } else if ("error" in read) {
    text = "Engine not reachable"
    tone = "destructive"
    title = read.error
  } else {
    const state = COPYING_STATES[read.status.state]
    tone = state.tone
    // With problems, the line says which: the account or service, what happened, what to do. A sentence has no room for the age.
    const problem = read.status.state === "degraded" ? copyingProblem(read.status) : undefined
    text = problem ?? state.label
    title = problem
    sentence = problem !== undefined
    if (!problem) note = ago(read.at, now)
  }

  // The dot pulses only while copying runs; every other state is a still dot.
  const live = engine.state === "running" && read !== null && !("error" in read) && read.status.state === "running"
  return { marker: <span className={styles.dot} data-tone={tone} data-live={live || undefined} />, text, note, title, sentence }
}
