import { describe, expect, it } from "vitest"
import { type Event, apply, ask, empty, fail, isRefusal, uniqueLinks } from "./conversation"

const event = (over: Partial<Event>): Event => ({ seq: 1, kind: "text", text: null, link: null, proposal_id: null, code: null, ...over })
const answering = () => ask(empty, "Why was the last post skipped?", "t1")
const last = (c: ReturnType<typeof answering>) => c.messages.at(-1)!

describe("ask", () => {
  it("adds the question and an empty answer to fill", () => {
    const c = answering()
    expect(c.messages.map((m) => [m.author, m.text])).toEqual([["owner", "Why was the last post skipped?"], ["assistant", ""]])
  })
})

describe("apply", () => {
  it("appends text to the answer", () => {
    const c = [event({ text: "It was " }), event({ text: "skipped." })].reduce(apply, answering())
    expect(last(c).text).toBe("It was skipped.")
  })

  it("starts a new paragraph for the words after a step line, but not before the first words", () => {
    const first = [event({ kind: "step", text: "Read zhap's history" }), event({ text: "Here." })].reduce(apply, answering())
    expect(last(first).text).toBe("Here.")
    expect(last(first).steps).toEqual(["Read zhap's history"])
    const second = [event({ text: "One." }), event({ kind: "step", text: "Checked" }), event({ text: "Two." })].reduce(apply, answering())
    expect(last(second).text).toBe("One.\n\nTwo.")
  })

  it("collects links and proposals, and a failure", () => {
    const c = [
      event({ kind: "link", link: { kind: "account", id: "a1", title: "a1" } }),
      event({ kind: "proposal", proposal_id: "p-0123456789ab" }),
      event({ kind: "error", text: "The model did not answer." }),
    ].reduce(apply, answering())
    expect(last(c)).toMatchObject({ links: [{ kind: "account", id: "a1" }], proposalIds: ["p-0123456789ab"], errorText: "The model did not answer." })
  })

  it("gives an error with no words a plain one, and ignores empty text, `done`, and an event with nothing in it", () => {
    const c = [event({ kind: "error" }), event({ text: "" }), event({ kind: "done" }), event({ kind: "link" }), event({ kind: "proposal" })].reduce(apply, answering())
    expect(last(c)).toMatchObject({ text: "", errorText: "The assistant could not answer.", links: [], proposalIds: [] })
  })

  it("never writes into the owner's question", () => {
    expect(apply(empty, event({ text: "x" }))).toEqual(empty)
    const asked = answering()
    const onlyQuestion = { ...asked, messages: asked.messages.slice(0, 1) }
    expect(apply(onlyQuestion, event({ text: "x" })).messages[0]!.text).toBe("Why was the last post skipped?")
  })
})

describe("helpers", () => {
  it("fails the answer being written", () => expect(last(fail(answering(), "No model."))?.errorText).toBe("No model."))
  it("lists each place once", () => {
    const link = { kind: "guru", id: "g", title: "G" }
    expect(uniqueLinks([link, { ...link, title: "again" }, { kind: "account", id: "g", title: "g" }])).toHaveLength(2)
  })
  it("knows a refused step", () => {
    expect(isRefusal("Couldn't read a1's history")).toBe(true)
    expect(isRefusal("Read a1's history")).toBe(false)
  })
})
