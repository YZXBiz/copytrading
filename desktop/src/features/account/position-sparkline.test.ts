import { describe, expect, it } from "vitest"
import type { Bar } from "../../../shared/contract"
import { dayDirection } from "./PositionSparkline"

const bar = (open: string, close: string): Bar => ({ at: "2026-11-04T14:30:00Z", open, close })

describe("dayDirection", () => {
  it("is up when the session closes at or above where it opened, down below it", () => {
    expect(dayDirection([bar("40.10", "40.20"), bar("40.20", "40.35")])).toBe("up")
    expect(dayDirection([bar("40.10", "40.50"), bar("40.50", "40.10")])).toBe("up")
    expect(dayDirection([bar("40.10", "40.50"), bar("40.50", "39.90")])).toBe("down")
  })

  it("has no direction without bars or a readable price", () => {
    expect(dayDirection([])).toBeNull()
    expect(dayDirection([bar("x", "40"), bar("40", "41")])).toBeNull()
  })
})
