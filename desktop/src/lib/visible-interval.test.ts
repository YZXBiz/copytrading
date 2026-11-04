import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { everyWhileVisible } from "./visible-interval"

/** A page that is shown or hidden on demand. */
function page(state: "visible" | "hidden") {
  const events = new EventTarget()
  const fake = {
    visibilityState: state,
    addEventListener: events.addEventListener.bind(events),
    removeEventListener: events.removeEventListener.bind(events),
  } as unknown as Document
  return { fake, set: (next: "visible" | "hidden") => { (fake as { visibilityState: string }).visibilityState = next; events.dispatchEvent(new Event("visibilitychange")) } }
}

beforeEach(() => vi.useFakeTimers())
afterEach(() => vi.useRealTimers())

describe("everyWhileVisible", () => {
  it("runs at once and then every interval while the page is visible", () => {
    const run = vi.fn()
    const p = page("visible")
    const stop = everyWhileVisible(run, 5000, p.fake)
    expect(run).toHaveBeenCalledTimes(1)
    vi.advanceTimersByTime(10_000)
    expect(run).toHaveBeenCalledTimes(3)
    stop()
  })

  it("pauses while the page is hidden and runs again at once when it is shown", () => {
    const run = vi.fn()
    const p = page("visible")
    const stop = everyWhileVisible(run, 5000, p.fake)
    p.set("hidden")
    vi.advanceTimersByTime(60_000)
    expect(run).toHaveBeenCalledTimes(1)
    p.set("visible")
    expect(run).toHaveBeenCalledTimes(2)
    vi.advanceTimersByTime(5000)
    expect(run).toHaveBeenCalledTimes(3)
    stop()
  })

  it("does not run at all for a page that starts hidden, until it is shown", () => {
    const run = vi.fn()
    const p = page("hidden")
    const stop = everyWhileVisible(run, 5000, p.fake)
    vi.advanceTimersByTime(20_000)
    expect(run).not.toHaveBeenCalled()
    p.set("visible")
    expect(run).toHaveBeenCalledTimes(1)
    stop()
  })

  it("never starts a second timer when shown twice, and stops for good when stopped", () => {
    const run = vi.fn()
    const p = page("visible")
    const stop = everyWhileVisible(run, 5000, p.fake)
    p.set("visible")
    vi.advanceTimersByTime(5000)
    expect(run).toHaveBeenCalledTimes(2)
    stop()
    p.set("hidden")
    p.set("visible")
    vi.advanceTimersByTime(60_000)
    expect(run).toHaveBeenCalledTimes(2)
  })
})
