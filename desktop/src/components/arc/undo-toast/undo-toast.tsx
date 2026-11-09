"use client";

import { useCallback, useEffect, useId, useImperativeHandle, useLayoutEffect, useRef, useState, useSyncExternalStore } from "react";
import type { CSSProperties, KeyboardEvent as ReactKeyboardEvent, ReactNode, Ref } from "react";
import { AnimatePresence, animate, motion, useMotionValue, useMotionValueEvent, useReducedMotion } from "motion/react";
import type { AnimationPlaybackControls, Transition } from "motion/react";
import { AlertCircleIcon as CircleAlert } from "../../icons/AlertCircleIcon";
import { Tick02Icon as Check } from "../../icons/Tick02Icon";
import { motionTokens } from "../lib/motion-tokens";
import styles from "./undo-toast.module.css";

/** One kind of removal, such as archive or delete. */
export interface UndoAction {
  /** The verb, used in failure copy: "Archive" reads "Couldn't archive conversation". */
  label: string;
  /** The past tense for the toast: "archived" reads "3 conversations archived". */
  done: string;
  /** A plain icon for the action, used by UndoToastRow buttons in your own markup if you want it. */
  icon?: ReactNode;
}

/** A removed item with where it was, so undo can put it back in exactly the same place. */
export interface UndoEntry<T> {
  key: string;
  kind: string;
  item: T;
  /** Position in the list when it was removed. */
  index: number;
}

export interface UndoRowContext {
  /** Removes this row with an action kind (the first key of actions by default). It collapses at once and joins the toast. */
  remove: (kind?: string) => void;
  /** True while the row is collapsed and waiting for its undo window to close. */
  removed: boolean;
  /** Changes each time the row is put back, so you can key your own highlight to it. 0 until then. */
  restoredAt: number;
}

export interface UndoToastHandle {
  /** Removes the item with this key, exactly like the row's own remove. */
  remove: (key: string, kind?: string) => void;
  /** Undoes the pending batch, if there is one. */
  undo: () => void;
  /** Closes the undo window now and commits the pending batch. */
  commit: () => void;
}

/**
 * A list whose rows can be archived or deleted with a second chance. The row folds away and the gap closes on a spring while a
 * toast rises with a draining countdown. Removing more rows merges them into the same toast, whose count rolls up. Undo, or
 * Cmd/Ctrl+Z, opens every row again in its exact original place and the toast confirms. Hovering or focusing the toast pauses
 * the countdown. When it runs out, onCommit runs; if it rejects, the rows come back and the toast says so.
 */
export interface UndoToastProps<T> {
  /** Controlled items. Pair with onItemsChange, which fires once a removal is committed. */
  items?: readonly T[];
  /** Starting items when uncontrolled. */
  defaultItems?: readonly T[];
  /** Called with the new list when a batch is committed, never while it can still be undone. */
  onItemsChange?: (items: T[]) => void;
  /** A stable key for each item. */
  getKey: (item: T) => string;
  /** Renders a row. Call ctx.remove(kind) from its buttons or shortcuts. */
  renderItem: (item: T, ctx: UndoRowContext) => ReactNode;
  /** The kinds of removal, keyed by name. Defaults to archive and delete. */
  actions?: Record<string, UndoAction>;
  /** Singular and plural nouns for the toast copy. */
  noun?: readonly [string, string];
  /** Milliseconds the undo window stays open. It restarts when another row joins the batch. */
  duration?: number;
  /** Called as soon as rows are removed, for optimistic updates. Pair with onUndo to reverse them. */
  onRemove?: (entries: UndoEntry<T>[]) => void;
  /** Called on undo. Return a promise to show a restoring state; a rejection keeps the rows removed and offers undo again. */
  onUndo?: (entries: UndoEntry<T>[]) => void | Promise<unknown>;
  /** Called when the undo window closes. Return a promise; a rejection puts the rows back and shows the failure. */
  onCommit?: (entries: UndoEntry<T>[]) => void | Promise<unknown>;
  /** Cmd+Z on Apple devices and Ctrl+Z elsewhere undo the pending batch, unless focus is in a text field. */
  undoShortcut?: boolean;
  /** Hovering or focusing the toast pauses the countdown. */
  pauseOnHover?: boolean;
  /** Shown when every row is gone. */
  empty?: ReactNode;
  /** Accessible name of the list. */
  label: string;
  /** container floats the toast at the bottom of the component; viewport fixes it to the bottom of the window. */
  toastPlacement?: "container" | "viewport";
  className?: string;
  style?: CSSProperties;
  ref?: Ref<UndoToastHandle>;
}

