import { derive } from "@/features/connections/derive"
import { useSetup } from "@/features/connections/setup-store"
import { SidebarGroup, SidebarMenu, SidebarMenuButton, SidebarMenuItem } from "@/components/ui/sidebar"
import { type Route, type ScreenId, href } from "./route"
import { SCREENS } from "./screens"

/**
 * Settings, with Getting Started above it until setup is complete: every step of its checklist done, which includes
 * copying started once (the setup saved). It stays while its own page is open, and #/getting-started and ⌘K reach it after.
 */
export function NavSecondary({ route }: { route: Route }) {
  const setup = derive(useSetup())
  const settingUp = setup !== null && setup.progress.next !== null
  const items: ScreenId[] = settingUp || route.screen === "getting-started" ? ["getting-started", "settings"] : ["settings"]
  return (
    <SidebarGroup>
      <SidebarMenu>
        {items.map((screen) => {
          const { title, icon: Icon } = SCREENS[screen]
          return (
            <SidebarMenuItem key={screen}>
              <SidebarMenuButton
                size="sm"
                tooltip={title}
                isActive={route.screen === screen}
                render={<a href={href(screen)} />}
                className="h-8! in-data-[state=collapsed]:h-8! [&_svg]:size-3.5"
              >
                <Icon aria-hidden="true" />
                <span>{title}</span>
              </SidebarMenuButton>
            </SidebarMenuItem>
          )
        })}
      </SidebarMenu>
    </SidebarGroup>
  )
}
