import { randomUUID } from "node:crypto"
import type { Readable, Writable } from "node:stream"

/** Mirrors EngineClient.swift: one request line out, one matching response line back. */
export const REQUEST_TIMEOUT_MS = 10_000
const MAX_REQUEST_BYTES = 1_048_576

export class EngineError extends Error {
  constructor(
    readonly code: "timed_out" | "disconnected" | "too_large" | "malformed" | "engine",
    message: string,
  ) {
    super(message)
  }
}

interface Pending {
  resolve: (value: unknown) => void
  reject: (error: Error) => void
  timer: NodeJS.Timeout
}

export class EngineBridge {
  private readonly pending = new Map<string, Pending>()
  private buffer = ""
  private closed = false

  constructor(
    private readonly input: Writable,
    output: Readable,
    private readonly timeoutMs = REQUEST_TIMEOUT_MS,
  ) {
    output.setEncoding("utf8")
    output.on("data", (chunk: string) => this.read(chunk))
    input.on("error", () => this.failAll(new EngineError("disconnected", "The engine stopped.")))
  }

  /** Sends one operation and resolves with the `ok` payload of its reply. */
  request(operation: string, params: Record<string, unknown> = {}): Promise<unknown> {
    if (this.closed) return Promise.reject(new EngineError("disconnected", "The engine stopped."))
    const requestId = randomUUID()
    const line = JSON.stringify({ version: 1, request_id: requestId, operation, ...params })
    if (Buffer.byteLength(line) > MAX_REQUEST_BYTES) {
      return Promise.reject(new EngineError("too_large", "The request is too large."))
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(requestId)
        reject(new EngineError("timed_out", "The engine did not answer in time."))
      }, this.timeoutMs)
      this.pending.set(requestId, { resolve, reject, timer })
      this.input.write(`${line}\n`)
    })
  }

  private read(chunk: string): void {
    this.buffer += chunk
    for (let end = this.buffer.indexOf("\n"); end >= 0; end = this.buffer.indexOf("\n")) {
      const line = this.buffer.slice(0, end)
      this.buffer = this.buffer.slice(end + 1)
      if (line) this.settle(line)
    }
  }

  private settle(line: string): void {
    let reply: { request_id?: unknown; ok?: unknown; error?: { code?: unknown; message?: unknown } }
    try {
      reply = JSON.parse(line)
    } catch {
      // A line that is not JSON names no request; the ones waiting time out on their own.
      return
    }
    const entry = typeof reply.request_id === "string" ? this.pending.get(reply.request_id) : undefined
    if (!entry) return
    this.pending.delete(reply.request_id as string)
    clearTimeout(entry.timer)
    if (reply.ok !== undefined) entry.resolve(reply.ok)
    else if (reply.error) {
      entry.reject(new EngineError("engine", String(reply.error.message ?? reply.error.code ?? "error")))
    } else entry.reject(new EngineError("malformed", "The engine sent a reply the app cannot read."))
  }

  /** Called by whoever owns the process when it ends (its stderr tells why): every waiting request fails now, none hangs to its deadline. */
  failAll(error: Error): void {
    this.closed = true
    for (const entry of this.pending.values()) {
      clearTimeout(entry.timer)
      entry.reject(error)
    }
    this.pending.clear()
  }
}