type Phase = "pending" | "undoing" | "restored" | "error";
type HiddenState = "pending" | "committing" | "gone";
interface ToastModel<T> {
  id: number;
  phase: Phase;
  entries: UndoEntry<T>[];
  /** Undo was tried and failed; offer it again. */
  retry?: boolean;
}

const DEFAULT_ACTIONS: Record<string, UndoAction> = {
  remove: { label: "Remove", done: "removed" },
};
const DEFAULT_NOUN = ["item", "items"] as const;
const FOCUSABLE = "button:not([disabled]), a[href], input:not([disabled]), select, textarea, [tabindex]:not([tabindex='-1'])";
const EDITABLE = "input, textarea, select, [contenteditable]:not([contenteditable='false'])";

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** Counts per kind, in the order they were first used. */
function tally<T>(entries: UndoEntry<T>[]) {
  const counts = new Map<string, number>();
  for (const e of entries) counts.set(e.kind, (counts.get(e.kind) ?? 0) + 1);
  return [...counts];
}

interface Message { key: string; count?: number; text: string }

function describe<T>(model: ToastModel<T>, actions: Record<string, UndoAction>, noun: readonly [string, string]): Message {
  const n = model.entries.length;
  const kinds = tally(model.entries);
  const one = n === 1;
  const action = (kind: string) => actions[kind] ?? { label: cap(kind), done: kind };
  if (model.phase === "undoing") return { key: "undoing", text: "Restoring…" };
  if (model.phase === "restored") return one ? { key: "restored-1", text: `${cap(noun[0])} restored` } : { key: "restored-n", count: n, text: `${noun[1]} restored` };
  if (model.phase === "error") {
    const verb = kinds.length === 1 ? action(kinds[0][0]).label.toLowerCase() : "update";
    return one ? { key: "error-1", text: `Couldn't ${verb} ${noun[0]}` } : { key: "error-n", text: `Couldn't ${verb} ${n} ${noun[1]}` };
  }
  if (model.retry) return { key: "retry", text: "Couldn't undo, try again" };
  if (kinds.length > 1) return { key: "mixed", text: kinds.map(([kind, count]) => `${count} ${action(kind).done}`).join(", ") };
  const done = action(kinds[0][0]).done;
  return one ? { key: `one-${kinds[0][0]}`, text: `${cap(noun[0])} ${done}` } : { key: `many-${kinds[0][0]}`, count: n, text: `${noun[1]} ${done}` };
}

function announce<T>(model: ToastModel<T>, message: Message, shortcut: string) {
  const text = message.count ? `${message.count} ${message.text}` : message.text;
  if (model.phase === "pending") return `${text}. ${shortcut ? `Press ${shortcut} or the Undo button` : "Use the Undo button"} to undo.`;
  return text;
}

/* Platform, read after hydration so the server and first client render agree. */
const noop = () => () => {};
const readShortcut = () => (/Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent) ? "mac" : "other");
const useShortcutPlatform = () => useSyncExternalStore(noop, readShortcut, () => "");

/** A number that rolls to its new value. */
function Roll({ value, reduced }: { value: number; reduced: boolean }) {
  return <span className={styles.roll}>
    <AnimatePresence initial={false} mode="popLayout">
      <motion.span
        key={value}
        className={styles.rollDigit}
        initial={reduced ? { opacity: 0 } : { y: "80%", opacity: 0, filter: `blur(${motionTokens.blur.subtle}px)` }}
        animate={{ y: 0, opacity: 1, filter: "blur(0px)" }}
        exit={reduced ? { opacity: 0 } : { y: "-80%", opacity: 0, filter: `blur(${motionTokens.blur.subtle}px)` }}
        transition={reduced ? { duration: 0 } : motionTokens.spring.snappy}
      >{value}</motion.span>
    </AnimatePresence>
  </span>;
}

