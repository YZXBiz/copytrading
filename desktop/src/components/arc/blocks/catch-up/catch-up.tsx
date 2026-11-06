"use client";

import { useId } from "react";
import type { ReactNode } from "react";
import { motion, useReducedMotion } from "motion/react";
import { AlertCircleIcon } from "../../../icons/AlertCircleIcon";
import { ArrowUpRight01Icon as ArrowUpRight } from "../../../icons/ArrowUpRight01Icon";
import { CheckmarkCircle02Icon as CheckCircle } from "../../../icons/CheckmarkCircle02Icon";
import { MinusSignCircleIcon as MinusCircle } from "../../../icons/MinusSignCircleIcon";
import { motionTokens } from "../../lib/motion-tokens";
import { Button } from "../../button/button";
import { Tooltip } from "../../tooltip/tooltip";
import { sectionNames, sectionOrder } from "./catch-up-data";
import type { CatchUpItem, CatchUpPerson, CatchUpSectionId } from "./catch-up-data";
import styles from "./catch-up.module.css";

export type { CatchUpItem, CatchUpPerson, CatchUpSectionId } from "./catch-up-data";

export interface CatchUpProps {
  /** What happened, in any order: the block groups it by section and hides a section with nothing in it. */
  items: CatchUpItem[];
  /** The line under the title, such as "3 copied, 1 waiting for you, since 9:12 AM". */
  summary: string;
  /** Jump to an item. */
  onOpen: (item: CatchUpItem) => void;
  /** The card has been read. It is the footer's one button. */
  onDismiss: () => void;
  /** Card title. */
  title?: string;
  /** A short card for a page that has other things to do: three lines at most, no groups, and a way on to the rest. */
  compact?: boolean;
  /** Shown beside the dismiss button in the compact card, to reach everything. */
  onSeeAll?: () => void;
  className?: string;
}

const sectionIcons: Record<CatchUpSectionId, (props: { width: number; height: number; "aria-hidden": true; className?: string }) => ReactNode> = {
  "needs-you": props => <AlertCircleIcon {...props} />,
  copied: props => <CheckCircle {...props} />,
  skipped: props => <MinusCircle {...props} />,
};
/** A short card shows three lines in all; a full one shows three of each group, so a busy day never fills the page. */
const ROWS = 3;
const ease = [...motionTokens.ease.standard] as [number, number, number, number];

/**
 * A card for when someone comes back: what happened while they were away, grouped by what it asks of them, each line one
 * sentence with who it concerned, when, and a way to the post. One button says it has been read.
 */
export function CatchUp({ items, summary, onOpen, onDismiss, title = "Since you last looked", compact = false, onSeeAll, className }: CatchUpProps) {
  const uid = useId();
  const reduced = useReducedMotion() ?? false;
  const groups = sectionOrder.map(id => ({ id, all: items.filter(item => item.section === id) })).filter(group => group.all.length);
  const shown = compact ? groups.flatMap(group => group.all).slice(0, ROWS) : null;
  const sections = groups.map(group => ({ id: group.id, total: group.all.length, items: shown ? group.all.filter(item => shown.includes(item)) : group.all.slice(0, ROWS) })).filter(section => section.items.length);
  const hidden = items.length - sections.reduce((sum, section) => sum + section.items.length, 0);

  return (
    <motion.div
      className={styles.wrap}
      initial={reduced ? { opacity: 0 } : { opacity: 0, height: 0 }}
      animate={{ opacity: 1, height: "auto", transition: reduced ? { duration: 0 } : motionTokens.spring.smooth }}
      exit={{ opacity: 0, ...(reduced ? {} : { height: 0 }), transition: { duration: reduced ? 0 : motionTokens.duration.exit, ease } }}
    >
      <section className={[styles.root, className].filter(Boolean).join(" ")} data-compact={compact || undefined} aria-labelledby={`${uid}-title`}>
        <header className={styles.header}>
          <h2 id={`${uid}-title`} className={styles.title}>{title}</h2>
          <p className={styles.summary}>{summary}</p>
        </header>

        <div className={styles.body}>
          {sections.map(section => {
            const Icon = sectionIcons[section.id];
            const headId = `${uid}-${section.id}`;
            return (
              <section key={section.id} className={styles.section} aria-labelledby={headId}>
                {!compact && (
                  <h3 id={headId} className={styles.sectionHead} data-section={section.id}>
                    <Icon width={16} height={16} aria-hidden className={styles.sectionIcon} />
                    <span>{sectionNames[section.id]}</span>
                    <span className={styles.sectionCount}>{section.total}</span>
                  </h3>
                )}
                <ul className={styles.items}>
                  {section.items.map(item => <li key={item.id} className={styles.item}><DigestRow item={item} compact={compact} Icon={Icon} waiting={section.id === "needs-you"} onOpen={() => onOpen(item)} /></li>)}
                </ul>
                {!compact && section.total > section.items.length && <p className={styles.more}>and {section.total - section.items.length} more</p>}
              </section>
            );
          })}
          {compact && hidden > 0 && <p className={styles.more}>and {hidden} more</p>}
        </div>

        <footer className={styles.footer}>
          {compact && onSeeAll && <Button variant="ghost" onClick={onSeeAll}>See all activity</Button>}
          <Button variant="secondary" className={styles.action} onClick={onDismiss}>Dismiss</Button>
        </footer>
      </section>
    </motion.div>
  );
}

function DigestRow({ item, compact, Icon, waiting, onOpen }: { item: CatchUpItem; compact: boolean; Icon: (typeof sectionIcons)[CatchUpSectionId]; waiting: boolean; onOpen: () => void }) {
  const people = item.people ?? [];
  const lead = people[0]?.name;
  const meta = [lead ? `${lead}${people.length > 1 ? ` +${people.length - 1}` : ""}` : "", item.context ?? "", item.when ?? ""].filter(Boolean);
  return (
    <div className={styles.row}>
      <Icon width={16} height={16} aria-hidden className={[styles.mark, styles.rowMark, waiting && styles.waiting].filter(Boolean).join(" ")} />
      <div className={styles.rowBody}>
        <p className={styles.text}>{item.text}</p>
        {!compact && meta.length > 0 && <p className={styles.meta}>{meta.join(" · ")}</p>}
      </div>
      <Tooltip content="Open the post">
        <button type="button" className={styles.iconButton} aria-label={`Open the post: ${item.text}`} onClick={onOpen}>
          <ArrowUpRight width={16} height={16} aria-hidden="true" />
        </button>
      </Tooltip>
    </div>
  );
}

export default CatchUp;
