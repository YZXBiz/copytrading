import { useEffect, useRef } from "react"

/**
 * Opens the sheet the window was opened to (`#/accounts/<id>?open=review|sale|limits`) once `ready`, then forgets
 * the link, so closing the sheet does not open it again.
 */
export function useDeepLink(ready: boolean, open: (sheet: string) => void) {
  const wanted = useRef(new URLSearchParams(window.location.hash.split("?")[1]).get("open"))
  useEffect(() => {
    if (!ready || !wanted.current) return
    open(wanted.current)
    wanted.current = null
    // `open` is a fresh closure each render; `ready` says when the data it needs is here.
  }, [ready])
}
