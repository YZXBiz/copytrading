"use client";

import { createContext, useCallback, useContext, useEffect, useId, useState, type ReactElement, type ReactNode } from "react";
import * as TooltipPrimitive from "@radix-ui/react-tooltip";
import { LayoutGroup, motion, useReducedMotion, type Transition } from "motion/react";
import type { Icon } from "@/lib/icon";
import { Tooltip } from "../../tooltip/tooltip";
import { motionTokens } from "../../lib/motion-tokens";
import styles from "./sidebar-rail.module.css";

const FULL = 240;
const RAIL = 64;

export type RailEntry = {
  id: string;
  label: string;
  /** Where the row goes. A row with `onSelect` instead does something here, such as opening search. */
  href?: string;
  onSelect?: () => void;
  icon: Icon;
  /** A figure set at the row's right edge, such as a balance. It is read with the label and folds away in the rail. */
  value?: string;
};
export type RailSection = {
  id: string;
  heading?: string;
  items: RailEntry[];
  /** Shown in place of the items while they load, fail or are missing. It folds away in the rail. */
  note?: ReactNode;
};
export type RailStatus = {
  /** The mark that sits on the icon axis, such as a dot. */
  marker: ReactNode;
  text: string;
  /** A second, quieter line. */
  note?: string;
  /** What a long reason or problem reads in full. */
  title?: string;
  /** The text is a sentence, so it wraps instead of cutting off. */
  sentence?: boolean;
};

const curve = (points: readonly number[]) => [...points] as [number, number, number, number];
const instant: Transition = { duration: 0 };

/** Labels leave quickly so they are gone a beat before the rail settles, and return a beat after the width starts opening. */
function labelTiming(collapsed: boolean, reduce: boolean): Transition {
  if (reduce) return instant;
  return collapsed ? { duration: .14, ease: curve(motionTokens.ease.standard) } : { duration: .24, delay: .1, ease: curve(motionTokens.ease.enter) };
}

/** Rail-only marks (dividers) arrive once the labels have cleared, and leave first when the rail opens. */
function markTiming(collapsed: boolean, reduce: boolean): Transition {
  if (reduce) return instant;
  return collapsed ? { duration: .2, delay: .16, ease: curve(motionTokens.ease.enter) } : { duration: .1, ease: curve(motionTokens.ease.standard) };
}

type RailState = { collapsed: boolean; reduce: boolean; sidebarId: string; toggle: () => void; fold: () => void };
const RailContext = createContext<RailState | null>(null);

/** The rail's state for the page beside it: the toggle in the top bar, and a way to fold the rail to make room. */
export function useSidebarRail() {
  const state = useContext(RailContext);
  if (!state) throw new Error("Render rail controls inside <SidebarRail>.");
  return state;
}

function RailTip({ enabled, label, note, children }: { enabled: boolean; label: string; note?: string; children: ReactElement }) {
  const [open, setOpen] = useState(false);
  // Closing the rail while a tip is open should not leave it armed for the next collapse.
  if (!enabled && open) setOpen(false);
  return <TooltipPrimitive.Root open={enabled && open} onOpenChange={next => setOpen(next && enabled)}>
    <TooltipPrimitive.Trigger asChild>{children}</TooltipPrimitive.Trigger>
    <TooltipPrimitive.Portal>
      <TooltipPrimitive.Content className={styles.tip} side="right" sideOffset={14} collisionPadding={8}>{label}{note && <span className={styles.tipNote}>{note}</span>}</TooltipPrimitive.Content>
    </TooltipPrimitive.Portal>
  </TooltipPrimitive.Root>;
}

type RowProps = { entry: RailEntry; current: boolean; collapsed: boolean; reduce: boolean };

