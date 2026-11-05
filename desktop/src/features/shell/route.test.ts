import { describe, expect, it } from "vitest"
import { href, movedHash, parseHash } from "./route"

describe("route", () => {
  it("opens the accounts screen when there is no hash or an unknown one", () => {
    expect(parseHash("")).toEqual({ screen: "accounts", id: null, sub: null })
    expect(parseHash("#/nowhere")).toEqual({ screen: "accounts", id: null, sub: null })
  })

  it("reads a screen and the id after it", () => {
    expect(parseHash("#/gurus")).toEqual({ screen: "gurus", id: null, sub: null })
    expect(parseHash("#/accounts/zhap-account-2")).toEqual({ screen: "accounts", id: "zhap-account-2", sub: null })
  })

  it("leaves a query after the path out of the id", () => {
    expect(parseHash("#/accounts/zhap-account-2?open=limits")).toEqual({ screen: "accounts", id: "zhap-account-2", sub: null })
  })

  it("round-trips an id that needs escaping, such as a Chinese guru name", () => {
    expect(parseHash(href("gurus", "赵哥/1"))).toEqual({ screen: "gurus", id: "赵哥/1", sub: null })
  })

  it("reads the sheet a Settings page opens as the third segment", () => {
    expect(parseHash("#/settings/connections/account:0")).toEqual({ screen: "settings", id: "connections", sub: "account:0" })
    expect(href("settings", "connections", "guru:1")).toBe("#/settings/connections/guru%3A1")
    expect(parseHash(href("settings", "connections", "guru:1")).sub).toBe("guru:1")
  })

  it("sends the old Connections route, and its sheets, to Settings", () => {
    expect(movedHash("#/connections")).toBe("#/settings/connections")
    expect(movedHash("#/connections/discord")).toBe("#/settings/connections/discord")
    expect(movedHash("#/connections/account:0?x=1")).toBe("#/settings/connections/account:0?x=1")
    expect(parseHash("#/connections/guru:0")).toEqual({ screen: "settings", id: "connections", sub: "guru:0" })
    expect(movedHash("#/connectionsx")).toBeNull()
    expect(movedHash("#/settings/connections")).toBeNull()
  })
})
