"use client";

import { useId } from "react";
import type { ReactNode } from "react";
import { AnimatePresence, motion, useIsPresent, useReducedMotion } from "motion/react";
import { AlertCircleIcon } from "@/components/icons/AlertCircleIcon";
import { Tick02Icon } from "@/components/icons/Tick02Icon";
import { Button } from "../button/button";
import { TextShimmer } from "../text-shimmer/text-shimmer";
import styles from "./connector-setup.module.css";

export type ConnectorStatus = "available" | "connecting" | "connected" | "error";

/** One service a person connects, with where its check stands. The caller owns the check and passes its state in. */
export interface Connector {
  id: string;
  name: string;
  /** One line under the name while nothing has happened yet: what connecting does. */
  description: string;
  /** A 20px mark, drawn in the text color. */
  mark: ReactNode;
  status: ConnectorStatus;
  /** The step in flight, while connecting: "Checking your token with Discord". */
  step?: string;
  /** What the check found, once connected. */
  result?: string;
  /** Why it did not connect, in words, with what to do about it. */
  problem?: string;
  /** What an idle control offers: "Connect" the first time, "Check again" after a result. */
  connectLabel?: string;
}

export interface ConnectorSetupProps {
  connectors: Connector[];
  /** Starts the check. Every Connect checks the service before anything is saved. */
  onConnect: (connector: Connector) => void;
  title?: ReactNode;
  description?: ReactNode;
  /** A line under the list, such as what the check will not do. */
  footer?: ReactNode;
  className?: string;
}

const cx = (...names: (string | false | null | undefined)[]) => names.filter(Boolean).join(" ");
const ease = [0.22, 1, 0.36, 1] as const;

/** A single crossfade between keyed contents stacked in one grid cell: the old one leaves in 100ms, the new one rises 2px in 160ms. */
function Swap({ swapKey, children, className, reduced }: { swapKey: string; children: ReactNode; className?: string; reduced: boolean }) {
  return <span className={cx(styles.swap, className)}>
    <AnimatePresence initial={false}>
      <SwapItem key={swapKey} reduced={reduced}>{children}</SwapItem>
    </AnimatePresence>
  </span>;
}

/** The leaving copy stops taking clicks and drops out of the accessibility tree the moment it starts to fade. */
function SwapItem({ children, reduced }: { children: ReactNode; reduced: boolean }) {
  const present = useIsPresent();
  return <motion.span className={styles.swapItem} data-leaving={present ? undefined : ""} aria-hidden={present ? undefined : true}
    initial={reduced ? { opacity: 0 } : { opacity: 0, y: 2 }}
    animate={{ opacity: 1, y: 0, transition: { duration: reduced ? 0 : .16, ease } }}
    exit={{ opacity: 0, y: 0, transition: { duration: reduced ? 0 : .1, ease } }}>{children}</motion.span>;
}

/**
 * A "Connect" card: each service shows its mark, what connecting does, and one control. While the check runs the line names
 * the step and a hairline fills under it; it ends as a check mark with what was found, or the reason it failed with a retry.
 */
export function ConnectorSetup({ connectors, onConnect, title = "Connect", description, footer, className }: ConnectorSetupProps) {
  const reduced = Boolean(useReducedMotion());
  const uid = useId();

  return <div className={cx(styles.root, className)} role="group" aria-labelledby={`${uid}-title`}>
    <div className={styles.header}>
      <div className={styles.headText}>
        <h3 id={`${uid}-title`} className={styles.title}>{title}</h3>
        {description ? <p className={styles.description}>{description}</p> : null}
      </div>
    </div>

    <ul className={styles.list} aria-label="Connections">
      {connectors.map(connector => {
        const { status } = connector;
        let lineKey: string = status;
        let line: ReactNode = connector.description;
        if (status === "connecting") {
          lineKey = `connecting:${connector.step ?? ""}`;
          line = <TextShimmer>{connector.step ?? `Checking ${connector.name}`}</TextShimmer>;
        } else if (status === "error") {
          lineKey = `error:${connector.problem ?? ""}`;
          line = <span className={styles.errorLine}><AlertCircleIcon width={16} height={16} aria-hidden="true" /><span>{connector.problem ?? `Could not connect ${connector.name}`}</span></span>;
        } else if (status === "connected") {
          lineKey = `connected:${connector.result ?? ""}`;
          line = connector.result ?? connector.description;
        }

        const label = connector.connectLabel ?? "Connect";
        const action = status === "available"
          ? <Button size="sm" variant="secondary" className={cx(styles.action, styles.connect)} onClick={() => onConnect(connector)} aria-label={`${label} ${connector.name}`}>{label}</Button>
          : status === "connecting"
          ? <Button size="sm" variant="ghost" className={styles.action} loading disabled aria-label={`Checking ${connector.name}`}>Checking</Button>
          : status === "error"
          ? <Button size="sm" variant="secondary" className={cx(styles.action, styles.connect)} onClick={() => onConnect(connector)} aria-label={`Try ${connector.name} again`}>Try again</Button>
          : <span className={styles.connectedGroup}>
              <span className={styles.connectedMark}><Tick02Icon className={styles.ok} width={16} height={16} aria-hidden="true" /><span>Connected</span></span>
              <Button size="sm" variant="ghost" className={styles.action} onClick={() => onConnect(connector)} aria-label={`Check ${connector.name} again`}>Check again</Button>
            </span>;

        return <li key={connector.id} className={styles.row} data-status={status} data-active={status === "connecting" || undefined}>
          <div className={styles.rowMain}>
            <span className={styles.mark}>{connector.mark}</span>
            <span className={styles.text}>
              <span className={styles.name}>{connector.name}</span>
              <Swap swapKey={lineKey} reduced={reduced} className={cx(styles.line, status === "connecting" && styles.lineLive, status === "error" && styles.lineError)}>
                {typeof line === "string" ? <span className={styles.ellipsis}>{line}</span> : line}
              </Swap>
            </span>
            <span className={styles.actionSlot}><Swap swapKey={status} reduced={reduced} className={styles.actionSwap}>{action}</Swap></span>
          </div>

          <AnimatePresence initial={false}>
            {status === "connecting" ? <motion.span key="progress" className={styles.track} aria-hidden="true"
              initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: reduced ? 0 : .2, delay: reduced ? 0 : .08 } }} transition={{ duration: reduced ? 0 : .16 }}>
              <span className={styles.fill} />
            </motion.span> : null}
          </AnimatePresence>
        </li>;
      })}
    </ul>

    {footer ? <div className={styles.footer}>{footer}</div> : null}
    <span className={styles.srOnly} role="status" aria-live="polite">{connectors.map(connector => connector.status === "connected" ? `${connector.name} connected.` : connector.status === "error" ? `${connector.name} did not connect. ${connector.problem ?? ""}` : "").join(" ")}</span>
  </div>;
}

export default ConnectorSetup;
