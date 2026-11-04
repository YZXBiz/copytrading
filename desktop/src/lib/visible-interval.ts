type Page = Pick<Document, "visibilityState" | "addEventListener" | "removeEventListener">

/**
 * Runs `run` now and then every `ms`, but only while the window is visible: it stops when the page is hidden and
 * runs again at once, then on the interval, when it is shown. Returns the way to stop.
 */
export function everyWhileVisible(run: () => void, ms: number, page: Page = document): () => void {
  let timer: ReturnType<typeof setInterval> | undefined
  const start = () => {
    if (timer !== undefined || page.visibilityState !== "visible") return
    run()
    timer = setInterval(run, ms)
  }
  const stop = () => {
    clearInterval(timer)
    timer = undefined
  }
  const onChange = () => (page.visibilityState === "visible" ? start() : stop())
  page.addEventListener("visibilitychange", onChange)
  start()
  return () => {
    page.removeEventListener("visibilitychange", onChange)
    stop()
  }
}