export function UndoToast<T>({
  items: itemsProp,
  defaultItems,
  onItemsChange,
  getKey,
  renderItem,
  actions = DEFAULT_ACTIONS,
  noun = DEFAULT_NOUN,
  duration = 6000,
  onRemove,
  onUndo,
  onCommit,
  undoShortcut = true,
  pauseOnHover = true,
  empty,
  label,
  toastPlacement = "container",
  className,
  style,
  ref,
}: UndoToastProps<T>) {
  const reduced = useReducedMotion() ?? false;
  const platform = useShortcutPlatform();
  const shortcutLabel = !undoShortcut || !platform ? "" : platform === "mac" ? "⌘Z" : "Ctrl Z";
  const shortcutSpoken = !undoShortcut || !platform ? "" : platform === "mac" ? "Command Z" : "Control Z";
  const statusId = useId();

  const [ownItems, setOwnItems] = useState<readonly T[]>(() => defaultItems ?? []);
  const controlled = itemsProp !== undefined;
  const list = controlled ? itemsProp : ownItems;

  const [hidden, setHiddenState] = useState<Record<string, HiddenState>>({});
  const [restored, setRestored] = useState<Record<string, number>>({});
  const [toast, setToastState] = useState<ToastModel<T> | null>(null);
  const [seconds, setSeconds] = useState(Math.ceil(duration / 1000));

  const listRef = useRef(list);
  const hiddenRef = useRef(hidden);
  const toastRef = useRef(toast);
  const ulRef = useRef<HTMLUListElement>(null);
  const toastElRef = useRef<HTMLDivElement>(null);
  const timerRef = useRef<AnimationPlaybackControls | null>(null);
  const hideRef = useRef<number | undefined>(undefined);
  const pausedRef = useRef(new Set<string>());
  /* True while the toast moves focus to its own Undo button: only someone tabbing or clicking in pauses the countdown. */
  const handingOffRef = useRef(false);
  const idRef = useRef(0);
  const restoreTokenRef = useRef(0);
  const props = { onItemsChange, getKey, actions, duration, onRemove, onUndo, onCommit, controlled, reduced };
  const propsRef = useRef(props);
  useLayoutEffect(() => { propsRef.current = props; listRef.current = list; });

  const progress = useMotionValue(1);
  const bump = useMotionValue(1);
  useMotionValueEvent(progress, "change", p => setSeconds(Math.max(1, Math.ceil(p * propsRef.current.duration / 1000 - .001))));

  const setHidden = useCallback((update: (h: Record<string, HiddenState>) => Record<string, HiddenState>) => {
    hiddenRef.current = update(hiddenRef.current);
    setHiddenState(hiddenRef.current);
  }, []);
  const setToast = useCallback((next: ToastModel<T> | null, hideAfter = 0) => {
    window.clearTimeout(hideRef.current);
    toastRef.current = next;
    setToastState(next);
    if (next && hideAfter) hideRef.current = window.setTimeout(() => { if (toastRef.current?.id === next.id) { toastRef.current = null; setToastState(null); } }, hideAfter);
  }, []);

  /* Keys that have left the list for good no longer need tracking. */
  useEffect(() => {
    const present = new Set(list.map(item => getKey(item)));
    const stale = Object.keys(hiddenRef.current).filter(key => !present.has(key));
    if (stale.length) setHidden(h => { const next = { ...h }; for (const key of stale) delete next[key]; return next; });
  }, [list, getKey, setHidden]);

  const stopTimer = useCallback(() => { timerRef.current?.stop(); timerRef.current = null; }, []);

  const finalize = useCallback((entries: UndoEntry<T>[]) => {
    const keys = new Set(entries.map(e => e.key));
    const p = propsRef.current;
    setHidden(h => { const next = { ...h }; for (const key of keys) next[key] = "gone"; return next; });
    const nextItems = listRef.current.filter(item => !keys.has(p.getKey(item)));
    if (!p.controlled) setOwnItems(nextItems);
    p.onItemsChange?.(nextItems);
  }, [setHidden]);

  const reveal = useCallback((entries: UndoEntry<T>[]) => {
    const keys = entries.map(e => e.key);
    const token = ++restoreTokenRef.current;
    setHidden(h => { const next = { ...h }; for (const key of keys) delete next[key]; return next; });
    setRestored(r => { const next = { ...r }; for (const key of keys) next[key] = token; return next; });
  }, [setHidden]);

  const commitBatch = useCallback(async (model: ToastModel<T>) => {
    stopTimer();
    const { entries } = model;
    if (toastRef.current?.id === model.id) setToast(null);
    setHidden(h => { const next = { ...h }; for (const e of entries) next[e.key] = "committing"; return next; });
    try {
      await propsRef.current.onCommit?.(entries);
      finalize(entries);
    } catch {
      reveal(entries);
      if (!toastRef.current || toastRef.current.phase !== "pending") setToast({ id: ++idRef.current, phase: "error", entries }, 4200);
    }
  }, [finalize, reveal, setHidden, setToast, stopTimer]);

  const startTimer = useCallback((refill: boolean) => {
    stopTimer();
    const model = toastRef.current;
    if (!model) return;
    const total = propsRef.current.duration / 1000;
    const drain = () => {
      const controls = animate(progress, 0, { duration: Math.max(.01, total * progress.get()), ease: "linear", onComplete: () => { if (toastRef.current?.id === model.id) void commitBatch(toastRef.current); } });
      timerRef.current = controls;
      if (pausedRef.current.size) controls.pause();
    };
    if (refill && !propsRef.current.reduced && progress.get() < .98) {
      const controls = animate(progress, 1, { ...motionTokens.spring.smooth, visualDuration: .36, onComplete: drain });
      timerRef.current = controls;
      if (pausedRef.current.size) controls.pause();
    } else {
      progress.set(1);
      drain();
    }
  }, [commitBatch, progress, stopTimer]);

  const pause = useCallback((reason: string) => { pausedRef.current.add(reason); timerRef.current?.pause(); }, []);
  const resume = useCallback((reason: string) => {
    pausedRef.current.delete(reason);
    if (!pausedRef.current.size && toastRef.current?.phase === "pending") timerRef.current?.play();
  }, []);

  /* Hidden tabs never run out the clock. */
  useEffect(() => {
    const onVisibility = () => (document.hidden ? pause("tab") : resume("tab"));
    document.addEventListener("visibilitychange", onVisibility);
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, [pause, resume]);

  useEffect(() => () => { timerRef.current?.stop(); window.clearTimeout(hideRef.current); }, []);

  /** Moves focus out of a row that is about to fold away: to the same control on the next row, or the previous one. */
  const handOffFocus = useCallback((key: string) => {
    const ul = ulRef.current;
    const active = document.activeElement;
    if (!ul || !(active instanceof HTMLElement)) return;
    const rows = [...ul.querySelectorAll<HTMLElement>(":scope > li")];
    const index = rows.findIndex(row => row.dataset.key === key);
    const row = rows[index];
    if (!row || !row.contains(active)) return;
    const position = [...row.querySelectorAll<HTMLElement>(FOCUSABLE)].indexOf(active);
    const visible = (r: HTMLElement) => r.dataset.key !== key && !hiddenRef.current[r.dataset.key ?? ""];
    const target = rows.slice(index + 1).find(visible) ?? rows.slice(0, index).reverse().find(visible);
    if (target) {
      const controls = [...target.querySelectorAll<HTMLElement>(FOCUSABLE)];
      (controls[position] ?? controls[0])?.focus({ preventScroll: true });
    } else {
      requestAnimationFrame(() => {
        handingOffRef.current = true;
        toastElRef.current?.querySelector<HTMLElement>("button")?.focus({ preventScroll: true });
        handingOffRef.current = false;
      });
    }
  }, []);

  const remove = useCallback((key: string, kind?: string) => {
    const p = propsRef.current;
    if (hiddenRef.current[key]) return;
    const index = listRef.current.findIndex(item => p.getKey(item) === key);
    if (index < 0) return;
    const entry: UndoEntry<T> = { key, kind: kind ?? Object.keys(p.actions)[0] ?? "remove", item: listRef.current[index], index };
    handOffFocus(key);
    setHidden(h => ({ ...h, [key]: "pending" }));
    p.onRemove?.([entry]);
    const current = toastRef.current;
    if (current?.phase === "pending") {
      setToast({ ...current, retry: false, entries: [...current.entries, entry] });
      if (!p.reduced) animate(bump, 1, { type: "spring", stiffness: 700, damping: 51, velocity: .9 });
      startTimer(true);
    } else {
      setToast({ id: ++idRef.current, phase: "pending", entries: [entry] });
      startTimer(false);
    }
  }, [bump, handOffFocus, setHidden, setToast, startTimer]);

  const undo = useCallback(async () => {
    const model = toastRef.current;
    if (!model || model.phase !== "pending") return;
    stopTimer();
    const toastHadFocus = !!toastElRef.current?.contains(document.activeElement) || document.activeElement === document.body;
    if (propsRef.current.onUndo) {
      setToast({ ...model, phase: "undoing" });
      try {
        await propsRef.current.onUndo(model.entries);
      } catch {
        if (toastRef.current?.id === model.id) { setToast({ ...model, phase: "pending", retry: true }); startTimer(false); }
        return;
      }
    }
    reveal(model.entries);
    if (toastRef.current?.id === model.id || !toastRef.current) setToast({ ...model, phase: "restored", retry: false }, 2000);
    if (toastHadFocus) {
      const first = [...model.entries].sort((a, b) => a.index - b.index)[0];
      requestAnimationFrame(() => {
        const row = ulRef.current?.querySelector<HTMLElement>(`:scope > li[data-key="${CSS.escape(first.key)}"]`);
        row?.querySelector<HTMLElement>(FOCUSABLE)?.focus({ preventScroll: true });
      });
    }
  }, [reveal, setToast, startTimer, stopTimer]);

  const commitNow = useCallback(() => { const model = toastRef.current; if (model?.phase === "pending") void commitBatch(model); }, [commitBatch]);

  useImperativeHandle(ref, () => ({ remove, undo: () => void undo(), commit: commitNow }), [remove, undo, commitNow]);

  /* Cmd/Ctrl+Z, while there is something to undo and focus is not in a field with its own undo. */
  const pending = toast?.phase === "pending";
  useEffect(() => {
    if (!undoShortcut || !pending) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key.toLowerCase() !== "z" || event.shiftKey || event.altKey || !(event.metaKey || event.ctrlKey)) return;
      if (event.target instanceof Element && event.target.closest(EDITABLE)) return;
      event.preventDefault();
      void undo();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [pending, undo, undoShortcut]);

  const onToastKeyDown = (event: ReactKeyboardEvent) => {
    if (event.key === "Escape" && toastRef.current?.phase === "pending") { event.stopPropagation(); commitNow(); }
  };

  const message = toast ? describe(toast, actions, noun) : null;
  const visibleCount = list.filter(item => !hidden[getKey(item)]).length;
  const orderedRestore = new Map<string, number>();
  if (toast?.phase === "restored") [...toast.entries].sort((a, b) => a.index - b.index).forEach((e, i) => orderedRestore.set(e.key, i));

  const collapse: Transition = reduced ? { duration: 0 } : motionTokens.spring.smooth;
  const lead = !toast ? null : toast.phase === "restored" ? "done" : toast.phase === "error" ? "error" : toast.phase === "undoing" ? "busy" : "ring";

  return <div className={[styles.root, className].filter(Boolean).join(" ")} style={style}>
    <ul ref={ulRef} className={styles.list} aria-label={label}>
      <AnimatePresence initial={false}>
      {list.map(item => {
        const key = getKey(item);
        const state = hidden[key];
        const gone = !!state;
        const stagger = (orderedRestore.get(key) ?? 0) * motionTokens.stagger.item;
        const token = restored[key] ?? 0;
        return <motion.li
          key={key}
          data-key={key}
          className={styles.row}
          initial={{ height: 0 }}
          animate={gone ? { height: 0 } : { height: "auto" }}
          exit={{ height: 0, transition: collapse }}
          transition={gone ? { ...collapse, delay: reduced ? 0 : .05 } : { ...collapse, delay: reduced ? 0 : stagger }}
          aria-hidden={gone || undefined}
          inert={gone}
        >
          <motion.div
            className={styles.rowInner}
            initial={{ opacity: 0, x: reduced ? 0 : 28 }}
            animate={gone
              ? { opacity: 0, x: reduced ? 0 : 28, scale: reduced ? 1 : .985, filter: reduced ? "blur(0px)" : `blur(${motionTokens.blur.subtle}px)` }
              : { opacity: 1, x: 0, scale: 1, filter: "blur(0px)" }}
            transition={reduced
              ? { duration: 0 }
              : gone
                ? { duration: motionTokens.duration.exit, ease: motionTokens.ease.standard }
                : { ...motionTokens.spring.snappy, delay: .06 + stagger, filter: { duration: .2, delay: .06 + stagger } }}
          >
            {token ? <span key={token} className={styles.flash} aria-hidden /> : null}
            <RowContent item={item} rowKey={key} removed={gone} restoredAt={token} onRemove={remove} render={renderItem} />
          </motion.div>
        </motion.li>;
      })}
      </AnimatePresence>
    </ul>

    <AnimatePresence initial={false}>
      {visibleCount === 0 && empty ? <motion.div
        key="empty"
        className={styles.empty}
        initial={reduced ? { opacity: 0 } : { opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, transition: { duration: motionTokens.duration.instant } }}
        transition={reduced ? { duration: 0 } : { ...motionTokens.spring.smooth, delay: .18 }}
      >{empty}</motion.div> : null}
    </AnimatePresence>

    <div id={statusId} className={styles.srOnly} role="status" aria-live="polite" aria-atomic="true">
      {toast && message ? announce(toast, message, shortcutSpoken) : ""}
    </div>

    <div className={styles.toastLayer} data-placement={toastPlacement}>
      <AnimatePresence>
        {toast && message ? <motion.div
          key="toast"
          className={styles.toastShell}
          initial={reduced ? { opacity: 0 } : { opacity: 0, y: 18, scale: .94, filter: `blur(${motionTokens.blur.soft}px)` }}
          animate={{ opacity: 1, y: 0, scale: 1, filter: "blur(0px)" }}
          exit={reduced ? { opacity: 0 } : { opacity: 0, y: 12, scale: .96, filter: `blur(${motionTokens.blur.subtle}px)`, transition: { duration: motionTokens.duration.exit, ease: motionTokens.ease.exit } }}
          transition={reduced ? { duration: motionTokens.duration.fast } : { ...motionTokens.spring.morph, filter: { duration: .24 } }}
        >
          <motion.div
            ref={toastElRef}
            className={styles.toast}
            data-phase={toast.phase}
            style={{ scale: bump }}
            role="group"
            aria-label="Undo"
            aria-describedby={statusId}
            onPointerEnter={() => pauseOnHover && pause("hover")}
            onPointerLeave={() => resume("hover")}
            onFocus={() => pauseOnHover && !handingOffRef.current && pause("focus")}
            onBlur={event => { if (!event.currentTarget.contains(event.relatedTarget as Node | null)) resume("focus"); }}
            onKeyDown={onToastKeyDown}
          >
            <span className={styles.lead} aria-hidden>
              <AnimatePresence initial={false} mode="popLayout">
                <motion.span
                  key={lead}
                  className={styles.leadFace}
                  data-lead={lead}
                  initial={reduced ? { opacity: 0 } : { opacity: 0, scale: .5, rotate: lead === "done" ? -45 : 0 }}
                  animate={{ opacity: 1, scale: 1, rotate: 0 }}
                  exit={reduced ? { opacity: 0 } : { opacity: 0, scale: .5 }}
                  transition={reduced ? { duration: 0 } : motionTokens.spring.snappy}
                >
                  {lead === "ring" ? <Countdown progress={progress} seconds={seconds} reduced={reduced} />
                    : lead === "busy" ? <span className={styles.spinner} />
                      : lead === "done" ? <Check width={16} height={16} />
                        : <CircleAlert width={16} height={16} />}
                </motion.span>
              </AnimatePresence>
            </span>

            <span className={styles.message}>
              <AnimatePresence initial={false} mode="popLayout">
                <motion.span
                  key={message.key}
                  className={styles.messageFace}
                  initial={reduced ? { opacity: 0 } : { opacity: 0, y: 8, filter: `blur(${motionTokens.blur.subtle}px)` }}
                  animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
                  exit={reduced ? { opacity: 0 } : { opacity: 0, y: -8, filter: `blur(${motionTokens.blur.subtle}px)` }}
                  transition={reduced ? { duration: 0 } : { ...motionTokens.spring.snappy, filter: { duration: .18 } }}
                >
                  {message.count ? <><Roll value={message.count} reduced={reduced} />{" "}</> : null}
                  {message.text}
                </motion.span>
              </AnimatePresence>
            </span>

            <AnimatePresence initial={false}>
              {toast.phase === "pending" || toast.phase === "undoing" ? <motion.button
                key="undo"
                type="button"
                className={styles.undo}
                disabled={toast.phase === "undoing"}
                onClick={() => void undo()}
                initial={reduced ? { opacity: 0 } : { opacity: 0, scale: .9 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={reduced ? { opacity: 0 } : { opacity: 0, scale: .9, filter: `blur(${motionTokens.blur.subtle}px)` }}
                transition={reduced ? { duration: 0 } : motionTokens.spring.snappy}
                aria-keyshortcuts={undoShortcut ? "Meta+Z Control+Z" : undefined}
              >
                Undo
                {shortcutLabel ? <kbd className={styles.kbd} aria-hidden>{shortcutLabel}</kbd> : null}
              </motion.button> : null}
            </AnimatePresence>
          </motion.div>
        </motion.div> : null}
      </AnimatePresence>
    </div>
  </div>;
}

function RowContent<T>({ item, rowKey, removed, restoredAt, onRemove, render }: { item: T; rowKey: string; removed: boolean; restoredAt: number; onRemove: (key: string, kind?: string) => void; render: UndoToastProps<T>["renderItem"] }) {
  return render(item, { remove: kind => onRemove(rowKey, kind), removed, restoredAt });
}

/** A ring that drains with the undo window, with the whole seconds left inside it. */
function Countdown({ progress, seconds, reduced }: { progress: ReturnType<typeof useMotionValue<number>>; seconds: number; reduced: boolean }) {
  return <span className={styles.countdown}>
    <svg viewBox="0 0 24 24" className={styles.ring}>
      <circle cx="12" cy="12" r="10" className={styles.ringTrack} />
      <motion.circle cx="12" cy="12" r="10" className={styles.ringFill} style={{ pathLength: progress }} />
    </svg>
    <span className={styles.seconds}><Roll value={seconds} reduced={reduced} /></span>
  </span>;
}

/* ─── Row ─────────────────────────────────────────────────────────────────── */

export interface UndoToastRowProps {
  /** Leading media, such as an avatar. */
  leading?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  /** Right aligned metadata, such as a time. It gives way to the actions while the row is hovered or focused. */
  meta?: ReactNode;
  /** Row buttons, usually archive and delete, shown on hover and focus and always on touch. */
  actions?: ReactNode;
  /** Keyboard shortcuts on the focused row, such as { e: archive, Backspace: remove }. */
  shortcuts?: Record<string, () => void>;
  /** Accessible name of the row. */
  label?: string;
  unread?: boolean;
  className?: string;
}

/** A ready made row for UndoToast: leading media, a title and description, metadata that gives way to actions on hover. */
export function UndoToastRow({ leading, title, description, meta, actions, shortcuts, label, unread, className }: UndoToastRowProps) {
  return <div
    className={[styles.item, className].filter(Boolean).join(" ")}
    data-unread={unread || undefined}
    tabIndex={0}
    aria-label={label}
    onKeyDown={event => {
      if (event.target !== event.currentTarget || !shortcuts || event.metaKey || event.ctrlKey || event.altKey) return;
      const run = shortcuts[event.key] ?? shortcuts[event.key.toLowerCase()];
      if (run) { event.preventDefault(); run(); }
    }}
  >
    {leading ? <span className={styles.leading}>{leading}</span> : null}
    <span className={styles.body}>
      <span className={styles.title}>{title}</span>
      {description ? <span className={styles.description}>{description}</span> : null}
    </span>
    <span className={styles.trailing}>
      {meta ? <span className={styles.meta}>{meta}</span> : null}
      {actions ? <span className={styles.actions}>{actions}</span> : null}
    </span>
  </div>;
}

export interface UndoToastRowActionProps {
  label: string;
  icon: ReactNode;
  onClick: () => void;
}

/** An icon button for UndoToastRow actions, with its label as the accessible name and tooltip. */
export function UndoToastRowAction({ label, icon, onClick }: UndoToastRowActionProps) {
  return <button type="button" className={styles.rowAction} aria-label={label} title={label} onClick={event => { event.stopPropagation(); onClick(); }}>
    {icon}
  </button>;
}
