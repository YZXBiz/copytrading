import { useEffect, useState } from "react"
import { SparklesIcon, SquarePenIcon } from "lucide-react"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { Skeleton } from "@/components/ui/skeleton"
import { SidebarMenuButton, SidebarMenuItem } from "@/components/ui/sidebar"
import { navigate, useRoute } from "@/features/shell/route"
import { useResult } from "@/lib/use-result"
import { AssistantComposer } from "./AssistantComposer"
import { AssistantEmpty } from "./AssistantEmpty"
import { AssistantTranscript } from "./AssistantTranscript"
import { assistantContext, assistantGurus, hasModel, suggestions } from "./context"
import { useAssistant } from "./use-assistant"

/** The assistant's button for the sidebar, and its panel: a sheet on the right that closes on Esc, with ⌘J to open it. */
export function AssistantPanel() {
  const [open, setOpen] = useState(false)
  const route = useRoute()
  const assistant = useAssistant()

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.metaKey && event.key.toLowerCase() === "j") {
        event.preventDefault()
        setOpen((was) => !was)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [])

  // Read again each time the panel opens, so a model set up in Connections is seen.
  const model = useResult(async () => {
    const { read } = window.copytrading
    const [setup, secrets] = await Promise.all([read.getSetup(), read.getSecretStatus()])
    if (!setup.ok) return setup
    if (!secrets.ok) return secrets
    return { ok: true as const, value: { setup: setup.value?.configuration ?? null, hasModel: hasModel(setup.value, secrets.value) } }
  }, `model:${open}`)

  const configuration = model.status === "ready" ? model.data.setup : null
  const gurus = assistantGurus(configuration)
  const guru = (route.screen === "gurus" && gurus.find((g) => g.id === route.id)?.name) || gurus[0]?.name || null
  const ready = model.status === "ready" && model.data.hasModel
  const ask = (text: string) => void assistant.ask(text, assistantContext(route, configuration), ready)

  return (
    <>
      <SidebarMenuItem>
        <SidebarMenuButton onClick={() => setOpen(true)} tooltip="Assistant (⌘J)">
          <SparklesIcon aria-hidden="true" />
          <span>Assistant</span>
        </SidebarMenuButton>
      </SidebarMenuItem>
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent className="gap-0 p-0 sm:max-w-md" aria-label="Assistant">
          <SheetHeader className="flex-row items-center gap-2 border-b py-3 pr-14">
            <SheetTitle>Assistant</SheetTitle>
            <SheetDescription className="sr-only">Ask about your posts, accounts, and setup.</SheetDescription>
            {assistant.messages.length > 0 && (
              <Button type="button" variant="ghost" size="icon-sm" className="ml-auto" aria-label="New conversation" onClick={() => void assistant.reset()}>
                <SquarePenIcon />
              </Button>
            )}
          </SheetHeader>
          {model.status === "error" ? (
            <div className="p-4">
              <RegionError title="The assistant's model did not load" message={model.error} onRetry={model.retry} />
            </div>
          ) : model.status === "loading" ? (
            <div className="flex flex-1 flex-col gap-3 p-4">
              <Skeleton className="h-6 w-2/3" />
              <Skeleton className="h-12 w-full" />
            </div>
          ) : assistant.messages.length === 0 ? (
            <AssistantEmpty hasModel={ready} suggestions={suggestions(route.screen, guru, configuration !== null)} onAsk={ask} onOpenConnections={() => (setOpen(false), navigate("connections"))} />
          ) : (
            <div className="min-h-0 flex-1">
              <AssistantTranscript messages={assistant.messages} answering={assistant.answering} onNavigate={() => setOpen(false)} />
            </div>
          )}
          <AssistantComposer answering={assistant.answering} enabled={ready} onSend={ask} onStop={() => void assistant.stop()} />
        </SheetContent>
      </Sheet>
    </>
  )
}
