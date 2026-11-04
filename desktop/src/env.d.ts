import type { DesktopApi } from "../shared/contract"

declare global {
  interface Window {
    copytrading: DesktopApi
  }
}
