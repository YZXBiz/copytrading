"use client";

import { useCallback, useEffect, useImperativeHandle, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore, type KeyboardEvent, type PointerEvent, type Ref } from "react";
import { animate, motion, useInView, useMotionValue, useReducedMotion, useSpring } from "motion/react";
import { motionTokens } from "../lib/motion-tokens";
import styles from "./sankey-flow.module.css";

export interface SankeyNode {
  /** Stable identity. A node that survives a data change keeps its bar, so switching datasets morphs the flows. */
  id: string;
  label: string;
  /** Column index from the left. Defaults to the node's distance from a source. */
  column?: number;
}

export interface SankeyLink {
  source: string;
  target: string;
  value: number;
}

/** Use a Sankey diagram for how a quantity splits and merges through stages, such as signups moving through activation, plans, and retention. */
export interface SankeyFlowProps {
  /** Nodes in the order they stack within each column, top to bottom. */
  nodes: SankeyNode[];
  links: SankeyLink[];
  /** What flows, such as "Signups, Q3 2026". Names the chart for assistive technology. */
  label: string;
  /** Stage names printed above each column. */
  columns?: string[];
  /** Unit after values in the tooltip and table, such as "people". */
  unit?: string;
  /** What the first column adds up to, used in shares such as "21% of signups". */
  totalLabel?: string;
  formatValue?: (value: number) => string;
  /** Plot height in pixels. The width follows the container. */
  height?: number;
  /** Controlled flowing particles along the ribbons. */
  particles?: boolean;
  defaultParticles?: boolean;
  onParticlesChange?: (on: boolean) => void;
  /** Shows the built in particles toggle above the plot. */
  particleToggle?: boolean;
  emptyLabel?: string;
  ref?: Ref<HTMLElement>;
  className?: string;
}

type Box = { id: string; label: string; column: number; value: number; x0: number; x1: number; y0: number; y1: number };
type Band = { id: string; source: string; target: string; value: number; sy: number; ty: number; w: number };
type Layout = { boxes: Map<string, Box>; bands: Map<string, Band>; columns: number; scale: number };
type Glow = { links: Map<string, number>; nodes: Map<string, number> };
type Focus = { kind: "node" | "link"; id: string } | null;

const { spring } = motionTokens;
const physical = ({ visualDuration, bounce }: { visualDuration: number; bounce: number }, restDelta = .001) => { const root = (2 * Math.PI) / (visualDuration * 1.2); return { type: "spring" as const, stiffness: root * root, damping: 2 * (1 - bounce) * root, restDelta, restSpeed: restDelta * 2 }; };
const settle = physical(spring.smooth);
const reveal = physical({ visualDuration: .95, bounce: 0 });
const pour = physical({ visualDuration: .34, bounce: 0 });
const glide = physical(spring.snappy, .01);
const follow = { stiffness: glide.stiffness, damping: glide.damping, restDelta: .01 };
const NODE = 10, PAD = 14, TOP = 4, GAP = 14, SPEED = 46;
const grouped = new Intl.NumberFormat("en-US", { maximumFractionDigits: 1 });
const percent = new Intl.NumberFormat("en-US", { style: "percent", maximumFractionDigits: 0 });
const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value));
const linkId = (link: SankeyLink) => `${link.source}>${link.target}`;

