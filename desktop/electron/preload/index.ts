import { contextBridge, ipcRenderer } from "electron"
import { ACTS, CHANNELS, type DesktopApi, type EngineState, type FillAlert, READS } from "../../shared/contract"

// The renderer gets `read.*`, `act.*` and the engine's state, and nothing else: no ipcRenderer, no raw
// engine pipe. A method here is a name sent to main, which checks it against the same lists.
const methods = (channel: string, names: readonly string[]) =>
  Object.fromEntries(names.map((name) => [name, (params?: unknown) => ipcRenderer.invoke(channel, name, params)]))

const api = {
  read: methods(CHANNELS.read, READS),
  act: methods(CHANNELS.act, ACTS),
  engine: {
    state: () => ipcRenderer.invoke(CHANNELS.state),
    onState: (listener: (state: EngineState) => void) => {
      const handler = (_event: unknown, state: EngineState) => listener(state)
      ipcRenderer.on(CHANNELS.stateChanged, handler)
      return () => ipcRenderer.removeListener(CHANNELS.stateChanged, handler)
    },
    onFill: (listener: (fill: FillAlert) => void) => {
      const handler = (_event: unknown, fill: FillAlert) => listener(fill)
      ipcRenderer.on(CHANNELS.fill, handler)
      return () => ipcRenderer.removeListener(CHANNELS.fill, handler)
    },
  },
} as unknown as DesktopApi // the method names are the READS/ACTS lists, which contract.ts keeps equal to the types

contextBridge.exposeInMainWorld("copytrading", api)
