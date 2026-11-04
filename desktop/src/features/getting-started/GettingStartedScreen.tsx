import { useEffect, useId, useState } from "react"
import { Badge } from "@/components/reui/badge"
import { Frame, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Item, ItemContent, ItemGroup, ItemSeparator } from "@/components/ui/item"
import { Skeleton } from "@/components/ui/skeleton"
import { StartBar } from "@/features/connections/StartBar"
import { derive } from "@/features/connections/derive"
import { refreshStatus, useSetup } from "@/features/connections/setup-store"
import { STEPS } from "@/features/connections/state"
import { navigate } from "@/features/shell/route"
import { BEFORE_YOU_GO } from "./before-you-go"
import { OnboardingStepper } from "./OnboardingStepper"

// One short line under each step in the rail (onboarding-2 gives each step a few words); the full sentence is in the panel.
const RAIL_LINES: Record<(typeof STEPS)[number]["id"], string> = {
  discord: "Channels and token.",
  interpreter: "The AI model.",
  account: "Where orders go.",
  guru: "Who to copy.",
  start: "Test, save and begin.",
}

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
  if (!derived) return <GettingStartedSkeleton />

  const { progress } = derived
  const next = STEPS.findIndex((step) => step.id === progress.next) + 1
  const current = picked ?? (next || STEPS.length)
  const selected = STEPS[current - 1]!
  const selectedDone = progress.done.has(selected.id)

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <header className="flex flex-col gap-0.5">
        <h1 className="text-xl font-semibold tracking-tight">Getting Started</h1>
        {progress.next && <p className="text-muted-foreground text-sm">About 10 minutes. Have your Discord, AI provider, and Alpaca logins at hand.</p>}
      </header>

      <Frame>
        <FramePanel className="grid min-w-0 gap-6 sm:grid-cols-[14rem_minmax(0,1fr)]">
          <OnboardingStepper
            currentStep={current}
            onStepChange={setPicked}
            panelId={panelId}
            steps={STEPS.map((step, index) => ({ id: step.id, value: index + 1, label: step.title, description: RAIL_LINES[step.id], done: progress.done.has(step.id) }))}
          />
          <div id={panelId} className="flex min-w-0 flex-col items-start gap-3 sm:border-l sm:pl-6">
            <div className="flex min-w-0 flex-col gap-1.5">
              <div className="flex min-w-0 items-center gap-2">
                <h2 className="truncate text-sm font-semibold">{selected.title}</h2>
                <Badge variant={selectedDone ? "success-light" : "outline"}>{selectedDone ? "Done" : selected.id === "start" ? "Not started" : "To do"}</Badge>
              </div>
              <p className="text-muted-foreground text-sm text-pretty">{selected.detail}</p>
            </div>
            {current < STEPS.length && (
              <Button type="button" variant="outline" size="sm" onClick={() => navigate("connections")}>
                Open Connections
              </Button>
            )}
          </div>
        </FramePanel>
      </Frame>

      <StartBar s={s} derived={derived} />

      <Frame>
        <FrameHeader>
          <FrameTitle>Before you go</FrameTitle>
        </FrameHeader>
        <FramePanel className="p-0!">
          <ItemGroup className="gap-0">
            {BEFORE_YOU_GO.map((note, index) => (
              <div key={note.lead}>
                {index > 0 && <ItemSeparator className="my-0" />}
                <Item size="sm">
                  <ItemContent>
                    <p className="text-sm">
                      <span className="font-medium">{note.lead}</span> <span className="text-muted-foreground">{note.rest}</span>
                    </p>
                  </ItemContent>
                </Item>
              </div>
            ))}
          </ItemGroup>
        </FramePanel>
      </Frame>
    </div>
  )
}

/** The rail, the step and the notes in their real layout while the setup is read. */
function GettingStartedSkeleton() {
  return (
    <div role="status" aria-label="Loading setup steps" className="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <div className="flex flex-col gap-1.5">
        <Skeleton className="h-7 w-44" />
        <Skeleton className="h-4 w-80" />
      </div>
      <Frame>
        <FramePanel className="grid gap-6 sm:grid-cols-[14rem_minmax(0,1fr)]">
          <div className="flex flex-col gap-4">
            {STEPS.map((step) => (
              <div key={step.id} className="flex gap-2.5">
                <Skeleton className="size-5 rounded-full" />
                <div className="flex flex-1 flex-col gap-1.5">
                  <Skeleton className="h-4 w-32" />
                  <Skeleton className="h-3.5 w-24" />
                </div>
              </div>
            ))}
          </div>
          <div className="flex flex-col gap-3 sm:border-l sm:pl-6">
            <Skeleton className="h-4 w-48" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-8 w-36" />
          </div>
        </FramePanel>
      </Frame>
      <Skeleton className="h-16 w-full" />
    </div>
  )
}
