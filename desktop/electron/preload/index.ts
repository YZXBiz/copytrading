import { contextBridge, ipcRenderer } from "electron"
import { CHANNELS, type DesktopApi } from "../../shared/contract"

// The renderer gets these reads and nothing else: no ipcRenderer, no raw engine pipe.
const api: DesktopApi = {
  getStatus: () => ipcRenderer.invoke(CHANNELS.getStatus),
  getAccounts: () => ipcRenderer.invoke(CHANNELS.getAccounts),
  getEquityHistory: (accountId, range) => ipcRenderer.invoke(CHANNELS.getEquityHistory, accountId, range),
  getSourceActivity: () => ipcRenderer.invoke(CHANNELS.getSourceActivity),
  getLimits: (accountId) => ipcRenderer.invoke(CHANNELS.getLimits, accountId),
}

contextBridge.exposeInMainWorld("copytrading", api)
