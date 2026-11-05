import { RailTopbar } from "@/components/arc/blocks/sidebar-rail/sidebar-rail"
import { AssistantToggle } from "@/features/assistant/AssistantToggle"
import { SCREENS } from "./screens"
import type { Route } from "./route"

/** The page's top bar: the rail's toggle and the screen's title, with the Assistant's one control at the right. */
export function AppHeader({ route, selectedAccountId }: { route: Route; selectedAccountId: string | null }) {
  // An account page carries its own breadcrumb row beside its actions.
  return <RailTopbar title={selectedAccountId ? undefined : SCREENS[route.screen].title} end={<AssistantToggle />} />
}
