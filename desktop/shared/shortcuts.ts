/** The keyboard shortcuts, one table: the app menu registers them and ⌘K lists them. ⌘ is held for all of them. */
export const SCREEN_SHORTCUTS = [
  { key: "1", screen: "accounts", title: "Accounts" },
  { key: "2", screen: "gurus", title: "Gurus" },
  { key: "3", screen: "activity", title: "Activity" },
  { key: "4", screen: "connections", title: "Connections" },
  { key: ",", screen: "settings", title: "Settings" },
] as const

export const ASSISTANT_SHORTCUT = "j"

/** What the app menu tells the page to do for ⌘J, since main cannot reach the Assistant's state. */
export const ASSISTANT_EVENT = "copytrading:assistant"

/** The shortcut a screen has, written as the menus write it ("⌘1"), or undefined. */
export const shortcutOf = (screen: string): string | undefined => {
  const found = SCREEN_SHORTCUTS.find((s) => s.screen === screen)
  return found && `⌘${found.key}`
}
