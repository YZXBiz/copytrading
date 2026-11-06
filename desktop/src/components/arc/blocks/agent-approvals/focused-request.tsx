"use client";

import { useId } from "react";
import { AnimatePresence, motion } from "motion/react";
import { AlertCircleIcon } from "@/components/icons/AlertCircleIcon";
import { ArrowRight01Icon } from "@/components/icons/ArrowRight01Icon";
import { Cancel01Icon } from "@/components/icons/Cancel01Icon";
import { RotateClockwiseIcon } from "@/components/icons/RotateClockwiseIcon";
import { Tick02Icon } from "@/components/icons/Tick02Icon";
import { Button } from "../../button/button";
import { TextShimmer } from "../../text-shimmer/text-shimmer";
import { AskerMark, AutoHeight, LiveTag, fadeIn, fadeOut } from "./approval-parts";
import type { ApprovalArgument, ApprovalOutcome, ApprovalRequest } from "./agent-approvals-data";
import styles from "./agent-approvals.module.css";

export type CardPhase = "idle" | "sending" | "done" | "error";
export interface CardState {
  phase: CardPhase;
  outcome?: ApprovalOutcome;
  /** What came of it, once it is done. */
  note?: string;
  /** The decision went through but the request did not complete. */
  problem?: boolean;
  message?: string;
}

export interface FocusedRequestProps {
  request: ApprovalRequest;
  state: CardState;
  reduced: boolean;
  onDecide: (outcome: ApprovalOutcome) => void;
}

/** The request on top of the queue, laid out like an inline permission prompt. */
export function FocusedRequest({ request, state, reduced, onDecide }: FocusedRequestProps) {
  const titleId = useId();
  const { agent } = request;

  return <div className={styles.focus} role="group" aria-labelledby={titleId}>
    <div className={styles.focusMeta}>
      <span className={styles.agent}>
        <AskerMark className={styles.agentMark} />
        <span className={styles.agentName}>{agent.name}</span>
        <time className={styles.agentTime} dateTime={request.requestedAt}>{request.when}</time>
      </span>
      {request.live ? <LiveTag long /> : null}
    </div>

    <h3 id={titleId} className={styles.focusTitle}>
      <span className={styles.titleText}>{request.title}<span className={styles.srOnly}>, asked by {agent.name}</span></span>
    </h3>
    {request.reason ? <p className={styles.reason}>{request.reason}</p> : null}

    {request.args.length ? <dl className={styles.args} aria-label="What changes">
      {request.args.map(arg => <ArgRow key={arg.key} arg={arg} />)}
    </dl> : null}

    <AutoHeight reduced={reduced} className={styles.decisionSlot}>
      <div className={styles.decisionStack}>
        <AnimatePresence initial={false} mode="popLayout">
          <motion.div key={decisionKey(state)} className={styles.decision} initial={{ opacity: 0, y: reduced ? 0 : 2 }} animate={{ opacity: 1, y: 0, transition: reduced ? { duration: 0 } : fadeIn }} exit={{ opacity: 0, transition: reduced ? { duration: 0 } : fadeOut }}>
            <Decision request={request} state={state} reduced={reduced} onDecide={onDecide} />
          </motion.div>
        </AnimatePresence>
      </div>
    </AutoHeight>
  </div>;
}

const decisionKey = (state: CardState) => state.phase === "idle" ? "idle" : `${state.phase}-${state.outcome ?? ""}`;

function Decision({ request, state, reduced, onDecide }: Pick<FocusedRequestProps, "request" | "state" | "reduced" | "onDecide">) {
  switch (state.phase) {
    case "sending": return <p className={styles.line}>
      <TextShimmer active={!reduced}>{state.outcome === "rejected" ? "Rejecting the request" : "Waiting for your confirmation"}</TextShimmer>
    </p>;
    case "done":
      if (state.outcome === "rejected") return <p className={styles.line}><Cancel01Icon className={styles.lineIcon} data-tone="muted" width={16} height={16} aria-hidden="true" /><span>Rejected<span className={styles.lineNote}>{state.note ?? `${request.agent.name} will not run it`}</span></span></p>;
      return <p className={styles.line}>{state.problem
        ? <AlertCircleIcon className={styles.lineIcon} data-tone="warning" width={16} height={16} aria-hidden="true" />
        : <Tick02Icon className={styles.lineIcon} data-tone="accent" width={16} height={16} aria-hidden="true" />}<span>Approved{state.note ? <span className={styles.lineNote}>{state.note}</span> : null}</span></p>;
    case "error": return <div className={styles.errorRow} role="alert">
      <p className={styles.errorText}><AlertCircleIcon className={styles.lineIcon} data-tone="danger" width={16} height={16} aria-hidden="true" />{state.message}</p>
      <span className={styles.actionsEnd}>
        {state.outcome === "approved" && !request.readOnly ? <Button variant="ghost" size="sm" onClick={() => onDecide("rejected")}>Reject</Button> : null}
        <Button variant="secondary" size="sm" onClick={() => onDecide(state.outcome ?? "rejected")}><RotateClockwiseIcon width={16} height={16} aria-hidden="true" />Try again</Button>
      </span>
    </div>;
    default: return <div className={styles.actions}>
      <Button variant={request.readOnly ? "secondary" : "ghost"} size="sm" className={request.readOnly ? undefined : styles.deny} onClick={() => onDecide("rejected")}>Reject</Button>
      {request.readOnly ? null : <span className={styles.actionsEnd}>
        <Button size="sm" className={styles.approve} onClick={() => onDecide("approved")}>Approve</Button>
      </span>}
    </div>;
  }
}

/** One line of what changes: its name, and the value, or "before → value". */
function ArgRow({ arg }: { arg: ApprovalArgument }) {
  return <div className={styles.argRow}>
    <dt className={styles.argKey}>{arg.label}</dt>
    <dd className={styles.argCell}>
      <span className={styles.argValue}>
        {arg.before !== undefined ? <>
          <span className={styles.before}>{arg.before}</span>
          <span className={styles.srOnly}> to </span>
          <ArrowRight01Icon className={styles.beforeArrow} width={16} height={16} aria-hidden="true" />
        </> : null}
        <span>{arg.value}</span>
      </span>
    </dd>
  </div>;
}
