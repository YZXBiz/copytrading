import { useEffect, useState } from "react"
import type { EngineState } from "../../../shared/contract"

/** The engine process as main reports it: starting, running, or stopped with the reason. */
export function useEngineState(): EngineState {
  const [state, setState] = useState<EngineState>({ state: "starting" })
  useEffect(() => {
    let current = true
    void window.copytrading.engine.state().then((s) => current && setState(s))
    const stop = window.copytrading.engine.onState(setState)
    return () => {
      current = false
      stop()
    }
  }, [])
  return state
}