/** Columns, node heights, and ribbon offsets. Nodes keep their given order in a column and relax toward the nodes they connect to. */
function computeLayout(nodes: SankeyNode[], links: SankeyLink[], width: number, height: number): Layout {
  const valid = links.filter(link => link.value > 0 && nodes.some(node => node.id === link.source) && nodes.some(node => node.id === link.target));
  const inflow = new Map<string, number>(), outflow = new Map<string, number>();
  for (const link of valid) { outflow.set(link.source, (outflow.get(link.source) ?? 0) + link.value); inflow.set(link.target, (inflow.get(link.target) ?? 0) + link.value); }
  const column = new Map<string, number>();
  const depthOf = (id: string, seen = new Set<string>()): number => {
    const fixed = nodes.find(node => node.id === id)?.column;
    if (fixed !== undefined) return fixed;
    if (column.has(id)) return column.get(id)!;
    if (seen.has(id)) return 0;
    seen.add(id);
    const parents = valid.filter(link => link.target === id).map(link => depthOf(link.source, seen) + 1);
    const depth = parents.length ? Math.max(...parents) : 0;
    column.set(id, depth);
    return depth;
  };
  for (const node of nodes) column.set(node.id, depthOf(node.id));
  const count = Math.max(1, ...[...column.values()].map(value => value + 1));
  const plotH = height - TOP;
  const byColumn = Array.from({ length: count }, (_, at) => nodes.filter(node => column.get(node.id) === at && Math.max(inflow.get(node.id) ?? 0, outflow.get(node.id) ?? 0) > 0));
  const valueOf = (id: string) => Math.max(inflow.get(id) ?? 0, outflow.get(id) ?? 0);
  const scale = Math.min(...byColumn.filter(list => list.length).map(list => (plotH - (list.length - 1) * PAD) / Math.max(1e-9, list.reduce((sum, node) => sum + valueOf(node.id), 0))));
  const step = count > 1 ? (width - NODE) / (count - 1) : 0;
  const boxes = new Map<string, Box>();
  byColumn.forEach((list, at) => {
    const total = list.reduce((sum, node) => sum + valueOf(node.id) * scale, 0) + (list.length - 1) * PAD;
    let y = TOP + (plotH - total) / 2;
    for (const node of list) { const h = valueOf(node.id) * scale; boxes.set(node.id, { id: node.id, label: node.label, column: at, value: valueOf(node.id), x0: at * step, x1: at * step + NODE, y0: y, y1: y + h }); y += h + PAD; }
  });
  // Relaxation: each pass pulls a node toward the value weighted centre of its neighbours, then pushes overlaps apart in order.
  const center = (box: Box) => (box.y0 + box.y1) / 2;
  const resolve = (list: SankeyNode[]) => {
    const column = list.map(node => boxes.get(node.id)!);
    let y = TOP;
    for (const box of column) { const h = box.y1 - box.y0; if (box.y0 < y) { box.y0 = y; box.y1 = y + h; } y = box.y1 + PAD; }
    let bottom = height;
    for (const box of [...column].reverse()) { const h = box.y1 - box.y0; if (box.y1 > bottom) { box.y1 = bottom; box.y0 = bottom - h; } bottom = box.y0 - PAD; }
  };
  for (let pass = 0, alpha = .9; pass < 6; pass++, alpha *= .7) {
    for (const [direction, list] of [[1, byColumn.slice(1)], [-1, byColumn.slice(0, -1).reverse()]] as const) {
      for (const columnNodes of list) {
        for (const node of columnNodes) {
          const box = boxes.get(node.id)!;
          const near = valid.filter(link => direction === 1 ? link.target === node.id : link.source === node.id);
          const weight = near.reduce((sum, link) => sum + link.value, 0);
          if (!weight) continue;
          const target = near.reduce((sum, link) => sum + center(boxes.get(direction === 1 ? link.source : link.target)!) * link.value, 0) / weight;
          const shift = (target - center(box)) * alpha;
          box.y0 += shift; box.y1 += shift;
        }
        resolve(columnNodes);
      }
    }
  }
  const bands = new Map<string, Band>();
  const outOffset = new Map<string, number>(), inOffset = new Map<string, number>();
  const ordered = [...valid].sort((a, b) => center(boxes.get(a.target)!) - center(boxes.get(b.target)!) || center(boxes.get(a.source)!) - center(boxes.get(b.source)!));
  for (const link of ordered) { const source = boxes.get(link.source)!; const at = outOffset.get(link.source) ?? 0; outOffset.set(link.source, at + link.value * scale); bands.set(linkId(link), { id: linkId(link), source: link.source, target: link.target, value: link.value, sy: source.y0 + at, ty: 0, w: link.value * scale }); }
  for (const link of [...valid].sort((a, b) => center(boxes.get(a.source)!) - center(boxes.get(b.source)!))) { const target = boxes.get(link.target)!; const at = inOffset.get(link.target) ?? 0; inOffset.set(link.target, at + link.value * scale); bands.get(linkId(link))!.ty = target.y0 + at; }
  return { boxes, bands, columns: count, scale };
}

