import { useEffect, useState } from "react"
import { CircleIcon } from "lucide-react"
import type { TradingRunState, TradingStatus } from "../../../shared/contract"
import { SidebarMenuButton, SidebarMenuItem } from "@/components/ui/sidebar"
import { ago } from "@/lib/format"

const POLL_MS = 10_000

const STATES: Record<TradingRunState, { label: string; tone: string }> = {
  running: { label: "Copying", tone: "text-success" },
  starting: { label: "Starting", tone: "text-warning" },
  degraded: { label: "Copying, with problems", tone: "text-warning" },
  pausing: { label: "Pausing", tone: "text-warning" },
  paused: { label: "Not copying", tone: "text-muted-foreground" },
  failed: { label: "Stopped by an error", tone: "text-destructive" },
}

type Read = { status: TradingStatus; at: string } | { error: string } | null

/** The sidebar footer's copying status, read from the engine every ten seconds. */
export function CopyingStatus() {
  const [read, setRead] = useState<Read>(null)
  const [now, setNow] = useState(() => new Date())

  useEffect(() => {
    let current = true
    const load = () =>
      window.copytrading.getStatus().then(
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
  }, [])

  const state = read && "status" in read ? STATES[read.status.state] : null
  const text = !read ? "Checking the engine" : "error" in read ? "Engine not reachable" : `${state?.label} · ${ago(read.at, now)}`
  return (
    <SidebarMenuItem>
      <SidebarMenuButton role="status" title={read && "error" in read ? read.error : undefined}>
        <CircleIcon aria-hidden="true" className={state?.tone ?? (read ? "text-destructive" : "text-muted-foreground")} />
        <span>{text}</span>
      </SidebarMenuButton>
    </SidebarMenuItem>
  )
}
