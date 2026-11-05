"use client";

import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { KeyboardEvent, ReactNode } from "react";
import { AnimatePresence, LayoutGroup, animate, motion, useMotionValue, useReducedMotion } from "motion/react";
import type { Variants } from "motion/react";
import type { Icon } from "@/lib/icon";
import { motionTokens } from "../../lib/motion-tokens";
import styles from "./settings-page.module.css";

export type SettingsSection = { id: string; label: string; description: string; icon: Icon; /** How many edits in this section are not saved yet. */ pending?: number };
type Shift = { direction: number; axis: "x" | "y"; reduce: boolean };

const blur = (px: number) => `blur(${px}px)`;
const enterEase = [...motionTokens.ease.enter] as [number, number, number, number];
const standardEase = [...motionTokens.ease.standard] as [number, number, number, number];

/** Sections cross over along the nav's own axis: a later section arrives from below (or the right on phones), an earlier one from above. */
const pane: Variants = {
  enter: ({ direction, axis, reduce }: Shift) => reduce ? { opacity: 0 } : { opacity: 0, ...(axis === "x" ? { x: direction * 16 } : { y: direction * 14 }), filter: blur(motionTokens.blur.subtle) },
  center: ({ reduce }: Shift) => ({ opacity: 1, x: 0, y: 0, filter: blur(0), transition: reduce ? { duration: motionTokens.duration.instant } : { x: motionTokens.spring.smooth, y: motionTokens.spring.smooth, opacity: { duration: motionTokens.duration.standard, ease: enterEase }, filter: { duration: motionTokens.duration.standard, ease: enterEase } } }),
  exit: ({ direction, axis, reduce }: Shift) => reduce ? { opacity: 0, transition: { duration: motionTokens.duration.instant } } : { opacity: 0, ...(axis === "x" ? { x: direction * -10 } : { y: direction * -8 }), filter: blur(motionTokens.blur.subtle), transition: { duration: motionTokens.duration.fast, ease: standardEase } },
};
const rise = { initial: { opacity: 0, y: 6, filter: blur(motionTokens.blur.soft) }, animate: { opacity: 1, y: 0, filter: blur(0) }, exit: { opacity: 0, y: -4, filter: blur(motionTokens.blur.subtle) } };


