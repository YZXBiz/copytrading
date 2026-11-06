"use client";

import { useLayoutEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { AnimatePresence, motion } from "motion/react";
import { BotIcon } from "@/components/icons/BotIcon";
import { TriangleAlertIcon } from "@/components/icons/TriangleAlertIcon";
import { motionTokens } from "../../lib/motion-tokens";
import styles from "./agent-approvals.module.css";

type Bezier = [number, number, number, number];
export const easeOut = [...motionTokens.ease.enter] as Bezier;
/** Height and position moves: critically damped and quick, so nothing that travels or resizes overshoots. */
export const glide = { type: "spring", visualDuration: .3, bounce: 0 } as const;
export const fadeIn = { duration: motionTokens.duration.fast, ease: easeOut };
export const fadeOut = { duration: .1, ease: [...motionTokens.ease.standard] as Bezier };

const cx = (...names: (string | false | undefined)[]) => names.filter(Boolean).join(" ");

/** Whoever asked. */
export function AskerMark({ className }: { className?: string }) {
  return <BotIcon className={cx(styles.mark, className)} width={16} height={16} aria-hidden="true" />;
}

/** A request that could touch real money says so with an icon in the warning color and a word, never color alone. */
export function LiveTag({ long = false }: { long?: boolean }) {
  return <span className={styles.risk}>
    <TriangleAlertIcon width={16} height={16} aria-hidden="true" />
    <span>Live<span className={long ? styles.riskWord : styles.srOnly}> account</span></span>
  </span>;
}

/** One minimal crossfade for a label or icon that changes: the old one fades out fast while the new one fades in. */
export function Swap({ id, children, reduced, className }: { id: string; children: ReactNode; reduced: boolean; className?: string }) {
  return <span className={cx(styles.swap, className)}>
    <AnimatePresence initial={false} mode="popLayout">
      <motion.span key={id} className={styles.swapItem} initial={{ opacity: 0, y: reduced ? 0 : 2 }} animate={{ opacity: 1, y: 0, transition: reduced ? { duration: 0 } : fadeIn }} exit={{ opacity: 0, transition: reduced ? { duration: 0 } : fadeOut }}>
        {children}
      </motion.span>
    </AnimatePresence>
  </span>;
}

/**
 * Follows its content's height on a critically damped spring, so swapping content never resizes in one frame.
 * The 4px inset keeps keyboard focus outlines inside the clip.
 */
export function AutoHeight({ children, reduced, className, innerClassName }: { children: ReactNode; reduced: boolean; className?: string; innerClassName?: string }) {
  const inner = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState<number | "auto">("auto");
  useLayoutEffect(() => {
    const node = inner.current;
    if (!node || typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(([entry]) => { if (entry) setHeight(entry.borderBoxSize?.[0]?.blockSize ?? node.offsetHeight); });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  return <motion.div className={cx(styles.autoHeight, className)} initial={false} animate={{ height }} transition={reduced ? { duration: 0 } : glide}>
    <div ref={inner} className={cx(styles.autoHeightInner, innerClassName)}>{children}</div>
  </motion.div>;
}
