import type { AgentAccess, AgentAccessState } from "../../../shared/contract"
import type { AgentAccessStore } from "./access"
import { AgentRelay } from "./relay"

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

/**
 * The agent socket and the owner's choice of how far agents may go (AppModel+AgentAccess.swift). The relay carries the
 * choice into every request, so a change opens it again, and closes what agents had asked for under the old one.
 */
export class AgentAccessController {
  private relay: AgentRelay | null = null
  private access: AgentAccess = "off"
  private problem: string | null = null

  constructor(
    private readonly store: AgentAccessStore,
    private readonly socketPath: string,
    private readonly request: (operation: string, params?: Record<string, unknown>) => Promise<unknown>,
  ) {
    // The saved choice shows from the start, before the engine is up and the socket opens with it.
    try {
      this.access = store.load()
    } catch {
      // `start` reads it again and says why it cannot be read.
    }
  }

  state(): AgentAccessState {
    return { access: this.access, listening: this.relay !== null, problem: this.problem }
  }

  /** Reads the saved choice and listens if agents are allowed. An unreadable choice leaves them off until the owner picks again. */
  async start(): Promise<void> {
    try {
      this.access = this.store.load()
    } catch (error) {
      this.access = "off"
      this.problem = `${message(error)} Agent access stays off until you choose again.`
    }
    await this.open()
  }

  async set(access: AgentAccess): Promise<AgentAccessState> {
    // What agents asked for under the old choice is closed, so a request never outlives the choice that allowed it.
    if (this.relay) await this.request("discard_proposals").catch(() => {})
    this.store.save(access)
    this.access = access
    this.problem = null
    await this.open()
    return this.state()
  }

  async stop(): Promise<void> {
    await this.relay?.stop()
    this.relay = null
  }

  private async open(): Promise<void> {
    await this.stop()
    if (this.access === "off") return
    const relay = new AgentRelay(this.socketPath, this.access, async (line, context) => {
      const reply = (await this.request("control", { line, context })) as { line: string }
      return reply.line
    })
    try {
      await relay.start()
      this.relay = relay
    } catch (error) {
      this.problem = `Agents cannot connect: ${message(error)}`
    }
  }
}
