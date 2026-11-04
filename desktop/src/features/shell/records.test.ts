import { describe, expect, it } from "vitest"
import type { AccountOverview, TradingConfiguration } from "../../../shared/contract"
import { splitRecords } from "./records"

const account = (id: string) => ({ account_id: id }) as AccountOverview
const setup = (...ids: string[]) => ({ accounts: ids.map((id) => ({ id })) }) as unknown as TradingConfiguration

describe("splitRecords", () => {
  const all = [account("testing"), account("zhap"), account("primary")]

  it("keeps the accounts in the setup first and files the rest as old records", () => {
    const { live, old } = splitRecords(all, setup("zhap"))
    expect(live.map((a) => a.account_id)).toEqual(["zhap"])
    expect(old.map((a) => a.account_id)).toEqual(["testing", "primary"])
  })

  it("hides nothing before the setup is read or when none is saved", () => {
    expect(splitRecords(all, undefined)).toEqual({ live: all, old: [] })
    expect(splitRecords(all, null)).toEqual({ live: all, old: [] })
  })
})
