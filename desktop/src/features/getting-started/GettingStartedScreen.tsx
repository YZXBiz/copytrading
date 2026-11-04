import { useEffect, useId, useState } from "react"
import { CheckIcon, CircleDashedIcon } from "lucide-react"
import { Frame, FramePanel } from "@/components/reui/frame"
import { Stepper, StepperContent, StepperIndicator, StepperItem, StepperNav, StepperPanel, StepperTitle, StepperTrigger } from "@/components/reui/stepper"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Separator } from "@/components/ui/separator"
import { Skeleton } from "@/components/ui/skeleton"
import { StartBar } from "@/features/connections/StartBar"
import { derive } from "@/features/connections/derive"
import { refreshStatus, useSetup } from "@/features/connections/setup-store"
import { STEPS } from "@/features/connections/state"
import { navigate } from "@/features/shell/route"
import { BEFORE_YOU_GO } from "./before-you-go"

// A done step is a check, the one selected a spinning ring that follows the selection, the rest a dashed circle (c-stepper-41).
const completed = (
  <span className="border-success bg-success/10 text-success flex size-3.5 items-center justify-center rounded-full border">
    <CheckIcon strokeWidth={2.88} className="size-2.5 *:stroke-[2.88]" aria-hidden="true" />
  </span>
)
const pending = <CircleDashedIcon className="text-ring/60 size-3.5" aria-hidden="true" />
const loading = (
  <svg viewBox="0 0 14 14" fill="none" strokeWidth={1.2} className="size-3.5" aria-hidden="true">
    <circle cx="7" cy="7" r="6" pathLength={40} strokeDasharray="3 1" transform="rotate(-54 7 7)" className="stroke-ring/80" />
    <circle cx="7" cy="7" r="6" pathLength={360} strokeDasharray="140 220" strokeDashoffset={118} className="origin-center stroke-blue-500 motion-safe:animate-spin" />
  </svg>
)
const indicators = { completed, inactive: pending, loading }

/** What is connected, what is left, and the one Start copying: the five setup steps as a status list, then what to know before copying. */
export function GettingStartedScreen() {
  const s = useSetup()
  const derived = derive(s)
  const id = useId()
  const panelId = `${id}-panel`
  const [picked, setPicked] = useState<number | null>(null)

  useEffect(() => {
    const timer = setInterval(() => void refreshStatus(), 5000)
    return () => clearInterval(timer)
  }, [])

  if (s.load.status === "error") return <RegionError title="Getting started did not load" message={s.load.error} onRetry={s.retry} />
  if (!derived) {
    return (
      <div role="status" aria-label="Loading setup steps" className="mx-auto flex w-full max-w-2xl flex-col gap-4">
        <Skeleton className="h-8 w-56" />
        <Skeleton className="h-48 w-full" />
      </div>
    )
  }

  const { progress } = derived
  const next = STEPS.findIndex((step) => step.id === progress.next) + 1
  const current = picked ?? (next || STEPS.length)

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-8">
      <header className="flex flex-col gap-1">
        <h1 className="text-xl font-semibold tracking-tight">Getting started</h1>
        <p className="text-muted-foreground text-sm">
          {progress.next ? "About 10 minutes, five steps. Have your Discord, AI provider, and Alpaca logins at hand." : "You're set up. This page stays here as your guide."}
        </p>
      </header>

      <Stepper value={current} onValueChange={setPicked} orientation="vertical" indicators={indicators} className="@container" aria-label="Setup steps">
        <div className="flex flex-col gap-6 @md:flex-row @md:items-start">
          <Frame variant="ghost" spacing="xs" className="w-52 shrink-0 bg-transparent p-0 [--frame-panel-py-base:--spacing(1.5)]">
            <StepperNav className="gap-1.5">
              {STEPS.map((step, index) => {
                const number = index + 1
                const done = progress.done.has(step.id)
                return (
                  <StepperItem key={step.id} step={number} completed={done} loading>
                    <StepperTrigger
                      id={`${id}-tab-${number}`}
                      aria-controls={panelId}
                      render={<FramePanel />}
                      className="hover:bg-muted/50 data-[state=active]:bg-muted/50 w-full gap-2 rounded-[calc(var(--frame-panel-radius)-3px)] border-transparent bg-transparent px-[calc(var(--frame-panel-px)-1px)] shadow-none data-[state=active]:border-(--frame-panel-border-color)"
                    >
                      <StepperIndicator className="size-3.5 overflow-visible bg-transparent data-[state=active]:bg-transparent data-[state=completed]:bg-transparent" />
                      <StepperTitle className="data-[state=inactive]:text-muted-foreground min-w-0 flex-1 truncate leading-5 data-[state=active]:text-blue-500">{step.title}</StepperTitle>
                      <span className="sr-only">, {done ? "done" : number === current ? "in progress" : "to do"}</span>
                    </StepperTrigger>
                  </StepperItem>
                )
              })}
            </StepperNav>
          </Frame>

          <Separator aria-hidden="true" className="@md:hidden" />
          <Separator aria-hidden="true" orientation="vertical" className="hidden @md:block" />
          <div className="flex min-w-0 flex-1 flex-col gap-3 px-2 text-start @md:px-0">
            <StepperPanel>
              {STEPS.map((step, index) => (
                <StepperContent key={step.id} value={index + 1}>
                  <div id={panelId} className="flex flex-col gap-1">
                    <p className="text-muted-foreground text-xs">
                      Step {index + 1} of {STEPS.length}
                    </p>
                    <p className="text-sm font-medium">{step.title}</p>
                    <p className="text-muted-foreground text-sm text-pretty">{step.detail}</p>
                    <p className="text-sm">{progress.done.has(step.id) ? "Done." : step.id === "start" ? "Not started yet." : "Not done yet."}</p>
                  </div>
                </StepperContent>
              ))}
            </StepperPanel>
            {current < STEPS.length && (
              <div className="flex justify-start">
                <Button type="button" variant="outline" size="sm" onClick={() => navigate("connections")}>
                  Open Connections
                </Button>
              </div>
            )}
          </div>
        </div>
      </Stepper>

      <StartBar s={s} derived={derived} />

      <section aria-labelledby="before" className="flex flex-col gap-3">
        <h2 id="before" className="text-sm font-medium">
          Before you go
        </h2>
        <ul className="flex flex-col gap-2 text-sm">
          {BEFORE_YOU_GO.map((note) => (
            <li key={note.lead}>
              <span className="font-medium">{note.lead}</span> <span className="text-muted-foreground">{note.rest}</span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}