/** How much of every flow passes through the node or ribbon in focus, assuming each node mixes what reaches it. */
function trace(focus: Focus, layout: Layout): Glow {
  const links = new Map<string, number>(), nodes = new Map<string, number>();
  if (!focus) return { links, nodes };
  const bands = [...layout.bands.values()];
  const seed = focus.kind === "link" ? layout.bands.get(focus.id) : undefined;
  if (focus.kind === "link" && !seed) return { links, nodes };
  const into = (id: string) => bands.filter(band => band.target === id), from = (id: string) => bands.filter(band => band.source === id);
  const total = (list: Band[]) => list.reduce((sum, band) => sum + band.value, 0);
  const order = [...layout.boxes.values()].sort((a, b) => a.column - b.column);
  const isFocus = (id: string) => focus.kind === "node" && focus.id === id;
  // down: the share of a node's inflow that came through the focus. up: the share of it that goes on to the focus.
  const down = new Map<string, number>(), up = new Map<string, number>();
  if (seed) { links.set(seed.id, seed.value); nodes.set(seed.source, seed.value); nodes.set(seed.target, seed.value); }
  else { down.set(focus.id, 1); up.set(focus.id, 1); nodes.set(focus.id, layout.boxes.get(focus.id)?.value ?? 0); }
  for (const box of order) {
    if (isFocus(box.id)) continue;
    const lit = into(box.id).reduce((sum, band) => sum + (band === seed ? band.value : band.value * (down.get(band.source) ?? 0)), 0);
    if (!lit) continue;
    for (const band of into(box.id)) if (band !== seed && down.get(band.source)) links.set(band.id, band.value * down.get(band.source)!);
    down.set(box.id, lit / (total(into(box.id)) || 1));
    nodes.set(box.id, Math.max(nodes.get(box.id) ?? 0, lit));
  }
  for (const box of [...order].reverse()) {
    if (isFocus(box.id)) continue;
    const lit = from(box.id).reduce((sum, band) => sum + (band === seed ? band.value : band.value * (up.get(band.target) ?? 0)), 0);
    if (!lit) continue;
    for (const band of from(box.id)) if (band !== seed && up.get(band.target)) links.set(band.id, band.value * up.get(band.target)!);
    up.set(box.id, lit / (total(into(box.id)) || total(from(box.id)) || 1));
    nodes.set(box.id, Math.max(nodes.get(box.id) ?? 0, lit));
  }
  return { links, nodes };
}

/** The ribbon as a closed band: two cubic curves joined at the nodes. Laid out along the flow, then turned upright when vertical. */
function ribbon(x0: number, x1: number, sy: number, ty: number, w: number, vertical = false) {
  const xm = (x0 + x1) / 2, p = (along: number, across: number) => vertical ? `${across.toFixed(2)},${along.toFixed(2)}` : `${along.toFixed(2)},${across.toFixed(2)}`;
  return `M${p(x0, sy)}C${p(xm, sy)} ${p(xm, ty)} ${p(x1, ty)}L${p(x1, ty + w)}C${p(xm, ty + w)} ${p(xm, sy + w)} ${p(x0, sy + w)}Z`;
}
const bezier = (a: number, b: number, t: number) => { const u = 1 - t; return u * u * u * a + 3 * u * u * t * a + 3 * u * t * t * b + t * t * t * b; };
const bezierX = (x0: number, x1: number, t: number) => { const xm = (x0 + x1) / 2, u = 1 - t; return u * u * u * x0 + 3 * u * u * t * xm + 3 * u * t * t * xm + t * t * t * x1; };

const subscribeNothing = () => () => {};
function useReducedMotionSafe() {
  const hydrated = useSyncExternalStore(subscribeNothing, () => true, () => false);
  return !!useReducedMotion() && hydrated;
}

