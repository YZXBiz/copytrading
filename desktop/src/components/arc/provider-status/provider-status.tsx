"use client";

import { useId } from "react";
import type { ReactNode } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { AlertCircleIcon } from "@/components/icons/AlertCircleIcon";
import { CircleCheckIcon } from "@/components/icons/CircleCheckIcon";
import { CircleDashedIcon } from "@/components/icons/CircleDashedIcon";
import { LoaderCircleIcon } from "@/components/icons/LoaderCircleIcon";
import { TriangleAlertIcon } from "@/components/icons/TriangleAlertIcon";
import { motionTokens } from "../lib/motion-tokens";
import { TextShimmer } from "../text-shimmer/text-shimmer";
import styles from "./provider-status.module.css";

/** Where a connection stands: working, being checked, needs a look, failed, or simply not checked yet. */
export type ProviderHealth = "operational" | "checking" | "degraded" | "outage" | "idle";

export interface ProviderStatusItem {
  id: string;
  name: string;
  /** A 16px mark, drawn in the text color. */
  mark?: ReactNode;
  /** One short line under the name. */
  detail?: string;
  /** Why it is not working, in words. Always visible, never behind a toggle. */
  problem?: string | null;
  status: ProviderHealth;
  /** The status in words: "Connected", "Needs an API key". */
  statusLabel: string;
  /** What can be done with it: Connect, Edit. */
  actions?: ReactNode;
}

export interface ProviderStatusProps {
  providers: ProviderStatusItem[];
  /** The card's title. */
  title: string;
  /** One quiet line under the title. */
  description?: string;
  /** A control at the title's end, such as Add account. */
  action?: ReactNode;
  /** Shown in place of the rows when there are none. */
  empty?: ReactNode;
  className?: string;
}

const ease = [...motionTokens.ease.standard] as [number, number, number, number];
const icons = { operational: CircleCheckIcon, degraded: TriangleAlertIcon, outage: AlertCircleIcon, idle: CircleDashedIcon, checking: LoaderCircleIcon } as const;

/** Icon and label for a health state. Both crossfade together when the state changes. */
function HealthLabel({ health, label, reduced }: { health: ProviderHealth; label: string; reduced: boolean }) {
  const Icon = icons[health];
  return (
    <span className={styles.swap}>
      <AnimatePresence initial={false}>
        <motion.span key={`${health}:${label}`} className={styles.health} data-health={health}
          initial={{ opacity: 0, y: reduced ? 0 : 2 }}
          animate={{ opacity: 1, y: 0, transition: { duration: reduced ? 0 : .16, ease } }}
          exit={{ opacity: 0, transition: { duration: reduced ? 0 : .1, ease } }}>
          <Icon className={styles.healthIcon} width={16} height={16} aria-hidden="true" />
          {health === "checking" ? <TextShimmer className={styles.healthText}>{label}</TextShimmer> : <span className={styles.healthText}>{label}</span>}
        </motion.span>
      </AnimatePresence>
    </span>
  );
}

/**
 * A status card for the services a product depends on. Each row shows the service's mark, its state with an icon and a label,
 * the reason when it is not working, and what can be done with it. A row never claims more than is known: no uptime or latency.
 */
export function ProviderStatus({ providers, title, description, action, empty, className }: ProviderStatusProps) {
  const reduced = useReducedMotion() ?? false;
  const baseId = useId();
  const checking = providers.some(provider => provider.status === "checking");
  return (
    <section className={[styles.root, className].filter(Boolean).join(" ")} aria-labelledby={`${baseId}-title`} aria-busy={checking || undefined}>
      <header className={styles.header}>
        <div className={styles.heading}>
          <h3 id={`${baseId}-title`} className={styles.title}>{title}</h3>
          {description ? <p className={styles.summary}>{description}</p> : null}
        </div>
        {action ? <div className={styles.action}>{action}</div> : null}
      </header>

      {providers.length === 0 ? <div className={styles.empty}>{empty}</div> : (
        <ul className={styles.list} role="list">
          {providers.map(provider => (
            <li key={provider.id} className={styles.item} data-health={provider.status}>
              <div className={styles.line}>
                <span className={styles.mark} aria-hidden="true">{provider.mark}</span>
                <span className={styles.name}>
                  <span className={styles.nameText}>{provider.name}</span>
                  {provider.detail ? <span className={styles.meta}><span className={styles.detail}>{provider.detail}</span></span> : null}
                  {provider.problem ? <span className={styles.problem}>{provider.problem}</span> : null}
                </span>
                <span className={styles.status}><HealthLabel health={provider.status} label={provider.statusLabel} reduced={reduced} /></span>
                {provider.actions ? <span className={styles.actions}>{provider.actions}</span> : null}
              </div>
            </li>
          ))}
        </ul>
      )}
      <span className={styles.srOnly} role="status" aria-live="polite">{checking ? "Checking" : ""}</span>
    </section>
  );
}

export default ProviderStatus;
