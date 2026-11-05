import { useEffect, useState } from "react"

// The route is `location.hash`: #/accounts/zhap-account-2, #/gurus, #/settings. No router library:
// a screen is a hash segment, and a link is an <a href={href(...)}> or navigate().

export const SCREEN_IDS = ["accounts", "gurus", "activity", "getting-started", "settings"] as const
export type ScreenId = (typeof SCREEN_IDS)[number]

export interface Route {
  screen: ScreenId
  /** The second segment: an account id on #/accounts/<id>, a guru id on #/gurus/<id>. */
  id: string | null
  /** The third segment: the sheet a Settings page opens, as in #/settings/connections/account:0. */
  sub: string | null
}

/** Connections moved into Settings: #/connections[/sheet] is now #/settings/connections[/sheet], and null for any other hash. */
export function movedHash(hash: string): string | null {
  const moved = /^#\/connections(?=[/?]|$)/.exec(hash)
  return moved ? `#/settings/connections${hash.slice(moved[0].length)}` : null
}

export function parseHash(hash: string): Route {
  // A `?name=value` after the path is for the screen (an account page opens its sheet from `?open=`), not part of the id.
  const [screen, id, sub] = (movedHash(hash) ?? hash).replace(/^#\/?/, "").split("?")[0]!.split("/")
  return {
    screen: SCREEN_IDS.find((s) => s === screen) ?? "accounts",
    id: id ? decodeURIComponent(id) : null,
    sub: sub ? decodeURIComponent(sub) : null,
  }
}

export const href = (screen: ScreenId, id?: string | null, sub?: string | null) =>
  `#/${screen}${id ? `/${encodeURIComponent(id)}` : ""}${id && sub ? `/${encodeURIComponent(sub)}` : ""}`

export const navigate = (screen: ScreenId, id?: string | null, sub?: string | null) => {
  window.location.hash = href(screen, id, sub)
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parseHash(window.location.hash))
  useEffect(() => {
    const update = () => {
      // An old link is rewritten in place, so the address bar and Back never hold the removed path.
      const moved = movedHash(window.location.hash)
      if (moved) window.location.replace(moved)
      setRoute(parseHash(window.location.hash))
    }
    update()
    window.addEventListener("hashchange", update)
    return () => window.removeEventListener("hashchange", update)
  }, [])
  return route
}
