import type { Format } from "@number-flow/react"
import { createElement } from "react"
import { renderToString } from "react-dom/server"
import { describe, expect, it } from "vitest"
import { RollingNumber } from "@/components/rolling-number"
import { PERCENT_SIGNED_OPTIONS, USD_OPTIONS, USD_SIGNED_OPTIONS, USD_WHOLE_OPTIONS, formatSignedPercent, formatSignedUsd, formatUsd } from "./format"

const text = (value: number, options: Intl.NumberFormatOptions) => new Intl.NumberFormat("en-US", options).format(value)

// NumberFlow's first render (what the page and the server draw) names its text in aria-label: the formatter's own string.
const label = (value: number | null, format: Format) =>
  renderToString(createElement(RollingNumber, { value, format })).match(/aria-label="([^"]*)"/)?.[1]

describe("the options the rolling figures format with", () => {
  it.each([
    [2700.08, "$2,700.08", "+$2,700.08"],
    [-88.1, "-$88.10", "-$88.10"],
    [0, "$0.00", "$0.00"],
    [1234567.891, "$1,234,567.89", "+$1,234,567.89"],
  ])("%s reads exactly as the page's formatters write it", (value, plain, signed) => {
    expect(formatUsd(value)).toBe(plain)
    expect(formatSignedUsd(value)).toBe(signed)
    expect(text(value, USD_OPTIONS)).toBe(formatUsd(value))
    expect(text(value, USD_SIGNED_OPTIONS)).toBe(formatSignedUsd(value))
  })

  it("keeps the sign rules: a gain has a plus, a loss a minus, a zero neither", () => {
    for (const ratio of [0.0126, -0.0126, 0]) expect(text(ratio, PERCENT_SIGNED_OPTIONS)).toBe(formatSignedPercent(ratio))
    expect(formatSignedPercent(0.0126)).toBe("+1.26%")
    expect(formatSignedPercent(-0.0126)).toBe("-1.26%")
    expect(formatSignedPercent(0)).toBe("0.00%")
  })

  it("cuts the sidebar's cents off instead of rounding them up", () => {
    const cut = (n: number) => formatUsd(n).replace(/\.\d+$/, "")
    for (const n of [2700.08, 2700.99, 0.5, 999999.99, 1234567.891]) expect(text(n, USD_WHOLE_OPTIONS)).toBe(cut(n))
    expect(text(2700.99, USD_WHOLE_OPTIONS)).toBe("$2,700")
  })
})

describe("RollingNumber", () => {
  it("shows its first value as the formatter writes it, for gains, losses, zero and large values", () => {
    for (const value of [2700.08, 37.42, -15.19, 0, 1234567.89]) {
      expect(label(value, USD_OPTIONS)).toBe(formatUsd(value))
      expect(label(value, USD_SIGNED_OPTIONS)).toBe(formatSignedUsd(value))
    }
    expect(label(-15.19, USD_SIGNED_OPTIONS)).toBe("-$15.19")
    expect(label(0, USD_SIGNED_OPTIONS)).toBe("$0.00")
  })

  it("reads a missing or non-numeric value as a dash", () => {
    for (const value of [null, Number.NaN]) expect(renderToString(createElement(RollingNumber, { value, format: USD_OPTIONS }))).toBe("<span>—</span>")
  })
})
