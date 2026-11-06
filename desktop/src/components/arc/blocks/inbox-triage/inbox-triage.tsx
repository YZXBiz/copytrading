"use client";

import { useId, useState, type KeyboardEvent, type ReactNode, type Ref } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { Copy01Icon as Copy } from "../../../icons/Copy01Icon";
import { SkipForwardIcon as Skip } from "../../../icons/SkipForwardIcon";
import { Button } from "../../button/button";
import { motionTokens } from "../../lib/motion-tokens";
import { UndoToast } from "../../undo-toast/undo-toast";
import type { UndoEntry, UndoToastHandle } from "../../undo-toast/undo-toast";
import styles from "./inbox-triage.module.css";

/** How one item reads in the queue: a mark, the line it leads with, a quieter line beside it, a time, and what opens under it. */
export interface TriageRow {
  mark: ReactNode;
  title: string;
  subtitle?: string;
  time: string;
  detail: ReactNode;
}

/** The first action of a row, such as Copy. It stays visible and runs on C. */
export interface TriageAnswer {
  label: string;
  onRun: () => void;
  disabled?: boolean;
  /** Why it is disabled, shown as the button's tooltip. */
  reason?: string;
}

export interface InboxTriageProps<T> {
  items: readonly T[];
  getKey: (item: T) => string;
  row: (item: T) => TriageRow;
  answer: (item: T) => TriageAnswer;
  /** Accessible name of the queue. */
  label: string;
  /** What skipping an item is called in the toast: the noun in singular and plural. */
  noun: readonly [string, string];
  /** Shown when the last item is gone and its undo window is still open. */
  empty: ReactNode;
  duration: number;
  /** Called as soon as items are skipped, for an optimistic update. */
  onSkip: (entries: UndoEntry<T>[]) => void;
  onUndo: (entries: UndoEntry<T>[]) => void;
  onCommit: (entries: UndoEntry<T>[]) => void;
  /** Skips an item by its key from outside the queue, such as a Skip all button. */
  handle?: Ref<UndoToastHandle>;
}

const SKIP = { skip: { label: "Skip", done: "skipped" } };
const EDITABLE = "input, textarea, select, [contenteditable]:not([contenteditable='false'])";
const cx = (...names: (string | false | null | undefined)[]) => names.filter(Boolean).join(" ");

/**
 * A queue to answer one call at a time. One item is open at a time, showing everything needed to answer it; J and K or the
 * arrow keys move down and up, C answers, S skips. A skip folds the item away, opens the next one and leaves a toast with
 * the undo window.
 */
