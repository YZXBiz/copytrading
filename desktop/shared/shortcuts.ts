/** The keyboard shortcuts, one table: the app menu registers them and ⌘K lists them. ⌘ is held for all of them. */
export const SCREEN_SHORTCUTS = [
  { key: "1", hash: "#/accounts", title: "Accounts" },
  { key: "2", hash: "#/gurus", title: "Gurus" },
  { key: "3", hash: "#/activity", title: "Activity" },
  { key: "4", hash: "#/settings/connections", title: "Connections" },
  { key: ",", hash: "#/settings", title: "Settings" },
] as const

export const ASSISTANT_SHORTCUT = "j"

/** What the app menu tells the page to do for ⌘J, since main cannot reach the Assistant's state. */
export const ASSISTANT_EVENT = "copytrading:assistant"

/** The shortcut a route has, written as the menus write it ("⌘1"), or undefined. */
export const shortcutOf = (hash: string): string | undefined => {
  const found = SCREEN_SHORTCUTS.find((s) => s.hash === hash)
  return found && `⌘${found.key}`
}
