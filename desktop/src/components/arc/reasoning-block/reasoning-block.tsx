"use client";

import { Fragment, useEffect, useId, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import { AnimatePresence, animate, motion, useInView, useMotionValue, usePageInView, useReducedMotion } from "motion/react";
import type { AnimationPlaybackControls, Transition } from "motion/react";
import { AlertCircleIcon as CircleAlert } from "../../icons/AlertCircleIcon";
import { ArrowDown01Icon as ChevronDown } from "../../icons/ArrowDown01Icon";
import { Button } from "../button/button";
import { TextShimmer } from "../text-shimmer/text-shimmer";
import { motionTokens } from "../lib/motion-tokens";
import { reasoningSamples } from "./reasoning-block-data";
import type { ReasoningStep } from "./reasoning-block-data";
import styles from "./reasoning-block.module.css";

export type { ReasoningSample, ReasoningStep } from "./reasoning-block-data";
export { reasoningSamples } from "./reasoning-block-data";

export type ReasoningStatus = "thinking" | "done" | "stopped" | "error";

export interface ReasoningModel {
  /** Read by assistive technology with the block, such as "Claude Opus 5.5". */
  name: string;
  /** An 18px mark drawn at the left. Defaults to the Claude mark. */
  mark?: ReactNode;
}

export interface ReasoningBlockProps {
  /**
   * The reasoning so far. Pass the growing string while the model streams: blank lines split paragraphs, and a line
   * written as **Heading** or ## Heading starts a new step. Or pass structured steps.
   */
  reasoning?: string | ReasoningStep[];
  /** thinking shimmers the label and streams the latest line; done collapses to "Thought for 7s". Defaults to done when reasoning is passed. */
  status?: ReasoningStatus;
  /** Seconds spent thinking. Measured from when status turns thinking when left out. */
  seconds?: number;
  /** The model doing the thinking. Defaults to Claude Opus 5.5 with the Claude mark. */
  model?: ReasoningModel;
  /** Controls whether the full reasoning is shown. Pair with onOpenChange. */
  open?: boolean;
  defaultOpen?: boolean;
  onOpenChange?: (open: boolean) => void;
  /** Shows Stop while thinking. Set status to stopped yourself once the request is aborted. */
  onStop?: () => void;
  /** Shows Retry when status is error. */
  onRetry?: () => void;
  /** The reason shown under the reasoning when status is error. */
  error?: string;
  /** card draws a quiet bordered surface; plain sits flush inside a message. Defaults to card. */
  variant?: "card" | "plain";
  /** The line shown while the block is closed once it is done, in place of "Thought for 7s", and the block's accessible name. */
  title?: string;
  className?: string;
}

/** A small filled square, the Stop mark. */
const StopSquare = ({ size }: { size: number }) => <svg width={size} height={size} viewBox="0 0 10 10" fill="currentColor" aria-hidden="true"><rect width="10" height="10" rx="1.5" /></svg>;

const cx =(...names: (string | false | null | undefined)[]) => names.filter(Boolean).join(" ");
const defaultModel: ReasoningModel = { name: "Reasoning" };

/** 4s, 1m 12s: short, so the header never wraps. */
export function formatThinkingTime(seconds: number) {
  const s = Math.max(0, Math.round(seconds));
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`;
}
const spokenTime = (seconds: number) => {
  const s = Math.max(1, Math.round(seconds));
  if (s < 60) return `${s} second${s === 1 ? "" : "s"}`;
  const m = Math.floor(s / 60), r = s % 60;
  return `${m} minute${m === 1 ? "" : "s"}${r ? ` ${r} seconds` : ""}`;
};

const headingLine = /^(?:\*\*(.+?)\*\*:?|#{1,4}\s+(.+))\s*$/;
/** An opening ** still streaming, so a half written heading never flashes as raw asterisks. */
const partialHeading = /^\*\*([^*\n]*)\*?$/;

/** Splits streamed reasoning into steps. Text before the first heading becomes an untitled step. */
export function parseReasoning(reasoning: string | ReasoningStep[] | undefined): ReasoningStep[] {
  if (!reasoning) return [];
  if (Array.isArray(reasoning)) return reasoning.filter(step => step.title || step.text);
  const steps: ReasoningStep[] = [];
  const blocks = reasoning.replace(/\r\n/g, "\n").split(/\n{2,}/);
  blocks.forEach((raw, index) => {
    const block = raw.trim();
    if (!block) return;
    const [first, ...rest] = block.split("\n");
    const match = first.match(headingLine) ?? (index === blocks.length - 1 && !rest.length ? first.match(partialHeading) : null);
    if (match) {
      steps.push({ title: (match[1] ?? match[2] ?? "").trim(), text: rest.join(" ").trim() });
      return;
    }
    const last = steps[steps.length - 1];
    if (last) last.text = last.text ? `${last.text}\n\n${block.replace(/\n/g, " ")}` : block.replace(/\n/g, " ");
    else steps.push({ text: block.replace(/\n/g, " ") });
  });
  return steps;
}

const paragraphs = (text: string) => text ? text.split(/\n{2,}/) : [];

/* Height changes share one critically damped spring; opacity takes a short tween. */
const heightSpring = { type: "spring", visualDuration: .26, bounce: 0 } as const;
const fold = (reduced: boolean): Transition => reduced ? { duration: 0 } : {
  height: heightSpring,
  opacity: { duration: motionTokens.duration.fast, ease: [...motionTokens.ease.standard] },
};
const swapIn = { duration: motionTokens.duration.fast, ease: [...motionTokens.ease.enter] } as const;
const swapOut = { duration: .1, ease: [...motionTokens.ease.standard] } as const;

/**
 * Renders text that only ever grows as a run of chunks. Each appended chunk fades in once; text already on screen
 * never re-renders its spans, so nothing flickers. When the text is replaced instead of extended it simply resets.
 */
function StreamText({ text, live, enter = false }: { text: string; live: boolean; enter?: boolean }) {
  const [state, setState] = useState(() => ({ text, cuts: [{ at: 0, fade: live && enter }] }));
  let current = state;
  if (state.text !== text) {
    const grew = live && text.length > state.text.length && text.startsWith(state.text);
    current = grew ? { text, cuts: [...state.cuts, { at: state.text.length, fade: true }] } : { text, cuts: [{ at: 0, fade: live && !state.text }] };
    setState(current);
  }
  return <>{current.cuts.map((cut, i) => {
    const slice = text.slice(cut.at, current.cuts[i + 1]?.at ?? text.length);
    return cut.fade ? <span key={i} className={styles.chunk}>{slice}</span> : <Fragment key={i}>{slice}</Fragment>;
  })}</>;
}

/**
 * The latest reasoning in a two line window. Short text sits at the top; longer text stays anchored to the bottom so the
 * newest words are always in view. When a new line wraps, the text glides up by one line instead of jumping.
 */
function LiveTail({ text, reduced }: { text: string; reduced: boolean }) {
  const slot = useRef<HTMLDivElement>(null);
  const tail = useRef<HTMLDivElement>(null);
  const y = useMotionValue(0);
  const [overflowing, setOverflowing] = useState(false);
  useEffect(() => {
    const box = slot.current, content = tail.current;
    if (!box || !content || typeof ResizeObserver === "undefined") return;
    let overflow = Math.max(0, content.offsetHeight - box.clientHeight);
    let width = content.offsetWidth;
    let controls: AnimationPlaybackControls | undefined;
    const observer = new ResizeObserver(() => {
      const next = Math.max(0, content.offsetHeight - box.clientHeight);
      const resized = content.offsetWidth !== width;
      width = content.offsetWidth;
      const shift = next - overflow;
      overflow = next;
      setOverflowing(next > 0);
      if (shift <= 0 || reduced || resized) return;
      controls?.stop();
      y.jump(y.get() + shift);
      /* Written now, inside the observer, so the frame that paints the new line already has it pushed down. */
      content.style.transform = `translateY(${y.get()}px)`;
      controls = animate(y, 0, { type: "spring", visualDuration: .24, bounce: 0 });
    });
    observer.observe(content);
    return () => { observer.disconnect(); controls?.stop(); };
  }, [reduced, y]);
  return <div ref={slot} className={styles.liveSlot} data-overflow={overflowing || undefined}>
    <motion.div ref={tail} className={styles.liveTail} style={{ y }}><StreamText text={text} live /></motion.div>
  </div>;
}

/** Counts up in tabular numerals; each new value rises in while the old one fades, inside a reserved width. */
function Counter({ seconds, reduced }: { seconds: number; reduced: boolean }) {
  const label = formatThinkingTime(seconds);
  return <span className={styles.counter} aria-hidden="true">
    <AnimatePresence initial={false}>
      <motion.span key={label} className={styles.counterValue}
        initial={reduced ? { opacity: 0 } : { opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0, transition: reduced ? { duration: 0 } : swapIn }}
        exit={reduced ? { opacity: 0, transition: { duration: 0 } } : { opacity: 0, y: -4, transition: swapOut }}>{label}</motion.span>
    </AnimatePresence>
  </span>;
}

/** Measures thinking time when the caller does not pass seconds. Restarts each time status turns thinking. */
function useThinkingSeconds(status: ReasoningStatus, seconds: number | undefined) {
  const [run, setRun] = useState<{ status: ReasoningStatus; elapsed?: number }>({ status, elapsed: status === "thinking" ? 0 : undefined });
  let current = run;
  if (run.status !== status) {
    current = { status, elapsed: status === "thinking" ? 0 : run.elapsed };
    setRun(current);
  }
  useEffect(() => {
    if (seconds !== undefined || status !== "thinking") return;
    const start = performance.now();
    const id = window.setInterval(() => {
      const elapsed = Math.floor((performance.now() - start) / 1000);
      setRun(prev => prev.elapsed === elapsed ? prev : { ...prev, elapsed });
    }, 250);
    return () => window.clearInterval(id);
  }, [status, seconds]);
  return seconds ?? current.elapsed;
}

type AutoPhase = "wait" | "stream" | "pause" | "settle" | "reveal" | "rest" | "hold" | "stopped";
interface AutoState { scene: number; step: number; words: number; ms: number; status: ReasoningStatus; phase: AutoPhase; open: boolean; touched: boolean }
const freshScene = (scene: number): AutoState => ({ scene, step: 0, words: 0, ms: 0, status: "thinking", phase: "wait", open: false, touched: false });
const sceneWords = reasoningSamples.map(sample => sample.steps.map(step => step.text.split(" ")));
const chunk = () => 3 + Math.floor(Math.random() * 6);

/**
 * The self-playing preview: think, stream four steps in fast chunks, collapse to "Thought for 4s", open to show the full
 * reasoning, close, then the next sample. Touching the block hands control to the viewer. Pauses off screen.
 */
function useAutoplay(enabled: boolean, running: boolean) {
  const [state, setState] = useState<AutoState>(() => freshScene(0));
  useEffect(() => {
    if (!enabled || !running) return;
    const s = state;
    const words = sceneWords[s.scene];
    const next = (scene: number) => freshScene((scene + 1) % reasoningSamples.length);
    let delay = 0;
    let apply: (prev: AutoState) => AutoState;
    switch (s.phase) {
      case "wait": delay = 900; apply = prev => ({ ...prev, phase: "stream", words: chunk() }); break;
      case "stream": {
        delay = 30 + Math.floor(Math.random() * 10);
        apply = prev => {
          const total = words[prev.step].length;
          const reached = Math.min(total, prev.words + chunk());
          if (reached < total) return { ...prev, words: reached };
          if (prev.step === words.length - 1) return { ...prev, words: reached, status: "done", phase: "settle" };
          return { ...prev, words: reached, phase: "pause" };
        };
        break;
      }
      case "pause": delay = 780; apply = prev => ({ ...prev, step: prev.step + 1, words: chunk(), phase: "stream" }); break;
      case "settle": delay = 1100; apply = prev => prev.touched ? { ...prev, phase: "hold" } : { ...prev, open: true, phase: "reveal" }; break;
      case "reveal": delay = 4600; apply = prev => prev.touched ? { ...prev, phase: "hold" } : { ...prev, open: false, phase: "rest" }; break;
      case "rest": delay = 900; apply = prev => prev.touched ? { ...prev, phase: "hold" } : next(prev.scene); break;
      case "hold": case "stopped":
        if (s.open) return;
        delay = s.phase === "stopped" ? 2800 : 2400; apply = prev => prev.open ? prev : next(prev.scene); break;
    }
    const id = window.setTimeout(() => setState(prev => {
      const updated = apply(prev);
      return prev.status === "thinking" ? { ...updated, ms: prev.ms + delay } : updated;
    }), delay);
    return () => window.clearTimeout(id);
  }, [enabled, running, state]);

  const sample = reasoningSamples[state.scene];
  const steps = useMemo(() => state.phase === "wait" ? [] : sample.steps.slice(0, state.step + 1).map((step, i) => i < state.step ? step : { title: step.title, text: sceneWords[state.scene][i].slice(0, state.words).join(" ") }),
    [sample, state.scene, state.step, state.words, state.phase]);
  return {
    steps, status: state.status, seconds: Math.floor(state.ms / 1000), open: state.open, model: sample.model, scene: state.scene,
    toggle: () => setState(prev => ({ ...prev, open: !prev.open, touched: true })),
    stop: () => setState(prev => prev.status === "thinking" ? { ...prev, status: "stopped", phase: "stopped" } : prev),
  };
}

/**
 * The collapsible thinking block of an AI reply. While the model thinks, a shimmering "Thinking" label counts the
 * seconds and the latest reasoning streams under it in muted text. When it finishes the block collapses to
 * "Thought for 7s", and opening it shows the full reasoning as steps with headings. With no props it plays a simulation.
 */
export function ReasoningBlock({ reasoning, status: statusProp, seconds: secondsProp, model: modelProp, open: openProp, defaultOpen = false, onOpenChange, onStop, onRetry, error, variant = "card", title, className }: ReasoningBlockProps) {
  const rootRef = useRef<HTMLDivElement>(null);
  const reduced = useReducedMotion() ?? false;
  const inView = useInView(rootRef, { margin: "80px" });
  const pageVisible = usePageInView();
  const auto = reasoning === undefined && statusProp === undefined;
  const play = useAutoplay(auto, inView && pageVisible);
  const id = useId();
  const labelId = `${id}-label`, panelId = `${id}-panel`;

  const parsed = useMemo(() => parseReasoning(reasoning), [reasoning]);
  const status: ReasoningStatus = auto ? play.status : statusProp ?? "done";
  const measured = useThinkingSeconds(status, secondsProp);
  const seconds = auto ? play.seconds : measured;
  const steps = auto ? play.steps : parsed;
  const model = auto ? { name: play.model } : modelProp ?? defaultModel;

  const [openState, setOpenState] = useState(defaultOpen);
  const open = auto ? play.open : openProp ?? openState;
  const expandable = steps.length > 0;
  const thinking = status === "thinking";
  const toggle = () => {
    if (!expandable) return;
    if (auto) { play.toggle(); return; }
    if (openProp === undefined) setOpenState(!open);
    onOpenChange?.(!open);
  };
  const stop = auto ? play.stop : onStop;

  const current = steps[steps.length - 1];
  const tailText = current ? current.text || current.title || "" : "";
  const showTail = thinking && !open && Boolean(tailText);

  // A title names what the block says (a finished block that is not a model's thinking), so it has no thinking time to announce.
  const announce = status === "thinking" ? `${model.name} is thinking`
    : status === "done" ? (title ? "" : seconds !== undefined ? `Thought for ${spokenTime(seconds)}` : "Finished thinking")
    : status === "stopped" ? "Stopped thinking" : "Thinking interrupted";

  const label = status === "thinking"
    ? <><TextShimmer className={styles.shimmer}>Thinking</TextShimmer>{seconds !== undefined ? <Counter seconds={seconds} reduced={reduced} /> : null}</>
    : status === "done" ? <span className={styles.labelText}>{title ?? (seconds !== undefined ? `Thought for ${formatThinkingTime(Math.max(1, seconds))}` : "Thought process")}</span>
    : status === "stopped" ? <span className={styles.labelText}>{seconds ? `Stopped after ${formatThinkingTime(seconds)}` : "Stopped thinking"}</span>
    : <><CircleAlert className={styles.alert} width={16} height={16} aria-hidden="true" /><span className={styles.labelText}>Thinking interrupted</span></>;

  return <div ref={rootRef} role="group" aria-label={title ?? `${model.name} reasoning`} className={cx(styles.root, className)} data-variant={variant} data-status={status} data-open={open || undefined}>
    <div className={styles.top} data-expandable={expandable || undefined}>
      {expandable ? <button type="button" className={styles.toggle} aria-expanded={open} aria-controls={panelId} aria-labelledby={labelId} onClick={toggle} /> : null}
      <div className={styles.head}>
        <span className={styles.mark} aria-hidden="true">{model.mark}</span>
        <span className={styles.label} id={labelId}>
          <AnimatePresence initial={false} mode="popLayout">
            <motion.span key={status} className={styles.labelInner}
              initial={{ opacity: 0, y: reduced ? 0 : 2 }} animate={{ opacity: 1, y: 0, transition: reduced ? { duration: 0 } : swapIn }}
              exit={{ opacity: 0, transition: reduced ? { duration: 0 } : swapOut }}>{label}</motion.span>
          </AnimatePresence>
        </span>
        <span className={styles.actions}>
          <AnimatePresence initial={false} mode="popLayout">
            {thinking && stop ? <motion.span key="stop" initial={{ opacity: 0 }} animate={{ opacity: 1, transition: swapIn }} exit={{ opacity: 0, transition: swapOut }}>
              <Button variant="ghost" size="sm" className={styles.action} onClick={stop}><StopSquare size={10} />Stop</Button>
            </motion.span> : null}
            {status === "error" && onRetry ? <motion.span key="retry" initial={{ opacity: 0 }} animate={{ opacity: 1, transition: swapIn }} exit={{ opacity: 0, transition: swapOut }}>
              <Button variant="secondary" size="sm" className={styles.action} onClick={onRetry}>Retry</Button>
            </motion.span> : null}
          </AnimatePresence>
        </span>
        {expandable ? <ChevronDown className={styles.chevron} width={16} height={16} aria-hidden="true" /> : <span aria-hidden="true" />}
      </div>
      <AnimatePresence initial={false}>
        {showTail ? <motion.div key="tail" className={styles.liveClip} aria-hidden="true"
          initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0, transition: reduced ? { duration: 0 } : { height: heightSpring, opacity: swapOut } }} transition={fold(reduced)}>
          <div className={styles.live}>
            <AnimatePresence initial={false}>
              <motion.div key={`${auto ? play.scene : 0}-${steps.length}`} className={styles.liveLayer}
                initial={{ opacity: 0 }} animate={{ opacity: 1, transition: reduced ? { duration: 0 } : swapIn }} exit={{ opacity: 0, transition: reduced ? { duration: 0 } : swapOut }}>
                <LiveTail text={tailText} reduced={reduced} />
              </motion.div>
            </AnimatePresence>
          </div>
        </motion.div> : null}
      </AnimatePresence>
    </div>

    <AnimatePresence initial={false}>
      {open && expandable ? <motion.div key="panel" id={panelId} role="region" aria-labelledby={labelId} aria-busy={thinking || undefined} className={styles.panelClip}
        initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0, transition: reduced ? { duration: 0 } : { height: heightSpring, opacity: swapOut } }} transition={fold(reduced)}>
        <Thoughts steps={steps} status={status} error={error} reduced={reduced} />
      </motion.div> : null}
    </AnimatePresence>

    <span className={styles.srOnly} role="status" aria-live="polite">{auto ? `${announce}. Simulated, nothing was sent to a model.` : announce}</span>
  </div>;
}

/**
 * The full reasoning: a quiet rail under the mark, a dot per step, headings and calm paragraphs. The panel's own fade
 * covers everything present when it opens; only what streams in afterwards (a new step, a new paragraph, a chunk)
 * fades on its own, so nothing animates twice.
 */
function Thoughts({ steps, status, error, reduced }: { steps: ReasoningStep[]; status: ReasoningStatus; error?: string; reduced: boolean }) {
  const thinking = status === "thinking";
  const [opened] = useState(() => steps.map(step => paragraphs(step.text).length));
  return <div className={styles.panel}>
    <ol className={styles.steps}>
      {steps.map((step, i) => {
        const isCurrent = thinking && i === steps.length - 1;
        const fresh = thinking && i >= opened.length;
        return <li key={i} className={styles.step} data-current={isCurrent || undefined}>
          <span className={cx(styles.dot, fresh && styles.chunk)} aria-hidden="true" />
          {step.title ? <h4 className={cx(styles.stepTitle, fresh && styles.chunk)}>{step.title}</h4> : null}
          {paragraphs(step.text).map((text, p) => <p key={p} className={styles.para}><StreamText text={text} live={thinking} enter={fresh || p >= (opened[i] ?? 0)} /></p>)}
        </li>;
      })}
    </ol>
    <AnimatePresence initial={false}>
      {!thinking && status !== "done" ? <motion.div key={status} className={styles.foot} data-status={status} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={reduced ? { duration: 0 } : swapIn}>
        <span className={styles.footIcon} aria-hidden="true">
          {status === "stopped" ? <StopSquare size={9} /> : <CircleAlert width={14} height={14} />}
        </span>
        <span className={styles.footText}>{status === "stopped" ? "Stopped before finishing" : error ?? "The connection dropped before the model finished."}</span>
      </motion.div> : null}
    </AnimatePresence>
  </div>;
}

export default ReasoningBlock;
