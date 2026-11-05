import { describe, expect, it } from "vitest"
import { MAX_VISIBLE, TOAST_GAP, TOAST_HEIGHT, stackPose } from "./toast-stack"

describe("stackPose", () => {
  it("rests the newest toast in front at full size", () => {
    const front = stackPose(0, false)
    expect(front.y).toBeCloseTo(0)
    expect([front.scale, front.opacity]).toEqual([1, 1])
  })
  it("tucks older toasts behind, smaller and fainter", () => {
    const back = stackPose(2, false)
    expect(back.y).toBe(-20)
    expect(back.scale).toBeCloseTo(0.88)
    expect(back.opacity).toBeCloseTo(0.8)
  })
  it("spreads them in a column when open, all at full size", () => expect(stackPose(2, true)).toEqual({ y: -2 * (TOAST_HEIGHT + TOAST_GAP), scale: 1, opacity: 1 }))
  it("hides toasts past the visible few, open or not", () => {
    expect(stackPose(MAX_VISIBLE, false).opacity).toBe(0)
    expect(stackPose(MAX_VISIBLE, true).opacity).toBe(0)
  })
})
