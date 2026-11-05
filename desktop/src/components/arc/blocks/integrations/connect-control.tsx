"use client";

import { useEffect, useState } from "react";
import type { Ref } from "react";
import { AnimatePresence, animate, motion, useIsPresent, useMotionValue } from "motion/react";
import type { AnimationPlaybackControls, HTMLMotionProps, TargetAndTransition, Transition } from "motion/react";
import { Add01Icon as Plus } from "../../../icons/Add01Icon";
import { motionTokens } from "../../lib/motion-tokens";
import styles from "./integrations.module.css";

export type ConnectStatus = "idle" | "connecting" | "connected";
const phaseLabel = { connecting: "Checking", connected: "Connected" } as const;
const enter = [...motionTokens.ease.enter] as [number, number, number, number];
const standard = [...motionTokens.ease.standard] as [number, number, number, number];
const quick: Transition = { duration: motionTokens.duration.instant };
const fadeOut: TargetAndTransition = { opacity: 0, transition: quick };
const shown: TargetAndTransition = { opacity: 1, x: 0, y: 0, scale: 1, filter: "blur(0px)" };
const textIn: TargetAndTransition = { opacity: 0, y: "0.35em", filter: `blur(${motionTokens.blur.soft}px)` };
const textOut: TargetAndTransition = { opacity: 0, y: "-0.3em", filter: `blur(${motionTokens.blur.subtle}px)`, transition: { duration: motionTokens.duration.fast, ease: standard } };
const textEnter: Transition = { duration: motionTokens.duration.standard, ease: enter };
/** Outgoing copies are hidden from assistive tech while they leave, so only the current text is read. */
function Swap(props: HTMLMotionProps<"span">) {
  const present = useIsPresent();
  return <motion.span {...props} aria-hidden={present ? props["aria-hidden"] : true} />;
}

/** Changing text rises in with a small blur while the old copy lifts away. */

/** The tick draws itself once the connection lands. */
function DrawnCheck({ reduce }: { reduce: boolean }) {
  return <svg width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.25} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <motion.path d="M5 12.5l4.5 4.5L19 7.5" initial={reduce ? false : { pathLength: 0, opacity: 0 }} animate={{ pathLength: 1, opacity: 1 }} transition={{ pathLength: { duration: .34, ease: enter, delay: .1 }, opacity: { duration: .05, delay: .1 } }} />
  </svg>;
}


/** Springs the label slot to the width of each new phase, so the control morphs instead of snapping. Passive resizes, like a late web font, follow at once. */
function useMorphWidth(reduce: boolean) {
  const width = useMotionValue<number | "auto">("auto");
  const [node, setNode] = useState<HTMLSpanElement | null>(null);
  useEffect(() => {
    if (!node || typeof ResizeObserver === "undefined") return;
    let phase: string | null = null;
    let sizing: AnimationPlaybackControls | undefined;
    const observer = new ResizeObserver(([entry]) => {
      const next = entry?.borderBoxSize?.[0]?.inlineSize ?? node.offsetWidth;
      const morph = phase !== null && phase !== node.dataset.phase && !reduce && typeof width.get() === "number";
      phase = node.dataset.phase ?? null;
      sizing?.stop();
      if (morph) sizing = animate(width, next, motionTokens.spring.morph);
      else width.jump(next);
    });
    observer.observe(node);
    return () => { observer.disconnect(); sizing?.stop(); };
  }, [node, reduce, width]);
  return [width, setNode] as const;
}


/** Connect morphs through Connecting into Connected. The pill keeps one shape the whole way; only its width, icon, label, and tint change. */
export function ConnectControl({ name, status, reduce, onConnect, buttonRef, idleLabel = "Connect" }: { name: string; status: ConnectStatus; reduce: boolean; onConnect: () => void; buttonRef?: Ref<HTMLButtonElement>; /** What an idle control offers: Connect the first time, Check again after a result. */ idleLabel?: string }) {
  const [width, measure] = useMorphWidth(reduce);
  const icon = status === "idle" ? <Plus width={16} height={16} aria-hidden="true" /> : status === "connecting" ? <span className={styles.spinner} aria-hidden="true" /> : <DrawnCheck reduce={reduce} />;
  return <motion.div className={styles.connect} data-status={status} whileTap={status === "idle" && !reduce ? { scale: .97 } : undefined} transition={motionTokens.spring.snappy}>
    <motion.span className={styles.connectSlot} style={{ width }}>
      <span ref={measure} className={styles.connectContent} data-phase={status} aria-hidden={status === "connected" ? undefined : true}>
        <AnimatePresence mode="popLayout" initial={false}>
          <Swap key={status} className={styles.connectPhase} initial={reduce ? { opacity: 0 } : textIn} animate={shown} exit={reduce ? fadeOut : textOut} transition={reduce ? quick : textEnter}>
            <span className={styles.phaseIcon}>{icon}</span>{status === "idle" ? idleLabel : phaseLabel[status]}
          </Swap>
        </AnimatePresence>
      </span>
    </motion.span>
    {status !== "connected" ? <button ref={buttonRef} type="button" className={styles.connectHit} aria-label={status === "connecting" ? `Checking ${name}` : `${idleLabel} ${name}`} aria-busy={status === "connecting" || undefined} onClick={() => { if (status === "idle") onConnect(); }} /> : null}
  </motion.div>;
}