export function SankeyFlow({ nodes, links, label, columns, unit = "", totalLabel = "the total", formatValue = value => grouped.format(value), height = 340, particles, defaultParticles = true, onParticlesChange, particleToggle = true, emptyLabel = "No flows yet", ref, className }: SankeyFlowProps) {
  const reduced = useReducedMotionSafe();
  const figure = useRef<HTMLElement>(null);
  const plot = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const tip = useRef<HTMLDivElement>(null);
  const inks = useRef<HTMLSpanElement>(null);
  const svg = useRef<SVGSVGElement>(null);
  const labelLayer = useRef<HTMLDivElement>(null);
  useImperativeHandle(ref, () => figure.current as HTMLElement);
  const seen = useInView(figure, { once: true, amount: .3 });
  const visible = useInView(figure, { amount: 0 });
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const node = plot.current;
    if (!node) return;
    setWidth(node.clientWidth);
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(() => setWidth(node.clientWidth));
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  const [ownParticles, setOwnParticles] = useState(defaultParticles);
  const flowing = (particles ?? ownParticles) && !reduced;
  const setFlowing = (on: boolean) => { if (particles === undefined) setOwnParticles(on); onParticlesChange?.(on); };

  const signature = JSON.stringify([nodes, links]);
  // The last column labels to its right, so every label has a gap of its own; the diagram leaves a gutter for them.
  const sinks = nodes.filter(node => links.some(link => link.target === node.id) && !links.some(link => link.source === node.id));
  const gutter = clamp(Math.max(0, ...sinks.map(node => Math.max(node.label.length, formatValue(links.filter(link => link.target === node.id).reduce((sum, link) => sum + link.value, 0)).length + 1))) * 6.6 + 14, 48, 120);
  // Narrow containers turn the diagram upright: stages run top to bottom and every label gets the full width.
  const vertical = width > 0 && width < 420;
  const plotH = vertical ? Math.max(height, 480) : height;
  const layout = useMemo(() => width ? vertical ? computeLayout(nodes, links, plotH - 40, width) : computeLayout(nodes, links, Math.max(120, width - gutter), height) : null, [signature, width, height, gutter, vertical, plotH]); // eslint-disable-line react-hooks/exhaustive-deps
  const empty = !layout || layout.bands.size === 0;

  // On screen geometry, blended from the last layout to the new one; the painter and the particles both read it.
  const shown = useRef<Layout | null>(null);
  const glow = useRef<Glow>({ links: new Map(), nodes: new Map() });
  const [focus, setFocus] = useState<Focus>(null);
  const [pointer, setPointer] = useState<{ x: number; y: number } | null>(null);
  const focusValid = focus && layout && (focus.kind === "node" ? layout.boxes.has(focus.id) : layout.bands.has(focus.id)) ? focus : null;

  const gutterRef = useRef(gutter), verticalRef = useRef(vertical);
  useLayoutEffect(() => { gutterRef.current = gutter; verticalRef.current = vertical; });
  const paint = useCallback(() => {
    const now = shown.current;
    if (!now) return;
    const up = verticalRef.current;
    const find = <T extends Element>(root: Element | null, attribute: string) => new Map([...(root?.querySelectorAll<T>(`[${attribute}]`) ?? [])].map(node => [node.getAttribute(attribute)!, node]));
    const bandPaths = find<SVGPathElement>(svg.current, "data-band"), glowPaths = find<SVGPathElement>(svg.current, "data-glow");
    const nodeRects = find<SVGRectElement>(svg.current, "data-node"), nodeGlows = find<SVGRectElement>(svg.current, "data-node-glow"), nodeTexts = find<HTMLDivElement>(labelLayer.current, "data-label");
    for (const [id, band] of now.bands) {
      const source = now.boxes.get(band.source), target = now.boxes.get(band.target);
      if (!source || !target) continue;
      bandPaths.get(id)?.setAttribute("d", band.w > .05 ? ribbon(source.x1, target.x0, band.sy, band.ty, band.w, up) : "");
      const lit = (glow.current.links.get(id) ?? 0) * now.scale;
      glowPaths.get(id)?.setAttribute("d", lit > .05 ? ribbon(source.x1, target.x0, band.sy, band.ty, Math.min(band.w, lit), up) : "");
    }
    const place = (rect: SVGRectElement | undefined, box: Box, across: number) => {
      if (!rect) return;
      rect.setAttribute("x", (up ? box.y0 : box.x0).toFixed(2)); rect.setAttribute("y", (up ? box.x0 : box.y0).toFixed(2));
      rect.setAttribute("width", (up ? Math.max(0, across) : NODE).toFixed(2)); rect.setAttribute("height", (up ? NODE : Math.max(0, across)).toFixed(2));
    };
    const step = now.columns > 1 && now.boxes.size ? Math.max(...[...now.boxes.values()].map(item => item.x0)) / (now.columns - 1) : 0;
    for (const [id, box] of now.boxes) {
      const size = box.y1 - box.y0;
      place(nodeRects.get(id), box, size);
      place(nodeGlows.get(id), box, Math.min(size, (glow.current.nodes.get(id) ?? 0) * now.scale));
      const text = nodeTexts.get(id);
      if (!text) continue;
      if (up) {
        text.style.transform = `translate(${box.y0.toFixed(1)}px, ${(box.x1 + 6).toFixed(1)}px)`;
        text.style.maxWidth = `${Math.max(24, size + PAD - 6)}px`;
        text.dataset.size = size >= 22 ? "tall" : "none";
      } else {
        text.style.transform = `translate(${(box.x1 + 7).toFixed(1)}px, ${((box.y0 + box.y1) / 2).toFixed(1)}px) translateY(-50%)`;
        text.style.maxWidth = `${Math.max(24, box.column === now.columns - 1 ? gutterRef.current - 9 : step - NODE - 12)}px`;
        text.dataset.size = size >= 30 ? "tall" : size >= 13 ? "short" : "none";
      }
    }
  }, []);

  const flight = useRef<{ stop: () => void } | null>(null);
  const drawnSignature = useRef("");
  useEffect(() => {
    if (!layout || (!seen && !reduced)) return;
    const from = shown.current, first = !from;
    const start = (id: string, box: Box): Box => from?.boxes.get(id) ?? (first ? { ...box, y0: box.y0 + (box.y1 - box.y0) / 2, y1: box.y0 + (box.y1 - box.y0) / 2 } : { ...box, y0: (box.y0 + box.y1) / 2, y1: (box.y0 + box.y1) / 2 });
    const bandStart = (id: string, band: Band): Band => from?.bands.get(id) ?? { ...band, w: 0, sy: band.sy + (first ? band.w / 2 : 0), ty: band.ty + (first ? band.w / 2 : 0) };
    const boxFrom = new Map([...layout.boxes].map(([id, box]) => [id, start(id, box)]));
    const bandFrom = new Map([...layout.bands].map(([id, band]) => [id, bandStart(id, band)]));
    const scaleFrom = from?.scale ?? layout.scale;
    flight.current?.stop();
    const blend = (t: number): Layout => ({
      columns: layout.columns,
      scale: scaleFrom + (layout.scale - scaleFrom) * t,
      boxes: new Map([...layout.boxes].map(([id, to]) => { const f = boxFrom.get(id)!; return [id, { ...to, x0: f.x0 + (to.x0 - f.x0) * t, x1: f.x1 + (to.x1 - f.x1) * t, y0: f.y0 + (to.y0 - f.y0) * t, y1: f.y1 + (to.y1 - f.y1) * t }]; })),
      bands: new Map([...layout.bands].map(([id, to]) => { const f = bandFrom.get(id)!; return [id, { ...to, sy: f.sy + (to.sy - f.sy) * t, ty: f.ty + (to.ty - f.ty) * t, w: f.w + (to.w - f.w) * t }]; })),
    });
    // A resize redraws in place; only new data or the first reveal moves.
    const resized = drawnSignature.current === signature;
    drawnSignature.current = signature;
    if (reduced || (resized && !first)) { shown.current = layout; paint(); return; }
    flight.current = animate(0, 1, { ...(first ? reveal : settle), onUpdate: t => { shown.current = blend(t); paint(); }, onComplete: () => { shown.current = layout; paint(); } });
    return () => flight.current?.stop();
  }, [layout, seen, reduced, paint]); // eslint-disable-line react-hooks/exhaustive-deps
  useLayoutEffect(paint);

  // Focus pours the traced share into every ribbon on the way through, and drains it back out when focus leaves.
  const pourFlight = useRef<{ stop: () => void } | null>(null);
  useEffect(() => {
    if (!layout) return;
    const target = trace(focusValid, layout), from = glow.current;
    const ids = new Set([...from.links.keys(), ...target.links.keys()]), nodeIds = new Set([...from.nodes.keys(), ...target.nodes.keys()]);
    pourFlight.current?.stop();
    const at = (t: number): Glow => ({
      links: new Map([...ids].map(id => [id, (from.links.get(id) ?? 0) + ((target.links.get(id) ?? 0) - (from.links.get(id) ?? 0)) * t])),
      nodes: new Map([...nodeIds].map(id => [id, (from.nodes.get(id) ?? 0) + ((target.nodes.get(id) ?? 0) - (from.nodes.get(id) ?? 0)) * t])),
    });
    if (reduced) { glow.current = target; paint(); return; }
    pourFlight.current = animate(0, 1, { ...pour, onUpdate: t => { glow.current = at(t); paint(); }, onComplete: () => { glow.current = target; paint(); } });
    return () => pourFlight.current?.stop();
  }, [focusValid?.kind, focusValid?.id, layout, paint, reduced]); // eslint-disable-line react-hooks/exhaustive-deps

  // Particles: fine grains drift along each ribbon at one speed, on a canvas under the labels. Only while visible and wanted.
  const grains = useRef(new Map<string, { t: number; lane: number }[]>());
  useEffect(() => {
    const node = canvas.current;
    if (!node || !flowing || !visible || !layout || !width) { const ctx = node?.getContext("2d"); ctx?.clearRect(0, 0, node!.width, node!.height); return; }
    const ctx = node.getContext("2d");
    if (!ctx) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    node.width = Math.round(width * dpr); node.height = Math.round(plotH * dpr);
    for (const [id, band] of layout.bands) {
      const source = layout.boxes.get(band.source)!, target = layout.boxes.get(band.target)!;
      const count = clamp(Math.round((band.w * (target.x0 - source.x1)) / 520), 1, 34);
      const list = grains.current.get(id) ?? [];
      while (list.length < count) list.push({ t: Math.random(), lane: .12 + Math.random() * .76 });
      list.length = count;
      grains.current.set(id, list);
    }
    let colors = { ink: "#888", accent: "#888" }, frame = 0, last = performance.now(), raf = 0;
    const readColors = () => { const probe = inks.current; if (!probe) return; const style = getComputedStyle(probe); colors = { ink: style.color, accent: style.backgroundColor }; };
    readColors();
    const step = (now: number) => {
      const dt = Math.min(.05, (now - last) / 1000); last = now;
      if (++frame % 30 === 0) readColors();
      const view = shown.current;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, plotH);
      if (view) {
        const lit = glow.current.links.size > 0 && [...glow.current.links.values()].some(value => value > 0);
        for (const [id, band] of view.bands) {
          const source = view.boxes.get(band.source), target = view.boxes.get(band.target), list = grains.current.get(id);
          if (!source || !target || !list || band.w < .5) continue;
          const length = Math.max(1, target.x0 - source.x1), share = band.w ? Math.min(1, (glow.current.links.get(id) ?? 0) * view.scale / band.w) : 0;
          for (const grain of list) {
            grain.t = (grain.t + (SPEED * dt) / length) % 1;
            const t = grain.t, along = bezierX(source.x1, target.x0, t), across = bezier(band.sy, band.ty, t) + band.w * grain.lane;
            const x = vertical ? across : along, y = vertical ? along : across;
            const inLit = grain.lane <= share;
            const fadeEnds = Math.min(1, t * 8, (1 - t) * 8);
            ctx.globalAlpha = (lit ? (inLit ? .95 : .08) : .42) * fadeEnds;
            ctx.fillStyle = lit && inLit ? colors.accent : colors.ink;
            ctx.beginPath(); ctx.arc(x, y, 1.15, 0, Math.PI * 2); ctx.fill();
          }
        }
      }
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => { cancelAnimationFrame(raf); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, node.width, node.height); };
  }, [flowing, visible, layout, width, plotH, vertical]);

  // The tooltip follows the pointer, or sits beside the node in keyboard focus, and never leaves the plot.
  const tipX = useMotionValue(0), tipY = useMotionValue(0);
  const tipSpringX = useSpring(tipX, follow), tipSpringY = useSpring(tipY, follow);
  const wasOn = useRef(false);
  useLayoutEffect(() => {
    const bubble = tip.current;
    if (!bubble || !focusValid || !layout) { wasOn.current = false; return; }
    let ax = pointer?.x, ay = pointer?.y;
    if (ax === undefined || ay === undefined) {
      let along: number, across: number;
      if (focusValid.kind === "node") { const box = layout.boxes.get(focusValid.id)!; along = box.x1; across = (box.y0 + box.y1) / 2; }
      else { const band = layout.bands.get(focusValid.id)!, s = layout.boxes.get(band.source)!, t = layout.boxes.get(band.target)!; along = (s.x1 + t.x0) / 2; across = (band.sy + band.ty) / 2 + band.w / 2; }
      ax = vertical ? across : along; ay = vertical ? along : across;
    }
    const tw = bubble.offsetWidth, th = bubble.offsetHeight;
    let left = ax + GAP;
    if (left + tw > width) left = ax - GAP - tw;
    let top = ay - th - GAP;
    if (top < 0) top = ay + GAP;
    tipX.set(clamp(left, 0, Math.max(0, width - tw))); tipY.set(clamp(top, 0, Math.max(0, plotH - th)));
    if (!wasOn.current || reduced) { tipSpringX.jump(tipX.get()); tipSpringY.jump(tipY.get()); }
    wasOn.current = true;
  });

  const local = (event: PointerEvent) => { const rect = plot.current?.getBoundingClientRect(); return rect ? { x: event.clientX - rect.left, y: event.clientY - rect.top } : null; };
  /** Ribbons and nodes share one listener on the svg; the mark under the pointer names itself through a data attribute. */
  const markOf = (event: PointerEvent): Focus => { const mark = (event.target as Element).closest?.("[data-band], [data-node]"); if (!mark) return null; const band = mark.getAttribute("data-band"); return band ? { kind: "link", id: band } : { kind: "node", id: mark.getAttribute("data-node")! }; };
  const onHover = (event: PointerEvent, next: Focus) => { if (event.pointerType !== "mouse") return; setPointer(local(event)); setFocus(next); };
  const onTap = (event: PointerEvent, next: Focus) => { if (event.pointerType === "mouse") return; setPointer(local(event)); setFocus(current => current && next && current.id === next.id ? null : next); };

  // Keyboard: up and down move within a column, left and right step to the nearest node in the next column.
  /** Sources take the chart series in the order they are given, so a source keeps its colour when the data changes. Past four they fall back to ink. */
  const slots = useMemo(() => new Map(layout ? nodes.filter(node => layout.boxes.get(node.id)?.column === 0).slice(0, 4).map((node, index) => [node.id, index] as const) : []), [layout, nodes]);
  const columnsOf = useMemo(() => { if (!layout) return [] as Box[][]; const list: Box[][] = Array.from({ length: layout.columns }, () => []); for (const box of layout.boxes.values()) list[box.column].push(box); return list.map(column => column.sort((a, b) => a.y0 - b.y0)); }, [layout]);
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (!layout || empty) return;
    if (event.key === "Escape" && focusValid) { event.preventDefault(); setFocus(null); return; }
    const box = focusValid?.kind === "node" ? layout.boxes.get(focusValid.id) : undefined;
    let next: Box | undefined;
    if (!box) next = ["ArrowRight", "ArrowDown", "ArrowUp", "ArrowLeft", "Home"].includes(event.key) ? columnsOf[0]?.[0] : undefined;
    else if (event.key === (vertical ? "ArrowRight" : "ArrowDown") || event.key === (vertical ? "ArrowLeft" : "ArrowUp")) { const column = columnsOf[box.column], at = column.indexOf(box); next = column[clamp(at + (event.key === (vertical ? "ArrowRight" : "ArrowDown") ? 1 : -1), 0, column.length - 1)]; }
    else if (event.key === (vertical ? "ArrowDown" : "ArrowRight") || event.key === (vertical ? "ArrowUp" : "ArrowLeft")) {
      const column = columnsOf[box.column + (event.key === (vertical ? "ArrowDown" : "ArrowRight") ? 1 : -1)];
      if (column?.length) { const middle = (box.y0 + box.y1) / 2; next = column.reduce((best, item) => Math.abs((item.y0 + item.y1) / 2 - middle) < Math.abs((best.y0 + best.y1) / 2 - middle) ? item : best); }
    } else if (event.key === "Home") next = columnsOf[0]?.[0];
    else if (event.key === "End") next = columnsOf[columnsOf.length - 1]?.[0];
    if (!next) return;
    event.preventDefault();
    setPointer(null);
    setFocus({ kind: "node", id: next.id });
  };

  const format = (value: number) => `${formatValue(value)}${unit ? ` ${unit}` : ""}`;
  const firstTotal = layout ? [...layout.boxes.values()].filter(box => box.column === 0).reduce((sum, box) => sum + box.value, 0) : 0;
  const nameOf = (id: string) => nodes.find(node => node.id === id)?.label ?? id;
  const bandsOf = (id: string, side: "source" | "target") => layout ? [...layout.bands.values()].filter(band => band[side] === id).sort((a, b) => b.value - a.value) : [];
  let tipBody: { title: string; value: string; note: string; rows: [string, string][] } | null = null;
  if (focusValid && layout) {
    if (focusValid.kind === "node") {
      const box = layout.boxes.get(focusValid.id)!, out = bandsOf(box.id, "source"), into = bandsOf(box.id, "target");
      const rows = (out.length ? out : into).slice(0, 4).map((band): [string, string] => [`${out.length ? "to" : "from"} ${nameOf(out.length ? band.target : band.source)}`, percent.format(band.value / (box.value || 1))]);
      tipBody = { title: box.label, value: format(box.value), note: `${percent.format(box.value / (firstTotal || 1))} of ${totalLabel}`, rows };
    } else {
      const band = layout.bands.get(focusValid.id)!, source = layout.boxes.get(band.source)!, target = layout.boxes.get(band.target)!;
      tipBody = { title: `${source.label} to ${target.label}`, value: format(band.value), note: `${percent.format(band.value / (source.value || 1))} of ${source.label}, ${percent.format(band.value / (target.value || 1))} of ${target.label}`, rows: [] };
    }
  }
  // The tooltip keeps its last content while it fades out, so it never collapses to an empty box on the way out.
  const [lastTip, setLastTip] = useState(tipBody);
  const tipKey = tipBody ? JSON.stringify(tipBody) : "";
  if (tipBody && tipKey !== (lastTip ? JSON.stringify(lastTip) : "")) setLastTip(tipBody);
  const tipShown = tipBody ?? lastTip;
  const announce = tipBody ? `${tipBody.title}, ${tipBody.value}. ${tipBody.note}. ${tipBody.rows.map(row => `${row[1]} ${row[0]}`).join(", ")}` : "";

  return <figure ref={figure} className={[styles.figure, className].filter(Boolean).join(" ")} aria-label={label}>
    {!!columns?.length && !vertical && <div className={styles.stages} aria-hidden="true">
      {columns.map((name, at) => {
        const count = layout?.columns ?? columns.length, step = count > 1 ? (Math.max(120, width - gutter) - NODE) / (count - 1) : 0;
        const room = at === count - 1 ? step / 2 + gutter : step - 8;
        return <span key={name} className={styles.stage} data-hidden={name.length * 6.6 > room || undefined} style={{ left: at * step }}>{name}</span>;
      })}
    </div>}
    <div className={styles.chart} data-focus={focusValid ? focusValid.kind : undefined} data-glow={focusValid ? slots.get(focusValid.kind === "node" ? focusValid.id : layout?.bands.get(focusValid.id)?.source ?? "") : undefined}>
      <div ref={plot} className={styles.plot} style={{ height: plotH }} role="group" tabIndex={empty ? -1 : 0} aria-roledescription="flow diagram" aria-label={`${label}. Arrow keys move between stages and nodes, Escape clears.`}
        onKeyDown={onKeyDown} onBlur={() => setFocus(null)} onPointerLeave={event => { if (event.pointerType === "mouse") { setFocus(null); setPointer(null); } }}
        onPointerMove={event => { if (event.pointerType === "mouse" && focusValid) setPointer(local(event)); }}
        onFocus={event => { if (event.currentTarget.matches(":focus-visible") && !focusValid && columnsOf[0]?.[0]) setFocus({ kind: "node", id: columnsOf[0][0].id }); }}>
        <span ref={inks} className={styles.inks} aria-hidden="true" />
        <svg ref={svg} className={styles.svg} width="100%" height={plotH} aria-hidden="true" focusable="false" onPointerOver={event => { const next = markOf(event); if (next) onHover(event, next); }} onPointerDown={event => { const next = markOf(event); if (next) onTap(event, next); }}>
          <g>
            {layout && [...layout.bands.values()].map(band => <path key={band.id} data-band={band.id} className={styles.band} data-slot={slots.get(band.source)} data-lit={focusValid?.kind === "link" && focusValid.id === band.id || undefined} />)}
          </g>
          <g className={styles.glows}>
            {layout && [...layout.bands.values()].map(band => <path key={band.id} data-glow={band.id} className={styles.glow} />)}
          </g>
          {layout && [...layout.boxes.values()].map(box => <g key={box.id}>
            <rect data-node={box.id} className={styles.node} data-slot={slots.get(box.id)} rx={2.5} />
            <rect data-node-glow={box.id} className={styles.nodeGlow} rx={2.5} />
          </g>)}
        </svg>
        <canvas ref={canvas} className={styles.canvas} style={{ width: "100%", height: plotH }} aria-hidden="true" data-on={flowing || undefined} />
        <div ref={labelLayer} className={styles.labels} aria-hidden="true">
          {layout && [...layout.boxes.values()].map(box => <div key={box.id} data-label={box.id} className={styles.nodeLabel} data-lit={focusValid?.kind === "node" && focusValid.id === box.id || undefined}>
            <span className={styles.nodeName}>{box.label}</span>
            <span className={styles.nodeValue}>{formatValue(box.value)}</span>
          </div>)}
        </div>
        <motion.div ref={tip} className={styles.tooltip} style={{ x: reduced ? tipX : tipSpringX, y: reduced ? tipY : tipSpringY }} data-on={tipBody ? true : undefined} aria-hidden="true">
          {tipShown && <>
            <p className={styles.tipTitle}>{tipShown.title}</p>
            <p className={styles.tipValue}>{tipShown.value}</p>
            <p className={styles.tipNote}>{tipShown.note}</p>
            {tipShown.rows.map(([name, share]) => <p key={name} className={styles.tipRow}><span>{name}</span><span className={styles.tipShare}>{share}</span></p>)}
          </>}
        </motion.div>
        {empty && width > 0 && <p className={styles.message}>{emptyLabel}</p>}
      </div>
    </div>
    {particleToggle && !reduced && <div className={styles.footer}>
      <button type="button" className={styles.flowToggle} aria-pressed={flowing} onClick={() => setFlowing(!flowing)}>
        <span className={styles.flowIcon} aria-hidden="true"><span /><span /><span /></span>
        Flow
      </button>
    </div>}
    <p className={styles.srOnly} aria-live="polite" aria-atomic="true">{announce}</p>
    {!empty && layout && <div className={styles.srOnly}><table>
      <caption>{label}</caption>
      <thead><tr><th scope="col">From</th><th scope="col">To</th><th scope="col">Value</th><th scope="col">Share of source</th></tr></thead>
      <tbody>{[...layout.bands.values()].map(band => <tr key={band.id}><th scope="row">{nameOf(band.source)}</th><td>{nameOf(band.target)}</td><td>{format(band.value)}</td><td>{percent.format(band.value / (layout.boxes.get(band.source)?.value || 1))}</td></tr>)}</tbody>
    </table></div>}
  </figure>;
}

export default SankeyFlow;
