import { createElement } from "react"
import { renderToStaticMarkup } from "react-dom/server"
import { describe, expect, it } from "vitest"
import { Markdown } from "./Markdown"
import { parseLine, parseMarkdown } from "./light-markdown"

const plain = (line: string) => parseLine(line).map((r) => r.text).join("")

describe("parseLine", () => {
  it("makes bullets and bold headings", () => {
    expect(parseLine("- item")).toEqual([{ text: "• " }, { text: "item" }])
    expect(parseLine("  * item two")[0]).toEqual({ text: "• " })
    expect(parseLine("## Heading")).toEqual([{ text: "Heading", bold: true }])
    expect(parseLine("#")).toEqual([{ text: "#" }])
    expect(parseLine("# ")).toEqual([])
  })

  it("keeps a ticker tag as written", () => {
    expect(parseLine("#NVDA is up")).toEqual([{ text: "#NVDA is up" }])
  })

  it("reads bold, italic and code inline, and leaves snake_case alone", () => {
    expect(parseLine("a **b** *c* _d_ `e`")).toEqual([
      { text: "a " }, { text: "b", bold: true }, { text: " " }, { text: "c", italic: true }, { text: " " }, { text: "d", italic: true }, { text: " " }, { text: "e", code: true },
    ])
    expect(plain("price_too_high stays")).toBe("price_too_high stays")
  })

  it("keeps only the text of a link, so nothing is a live link", () => {
    expect(parseLine("see [the post](http://evil.example/x) now")).toEqual([{ text: "see " }, { text: "the post" }, { text: " now" }])
    expect(plain("[x](javascript:alert(1))")).toBe("x")
  })
})

describe("Markdown", () => {
  const html = (text: string) => renderToStaticMarkup(createElement(Markdown, { text }))

  it("escapes raw HTML instead of rendering it", () => {
    const out = html('<script>alert(1)</script> <img src=x onerror=alert(1)> **ok**')
    expect(out).not.toContain("<script")
    expect(out).not.toContain("<img")
    expect(out).toContain("&lt;script&gt;")
    expect(out).toContain("<strong>ok</strong>")
  })

  it("renders no anchor for a link", () => {
    expect(html("[x](http://evil.example)")).not.toContain("<a")
    expect(html("[x](http://evil.example)")).not.toContain("evil.example")
  })

  it("keeps lines apart", () => {
    expect(parseMarkdown("a\nb")).toHaveLength(2)
    expect(html("a\n- b")).toContain("a\n•")
  })
})
