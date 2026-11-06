import { describe, expect, it } from "vitest"
import { stopLine } from "./stops"

const stop = (stop_price: string, working = true) => ({ stop_price, quantity: "12", working, source_id: "discord:1:2" })

describe("the stop line on a holding", () => {
  it("says nothing for a holding with no stop", () => {
    expect(stopLine({})).toBeNull()
    expect(stopLine({ stops: [] })).toBeNull()
  })

  it("names the price to the cent", () => {
    expect(stopLine({ stops: [stop("44.5")] })).toBe("Stop $44.50")
  })

  it("lists several stops lowest first, and a price once", () => {
    expect(stopLine({ stops: [stop("44.5"), stop("38.4"), stop("44.50", false)] })).toBe("Stops $38.40, $44.50")
  })
})
