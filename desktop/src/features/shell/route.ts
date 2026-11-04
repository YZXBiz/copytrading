import { useEffect, useState } from "react"

// The route is `location.hash`: #/accounts/zhap-account-2, #/gurus, #/settings. No router library:
// a screen is a hash segment, and a link is an <a href={href(...)}> or navigate().

export const SCREEN_IDS = ["accounts", "gurus", "activity", "getting-started", "connections", "settings"] as const
export type ScreenId = (typeof SCREEN_IDS)[number]

export interface Route {
  screen: ScreenId
  /** The second segment: an account id on #/accounts/<id>, a guru id on #/gurus/<id>. */
  id: string | null
}

export function parseHash(hash: string): Route {
  // A `?name=value` after the path is for the screen (an account page opens its sheet from `?open=`), not part of the id.
  const [screen, id] = hash.replace(/^#\/?/, "").split("?")[0]!.split("/")
  return {
    screen: SCREEN_IDS.find((s) => s === screen) ?? "accounts",
    id: id ? decodeURIComponent(id) : null,
  }
}

export const href = (screen: ScreenId, id?: string | null) => `#/${screen}${id ? `/${encodeURIComponent(id)}` : ""}`

export const navigate = (screen: ScreenId, id?: string | null) => {
  window.location.hash = href(screen, id)
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parseHash(window.location.hash))
  useEffect(() => {
    const update = () => setRoute(parseHash(window.location.hash))
    window.addEventListener("hashchange", update)
    return () => window.removeEventListener("hashchange", update)
  }, [])
  return route
}
