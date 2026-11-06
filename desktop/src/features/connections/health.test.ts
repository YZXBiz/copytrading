import { describe, expect, it } from "vitest"
import { healthOf } from "./health"
import type { Status } from "./state"

const status = (text: string, tone: Status["tone"]): Status => ({ text, tone })

describe("healthOf", () => {
  it("reads a running check as checking, whatever the saved state says", () => {
    expect(healthOf(status("Connected", "positive"), "connecting")).toBe("checking")
    expect(healthOf(status("Checking…", "neutral"))).toBe("checking")
    expect(healthOf(status("Connecting", "neutral"))).toBe("checking")
  })

  it("reads a failed check as an outage so the reason shows in the danger colour", () => {
    expect(healthOf(status("Couldn't connect", "caution"), "idle", "The token was refused.")).toBe("outage")
  })

  it("maps the rest of the tones", () => {
    expect(healthOf(status("Connected", "positive"), "connected")).toBe("operational")
    expect(healthOf(status("Needs keys", "caution"))).toBe("degraded")
    expect(healthOf(status("Not saved yet", "inactive"))).toBe("idle")
    expect(healthOf(status("Saved", "neutral"))).toBe("idle")
  })
})
