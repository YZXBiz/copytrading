import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { leavesGap } from "./use-posts"

const posts = (...sequences: number[]) => sequences.map((sequence) => ({ sequence }) as SourceActivity)

describe("leavesGap", () => {
  it("keeps the kept posts when the newest page reaches them", () => {
    expect(leavesGap(posts(5, 4, 3), posts(7, 6, 5), 3)).toBe(false)
  })

  it("keeps them when the newest page is not full, so nothing lies between", () => {
    expect(leavesGap(posts(5, 4), posts(7, 6), 3)).toBe(false)
  })

  it("starts over when a full newest page reaches none of them", () => {
    expect(leavesGap(posts(5, 4), posts(9, 8, 7), 3)).toBe(true)
  })
})
