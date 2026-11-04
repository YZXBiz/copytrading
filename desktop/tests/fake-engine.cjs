// A stand-in engine: speaks the JSON-lines pipe on stdio. The mode picks how it misbehaves.
const mode = process.argv[2]
const held = []
let buffer = ""
process.stdin.setEncoding("utf8")
process.stdin.on("data", (chunk) => {
  buffer += chunk
  for (let end = buffer.indexOf("\n"); end >= 0; end = buffer.indexOf("\n")) {
    const request = JSON.parse(buffer.slice(0, end))
    buffer = buffer.slice(end + 1)
    const reply = (body) => process.stdout.write(JSON.stringify({ version: 1, request_id: request.request_id, ...body }) + "\n")
    if (mode === "silent") continue
    if (mode === "exit-on-request") process.exit(3)
    if (mode === "error") reply({ error: { code: "not_found" } })
    if (mode === "echo-reversed") {
      held.push(() => reply({ ok: { type: "echo", operation: request.operation } }))
      if (held.length === 2) held.reverse().forEach((send) => send())
    }
  }
})