function NavRow({ entry, current, collapsed, reduce }: RowProps) {
  const Icon = entry.icon;
  const fade = labelTiming(collapsed, reduce);
  const content = <>
    {current && <motion.span layoutId="rail-active" className={styles.highlight} style={{ borderRadius: 8 }} transition={reduce ? instant : motionTokens.spring.morph} />}
    <Icon className={styles.icon} width={16} height={16} aria-hidden="true" />
    <motion.span className={styles.label} initial={false} animate={{ opacity: collapsed ? 0 : 1, x: collapsed ? -6 : 0 }} transition={fade}>{entry.label}{entry.value ? <span className={styles.srOnly}>, {entry.value}</span> : null}</motion.span>
    {entry.value ? <motion.span className={styles.count} aria-hidden="true" initial={false} animate={{ opacity: collapsed ? 0 : 1 }} transition={fade}>{entry.value}</motion.span> : null}
  </>;
  const className = [styles.item, current ? styles.lit : ""].join(" ");
  return <RailTip enabled={collapsed} label={entry.label} note={entry.value}>
    {entry.href !== undefined
      ? <a href={entry.href} className={className} aria-current={current ? "page" : undefined}>{content}</a>
      : <button type="button" className={className} onClick={entry.onSelect}>{content}</button>}
  </RailTip>;
}

type NavProps = { label: string; sections: RailSection[]; footer: RailEntry[]; active: string | null; collapsed: boolean; reduce: boolean };

function Navigation({ label, sections, footer, active, collapsed, reduce }: NavProps) {
  const baseId = useId();
  const fade = labelTiming(collapsed, reduce);
  const mark = markTiming(collapsed, reduce);
  const height = reduce ? instant : motionTokens.spring.smooth;
  const shared = { collapsed, reduce };
  return <motion.nav className={styles.nav} aria-label={label} layoutScroll>
    {sections.map(section => {
      const headingId = `${baseId}-${section.id}`;
      return <div key={section.id} className={styles.section} role={section.heading ? "group" : undefined} aria-labelledby={section.heading ? headingId : undefined}>
        {section.heading && <motion.div className={styles.heading} initial={false} animate={{ height: collapsed ? 17 : 32 }} transition={height}>
          <motion.span id={headingId} className={styles.headingText} initial={false} animate={{ opacity: collapsed ? 0 : 1, x: collapsed ? -6 : 0 }} transition={fade}>{section.heading}</motion.span>
          <motion.span className={styles.divider} aria-hidden="true" initial={false} animate={{ opacity: collapsed ? 1 : 0, scaleX: collapsed ? 1 : .3 }} transition={mark} />
        </motion.div>}
        {section.items.length > 0 && <ul className={styles.list} role="list">
          {section.items.map(entry => <li key={entry.id}><NavRow entry={entry} current={active === entry.id} {...shared} /></li>)}
        </ul>}
        {section.note && !collapsed && <div className={styles.note}>{section.note}</div>}
      </div>;
    })}
    <ul className={`${styles.list} ${styles.footerList}`} role="list">
      {footer.map(entry => <li key={entry.id}><NavRow entry={entry} current={active === entry.id} {...shared} /></li>)}
    </ul>
  </motion.nav>;
}

function Brand({ name, mark, collapsed, reduce }: { name: string; mark: ReactNode; collapsed: boolean; reduce: boolean }) {
  return <div className={styles.brand}>
    <span className={styles.mark} aria-hidden="true">{mark}</span>
    <motion.span className={styles.stack} initial={false} animate={{ opacity: collapsed ? 0 : 1, x: collapsed ? -6 : 0 }} transition={labelTiming(collapsed, reduce)}><strong>{name}</strong></motion.span>
  </div>;
}

function Status({ status, collapsed, reduce }: { status: RailStatus; collapsed: boolean; reduce: boolean }) {
  const body = <div className={styles.profile} role="status" title={status.title}>
    <span className={styles.marker} aria-hidden="true">{status.marker}</span>
    <motion.span className={`${styles.stack} ${status.sentence ? styles.sentence : ""}`} initial={false} animate={{ opacity: collapsed ? 0 : 1, x: collapsed ? -6 : 0 }} transition={labelTiming(collapsed, reduce)}>
      <strong>{status.text}</strong>
      {status.note && <span>{status.note}</span>}
    </motion.span>
  </div>;
  return <RailTip enabled={collapsed} label={status.title ?? status.text}>{body}</RailTip>;
}

