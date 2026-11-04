import { useEffect, useState } from "react"
import type { EngineState, TradingRunState, TradingStatus } from "../../../shared/contract"
import { SidebarMenuButton, SidebarMenuItem } from "@/components/ui/sidebar"
import { ago } from "@/lib/format"
import { cn } from "@/lib/utils"

const POLL_MS = 10_000

const STATES: Record<TradingRunState, { label: string; tone: string }> = {
  running: { label: "Copying", tone: "bg-success" },
  starting: { label: "Starting", tone: "bg-warning" },
  degraded: { label: "Copying, with problems", tone: "bg-warning" },
  pausing: { label: "Pausing", tone: "bg-warning" },
  paused: { label: "Not copying", tone: "bg-muted-foreground/50" },
  failed: { label: "Stopped by an error", tone: "bg-destructive" },
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
    tone = "bg-warning"
  } else if (engine.state === "stopped") {
    text = `Engine stopped: ${engine.reason}`
    tone = "bg-destructive"
    title = engine.reason
  } else if (!read) {
    text = "Checking the engine"
    tone = "bg-muted-foreground/50"
  } else if ("error" in read) {
    text = "Engine not reachable"
    tone = "bg-destructive"
    title = read.error
  } else {
    const state = STATES[read.status.state]
    text = state.label
    age = ago(read.at, now)
    tone = state.tone
  }

  // The dot pulses only while copying runs; every other state is a still dot.
  const live = engine.state === "running" && read !== null && !("error" in read) && read.status.state === "running"

  return (
    <SidebarMenuItem>
      <SidebarMenuButton role="status" tooltip={title ?? text} title={title}>
        <span className="flex size-4 shrink-0 items-center justify-center" aria-hidden="true">
          <span
            className={cn(
              "relative size-1.5 rounded-full",
              tone,
              live &&
                "before:bg-success after:bg-success before:absolute before:inset-0 before:animate-ping before:rounded-full before:opacity-80 before:duration-1500 after:absolute after:inset-0 after:animate-ping after:rounded-full after:opacity-40 after:delay-500 after:duration-1500 motion-reduce:before:animate-none motion-reduce:after:animate-none",
            )}
          />
        </span>
        <span>{text}</span>
        {age && <span className="text-muted-foreground ml-auto text-xs tabular-nums in-data-[state=collapsed]:hidden">{age}</span>}
      </SidebarMenuButton>
    </SidebarMenuItem>
  )
}