export function InboxTriage<T>({ items, getKey, row, answer, label, noun, empty, duration, onSkip, onUndo, onCommit, handle }: InboxTriageProps<T>) {
  const id = useId();
  const reduce = !!useReducedMotion();
  const [openKey, setOpenKey] = useState<string | null>(() => (items[0] ? getKey(items[0]) : null));
  // Items skipped and waiting out their undo window: they no longer count when the next one opens.
  const [gone, setGone] = useState<ReadonlySet<string>>(new Set());
  const rowTransition = reduce ? { duration: 0 } : motionTokens.spring.smooth;

  const skipped = (entries: UndoEntry<T>[]) => {
    const keys = new Set([...gone, ...entries.map((entry) => entry.key)]);
    setGone(keys);
    // The open item leaves: the next one still waiting opens in its place.
    if (openKey !== null && keys.has(openKey)) {
      const at = items.findIndex((item) => getKey(item) === openKey);
      const next = [...items.slice(at + 1), ...items.slice(0, at)].find((item) => !keys.has(getKey(item)));
      setOpenKey(next ? getKey(next) : null);
    }
    onSkip(entries);
  };
  const restored = (entries: UndoEntry<T>[]) => {
    const back = new Set(entries.map((entry) => entry.key));
    setGone((current) => new Set([...current].filter((key) => !back.has(key))));
    onUndo(entries);
  };
  const committed = (entries: UndoEntry<T>[]) => {
    const done = new Set(entries.map((entry) => entry.key));
    setGone((current) => new Set([...current].filter((key) => !done.has(key))));
    onCommit(entries);
  };

  function onRowKey(event: KeyboardEvent<HTMLElement>, item: T, remove: (kind?: string) => void) {
    if (event.metaKey || event.ctrlKey || event.altKey || (event.target instanceof Element && event.target.closest(EDITABLE))) return;
    const key = event.key.toLowerCase();
    if (key === "arrowdown" || key === "j" || key === "arrowup" || key === "k") {
      event.preventDefault();
      const triggers = [...(event.currentTarget.closest("ul")?.querySelectorAll<HTMLButtonElement>("[data-trigger]") ?? [])].filter((node) => !node.closest("li[inert]"));
      const at = triggers.findIndex((node) => node.dataset.trigger === getKey(item));
      const next = triggers[at + (key === "arrowdown" || key === "j" ? 1 : -1)];
      if (next) {
        next.focus();
        setOpenKey(next.dataset.trigger ?? null);
      }
    } else if (key === "c") {
      const { disabled, onRun } = answer(item);
      event.preventDefault();
      if (!disabled) onRun();
    } else if (key === "s") {
      event.preventDefault();
      remove("skip");
    }
  }

  return (
    <div className={styles.triage}>
      <UndoToast<T>
        items={items}
        getKey={getKey}
        label={label}
        actions={SKIP}
        noun={noun}
        duration={duration}
        toastPlacement="viewport"
        onRemove={skipped}
        onUndo={restored}
        onCommit={committed}
        ref={handle}
        empty={<div className={styles.empty}>{empty}</div>}
        renderItem={(item, { remove }) => {
          const key = getKey(item);
          const { mark, title, subtitle, time, detail } = row(item);
          const { label: answerLabel, disabled, reason } = answer(item);
          const open = openKey === key;
          return (
            <article className={cx(styles.message, open && styles.open)} onKeyDown={(event) => onRowKey(event, item, remove)}>
              <div className={styles.row}>
                <button type="button" className={styles.trigger} data-trigger={key} aria-expanded={open} aria-controls={open ? `${id}-${key}-detail` : undefined} aria-keyshortcuts="J K C S" onClick={() => setOpenKey(open ? null : key)}>
                  <span className={styles.mark} aria-hidden="true">{mark}</span>
                  <span className={styles.sender}>{title}</span>
                  <span className={styles.summary}>{subtitle ? <span className={styles.subject}>{subtitle}</span> : null}</span>
                  <time className={styles.time}>{time}</time>
                </button>
                <span className={styles.quick}>
                  <button type="button" className={styles.quickButton} aria-label={`${answerLabel}: ${title}`} title={disabled ? reason : `${answerLabel} (C)`} tabIndex={-1} disabled={disabled} onClick={() => answer(item).onRun()}>
                    <Copy width={16} height={16} aria-hidden="true" />
                  </button>
                  <button type="button" className={styles.quickButton} aria-label={`Skip: ${title}`} title="Skip (S)" tabIndex={-1} onClick={() => remove("skip")}>
                    <Skip width={16} height={16} aria-hidden="true" />
                  </button>
                </span>
              </div>
              <AnimatePresence initial={false}>
                {open && (
                  <motion.div id={`${id}-${key}-detail`} className={styles.detail} initial={reduce ? { opacity: 0 } : { height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={reduce ? { opacity: 0, transition: { duration: 0 } } : { height: 0, opacity: 0 }} transition={rowTransition}>
                    <div className={styles.detailInner}>
                      {detail}
                      <div className={styles.detailActions}>
                        <Button type="button" variant="secondary" size="sm" disabled={disabled} title={disabled ? reason : undefined} onClick={() => answer(item).onRun()}>
                          {answerLabel}<kbd className={styles.kbd}>C</kbd>
                        </Button>
                        <Button type="button" variant="ghost" size="sm" onClick={() => remove("skip")}>
                          Skip<kbd className={styles.kbd}>S</kbd>
                        </Button>
                      </div>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </article>
          );
        }}
      />
      {items.some((item) => !gone.has(getKey(item))) && <footer className={styles.footer}>
        <p className={styles.hint}>
          <span><kbd className={styles.kbd}>J</kbd><kbd className={styles.kbd}>K</kbd>move</span>
          <span><kbd className={styles.kbd}>C</kbd>copy</span>
          <span><kbd className={styles.kbd}>S</kbd>skip</span>
        </p>
        <p className={styles.hintNarrow}>Open a call to copy or skip it</p>
      </footer>}
    </div>
  );
}

export default InboxTriage;
