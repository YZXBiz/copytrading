/** The page's clock: the real time, or the `now` the window was opened with (fixture mode pins it). */
export function readClock(): Date {
  const fixed = new URLSearchParams(window.location.search).get("now")
  return fixed ? new Date(fixed) : new Date()
}
