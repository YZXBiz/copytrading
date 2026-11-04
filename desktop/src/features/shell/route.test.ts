import { describe, expect, it } from "vitest"
import { href, parseHash } from "./route"

describe("route", () => {
  it("opens the accounts screen when there is no hash or an unknown one", () => {
    expect(parseHash("")).toEqual({ screen: "accounts", id: null })
    expect(parseHash("#/nowhere")).toEqual({ screen: "accounts", id: null })
  })

  it("reads a screen and the id after it", () => {
    expect(parseHash("#/gurus")).toEqual({ screen: "gurus", id: null })
    expect(parseHash("#/accounts/zhap-account-2")).toEqual({ screen: "accounts", id: "zhap-account-2" })
  })

  it("round-trips an id that needs escaping, such as a Chinese guru name", () => {
    expect(parseHash(href("gurus", "赵哥/1"))).toEqual({ screen: "gurus", id: "赵哥/1" })
  })
})