/** The bar grows out of a small puck, then its width and height follow whatever it holds, so saving shrinks it into a confirmation. */
export function SaveBar({ children, label }: { children: ReactNode; label: string }) {
  const reduce = useReducedMotion();
  const content = useRef<HTMLDivElement>(null);
  const width = useMotionValue(52);
  const height = useMotionValue(52);
  useLayoutEffect(() => {
    const node = content.current;
    if (!node) return;
    const measure = () => {
      const next = { width: node.offsetWidth + 2, height: node.offsetHeight + 2 };
      if (reduce) { width.jump(next.width); height.jump(next.height); return; }
      animate(width, next.width, motionTokens.spring.morph);
      animate(height, next.height, motionTokens.spring.morph);
    };
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, [height, reduce, width]);
  const phase = reduce ? { initial: { opacity: 0 }, animate: { opacity: 1 }, exit: { opacity: 0 } } : { initial: { opacity: 0, scale: .96, filter: blur(motionTokens.blur.soft) }, animate: { opacity: 1, scale: 1, filter: blur(0) }, exit: { opacity: 0, scale: .96, filter: blur(motionTokens.blur.soft) } };
  const phaseTransition = { duration: reduce ? motionTokens.duration.instant : motionTokens.duration.standard, ease: enterEase };
  return <motion.div className={styles.bar} role="group" aria-label={label} style={{ width, height }}
    initial={reduce ? { opacity: 0 } : { opacity: 0, y: 28, filter: blur(motionTokens.blur.soft) }} animate={{ opacity: 1, y: 0, filter: blur(0) }}
    exit={reduce ? { opacity: 0, transition: { duration: motionTokens.duration.instant } } : { opacity: 0, y: 20, width: 52, height: 52, filter: blur(motionTokens.blur.soft), transition: { width: motionTokens.spring.smooth, height: motionTokens.spring.smooth, y: { ...motionTokens.spring.smooth, delay: .06 }, opacity: { duration: motionTokens.duration.exit, delay: .1 }, filter: { duration: motionTokens.duration.exit, delay: .1 } } }}
    transition={reduce ? { duration: motionTokens.duration.instant } : { y: motionTokens.spring.smooth, opacity: { duration: motionTokens.duration.fast }, filter: { duration: motionTokens.duration.standard } }}>
    <div ref={content} className={styles.barContent}>
      <motion.div className={styles.barEdit} {...phase} transition={phaseTransition}>{children}</motion.div>
    </div>
  </motion.div>;
}

const SHIFT_AXIS = (list: HTMLElement | null) => (list && getComputedStyle(list).flexDirection === "row" ? "x" : "y") as "x" | "y";

/** The settings layout: sections listed on the left with a highlight that glides between them, the selected section's page beside it, and a bar that floats up over the page while there is something to save. */
export function SettingsFrame({ sections, section, onSectionChange, bar, status, children }: { sections: SettingsSection[]; section: string; onSectionChange: (id: string) => void; bar: ReactNode; status?: string; children: ReactNode }) {
  const reduce = useReducedMotion();
  const [shift, setShift] = useState<Omit<Shift, "reduce">>({ direction: 1, axis: "y" });
  const navList = useRef<HTMLUListElement>(null);
  const navButtons = useRef<(HTMLButtonElement | null)[]>([]);
  const scroller = useRef<HTMLDivElement>(null);
  const shown = useRef(section);
  const current = sections.find(item => item.id === section) ?? sections[0];
  const custom: Shift = { ...shift, reduce: !!reduce };

  // The page moves along the nav's own axis, whichever way the section changed (a link, a shortcut or a key press).
  useEffect(() => {
    if (shown.current === section) return;
    const from = sections.findIndex(item => item.id === shown.current), to = sections.findIndex(item => item.id === section);
    setShift({ direction: to > from ? 1 : -1, axis: SHIFT_AXIS(navList.current) });
    shown.current = section;
  }, [section, sections]);

  function onNavKey(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    const steps: Record<string, number> = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 };
    const next = event.key in steps ? (index + steps[event.key] + sections.length) % sections.length : event.key === "Home" ? 0 : event.key === "End" ? sections.length - 1 : -1;
    if (next < 0) return;
    event.preventDefault();
    navButtons.current[next]?.focus();
    onSectionChange(sections[next].id);
  }

  return (
    <section className={styles.root}>
      <div className={styles.settings}>
        <aside className={styles.sidebar}>
          <LayoutGroup id="settings-nav">
            <nav aria-label="Settings sections">
              <motion.ul ref={navList} className={styles.navList} layoutScroll>
                {sections.map((item, index) => {
                  const Icon = item.icon, pending = item.pending ?? 0;
                  return <li key={item.id}>
                    <button ref={node => { navButtons.current[index] = node; }} type="button" className={styles.navItem} aria-current={section === item.id ? "page" : undefined} onClick={() => onSectionChange(item.id)} onKeyDown={event => onNavKey(event, index)}>
                      {section === item.id && <motion.span layoutId="settings-section" layoutDependency={section} className={styles.highlight} transition={reduce ? { duration: 0 } : motionTokens.spring.morph} aria-hidden="true" />}
                      <Icon width={16} height={16} aria-hidden="true" />
                      <span className={styles.navLabel}>{item.label}</span>
                      <AnimatePresence initial={false}>{pending > 0 && <motion.span key="dot" className={styles.navDot} aria-hidden="true" initial={{ opacity: 0, scale: .2 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: .2 }} transition={reduce ? { duration: 0 } : motionTokens.spring.snappy} />}</AnimatePresence>
                      {pending > 0 && <span className={styles.srOnly}>, {pending} unsaved</span>}
                    </button>
                  </li>;
                })}
              </motion.ul>
            </nav>
          </LayoutGroup>
        </aside>

        <div className={styles.main}>
          <div ref={scroller} className={styles.scroller} role="region" aria-labelledby="settings-heading">
            <AnimatePresence mode="wait" initial={false} custom={custom} onExitComplete={() => scroller.current?.scrollTo({ top: 0 })}>
              <motion.div key={section} className={styles.pane} custom={custom} variants={pane} initial="enter" animate="center" exit="exit">
                <header className={styles.paneHead}>
                  <h2 id="settings-heading">{current.label}</h2>
                  <p>{current.description}</p>
                </header>
                {children}
              </motion.div>
            </AnimatePresence>
          </div>
          <div className={styles.dock}>
            <AnimatePresence>{bar}</AnimatePresence>
          </div>
          <p className={styles.srOnly} role="status" aria-live="polite">{status}</p>
        </div>
      </div>
    </section>
  );
}
