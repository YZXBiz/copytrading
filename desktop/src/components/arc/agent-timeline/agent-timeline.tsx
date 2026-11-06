"use client";

import { Fragment, memo, useCallback, useEffect, useId, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import type { CSSProperties, KeyboardEvent as ReactKeyboardEvent, ReactNode, RefObject } from "react";
import { AnimatePresence, animate, motion, useMotionValue, useReducedMotion } from "motion/react";
import { BankIcon as Bank } from "../../icons/BankIcon";
import { CancelCircleIcon as CircleX } from "../../icons/CancelCircleIcon";
import { ArrowDown01Icon as CornerDownRight } from "../../icons/ArrowDown01Icon";
import { ArrowUp01Icon as CornerUpLeft } from "../../icons/ArrowUp01Icon";
import { motionTokens } from "../lib/motion-tokens";
import { buildModel, pathFor } from "./agent-timeline-model";
import type { AgentTimelineAgent, AgentTimelineHandoff, AgentTimelineSpan, AgentTimelineTool, TimelineConnector, TimelineModel, TimelineSpan } from "./agent-timeline-model";
import styles from "./agent-timeline.module.css";

export type { AgentTimelineAgent, AgentTimelineHandoff, AgentTimelineSpan, AgentTimelineSpanKind, AgentTimelineTool } from "./agent-timeline-model";

/**
 * One finished run as rows: the first agent on top, each row's steps as bars on a shared line, and thin connectors where work was
 * handed from one row to another. Hover or focus a step for a card with what it did and when; click to pin it and trace its handoff path.
 * The line is not a clock: spans are placed in the units they are given, and a span's `meta` says when it happened.
 */
export interface AgentTimelineProps {
  agents: AgentTimelineAgent[];
  spans: AgentTimelineSpan[];
  handoffs?: AgentTimelineHandoff[];
  title: string;
  /** The parts of the line under the title. */
  summary?: string[];
  /** Called when a span is pinned or unpinned. */
  onSpanSelect?: (span: AgentTimelineSpan | null) => void;
  className?: string;
  style?: CSSProperties;
}

/** Row geometry in pixels, shared by the label column, the plot and the connectors. */
const ROW = 44;
const BAR = 16;
const PAD = 6;
const AXIS = 12;
const LINE = 1.5;
const CARD_W = 280;
const CARD_EST = 120;

const center = (row: number) => PAD + row * ROW + ROW / 2;
const at = (seconds: number) => `${seconds} / var(--axis) * 100%`;
const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));
const subscribe = () => () => {};

const NO_HANDOFFS: AgentTimelineHandoff[] = [];

const KIND_LABEL = { thinking: "Decided", tool: "At the broker", waiting: "Waited" } as const;

function toolMark(tool: AgentTimelineTool): ReactNode {
  return tool.mark ?? <Bank aria-hidden="true" />;
}

/** Elbow geometry for a connector: a box with two borders and one rounded corner, positioned in seconds on x and pixels on y. */
function linkStyle(link: TimelineConnector): CSSProperties {
  const top = (row: number) => center(row) - BAR / 2;
  const bottom = (row: number) => center(row) + BAR / 2;
  let y0: number, y1: number;
  if (link.shape === "out") [y0, y1] = link.up ? [center(link.to) - LINE / 2, top(link.from)] : [bottom(link.from), center(link.to) + LINE / 2];
  else if (link.shape === "in") [y0, y1] = link.up ? [bottom(link.to), center(link.from) + LINE / 2] : [center(link.from) - LINE / 2, top(link.to)];
  else [y0, y1] = link.up ? [bottom(link.to), top(link.from)] : [bottom(link.from), top(link.to)];
  const shiftLeft = link.shape === "in" ? 0 : LINE / 2;
  return {
    "--c": link.color,
    top: y0,
    height: Math.max(0, y1 - y0),
    left: `calc(${at(link.x0)} - ${shiftLeft}px)`,
    width: link.shape === "line" ? LINE : `calc(${at(link.x1 - link.x0)} + ${LINE / 2}px)`,
  } as CSSProperties;
}

