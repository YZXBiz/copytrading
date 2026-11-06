"use client";

import { useCallback, useEffect, useId, useLayoutEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { ArrowRight01Icon } from "@/components/icons/ArrowRight01Icon";
import { CircleCheckIcon } from "@/components/icons/CircleCheckIcon";
import { AnimatedCounter } from "../../animated-counter/animated-counter";
import { FocusedRequest } from "./focused-request";
import type { CardState } from "./focused-request";
import { ResolvedLog } from "./approval-extras";
import { AskerMark, AutoHeight, LiveTag, Swap, easeOut, fadeOut, glide } from "./approval-parts";
import type { ApprovalDecision, ApprovalRequest, DecisionResult, ResolvedEntry } from "./agent-approvals-data";
import styles from "./agent-approvals.module.css";

export type { ApprovalAgent, ApprovalArgument, ApprovalDecision, ApprovalOutcome, ApprovalRequest, DecisionResult, ResolvedEntry } from "./agent-approvals-data";

export interface AgentApprovalsProps {
  /** The requests waiting for a person, oldest first. A request that is no longer in the list leaves the queue. */
  requests: ApprovalRequest[];
  /** Earlier requests and decisions for the log, newest first. */
  resolved: ResolvedEntry[];
  title?: string;
  /** A quiet line beside the log toggle. */
  hint?: string;
  /**
   * Called when the person chooses Approve or Reject. Resolve with what came of it: a cancelled confirmation puts the
   * request back, a finished one shows its note and leaves the queue. A rejection shows the message with Try again.
   */
  onDecision: (decision: ApprovalDecision) => Promise<DecisionResult>;
  className?: string;
}

const idle: CardState = { phase: "idle" };
const actionable = (state?: CardState) => !state || state.phase === "idle" || state.phase === "error";
const busyPhase = (state?: CardState) => state?.phase === "sending" || state?.phase === "done";

/** Long enough to read the outcome, short enough to keep the queue moving. */
const SETTLE_MS = 900;

/** An approval prompt for agents: one request in focus, the rest queued below, and the log of what was decided. */
export function AgentApprovals({ requests, resolved, title = "Requests", hint, onDecision, className }: AgentApprovalsProps) {
  const reduced = !!useReducedMotion();
  const uid = useId();

  const [queue, setQueue] = useState<ApprovalRequest[]>(requests);
  const [focusId, setFocusId] = useState<string | null>(() => requests[0]?.id ?? null);
  const [cards, setCards] = useState<Record<string, CardState>>({});
  const [entry, setEntry] = useState<"swap" | "advance">("swap");
  const [logOpen, setLogOpen] = useState(false);
  const [message, setMessage] = useState("");

  // The list the app reads is the truth: a request that expired or was decided elsewhere leaves, a new one joins the end.
  // One being decided here stays until its outcome has been read.
  const [seen, setSeen] = useState(requests);
  const [left, setLeft] = useState<string[]>([]);
  if (requests !== seen) {
    setSeen(requests);
    const ids = new Set(requests.map(item => item.id));
    const kept = queue.filter(item => !ids.has(item.id) && busyPhase(cards[item.id]));
    const order = new Map(queue.map((item, index) => [item.id, index]));
    const next = [...requests.filter(item => !left.includes(item.id)), ...kept].sort((a, b) => (order.get(a.id) ?? Infinity) - (order.get(b.id) ?? Infinity));
    setQueue(next);
    if (!next.some(item => item.id === focusId)) setFocusId(next.find(item => actionable(cards[item.id]))?.id ?? next[0]?.id ?? null);
  }

  const latest = useRef({ queue, cards, focusId, onDecision });
  useLayoutEffect(() => { latest.current = { queue, cards, focusId, onDecision }; });
  const timers = useRef(new Set<number>());
  const busy = useRef(new Set<string>());
  useEffect(() => { const pending = timers.current; return () => { pending.forEach(window.clearTimeout); pending.clear(); }; }, []);

  const later = useCallback((run: () => void, ms: number) => {
    const timer = window.setTimeout(() => { timers.current.delete(timer); run(); }, ms);
    timers.current.add(timer);
  }, []);
  const announce = useCallback((text: string) => setMessage(current => current === text ? `${text} ` : text), []);
  const setCard = useCallback((id: string, state: CardState) => setCards(current => ({ ...current, [id]: state })), []);

  /** Moves a decided request out of the queue. If it was in focus, the next waiting request slides up. */
  const settle = useCallback((request: ApprovalRequest) => {
    const { queue: list, cards: states, focusId: focused } = latest.current;
    const index = list.findIndex(item => item.id === request.id);
    if (index < 0) return;
    busy.current.delete(request.id);
    const rest = list.filter(item => item.id !== request.id);
    if (focused === request.id) {
      const order = [...rest.slice(index), ...rest.slice(0, index)];
      const next = order.find(item => actionable(states[item.id]) && !busy.current.has(item.id)) ?? null;
      setEntry("advance");
      setFocusId(next?.id ?? null);
    }
    setQueue(current => current.filter(item => item.id !== request.id));
    setLeft(current => [...current, request.id]);
  }, []);

  const decide = useCallback((id: string, outcome: ApprovalDecision["outcome"]) => {
    const request = latest.current.queue.find(item => item.id === id);
    if (!request || !actionable(latest.current.cards[id]) || busy.current.has(id)) return;
    busy.current.add(id);
    setCard(id, { phase: "sending", outcome });
    latest.current.onDecision({ requestId: id, outcome }).then((result) => {
      if (result.status === "cancelled") {
        busy.current.delete(id);
        setCard(id, idle);
        return;
      }
      setCard(id, { phase: "done", outcome, note: result.note, problem: result.problem });
      announce(`${outcome === "approved" ? "Approved" : "Rejected"}: ${request.title}.${result.note ? ` ${result.note}` : ""}`);
      later(() => settle(request), SETTLE_MS);
    }, (error: unknown) => {
      const text = error instanceof Error && error.message ? error.message : `${request.agent.name} did not get your decision. Nothing ran.`;
      busy.current.delete(id);
      setCard(id, { phase: "error", outcome, message: text });
      announce(`Not sent. ${text}`);
    });
  }, [announce, later, setCard, settle]);

  /** Brings a queued request into focus. The request in focus keeps its place in the queue. */
  const select = useCallback((id: string) => {
    const { focusId: current, cards: states } = latest.current;
    if (id === current || (current && !actionable(states[current])) || !actionable(states[id]) || busy.current.has(id)) return;
    setEntry("swap");
    setFocusId(id);
  }, []);

  const focused = queue.find(item => item.id === focusId) ?? null;
  const rest = queue.filter(item => item.id !== focusId);
  const pending = queue.filter(item => cards[item.id]?.phase !== "done").length;
  const logId = `${uid}-log`;
  const advance = entry === "advance" && !reduced;

  return <section className={[styles.root, className].filter(Boolean).join(" ")} aria-labelledby={`${uid}-title`}>
    <header className={styles.header}>
      <h2 id={`${uid}-title`} className={styles.title}>{title}</h2>
      <span className={styles.count}><AnimatedCounter value={pending} /> waiting</span>
    </header>

    <div className={styles.focusArea}>
      <AutoHeight reduced={reduced} innerClassName={styles.focusStack}>
        <AnimatePresence initial={false} mode="popLayout">
          <motion.div
            key={focused?.id ?? "empty"}
            className={styles.focusSlide}
            initial={{ opacity: 0, y: reduced ? 0 : advance ? 14 : 3 }}
            animate={{ opacity: 1, y: 0, transition: reduced ? { duration: 0 } : { opacity: { duration: .2, ease: easeOut }, y: advance ? glide : { duration: .2, ease: easeOut } } }}
            exit={{ opacity: 0, y: reduced || !advance ? 0 : -6, transition: reduced ? { duration: 0 } : fadeOut }}
          >
            {focused
              ? <FocusedRequest request={focused} state={cards[focused.id] ?? idle} reduced={reduced} onDecide={outcome => decide(focused.id, outcome)} />
              : <div className={styles.empty}>
                <CircleCheckIcon className={styles.emptyIcon} width={24} height={24} aria-hidden="true" />
                <p className={styles.emptyTitle}>Nothing is waiting</p>
                <p className={styles.emptyText}>Agents ask here when a change needs you.</p>
              </div>}
          </motion.div>
        </AnimatePresence>
      </AutoHeight>
    </div>

    {rest.length ? <ul className={styles.queue} aria-label="Waiting requests">
      <AnimatePresence initial={false}>
        {rest.map(request => <motion.li key={request.id} className={styles.queueItem} initial={reduced ? { opacity: 0 } : { opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} exit={reduced ? { opacity: 0, transition: { duration: 0 } } : { opacity: 0, height: 0 }} transition={reduced ? { duration: 0 } : { height: glide, opacity: { duration: .16 } }}>
          <button type="button" className={styles.row} onClick={() => select(request.id)} aria-label={`${request.agent.name}: ${request.title}.${request.live ? " Live account." : ""}`}>
            <span className={styles.rowMarks} aria-hidden="true"><AskerMark className={styles.rowMark} /></span>
            <span className={styles.rowText}><span className={styles.rowSummary}>{request.title}</span><span className={styles.rowAgent}>{request.agent.name}</span></span>
            <Swap id={request.live ? "live" : "plain"} reduced={reduced} className={styles.rowStatus}>{request.live ? <LiveTag /> : null}</Swap>
          </button>
        </motion.li>)}
      </AnimatePresence>
    </ul> : null}

    <div className={styles.footer}>
      <button type="button" className={styles.logToggle} aria-expanded={logOpen} aria-controls={logId} onClick={() => setLogOpen(open => !open)}>
        <ArrowRight01Icon className={styles.chevron} width={16} height={16} aria-hidden="true" />
        Recent requests<span className={styles.dot} aria-hidden="true">·</span><AnimatedCounter value={resolved.length} />
      </button>
      {hint ? <span className={styles.hints}>{hint}</span> : null}
    </div>
    <AnimatePresence initial={false}>
      {logOpen && <motion.div key="log" className={styles.logWrap} initial={reduced ? { opacity: 0 } : { opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} exit={reduced ? { opacity: 0, transition: { duration: 0 } } : { opacity: 0, height: 0 }} transition={reduced ? { duration: 0 } : { height: glide, opacity: { duration: .16 } }}>
        <ResolvedLog id={logId} entries={resolved} reduced={reduced} />
      </motion.div>}
    </AnimatePresence>

    <p className={styles.srOnly} role="status" aria-live="polite">{message}</p>
  </section>;
}

export default AgentApprovals;
