import { SidebarGroup, SidebarMenu, SidebarMenuButton, SidebarMenuItem } from "@/components/ui/sidebar"
import { type Route, type ScreenId, href } from "./route"
import { SCREENS } from "./screens"

const ITEMS: ScreenId[] = ["getting-started", "connections", "settings"]

export function NavSecondary({ route }: { route: Route }) {
  return (
    <SidebarGroup>
      <SidebarMenu>
        {ITEMS.map((screen) => {
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
