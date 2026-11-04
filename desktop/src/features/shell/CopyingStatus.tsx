import { useEffect, useState } from "react"
import { CircleIcon } from "lucide-react"
import type { EngineState, TradingRunState, TradingStatus } from "../../../shared/contract"
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

/** The sidebar footer: the engine starting or stopped (with why), else whether copying is on. */
export function CopyingStatus({ engine }: { engine: EngineState }) {
  const { read, now } = useCopyingRead(engine.state === "running")

  let text: string
  // How fresh the reading is, set apart at the row's right edge.
  let age: string | undefined
  let tone: string
  let title: string | undefined
  if (engine.state === "starting") {
    text = "Engine starting"
    tone = "text-warning"
  } else if (engine.state === "stopped") {
    text = `Engine stopped: ${engine.reason}`
    tone = "text-destructive"
    title = engine.reason
  } else if (!read) {
    text = "Checking the engine"
    tone = "text-muted-foreground"
  } else if ("error" in read) {
    text = "Engine not reachable"
    tone = "text-destructive"
    title = read.error
  } else {
    const state = STATES[read.status.state]
    text = state.label
    age = ago(read.at, now)
    tone = state.tone
  }

  return (
    <SidebarMenuItem>
      <SidebarMenuButton
        role="status"
        title={title}
        // A stopped engine's reason may be a sentence: let it wrap to three lines instead of one cut-off line.
        className={engine.state === "stopped" ? "h-auto items-start py-1.5 [&>span:last-child]:line-clamp-3 [&>span:last-child]:whitespace-normal" : undefined}
      >
        <CircleIcon aria-hidden="true" className={tone} />
        <span>{text}</span>
        {age && <span className="text-muted-foreground ml-auto text-xs tabular-nums">{age}</span>}
      </SidebarMenuButton>
    </SidebarMenuItem>
  )
}