/** The divider in the panel icon slides with the sidebar, so the control shows what it is about to do. */
function PanelGlyph({ collapsed, reduce }: { collapsed: boolean; reduce: boolean }) {
  return <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden="true">
    <rect x="2.75" y="3.75" width="14.5" height="12.5" rx="3.5" />
    <motion.path d="M8.25 4.25v11.5" initial={false} animate={{ x: collapsed ? -2.5 : 0 }} transition={reduce ? instant : motionTokens.spring.smooth} />
  </svg>;
}

/** The top bar of the page beside the rail: the rail toggle, the screen's title, and the page's own controls at the right. */
export function RailTopbar({ title, end }: { title?: string; end?: ReactNode }) {
  const { collapsed, reduce, sidebarId, toggle } = useSidebarRail();
  return <header className={styles.topbar}>
    <Tooltip side="bottom" content={<span className={styles.shortcut}>{collapsed ? "Expand sidebar" : "Collapse sidebar"}<kbd>⌘</kbd><kbd>B</kbd></span>}>
      <button type="button" className={styles.iconButton} aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"} aria-expanded={!collapsed} aria-controls={sidebarId} aria-keyshortcuts="Meta+B" onClick={toggle}><PanelGlyph collapsed={collapsed} reduce={reduce} /></button>
    </Tooltip>
    {title && <p className={styles.title}>{title}</p>}
    <div className={styles.end}>{end}</div>
  </header>;
}

export interface SidebarRailProps {
  /** The navigation landmark's name. */
  label: string;
  brand: { name: string; mark: ReactNode };
  sections: RailSection[];
  /** Entries pinned to the bottom, above the status. */
  footer: RailEntry[];
  /** The id of the entry whose page is open, if any. */
  active: string | null;
  status: RailStatus;
  /** The page beside the rail. It renders a `RailTopbar` itself. */
  children: ReactNode;
}

export function SidebarRail({ label, brand, sections, footer, active, status, children }: SidebarRailProps) {
  const sidebarId = useId();
  const reduce = !!useReducedMotion();
  const [collapsed, setCollapsed] = useState(false);
  const [announce, setAnnounce] = useState("");

  const set = useCallback((next: boolean) => {
    setCollapsed(next);
    setAnnounce(next ? "Sidebar collapsed" : "Sidebar expanded");
  }, []);
  const toggle = useCallback(() => set(!collapsed), [collapsed, set]);
  const fold = useCallback(() => set(true), [set]);

  // ⌘B and [ toggle the rail. [ stays out of text fields.
  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.defaultPrevented || event.altKey || event.shiftKey) return;
      const command = (event.key === "b" || event.key === "B") && event.metaKey && !event.ctrlKey;
      const bracket = event.key === "[" && !event.metaKey && !event.ctrlKey;
      if (!command && !bracket) return;
      const target = event.target as HTMLElement | null;
      if (bracket && target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
      event.preventDefault();
      toggle();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [toggle]);

  const width = collapsed ? RAIL : FULL;
  return <RailContext.Provider value={{ collapsed, reduce, sidebarId, toggle, fold }}>
    <LayoutGroup id={sidebarId}>
      <TooltipPrimitive.Provider delayDuration={250} skipDelayDuration={300}>
        <div className={styles.shell}>
          {/* The slot holds the sidebar's place in the row. */}
          <motion.div className={styles.slot} initial={false} animate={{ width }} transition={reduce ? instant : motionTokens.spring.smooth}>
            <motion.div id={sidebarId} className={styles.sidebar} initial={false} animate={{ width }} transition={reduce ? instant : motionTokens.spring.smooth} data-collapsed={collapsed || undefined}>
              {/* The window's traffic lights sit here, and the strip drags the window. */}
              <div className={styles.drag} aria-hidden="true" />
              <Brand name={brand.name} mark={brand.mark} collapsed={collapsed} reduce={reduce} />
              <Navigation label={label} sections={sections} footer={footer} active={active} collapsed={collapsed} reduce={reduce} />
              <Status status={status} collapsed={collapsed} reduce={reduce} />
            </motion.div>
          </motion.div>
          <div className={styles.main}>{children}</div>
          <p className={styles.srOnly} role="status" aria-live="polite">{announce}</p>
        </div>
      </TooltipPrimitive.Provider>
    </LayoutGroup>
  </RailContext.Provider>;
}

export default SidebarRail;