function portStyle(link: TimelineConnector): CSSProperties {
  const row = link.shape === "in" ? link.to : link.from;
  const downward = !link.up;
  const edge = link.shape === "in" ? (link.up ? center(row) + BAR / 2 : center(row) - BAR / 2) : (downward ? center(row) + BAR / 2 : center(row) - BAR / 2);
  return { "--c": link.color, top: edge, left: `calc(${at(link.at)})` } as CSSProperties;
}

/** A separator that stays with the item before it, so a wrapped line never starts with a dot. */
function Sep() {
  return <><span className={styles.sep} aria-hidden="true">{" ·"}</span>{" "}</>;
}

interface SpanButtonProps {
  span: TimelineSpan;
  agentName: string;
  dim: boolean;
  pinned: boolean;
  tabbable: boolean;
  showIcon: boolean;
  onHover: (id: string) => void;
  onLeave: () => void;
  onFocusSpan: (id: string, visible: boolean) => void;
  onBlurSpan: () => void;
  onPick: (id: string) => void;
}

const SpanButton = memo(function SpanButton({ span, agentName, dim, pinned, tabbable, showIcon, onHover, onLeave, onFocusSpan, onBlurSpan, onPick }: SpanButtonProps) {
  const failed = span.status === "failed";
  const tool = span.toolInfo;
  const kind = tool ? `${KIND_LABEL[span.kind]}, ${tool.name}` : KIND_LABEL[span.kind];
  const label = `${agentName}, ${kind}${failed ? ", did not go through" : ""}: ${span.label}${span.meta ? `, ${span.meta}` : ""}`;
  return <button
    type="button"
    className={styles.span}
    data-kind={span.kind}
    data-state="done"
    data-failed={failed || undefined}
    data-dim={dim || undefined}
    data-span-id={span.id}
    aria-pressed={pinned}
    aria-label={label}
    tabIndex={tabbable ? 0 : -1}
    style={{ "--s": span.start, "--d": span.end! - span.start } as CSSProperties}
    onPointerEnter={event => { if (event.pointerType === "mouse") onHover(span.id); }}
    onPointerLeave={event => { if (event.pointerType === "mouse") onLeave(); }}
    onFocus={event => onFocusSpan(span.id, event.currentTarget.matches(":focus-visible"))}
    onBlur={onBlurSpan}
    onClick={() => onPick(span.id)}
  >
    {showIcon && failed ? <CircleX className={styles.spanIcon} aria-hidden="true" /> : null}
  </button>;
});

interface CardProps {
  span: TimelineSpan;
  model: TimelineModel;
  layoutKey: string;
  reduced: boolean;
  rootRef: RefObject<HTMLElement | null>;
  plotRef: RefObject<HTMLDivElement | null>;
  axis: number;
}

