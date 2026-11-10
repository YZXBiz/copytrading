import type { AgentProposal, SourceActivity, TradingStatus } from "../../../shared/contract"
import { openCall } from "@/features/account/waiting"
import { CopyingMemory, FillWatch, StoppedWatch, copyingStoppedDue } from "./watch"
import { type Note, accountStoppedNote, agentRequestNote, copyingPausedNote, fillNotes, waitingCallNote } from "./words"

const POLL_MS = 2_000
const ACTIVITY_LIMIT = 50

export interface MonitorDeps {
  request: (operation: string, params?: Record<string, unknown>) => Promise<unknown>
  notify: (note: Note) => void
  /** Whether orders sent and filled are announced; the owner's switch. Accounts stopping and copying paused always are. */
  fillsOn: () => boolean
  /** A guru's name from the saved setup. */
  guruName: (id: string) => string | null
  /** Whether a setup is saved to start. */
  hasSetup: () => boolean
  memory: CopyingMemory
  now?: () => Date
}

type Body = Record<string, unknown>

/**
 * Watches the running engine and tells the owner, with a macOS notification, what the SwiftUI app tells them: orders
 * sent and filled, a guru's call waiting for the owner, an agent's request waiting, an account that stopped on its own, and copying paused after a quit.
 * It reads only while the engine answers; a read that fails is skipped and the next one tries again.
 */
export class AlertMonitor {
  private readonly fills: FillWatch
  private readonly stopped = new StoppedWatch()
  private readonly announcedRequests = new Set<string>()
  /** Calls already waiting; null until the first read, which only learns them so a relaunch announces nothing old. */
  private waitingSeen: Set<string> | null = null
  private copyingStoppedAt: Date | null = null
  /** Copying was on when the app last stopped, and nothing has run since. Ends when copying runs again. */
  private stoppedWithQuit: boolean
  private timer: NodeJS.Timeout | null = null
  private reading = false

  constructor(private readonly deps: MonitorDeps) {
    this.fills = new FillWatch(deps.now?.())
    this.stoppedWithQuit = deps.memory.wasOn
  }

  start(): void {
    this.timer ??= setInterval(() => void this.tick(), POLL_MS)
  }

  /** Stops watching; quitting and restoring do this first so a status taken on the way down is never remembered. */
  stop(): void {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
  }

  async tick(): Promise<void> {
    if (this.reading) return
    this.reading = true
    try {
      const status = ((await this.deps.request("get_trading_status")) as Body).trading as TradingStatus
      this.trackStatus(status)
      const activity = ((await this.deps.request("get_source_activity", { limit: ACTIVITY_LIMIT })) as Body).activity as { items: SourceActivity[] }
      const news = this.fills.news(activity.items)
      if (this.deps.fillsOn()) fillNotes(news, this.deps.guruName).forEach(this.deps.notify)
      this.announceWaiting(activity.items)
      const proposals = ((await this.deps.request("list_proposals")) as Body).proposals as AgentProposal[]
      for (const proposal of proposals) {
        if (proposal.state !== "pending" || this.announcedRequests.has(proposal.proposal_id)) continue
        this.announcedRequests.add(proposal.proposal_id)
        const note = agentRequestNote(proposal)
        if (note) this.deps.notify(note)
      }
    } catch {
      // The engine is down or restarting: nothing to say, and nothing is forgotten.
    } finally {
      this.reading = false
    }
  }

  private announceWaiting(posts: SourceActivity[]): void {
    const now = (this.deps.now ?? (() => new Date()))()
    const primed = this.waitingSeen !== null
    const seen = (this.waitingSeen ??= new Set())
    for (const post of posts) {
      const call = openCall(post, { skipped: false, now })
      const key = post.source_id ?? String(post.sequence)
      if (!call || seen.has(key)) continue
      seen.add(key)
      if (primed) this.deps.notify(waitingCallNote(call, this.deps.guruName))
    }
  }

  private trackStatus(status: TradingStatus): void {
    const now = (this.deps.now ?? (() => new Date()))()
    for (const account of this.stopped.stopped(status)) this.deps.notify(accountStoppedNote(account, String(now.getTime())))
    if (this.stoppedWithQuit && this.deps.hasSetup() && status.state === "paused" && copyingStoppedDue(this.copyingStoppedAt, now)) {
      this.copyingStoppedAt = now
      this.deps.notify(copyingPausedNote())
    }
    if (this.stoppedWithQuit && ["running", "degraded", "starting"].includes(status.state)) this.stoppedWithQuit = false
    this.deps.memory.observe(status.state)
  }
}
