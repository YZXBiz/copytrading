"use client";

import { AnimatePresence, motion } from "motion/react";
import { AlertCircleIcon } from "@/components/icons/AlertCircleIcon";
import { Cancel01Icon } from "@/components/icons/Cancel01Icon";
import { MinusSignIcon } from "@/components/icons/MinusSignIcon";
import { Tick02Icon } from "@/components/icons/Tick02Icon";
import { glide } from "./approval-parts";
import type { ResolvedEntry } from "./agent-approvals-data";
import styles from "./agent-approvals.module.css";

const OutcomeIcon = { done: Tick02Icon, waiting: MinusSignIcon, stopped: Cancel01Icon, failed: AlertCircleIcon } as const;

/** Requests and decisions, newest first: what was asked, how it ended as an icon and a word, who made it and when. */
export function ResolvedLog({ entries, reduced, id }: { entries: ResolvedEntry[]; reduced: boolean; id: string }) {
  return <ul id={id} className={styles.log} aria-label="Recent requests">
    <AnimatePresence initial={false}>
      {entries.map(entry => {
        const Icon = OutcomeIcon[entry.tone];
        return <motion.li key={entry.id} className={styles.logItem} initial={reduced ? { opacity: 0 } : { opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} transition={reduced ? { duration: 0 } : { height: glide, opacity: { duration: .16 } }}>
          <div className={styles.logRow}>
            <span className={styles.logText}>
              <span className={styles.logSummary} title={entry.summary}>{entry.summary}</span>
              <span className={styles.logMeta}>
                <span className={styles.logOutcome} data-tone={entry.tone}><Icon width={16} height={16} aria-hidden="true" />{entry.outcome}</span>
                <span>{entry.by}</span>
              </span>
            </span>
            <time className={styles.logTime} dateTime={entry.at}>{entry.when}</time>
          </div>
        </motion.li>;
      })}
    </AnimatePresence>
  </ul>;
}