/** The floating span card. It glides between spans on a spring with no overshoot, crossfades its content and springs to its new height. */
function SpanCard({ span, model, layoutKey, reduced, rootRef, plotRef, axis }: CardProps) {
  const x = useMotionValue(0);
  const y = useMotionValue(0);
  const shift = useMotionValue("0%");
  const height = useMotionValue<number | "auto">("auto");
  const placed = useRef<{ id: string; above: boolean } | null>(null);
  const content = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const root = rootRef.current, plot = plotRef.current;
    if (!root || !plot) return;
    const box = root.getBoundingClientRect(), area = plot.getBoundingClientRect();
    const width = Math.min(CARD_W, box.width - 16);
    const left = area.left - box.left + (span.start / Math.max(axis, .001)) * area.width;
    const barTop = area.top - box.top + center(span.row) - BAR / 2;
    const above = barTop - 10 - CARD_EST > 0;
    const nextX = clamp(left - 12, 8, box.width - width - 8);
    const nextY = above ? barTop - 8 : barTop + BAR + 8;
    const previous = placed.current;
    placed.current = { id: span.id, above };
    if (!previous || reduced || previous.above !== above || previous.id === span.id) {
      x.jump(nextX); y.jump(nextY); shift.jump(above ? "-100%" : "0%");
      return;
    }
    animate(x, nextX, { type: "spring", visualDuration: 0.26, bounce: 0 });
    animate(y, nextY, { type: "spring", visualDuration: 0.26, bounce: 0 });
  }, [span.id, span.start, span.row, layoutKey, reduced, rootRef, plotRef, axis, x, y, shift]);

  useEffect(() => {
    const node = content.current;
    if (!node || typeof ResizeObserver === "undefined") return;
    let first = true;
    const observer = new ResizeObserver(([entry]) => {
      const next = entry?.borderBoxSize?.[0]?.blockSize ?? node.offsetHeight;
      if (first || reduced) { height.jump(next); first = false; return; }
      animate(height, next, motionTokens.spring.smooth);
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, [height, reduced]);

  const agent = model.agents[span.row];
  const tool = span.toolInfo;
  const failed = span.status === "failed";
  const links = model.connectors.filter(link => (link.targetSpan === span.id && link.to === span.row) || (link.sourceSpan === span.id && link.from === span.row));

  return <motion.div
    className={styles.cardLayer}
    style={{ x, y }}
    initial={{ opacity: 0 }}
    animate={{ opacity: 1, transition: { duration: motionTokens.duration.fast, ease: [...motionTokens.ease.enter] } }}
    exit={{ opacity: 0, transition: { duration: motionTokens.duration.instant, ease: [...motionTokens.ease.standard] } }}
    aria-hidden="true"
  >
    <motion.div style={{ y: shift }}>
      <motion.div className={styles.card} style={{ height }} initial={reduced ? false : { y: 3 }} animate={{ y: 0 }} transition={motionTokens.spring.smooth}>
        <div ref={content}>
          <AnimatePresence mode="popLayout" initial={false}>
            <motion.div
              key={span.id}
              className={styles.cardBody}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1, transition: { duration: motionTokens.duration.fast, ease: [...motionTokens.ease.enter] } }}
              exit={{ opacity: 0, transition: { duration: .1 } }}
            >
              <p className={styles.cardHead} style={{ "--c": agent.color } as CSSProperties}>
                <span className={styles.dot} />
                <span className={styles.cardAgent}>{agent.name}</span>
                {agent.model && <span className={styles.cardModel}>{agent.model}</span>}
              </p>
              <p className={styles.cardLabel}>{span.label}</p>
              <p className={styles.cardMeta}>
                {tool ? <span className={styles.cardTool}><span className={styles.mark}>{toolMark(tool)}</span>{tool.name}</span> : <span>{KIND_LABEL[span.kind]}</span>}
                {span.meta ? <><span className={styles.sep}>·</span><span className={styles.tabular}>{span.meta}</span></> : null}
              </p>
              {failed && <p className={styles.cardFailed}><CircleX aria-hidden="true" /><span>Did not go through{span.detail ? `: ${span.detail}` : ""}</span></p>}
              {!failed && span.detail && <p className={styles.cardNote}><span>{span.detail}</span></p>}
              {links.length > 0 && links.length <= 2 && links.map(link => {
                const incoming = link.targetSpan === span.id && link.to === span.row;
                const other = model.agents[incoming ? link.from : link.to];
                const Icon = incoming ? CornerDownRight : CornerUpLeft;
                return <p key={link.id} className={styles.cardNote}><Icon aria-hidden="true" /><span>{incoming ? "From" : "To"} {other.name.toLowerCase()}{link.handoff.label ? `: ${link.handoff.label}` : ""}</span></p>;
              })}
            </motion.div>
          </AnimatePresence>
        </div>
      </motion.div>
    </motion.div>
  </motion.div>;
}

