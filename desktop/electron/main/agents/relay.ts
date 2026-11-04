import { type Stats, chmodSync, lstatSync, mkdirSync, unlinkSync } from "node:fs"
import { type Server, type Socket, createServer } from "node:net"
import { dirname } from "node:path"
import type { AgentAccess } from "../../../shared/contract"

/** AgentRelay.swift + AgentControlSocket.swift: one JSON line in, one JSON line out, on a socket only this user can reach. */
export const MAX_LINE_BYTES = 64 * 1024
const MAX_CONNECTIONS = 4
const IO_TIMEOUT_MS = 30_000
// sockaddr_un.sun_path on macOS holds 104 bytes, the terminator included.
const MAX_PATH_BYTES = 103

/** What only the app knows about a request; the engine decides with it (AgentRequestContext). */
export interface AgentContext {
  access_level: Exclude<AgentAccess, "off">
  unlocked: true
  caller_pid: null
  caller_path: null
  app_actions: true
  setup_changes: false
}

export type Send = (line: string, context: AgentContext) => Promise<string>

/** The line a caller gets when the engine never saw its request. */
export const errorLine = (code: string, message: string): string =>
  JSON.stringify({ schema_version: 1, request_id: "", ok: null, error: { code, message } })

const BUSY = errorLine("busy", "Too many requests; wait a few seconds.")
const INVALID = errorLine("invalid_request", "The request is not valid.")
const TOO_LARGE = errorLine("invalid_request", "The request is too large: CopyTrading takes at most 64 KB in one request.")
const SETUP = errorLine("unavailable", "This CopyTrading cannot change its setup from here.")
const ENGINE_DOWN = errorLine("unavailable", "The CopyTrading engine is not available.")

// The operations the app answers itself because their lines carry keys (AgentSetupOperation).
const SETUP_OPERATIONS = new Set(["get_setup", "edit_setup_discord", "edit_setup_model", "edit_setup_account", "edit_setup_guru", "edit_setup_alerts", "import_setup", "apply_setup", "discard_setup"])

function setupOperation(line: string): boolean {
  try {
    const { operation } = JSON.parse(line) as { operation?: unknown }
    return typeof operation === "string" && SETUP_OPERATIONS.has(operation)
  } catch {
    return false
  }
}

const mine = (path: string, isRight: (stat: Stats) => boolean) => {
  try {
    const stat = lstatSync(path)
    return isRight(stat) && stat.uid === process.getuid!()
  } catch {
    return false
  }
}

/**
 * Answers without asking the engine. What the caller still sends is read and dropped until it hangs up (or the timeout),
 * so it gets the answer rather than a reset: closing a socket with unread data resets it and loses the answer.
 */
function refuse(socket: Socket, text: string): void {
  socket.setTimeout(IO_TIMEOUT_MS, () => socket.destroy())
  socket.on("error", () => socket.destroy())
  socket.on("data", () => {})
  socket.write(`${text}\n`)
  if (socket.readableEnded) socket.end()
  else socket.on("end", () => socket.end())
}

export class RelayError extends Error {}

export class AgentRelay {
  private server: Server | null = null
  private active = 0
  private readonly sockets = new Set<Socket>()

  constructor(
    private readonly path: string,
    private readonly access: Exclude<AgentAccess, "off">,
    private readonly send: Send,
  ) {}

  /** Listens on `<state root>/control/cli.sock` (folder 0700, socket 0600); a stale socket of this user's is replaced, anything else refuses. */
  async start(): Promise<void> {
    if (Buffer.byteLength(this.path) > MAX_PATH_BYTES) throw new RelayError("The agent control socket path is too long for a Unix socket.")
    const folder = dirname(this.path)
    mkdirSync(folder, { recursive: true, mode: 0o700 })
    if (!mine(folder, (s) => s.isDirectory())) throw new RelayError("The agent control folder is not a private folder owned by this user.")
    chmodSync(folder, 0o700)
    try {
      lstatSync(this.path)
      if (!mine(this.path, (s) => s.isSocket())) throw new RelayError("The agent control folder is not a private folder owned by this user.")
      unlinkSync(this.path)
    } catch (error) {
      if (error instanceof RelayError) throw error
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw new RelayError("The agent control socket could not be opened.")
    }
    // Half-open: a caller may close its sending side after the line and still wait for the answer.
    const server = createServer({ allowHalfOpen: true }, (socket) => this.accept(socket))
    await new Promise<void>((resolve, reject) => {
      server.once("error", () => reject(new RelayError("The agent control socket could not be opened.")))
      server.listen(this.path, () => {
        chmodSync(this.path, 0o600)
        resolve()
      })
    })
    this.server = server
  }

  /** Stops listening, ends open connections, and removes the socket, so a stopped app is never mistaken for a running one. */
  async stop(): Promise<void> {
    const server = this.server
    this.server = null
    if (!server) return
    for (const socket of this.sockets) socket.destroy()
    await new Promise<void>((resolve) => server.close(() => resolve()))
    try {
      unlinkSync(this.path)
    } catch {
      // already gone
    }
  }

  private accept(socket: Socket): void {
    if (this.active >= MAX_CONNECTIONS) return refuse(socket, BUSY)
    this.active += 1
    this.sockets.add(socket)
    socket.setTimeout(IO_TIMEOUT_MS, () => socket.destroy())
    socket.on("error", () => socket.destroy())
    socket.on("close", () => {
      this.active -= 1
      this.sockets.delete(socket)
    })
    let chunks: Buffer[] = []
    let size = 0
    let answered = false
    const finish = (text: string) => {
      answered = true
      refuse(socket, text)
    }
    socket.on("data", (chunk: Buffer) => {
      if (answered) return
      const newline = chunk.indexOf(10)
      const kept = newline >= 0 ? chunk.subarray(0, newline) : chunk
      size += kept.length
      if (size > MAX_LINE_BYTES) {
        chunks = []
        return finish(TOO_LARGE)
      }
      chunks.push(kept)
      if (newline < 0) return
      answered = true
      void this.answer(Buffer.concat(chunks)).then((text) => socket.end(`${text}\n`))
    })
    socket.on("end", () => {
      if (!answered) finish(INVALID)
    })
  }

  private async answer(bytes: Buffer): Promise<string> {
    let line: string
    try {
      line = new TextDecoder("utf-8", { fatal: true }).decode(bytes)
    } catch {
      return INVALID
    }
    if (setupOperation(line)) return SETUP
    const context: AgentContext = { access_level: this.access, unlocked: true, caller_pid: null, caller_path: null, app_actions: true, setup_changes: false }
    try {
      return await this.send(line, context)
    } catch {
      return ENGINE_DOWN
    }
  }
}