export function AgentTimeline({ agents, spans, handoffs = NO_HANDOFFS, title, summary = [], onSpanSelect, className, style }: AgentTimelineProps) {
  const model = useMemo(() => buildModel(agents, spans, handoffs), [agents, spans, handoffs]);
  const axis = Math.max(model.duration, .001);

  const uid = useId();
  const hydrated = useSyncExternalStore(subscribe, () => true, () => false);
  const prefersReduced = useReducedMotion();
  const reduced = hydrated && !!prefersReduced;

  const rootRef = useRef<HTMLElement>(null);
  const scrollerRef = useRef<HTMLDivElement>(null);
  const plotRef = useRef<HTMLDivElement>(null);
  const leaveTimer = useRef(0);

  const [plotWidth, setPlotWidth] = useState(360);
  const [hoverId, setHoverId] = useState<string | null>(null);
  const [focusId, setFocusId] = useState<string | null>(null);
  const [pinnedId, setPinnedId] = useState<string | null>(null);
  const [rovingId, setRovingId] = useState<string | null>(null);
  const [scrollTick, setScrollTick] = useState(0);

  useEffect(() => () => window.clearTimeout(leaveTimer.current), []);

  // Plot width, for the card's placement and the minimum width of a step's icon.
  useEffect(() => {
    const plot = plotRef.current, scroller = scrollerRef.current;
    if (!plot || !scroller || typeof ResizeObserver === "undefined") return;
    const measure = () => setPlotWidth(Math.round(plot.getBoundingClientRect().width));
    const observer = new ResizeObserver(measure);
    observer.observe(plot);
    observer.observe(scroller);
    return () => observer.disconnect();
  }, []);

  const byId = useMemo(() => new Map(model.spans.map(span => [span.id, span])), [model]);
  const path = useMemo(() => pathFor(model, pinnedId), [model, pinnedId]);
  const shownId = hoverId ?? focusId ?? pinnedId;
  const cardSpan = shownId ? byId.get(shownId) : undefined;
  const roving = rovingId && byId.get(rovingId) ? rovingId : model.spans[0]?.id ?? null;

  const hover = useCallback((id: string) => { window.clearTimeout(leaveTimer.current); setHoverId(id); }, []);
  const unhover = useCallback(() => {
    window.clearTimeout(leaveTimer.current);
    leaveTimer.current = window.setTimeout(() => setHoverId(null), 80);
  }, []);
  const focusSpan = useCallback((id: string, keyboard: boolean) => { setRovingId(id); if (keyboard) setFocusId(id); }, []);
  const blurSpan = useCallback(() => setFocusId(null), []);
  const pick = useCallback((id: string) => {
    const next = pinnedId === id ? null : id;
    setPinnedId(next);
    setRovingId(id);
    onSpanSelect?.(next ? byId.get(next) ?? null : null);
  }, [pinnedId, onSpanSelect, byId]);

  const unpin = () => { if (pinnedId) { setPinnedId(null); onSpanSelect?.(null); } };

  const onSpanKey = (event: ReactKeyboardEvent<HTMLDivElement>) => {
    const id = (event.target as HTMLElement).dataset?.spanId;
    const span = id ? byId.get(id) : undefined;
    if (!span) return;
    if (event.key === "Escape") { if (pinnedId) { event.preventDefault(); unpin(); } return; }
    const rowSpans = (row: number) => model.byRow[row];
    const mid = (item: TimelineSpan) => (item.start + item.end!) / 2;
    let next: TimelineSpan | undefined;
    const same = rowSpans(span.row), index = same.findIndex(item => item.id === span.id);
    if (event.key === "ArrowRight") next = same[index + 1];
    else if (event.key === "ArrowLeft") next = same[index - 1];
    else if (event.key === "Home") next = same[0];
    else if (event.key === "End") next = same.at(-1);
    else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      const direction = event.key === "ArrowDown" ? 1 : -1;
      for (let row = span.row + direction; row >= 0 && row < model.agents.length && !next; row += direction) {
        next = rowSpans(row).reduce<TimelineSpan | undefined>((best, item) => !best || Math.abs(mid(item) - mid(span)) < Math.abs(mid(best) - mid(span)) ? item : best, undefined);
      }
    } else return;
    event.preventDefault();
    if (!next) return;
    setRovingId(next.id);
    plotRef.current?.querySelector<HTMLElement>(`[data-span-id="${CSS.escape(next.id)}"]`)?.focus();
  };

  const onScroll = () => {
    const scroller = scrollerRef.current;
    if (!scroller) return;
    scroller.toggleAttribute("data-scrolled", scroller.scrollLeft > 1);
    if (cardSpan) setScrollTick(tick => tick + 1);
  };

  const secondsWide = plotWidth / axis;
  const rowsHeight = PAD + model.agents.length * ROW;
  const layoutKey = `${scrollTick}:${plotWidth}`;
  const kinds = (["thinking", "tool", "waiting"] as const).filter(kind => model.spans.some(span => span.kind === kind));

  return <section
    ref={rootRef}
    className={[styles.root, className].filter(Boolean).join(" ")}
    style={style}
    aria-labelledby={`${uid}-title`}
    onKeyDown={event => { if (event.key === "Escape" && pinnedId && !(event.target as HTMLElement).dataset?.spanId) unpin(); }}
  >
    <div className={styles.inner}>
      <header className={styles.header}>
        <h3 id={`${uid}-title`} className={styles.title}>{title}</h3>
        {summary.length > 0 && <p className={styles.status}>
          {summary.map((part, index) => <Fragment key={part}>{index > 0 && <Sep />}<span className={styles.part}>{part}</span></Fragment>)}
        </p>}
      </header>

      <div ref={scrollerRef} className={styles.scroller} onScroll={onScroll}>
        <div className={styles.body} style={{ "--now": axis, "--axis": axis, "--rows-h": `${rowsHeight}px`, "--row": `${ROW}px`, "--bar": `${BAR}px`, "--pad": `${PAD}px`, "--axis-h": `${AXIS}px` } as CSSProperties}>
          <div className={styles.labels}>
            {model.agents.map(agent => <div key={agent.id} id={`${uid}-row-${agent.index}`} className={styles.label} style={{ "--c": agent.color } as CSSProperties}>
              <span className={styles.dot} aria-hidden="true" />
              <span className={styles.labelText}>
                <span className={styles.name}>{agent.name}</span>
                {agent.model && <span className={styles.model}><span className={styles.modelName}>{agent.model}</span></span>}
              </span>
            </div>)}
          </div>
          <div className={styles.track}>
            <div
              ref={plotRef}
              className={styles.plot}
              data-path={path ? "" : undefined}
              onKeyDown={onSpanKey}
              onClick={event => { if (!(event.target as HTMLElement).closest("button")) unpin(); }}
            >
              <div className={styles.links} aria-hidden="true">
                {model.connectors.map(link => <span key={link.id} className={styles.link} data-shape={link.shape} data-dir={link.up ? "up" : "down"} data-hot={path?.links.has(link.id) || undefined} style={linkStyle(link)} />)}
              </div>
              {model.agents.map(agent => <div key={agent.id} role="group" aria-labelledby={`${uid}-row-${agent.index}`} className={styles.row} style={{ "--c": agent.color, top: PAD + agent.index * ROW } as CSSProperties}>
                {model.byRow[agent.index].map(span => <SpanButton
                  key={span.id}
                  span={span}
                  agentName={agent.name}
                  dim={!!path && !path.spans.has(span.id)}
                  pinned={pinnedId === span.id}
                  tabbable={roving === span.id}
                  showIcon={(span.end! - span.start) * secondsWide >= 15}
                  onHover={hover}
                  onLeave={unhover}
                  onFocusSpan={focusSpan}
                  onBlurSpan={blurSpan}
                  onPick={pick}
                />)}
              </div>)}
              <div className={styles.ports} aria-hidden="true">
                {model.connectors.map(link => <span key={link.id} className={styles.port} data-hot={path?.links.has(link.id) || undefined} style={portStyle(link)} />)}
              </div>
            </div>
          </div>
        </div>
      </div>

      <footer className={styles.footer}>
        <ul className={styles.legend} aria-label="Legend">
          {kinds.map(kind => <li key={kind}><span className={styles.swatch} data-kind={kind} aria-hidden="true" />{KIND_LABEL[kind]}</li>)}
          {model.connectors.length > 0 && <li><CornerDownRight className={styles.legendIcon} aria-hidden="true" />Handed over</li>}
          {model.spans.some(span => span.status === "failed") && <li><CircleX className={styles.legendFailed} aria-hidden="true" />Did not go through</li>}
        </ul>
      </footer>
    </div>

    <AnimatePresence>
      {cardSpan && <SpanCard key="card" span={cardSpan} model={model} layoutKey={layoutKey} reduced={reduced} rootRef={rootRef} plotRef={plotRef} axis={axis} />}
    </AnimatePresence>
  </section>;
}

export default AgentTimeline;
