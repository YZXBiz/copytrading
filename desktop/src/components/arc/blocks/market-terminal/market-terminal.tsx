"use client";

import { useEffect, useId, useMemo, useRef, useState, useSyncExternalStore, type KeyboardEvent, type PointerEvent as ReactPointerEvent } from "react";
import { AnimatePresence, LayoutGroup, motion, useReducedMotion } from "motion/react";
import { ArrowDownRight01Icon as ArrowDownRight } from "../../../icons/ArrowDownRight01Icon";
import { ArrowUpRight01Icon as ArrowUpRight } from "../../../icons/ArrowUpRight01Icon";
import { Tick02Icon as Check } from "../../../icons/Tick02Icon";
import { MaximizeScreenIcon as Maximize2 } from "../../../icons/MaximizeScreenIcon";
import { PauseIcon as Pause } from "../../../icons/PauseIcon";
import { PlayIcon as Play } from "../../../icons/PlayIcon";
import { Cancel01Icon as X } from "../../../icons/Cancel01Icon";
import { ZoomInAreaIcon as ZoomIn } from "../../../icons/ZoomInAreaIcon";
import { ZoomOutAreaIcon as ZoomOut } from "../../../icons/ZoomOutAreaIcon";
import { AnimatedCounter } from "../../animated-counter/animated-counter";
import { Button } from "../../button/button";
import { NumberField } from "../../number-field/number-field";
import SegmentedControl from "../../segmented-control/segmented-control";
import { motionTokens } from "../../lib/motion-tokens";
import {
  AVERAGES, BUYING_POWER, HOLDINGS, ORDERS, RANGES, SYMBOLS,
  alignSession, formatMoney, formatPercent, formatPrice, formatSigned, formatVolume, generateSeries, movingAverage, niceStep,
  type AverageId, type Candle, type Holding, type MarketSymbol, type OrderRecord, type RangeId, type RangeSpec,
} from "./market-terminal-data";
import styles from "./market-terminal.module.css";

export type { AverageId, Candle, Holding, MarketSymbol, OrderRecord, RangeId } from "./market-terminal-data";

export interface OrderRequest {
  side: "buy" | "sell";
  type: "market" | "limit";
  ticker: string;
  shares: number;
  /** Limit price for limit orders, the live price for market orders. */
  price: number;
}

export interface MarketTerminalProps {
  /** Watchlist symbols in order. Each needs a price, previous close, daily volatility and average volume. */
  symbols?: MarketSymbol[];
  /** Shares held per ticker; selling more than you hold is blocked. */
  holdings?: Holding[];
  /** Cash available for buys. */
  buyingPower?: number;
  /** Orders shown in the ticket's order list, newest first. */
  orders?: OrderRecord[];
  /** Ticker charted on first render. Defaults to the first symbol. */
  defaultTicker?: string;
  defaultRange?: RangeId;
  /** Moving averages drawn on first render. */
  defaultAverages?: AverageId[];
  /** Stream simulated ticks. Viewers can still pause them. */
  live?: boolean;
  /** Milliseconds between simulated ticks. */
  tickInterval?: number;
  /** Called when an order is submitted. Return a promise to keep the button pending; a rejection leaves the order unplaced. */
  onPlaceOrder?: (order: OrderRequest) => void | Promise<void>;
  /** Called when a working order is canceled. */
  onCancelOrder?: (order: OrderRecord) => void | Promise<void>;
  className?: string;
}

const { spring, duration } = motionTokens;
/** Per-frame easing for the canvas: an exponential approach that never overshoots, timed from the smooth spring. */
const TAU = spring.smooth.visualDuration / 4;
const AXIS_W = 68, AXIS_H = 28, PAD_RIGHT = 3, MIN_SPAN = 12;
/** Below this chart width the OHLC readout sits above the canvas instead of over it (matches the container query in the CSS). */
const READOUT_INLINE = 640;
const COLOR_TOKENS = ["--foreground", "--text-secondary", "--text-muted", "--border", "--border-subtle", "--success", "--danger", "--accent", "--series-1", "--series-3", "--surface"] as const;
type Colors = Record<(typeof COLOR_TOKENS)[number], string>;

const subscribeNothing = () => () => {};
/** Reduced motion, read only after hydration so the server and first client render agree. */
function useReducedFlag() {
  const hydrated = useSyncExternalStore(subscribeNothing, () => true, () => false);
  return !!useReducedMotion() && hydrated;
}
const clamp = (value: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, value));
const seriesKey = (ticker: string, range: RangeId) => `${ticker}:${range}`;
const rangeOf = (id: RangeId) => RANGES.find(range => range.id === id) ?? RANGES[3];

/* ================================================================ Chart engine */

type ReadoutNodes = { date: HTMLElement; o: HTMLElement; h: HTMLElement; l: HTMLElement; c: HTMLElement; change: HTMLElement; volume: HTMLElement; ma20: HTMLElement; ma50: HTMLElement };
type ChartNodes = { last: HTMLElement; crossPrice: HTMLElement; crossTime: HTMLElement; limit: HTMLElement; readout: ReadoutNodes; announce: HTMLElement };

/**
 * Draws candles, volume, averages and the crosshair on one canvas. All per-frame state lives here, outside React: the view window,
 * the price scale, the eased live price and pan momentum. React only hands it data, and a single rAF loop runs while anything moves.
 */
class ChartEngine {
  ctx: CanvasRenderingContext2D | null;
  bars: Candle[] = [];
  averages: Record<AverageId, (number | null)[]> = { ma20: [], ma50: [] };
  show = new Set<AverageId>();
  n = 0; count = 0;
  s = 0; e = 0; ts = 0; te = 0;
  lo = 0; hi = 1; vMax = 1; snapY = true;
  live = 0; shown = 0; prevClose = 0;
  alpha = 1; vel = 0;
  cross: { i: number; y: number | null } | null = null;
  limit: number | null = null;
  w = 0; h = 0; dpr = 1;
  colors: Colors | null = null;
  font = "Inter, sans-serif";
  reduced = false;
  raf = 0; lastT = 0;
  private text = new Map<HTMLElement, string>();
  private readIndex = -2;
  private readPrice = NaN;

  constructor(private canvas: HTMLCanvasElement, private nodes: ChartNodes) {
    this.ctx = canvas.getContext("2d");
  }

  get plotW() { return Math.max(1, this.w - AXIS_W); }
  get span() { return this.e - this.s; }
  get maxEnd() { return this.n + PAD_RIGHT; }
  /** Bars in the default view: the range's count, thinned on narrow plots so candles stay at least five pixels apart. */
  get viewCount() { return this.w ? Math.min(this.count, Math.max(MIN_SPAN, Math.floor(this.plotW / 5))) : this.count; }

  destroy() { cancelAnimationFrame(this.raf); this.raf = 0; }

  resize(w: number, h: number, dpr: number) {
    const first = !this.w;
    this.w = w; this.h = h; this.dpr = dpr;
    if (first && this.n) { this.ts = Math.max(0, this.n - this.viewCount); this.te = this.maxEnd; this.s = this.ts; this.e = this.te; this.snapY = true; }
    this.canvas.width = Math.round(w * dpr); this.canvas.height = Math.round(h * dpr);
    this.invalidate(true);
  }

  setBars(bars: Candle[], count: number, live: number, prevClose: number, fade: boolean) {
    this.bars = bars; this.n = bars.length; this.count = count;
    this.live = live; this.shown = live; this.prevClose = prevClose;
    this.recompute();
    this.ts = Math.max(0, this.n - this.viewCount); this.te = this.maxEnd;
    this.s = this.ts; this.e = this.te;
    this.snapY = true; this.cross = null; this.vel = 0;
    this.alpha = fade && !this.reduced ? 0 : 1;
    this.readIndex = -2;
    this.invalidate();
  }

  setLive(live: number) {
    this.live = live;
    if (this.reduced) this.shown = live;
    this.recompute();
    this.invalidate();
  }

  recompute() {
    for (const average of AVERAGES) this.averages[average.id] = movingAverage(this.bars, average.period);
  }

  clampTarget() {
    const span = clamp(this.te - this.ts, Math.min(MIN_SPAN, this.maxEnd), this.maxEnd);
    let start = this.ts;
    if (start < 0) start = 0;
    if (start + span > this.maxEnd) start = this.maxEnd - span;
    const moved = start !== this.ts || start + span !== this.te;
    this.ts = start; this.te = start + span;
    return moved;
  }

  /** Scales the target window around a point given as a fraction of the plot width. Returns false at a zoom limit. */
  zoom(factor: number, anchor: number, immediate = false) {
    const span = this.te - this.ts;
    const next = clamp(span * factor, Math.min(MIN_SPAN, this.maxEnd), this.maxEnd);
    if (Math.abs(next - span) < 1e-6) return false;
    const pivot = this.ts + anchor * span;
    this.ts = pivot - anchor * next; this.te = this.ts + next;
    this.clampTarget();
    this.vel = 0;
    if (immediate || this.reduced) { this.s = this.ts; this.e = this.te; }
    this.invalidate();
    return true;
  }

  pan(bars: number, immediate = false) {
    this.ts += bars; this.te += bars;
    this.clampTarget();
    if (immediate || this.reduced) { this.s = this.ts; this.e = this.te; }
    this.invalidate();
  }

  reset() {
    this.ts = Math.max(0, this.n - this.viewCount); this.te = this.maxEnd; this.vel = 0;
    if (this.reduced) { this.s = this.ts; this.e = this.te; }
    this.invalidate();
  }

  indexAt(x: number) { return clamp(Math.floor(this.s + (x / this.plotW) * this.span), 0, this.n - 1); }
  /** Where a bar sits as a fraction of the plot, used as the zoom anchor for buttons and keys. */
  anchorFor(index: number) { return clamp((index + .5 - this.ts) / (this.te - this.ts), 0, 1); }

  setCross(x: number | null, y: number | null = null) {
    this.cross = x === null ? null : { i: this.indexAt(x), y };
    this.invalidate();
  }

  /** Keyboard inspection: steps the crosshair and keeps the bar inside the window. */
  step(delta: number | "first" | "last") {
    const from = this.cross?.i ?? this.n - 1;
    const i = delta === "first" ? 0 : delta === "last" ? this.n - 1 : clamp(from + delta, 0, this.n - 1);
    this.cross = { i, y: null };
    const span = this.te - this.ts;
    if (i < this.ts + 1) this.pan(i - 1 - this.ts);
    else if (i + 1 > this.te - PAD_RIGHT + 1) this.pan(Math.min(this.maxEnd, i + PAD_RIGHT) - this.te);
    else if (span <= 0) this.reset();
    this.invalidate();
    return i;
  }

  invalidate(now = false) {
    if (now) { this.frame(performance.now(), true); return; }
    if (!this.raf) { this.lastT = 0; this.raf = requestAnimationFrame(this.frame); }
  }

  private frame = (t: number, single = false) => {
    if (!single) this.raf = 0;
    const dt = this.lastT ? Math.min(.05, (t - this.lastT) / 1000) : 1 / 60;
    if (!single) this.lastT = t;
    const ease = (tau: number) => this.reduced ? 1 : 1 - Math.exp(-dt / tau);

    // Momentum after a flick, fading like a thrown card.
    if (this.vel) {
      this.ts += this.vel * dt; this.te += this.vel * dt;
      const hit = this.clampTarget();
      this.s = this.ts; this.e = this.te;
      this.vel *= Math.exp(-dt / .32);
      if (hit || Math.abs(this.vel) * (this.plotW / this.span) < 12) this.vel = 0;
    }
    this.s += (this.ts - this.s) * ease(TAU * .6);
    this.e += (this.te - this.e) * ease(TAU * .6);
    this.shown += (this.live - this.shown) * ease(TAU * 1.6);
    this.alpha += (1 - this.alpha) * ease(TAU * .9);

    // The scale follows the visible bars.
    const i0 = clamp(Math.floor(this.s), 0, this.n - 1), i1 = clamp(Math.ceil(this.e), 0, this.n - 1);
    let lo = Infinity, hi = -Infinity, vMax = 0;
    for (let i = i0; i <= i1; i++) {
      const bar = this.bars[i], last = i === this.n - 1;
      lo = Math.min(lo, last ? Math.min(bar.l, this.shown) : bar.l);
      hi = Math.max(hi, last ? Math.max(bar.h, this.shown) : bar.h);
      vMax = Math.max(vMax, bar.v);
    }
    if (!Number.isFinite(lo)) { lo = 0; hi = 1; }
    const pad = Math.max((hi - lo) * .08, hi * .002);
    const tLo = lo - pad, tHi = hi + pad;
    if (this.snapY) { this.lo = tLo; this.hi = tHi; this.vMax = vMax; this.snapY = false; }
    else {
      this.lo += (tLo - this.lo) * ease(TAU); this.hi += (tHi - this.hi) * ease(TAU);
      this.vMax += (vMax - this.vMax) * ease(TAU);
    }

    this.draw();

    const range = this.hi - this.lo;
    const moving = this.vel !== 0 || Math.abs(this.ts - this.s) > 1e-3 || Math.abs(this.te - this.e) > 1e-3 || Math.abs(this.live - this.shown) > .0005 || 1 - this.alpha > .002
      || Math.abs(tLo - this.lo) > range * 1e-4 || Math.abs(tHi - this.hi) > range * 1e-4 || Math.abs(vMax - this.vMax) > vMax * 1e-3;
    if (single) return;
    if (moving) this.raf = requestAnimationFrame(this.frame);
    else {
      this.s = this.ts; this.e = this.te; this.shown = this.live; this.alpha = 1; this.lo = tLo; this.hi = tHi; this.vMax = vMax;
      this.draw();
    }
  };

  private setText(node: HTMLElement, value: string) {
    if (this.text.get(node) === value) return;
    this.text.set(node, value);
    node.textContent = value;
  }

  private draw() {
    const ctx = this.ctx, colors = this.colors;
    if (!ctx || !colors || !this.w || !this.n) return;
    const { w, h, dpr, bars, n } = this;
    const plotW = this.plotW;
    const volBottom = h - AXIS_H, volH = clamp((h - AXIS_H) * .15, 36, 88), volTop = volBottom - volH, priceBottom = volTop - 14, priceTop = w < READOUT_INLINE ? 20 : 56;
    const slot = plotW / this.span;
    const x = (i: number) => (i - this.s + .5) * slot;
    const y = (price: number) => priceBottom - ((price - this.lo) / (this.hi - this.lo)) * (priceBottom - priceTop);
    const i0 = clamp(Math.floor(this.s) - 1, 0, n - 1), i1 = clamp(Math.ceil(this.e) + 1, 0, n - 1);
    const lastBar = bars[n - 1];
    const closeOf = (i: number) => i === n - 1 ? this.shown : bars[i].c;
    const highOf = (i: number) => i === n - 1 ? Math.max(bars[i].h, this.shown) : bars[i].h;
    const lowOf = (i: number) => i === n - 1 ? Math.min(bars[i].l, this.shown) : bars[i].l;

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    ctx.font = `400 12px ${this.font}`;
    ctx.textBaseline = "middle";

    // Price grid and axis labels. A label that the live, crosshair or limit tag would cover steps aside.
    const up = this.shown >= this.prevClose;
    const lastY = clamp(y(this.shown), priceTop - 12, priceBottom + 12);
    const tagYs = [lastY];
    if (this.cross) tagYs.push(this.cross.y === null ? y(closeOf(clamp(this.cross.i, 0, n - 1))) : this.cross.y);
    const step = niceStep(this.hi - this.lo, Math.max(3, Math.floor((priceBottom - priceTop) / 64)));
    ctx.fillStyle = colors["--text-muted"];
    ctx.textAlign = "left";
    for (let price = Math.ceil(this.lo / step) * step; price <= this.hi; price += step) {
      const py = Math.round(y(price)) + .5;
      if (py < priceTop - 8 || py > priceBottom + 4) continue;
      ctx.fillStyle = colors["--border-subtle"];
      ctx.fillRect(0, py - .5, plotW, 1);
      if (tagYs.some(tagY => Math.abs(tagY - py) < 16)) continue;
      ctx.fillStyle = colors["--text-muted"];
      ctx.fillText(formatPrice(price), plotW + 12, py);
    }

    // Time labels: day or month starts first, then a steady stride keyed to the bar index so labels hold still while panning.
    const minGap = 76;
    const stride = [1, 2, 3, 4, 6, 12, 24, 48, 96, 192].find(item => item * slot >= minGap) ?? 384;
    const placed: number[] = [];
    const room = (px: number, gap: number) => placed.every(other => Math.abs(other - px) >= gap);
    ctx.textAlign = "center";
    for (const pass of [2, 1]) {
      for (let i = i0; i <= i1; i++) {
        const bar = bars[i];
        const eligible = pass === 2 ? bar.rank === 2 : bar.rank < 2 && i % stride === 0;
        if (!eligible) continue;
        const px = x(i);
        if (px < 24 || px > plotW - 24 || !room(px, pass === 2 ? minGap * .8 : minGap)) continue;
        placed.push(px);
        ctx.fillStyle = colors["--border-subtle"];
        ctx.fillRect(Math.round(px), priceTop - 8, 1, volBottom - priceTop + 8);
        ctx.fillStyle = pass === 2 ? colors["--text-secondary"] : colors["--text-muted"];
        ctx.fillText(bar.tick, px, volBottom + AXIS_H / 2 + 1);
      }
    }
    ctx.fillStyle = colors["--border"];
    ctx.fillRect(0, volBottom, plotW, 1);
    ctx.fillRect(plotW, priceTop - 8, 1, volBottom - priceTop + 8);

    // Hovered column.
    const cross = this.cross ? { i: clamp(this.cross.i, 0, n - 1), y: this.cross.y } : null;
    if (cross) {
      ctx.globalAlpha = .06;
      ctx.fillStyle = colors["--foreground"];
      ctx.fillRect(x(cross.i) - slot / 2, priceTop - 8, slot, volBottom - priceTop + 8);
      ctx.globalAlpha = 1;
    }

    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, plotW, h);
    ctx.clip();
    ctx.globalAlpha = this.alpha;

    // Volume.
    const body = Math.max(1, Math.min(slot * .66, 16));
    ctx.globalAlpha = this.alpha * .34;
    for (let i = i0; i <= i1; i++) {
      const bh = Math.max(1, (bars[i].v / Math.max(1, this.vMax)) * (volH - 4));
      ctx.fillStyle = closeOf(i) >= bars[i].o ? colors["--success"] : colors["--danger"];
      ctx.fillRect(Math.round(x(i) - body / 2), volBottom - bh, Math.max(1, Math.round(body)), bh);
    }
    ctx.globalAlpha = this.alpha;

    // Moving averages.
    for (const average of AVERAGES) {
      if (!this.show.has(average.id)) continue;
      const values = this.averages[average.id];
      ctx.beginPath();
      let open = false;
      for (let i = i0; i <= i1; i++) {
        let value = values[i];
        if (value === null) { open = false; continue; }
        if (i === n - 1) value += (this.shown - lastBar.c) / average.period;
        if (open) ctx.lineTo(x(i), y(value)); else { ctx.moveTo(x(i), y(value)); open = true; }
      }
      ctx.lineWidth = 1.5;
      ctx.lineJoin = "round";
      ctx.strokeStyle = average.id === "ma20" ? colors["--series-1"] : colors["--series-3"];
      ctx.stroke();
    }

    // Candles: a one pixel wick and a body at least one pixel tall, snapped to device pixels.
    for (let i = i0; i <= i1; i++) {
      const o = bars[i].o, c = closeOf(i);
      ctx.fillStyle = c >= o ? colors["--success"] : colors["--danger"];
      const cx = Math.round(x(i));
      const top = y(highOf(i)), bottom = y(lowOf(i));
      ctx.fillRect(cx - (body > 3 ? .5 : 0), top, 1, Math.max(1, bottom - top));
      if (body > 1.5) {
        const by = Math.min(y(o), y(c)), bh = Math.max(1, Math.abs(y(o) - y(c)));
        const bw = Math.max(2, Math.round(body));
        ctx.fillRect(cx - Math.floor(bw / 2), by, bw, bh);
      }
    }
    ctx.restore();
    ctx.globalAlpha = 1;

    // Live price line.
    ctx.setLineDash([2, 3]);
    ctx.lineWidth = 1;
    ctx.strokeStyle = up ? colors["--success"] : colors["--danger"];
    ctx.globalAlpha = .7;
    ctx.beginPath(); ctx.moveTo(0, Math.round(lastY) + .5); ctx.lineTo(plotW, Math.round(lastY) + .5); ctx.stroke();
    ctx.globalAlpha = 1;
    this.nodes.last.style.transform = `translate3d(0, ${lastY}px, 0)`;
    this.nodes.last.dataset.direction = up ? "up" : "down";
    this.setText(this.nodes.last, formatPrice(this.shown));

    // Draft limit price.
    if (this.limit !== null) {
      const ly = clamp(y(this.limit), priceTop - 12, priceBottom + 12);
      ctx.strokeStyle = colors["--accent"];
      ctx.setLineDash([5, 4]);
      ctx.beginPath(); ctx.moveTo(0, Math.round(ly) + .5); ctx.lineTo(plotW, Math.round(ly) + .5); ctx.stroke();
      this.nodes.limit.style.transform = `translate3d(0, ${ly}px, 0)`;
      this.nodes.limit.dataset.visible = "";
      this.setText(this.nodes.limit, `Limit ${formatPrice(this.limit)}`);
    } else delete this.nodes.limit.dataset.visible;
    ctx.setLineDash([]);

    // Crosshair.
    if (cross) {
      const cx = Math.round(x(cross.i)) + .5;
      const cy = cross.y === null ? y(closeOf(cross.i)) : clamp(cross.y, priceTop, volBottom);
      ctx.strokeStyle = colors["--text-muted"];
      ctx.setLineDash([3, 3]);
      ctx.beginPath(); ctx.moveTo(cx, priceTop - 8); ctx.lineTo(cx, volBottom); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(0, Math.round(cy) + .5); ctx.lineTo(plotW, Math.round(cy) + .5); ctx.stroke();
      ctx.setLineDash([]);
      const price = this.lo + ((priceBottom - cy) / (priceBottom - priceTop)) * (this.hi - this.lo);
      this.nodes.crossPrice.style.transform = `translate3d(0, ${cy}px, 0)`;
      this.setText(this.nodes.crossPrice, cy <= priceBottom + 6 ? formatPrice(price) : formatVolume(((volBottom - cy) / volH) * this.vMax));
      this.nodes.crossPrice.dataset.visible = "";
      const tx = clamp(cx, 60, plotW - 60);
      this.nodes.crossTime.style.transform = `translate3d(${tx}px, 0, 0) translateX(-50%)`;
      this.setText(this.nodes.crossTime, bars[cross.i].label);
      this.nodes.crossTime.dataset.visible = "";
    } else {
      delete this.nodes.crossPrice.dataset.visible;
      delete this.nodes.crossTime.dataset.visible;
    }

    this.readout(cross ? cross.i : n - 1);
  }

  /** Writes the OHLC readout straight into its spans, only when the bar or the live price it shows has changed. */
  private readout(i: number) {
    const live = i === this.n - 1;
    if (i === this.readIndex && (!live || this.readPrice === this.shown)) return;
    this.readIndex = i; this.readPrice = this.shown;
    const bar = this.bars[i], r = this.nodes.readout;
    const c = live ? this.shown : bar.c, h = live ? Math.max(bar.h, c) : bar.h, l = live ? Math.min(bar.l, c) : bar.l;
    const base = i > 0 ? this.bars[i - 1].c : bar.o;
    const change = ((c - base) / base) * 100;
    this.setText(r.date, bar.label);
    this.setText(r.o, formatPrice(bar.o));
    this.setText(r.h, formatPrice(h));
    this.setText(r.l, formatPrice(l));
    this.setText(r.c, formatPrice(c));
    this.setText(r.change, formatPercent(change));
    r.change.dataset.direction = change >= 0 ? "up" : "down";
    this.setText(r.volume, formatVolume(bar.v));
    for (const average of AVERAGES) {
      const value = this.averages[average.id][i];
      const adjusted = value === null ? null : live ? value + (this.shown - bar.c) / average.period : value;
      this.setText(r[average.id], adjusted === null ? "n/a" : formatPrice(adjusted));
    }
  }

  /** A sentence for screen readers, spoken when the keyboard moves the crosshair. */
  describe(i: number) {
    const bar = this.bars[i];
    const live = i === this.n - 1;
    const c = live ? this.live : bar.c;
    const base = i > 0 ? this.bars[i - 1].c : bar.o;
    const change = ((c - base) / base) * 100;
    return `${bar.label}${live ? ", live" : ""}. Open ${formatPrice(bar.o)}, high ${formatPrice(Math.max(bar.h, c))}, low ${formatPrice(Math.min(bar.l, c))}, close ${formatPrice(c)}, ${change >= 0 ? "up" : "down"} ${Math.abs(change).toFixed(2)} percent. Volume ${formatVolume(bar.v)}.`;
  }
}

/* ================================================================ Chart */

interface PriceChartProps {
  bars: Candle[];
  seriesId: string;
  range: RangeSpec;
  symbol: MarketSymbol;
  live: number;
  averages: AverageId[];
  limit: number | null;
  reduced: boolean;
  zoomRef: React.RefObject<{ zoom: (factor: number) => void; reset: () => void } | null>;
}

function PriceChart({ bars, seriesId, range, symbol, live, averages, limit, reduced, zoomRef }: PriceChartProps) {
  const surface = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const probe = useRef<HTMLSpanElement>(null);
  const last = useRef<HTMLSpanElement>(null), crossPrice = useRef<HTMLSpanElement>(null), crossTime = useRef<HTMLSpanElement>(null), limitTag = useRef<HTMLSpanElement>(null);
  const announce = useRef<HTMLSpanElement>(null);
  const readoutRef = useRef<HTMLDivElement>(null);
  const engine = useRef<ChartEngine | null>(null);
  const firstData = useRef(true);
  const descriptionId = useId();

  // Create the engine once; colors follow the theme and accent through a probe element that resolves each token.
  useEffect(() => {
    const node = canvas.current, box = surface.current, probeNode = probe.current, readoutNode = readoutRef.current;
    if (!node || !box || !probeNode || !readoutNode) return;
    const cell = (key: keyof ReadoutNodes) => readoutNode.querySelector<HTMLElement>(`[data-read="${key}"]`)!;
    const nodes: ChartNodes = {
      last: last.current!, crossPrice: crossPrice.current!, crossTime: crossTime.current!, limit: limitTag.current!, announce: announce.current!,
      readout: { date: cell("date"), o: cell("o"), h: cell("h"), l: cell("l"), c: cell("c"), change: cell("change"), volume: cell("volume"), ma20: cell("ma20"), ma50: cell("ma50") },
    };
    const chart = new ChartEngine(node, nodes);
    engine.current = chart;
    const readColors = () => {
      const colors = {} as Colors;
      for (const token of COLOR_TOKENS) { probeNode.style.color = `var(${token})`; colors[token] = getComputedStyle(probeNode).color; }
      chart.colors = colors;
      chart.font = getComputedStyle(box).fontFamily || chart.font;
      chart.invalidate();
    };
    readColors();
    const themeObserver = new MutationObserver(readColors);
    themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme", "data-accent", "class", "style"] });
    const scheme = window.matchMedia("(prefers-color-scheme: dark)");
    scheme.addEventListener("change", readColors);
    const sizeObserver = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect;
      chart.resize(width, height, Math.min(2, window.devicePixelRatio || 1));
    });
    sizeObserver.observe(box);
    return () => { themeObserver.disconnect(); scheme.removeEventListener("change", readColors); sizeObserver.disconnect(); chart.destroy(); engine.current = null; };
  }, []);

  useEffect(() => { if (engine.current) engine.current.reduced = reduced; }, [reduced]);
  // New symbol or range: swap the data and fade the candles in on a fresh scale.
  useEffect(() => {
    const chart = engine.current;
    if (!chart) return;
    chart.setBars(bars, range.count, live, symbol.prevClose, !firstData.current);
    firstData.current = false;
    // Live price changes arrive through the next effect; only a series change resets the view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seriesId]);
  useEffect(() => { engine.current?.setLive(live); }, [live]);
  useEffect(() => { const chart = engine.current; if (!chart) return; chart.show = new Set(averages); chart.invalidate(); }, [averages]);
  useEffect(() => { const chart = engine.current; if (!chart) return; chart.limit = limit; chart.invalidate(); }, [limit]);

  // Toolbar zoom buttons act through this handle.
  useEffect(() => {
    zoomRef.current = {
      zoom: factor => { const chart = engine.current; if (chart) chart.zoom(factor, chart.anchorFor(chart.cross?.i ?? chart.n - 1)); },
      reset: () => engine.current?.reset(),
    };
    return () => { zoomRef.current = null; };
  }, [zoomRef]);

  // Wheel zooms around the pointer and sideways scroll pans. At a zoom limit the page scrolls instead of getting stuck.
  useEffect(() => {
    const box = surface.current;
    if (!box) return;
    const onWheel = (event: WheelEvent) => {
      const chart = engine.current;
      if (!chart) return;
      const rect = box.getBoundingClientRect();
      const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? rect.height : 1;
      const dx = event.deltaX * unit, dy = event.deltaY * unit;
      if (!event.ctrlKey && Math.abs(dx) > Math.abs(dy)) {
        event.preventDefault();
        chart.pan(dx / (chart.plotW / (chart.te - chart.ts)));
        return;
      }
      const anchor = clamp((event.clientX - rect.left) / chart.plotW, 0, 1);
      const factor = Math.exp(dy * (event.ctrlKey ? .012 : .0022));
      if (chart.zoom(factor, anchor)) event.preventDefault();
    };
    box.addEventListener("wheel", onWheel, { passive: false });
    return () => box.removeEventListener("wheel", onWheel);
  }, []);

  // Pointer: mouse hovers to inspect and drags to pan; touch drags to pan, taps to inspect, and pinches to zoom.
  const gesture = useRef<{ pointers: Map<number, { x: number; y: number }>; startX: number; startY: number; moved: boolean; pinch: { distance: number; span: number; pivot: number } | null; samples: { t: number; x: number }[] }>({ pointers: new Map(), startX: 0, startY: 0, moved: false, pinch: null, samples: [] });
  const local = (event: ReactPointerEvent) => { const rect = surface.current!.getBoundingClientRect(); return { x: event.clientX - rect.left, y: event.clientY - rect.top }; };
  const onPointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
    const chart = engine.current, g = gesture.current;
    if (!chart || (event.pointerType === "mouse" && event.button !== 0)) return;
    const point = local(event);
    g.pointers.set(event.pointerId, point);
    event.currentTarget.setPointerCapture(event.pointerId);
    chart.vel = 0;
    if (g.pointers.size === 1) { g.startX = point.x; g.startY = point.y; g.moved = false; g.samples = [{ t: event.timeStamp, x: point.x }]; }
    if (g.pointers.size === 2) {
      const [a, b] = [...g.pointers.values()];
      const mid = (a.x + b.x) / 2;
      g.pinch = { distance: Math.max(24, Math.abs(a.x - b.x)), span: chart.te - chart.ts, pivot: chart.ts + (mid / chart.plotW) * (chart.te - chart.ts) };
      g.moved = true;
      chart.setCross(null);
    }
  };
  const onPointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    const chart = engine.current, g = gesture.current;
    if (!chart) return;
    const point = local(event);
    if (!g.pointers.has(event.pointerId)) {
      if (event.pointerType === "mouse") chart.setCross(point.x < chart.plotW ? point.x : null, point.y);
      return;
    }
    const previous = g.pointers.get(event.pointerId)!;
    g.pointers.set(event.pointerId, point);
    if (g.pinch && g.pointers.size >= 2) {
      const [a, b] = [...g.pointers.values()];
      const mid = (a.x + b.x) / 2, distance = Math.max(24, Math.abs(a.x - b.x));
      const span = clamp(g.pinch.span * (g.pinch.distance / distance), Math.min(MIN_SPAN, chart.maxEnd), chart.maxEnd);
      chart.ts = g.pinch.pivot - (mid / chart.plotW) * span; chart.te = chart.ts + span;
      chart.clampTarget(); chart.s = chart.ts; chart.e = chart.te;
      chart.invalidate();
      return;
    }
    if (!g.moved && Math.abs(point.x - g.startX) < 6 && Math.abs(point.y - g.startY) < 6) return;
    if (!g.moved) { g.moved = true; if (event.pointerType !== "mouse") chart.setCross(null); }
    chart.pan(-(point.x - previous.x) / (chart.plotW / (chart.te - chart.ts)), true);
    if (event.pointerType === "mouse") chart.setCross(point.x < chart.plotW ? point.x : null, point.y);
    g.samples.push({ t: event.timeStamp, x: point.x });
    if (g.samples.length > 6) g.samples.shift();
  };
  const onPointerEnd = (event: ReactPointerEvent<HTMLDivElement>) => {
    const chart = engine.current, g = gesture.current;
    if (!chart || !g.pointers.has(event.pointerId)) return;
    const point = local(event);
    g.pointers.delete(event.pointerId);
    if (g.pointers.size === 1) { g.pinch = null; const rest = [...g.pointers.values()][0]; g.samples = [{ t: event.timeStamp, x: rest.x }]; return; }
    if (g.pointers.size > 0) return;
    g.pinch = null;
    if (event.type === "pointercancel") return;
    if (!g.moved) {
      if (event.pointerType !== "mouse") chart.setCross(chart.cross && chart.cross.i === chart.indexAt(point.x) ? null : point.x < chart.plotW ? point.x : null, point.y);
      return;
    }
    // Flick: carry the recent velocity forward, in bars per second.
    const first = g.samples[0], lastSample = g.samples[g.samples.length - 1];
    const elapsed = (lastSample.t - first.t) / 1000;
    if (!reduced && elapsed > 0 && event.timeStamp - lastSample.t < 80) {
      const pxPerSecond = (lastSample.x - first.x) / elapsed;
      chart.vel = -pxPerSecond / (chart.plotW / (chart.te - chart.ts));
      chart.invalidate();
    }
  };

  // Keyboard: arrows inspect bar by bar, plus and minus zoom, 0 resets, Escape clears.
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    const chart = engine.current;
    if (!chart) return;
    const key = event.key;
    let index: number | null = null;
    if (key === "ArrowLeft" || key === "ArrowRight") index = chart.step((key === "ArrowLeft" ? -1 : 1) * (event.shiftKey ? 10 : 1));
    else if (key === "Home") index = chart.step("first");
    else if (key === "End") index = chart.step("last");
    else if (key === "+" || key === "=") chart.zoom(.8, chart.anchorFor(chart.cross?.i ?? chart.n - 1));
    else if (key === "-" || key === "_") chart.zoom(1.25, chart.anchorFor(chart.cross?.i ?? chart.n - 1));
    else if (key === "0") chart.reset();
    else if (key === "Escape" && chart.cross) chart.setCross(null);
    else return;
    event.preventDefault();
    if (index !== null && announce.current) announce.current.textContent = chart.describe(index);
  };
  const onFocus = () => { const chart = engine.current; if (chart && !chart.cross && !gesture.current.pointers.size) chart.step("last"); };
  const onBlur = () => engine.current?.setCross(null);

  const lastBar = bars[bars.length - 1];
  const change = live - (bars.length > 1 ? bars[bars.length - 2].c : lastBar.o);
  return <div className={styles.chart}>
    <span ref={probe} className={styles.probe} aria-hidden="true" />
    <div ref={readoutRef} className={styles.readout} aria-hidden="true">
      <span data-read="date" className={styles.readDate}>{lastBar.label}</span>
      <span className={styles.readGroup}>
        <span className={styles.readItem}><span className={styles.readKey}>O</span><span data-read="o">{formatPrice(lastBar.o)}</span></span>
        <span className={styles.readItem}><span className={styles.readKey}>H</span><span data-read="h">{formatPrice(Math.max(lastBar.h, live))}</span></span>
        <span className={styles.readItem}><span className={styles.readKey}>L</span><span data-read="l">{formatPrice(Math.min(lastBar.l, live))}</span></span>
        <span className={styles.readItem}><span className={styles.readKey}>C</span><span data-read="c">{formatPrice(live)}</span></span>
        <span data-read="change" className={styles.readChange} data-direction={change >= 0 ? "up" : "down"}>{formatPercent((change / (live - change)) * 100)}</span>
      </span>
      <span className={styles.readGroup}>
        <span className={styles.readItem}><span className={styles.readKey}>Vol</span><span data-read="volume">{formatVolume(lastBar.v)}</span></span>
        {AVERAGES.map(average => <span key={average.id} className={styles.readItem} data-average={average.id} data-hidden={averages.includes(average.id) ? undefined : ""}>
          <span className={styles.readKey}>{average.label}</span><span data-read={average.id}>n/a</span>
        </span>)}
      </span>
    </div>
    <div
      ref={surface}
      className={styles.surface}
      tabIndex={0}
      role="img"
      aria-roledescription="interactive chart"
      aria-label={`${symbol.ticker} ${range.label} chart, ${range.interval} candles`}
      aria-describedby={descriptionId}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerEnd}
      onPointerCancel={onPointerEnd}
      onPointerLeave={event => { if (event.pointerType === "mouse" && !gesture.current.pointers.size) engine.current?.setCross(null); }}
      onKeyDown={onKeyDown}
      onFocus={onFocus}
      onBlur={onBlur}
    >
      <canvas ref={canvas} className={styles.canvas} aria-hidden="true" />
      <span ref={last} className={styles.lastTag} aria-hidden="true">{formatPrice(live)}</span>
      <span ref={limitTag} className={styles.limitTag} aria-hidden="true" />
      <span ref={crossPrice} className={styles.crossPrice} aria-hidden="true" />
      <span ref={crossTime} className={styles.crossTime} aria-hidden="true" />
    </div>
    <span id={descriptionId} className={styles.srOnly}>Use left and right arrows to inspect candles, shift to move ten, plus and minus to zoom, and 0 to reset the view.</span>
    <span ref={announce} className={styles.srOnly} aria-live="polite" />
  </div>;
}

/* ================================================================ Watchlist */

function Sparkline({ points, base, up }: { points: number[]; base: number; up: boolean }) {
  const W = 64, H = 28;
  const lo = Math.min(base, ...points), hi = Math.max(base, ...points);
  const span = hi - lo || 1;
  const toY = (value: number) => (H - 3 - ((value - lo) / span) * (H - 6)).toFixed(2);
  const path = points.map((value, index) => `${index ? "L" : "M"}${((index / Math.max(1, points.length - 1)) * W).toFixed(2)} ${toY(value)}`).join("");
  return <svg className={styles.spark} data-direction={up ? "up" : "down"} viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden="true">
    <line className={styles.sparkBase} x1="0" x2={W} y1={toY(base)} y2={toY(base)} vectorEffect="non-scaling-stroke" />
    <path className={styles.sparkLine} d={path} vectorEffect="non-scaling-stroke" />
  </svg>;
}

interface WatchRowProps { symbol: MarketSymbol; price: number; points: number[]; selected: boolean; reduced: boolean; onSelect: () => void; onKeyDown: (event: KeyboardEvent<HTMLButtonElement>) => void; }

function WatchRow({ symbol, price, points, selected, reduced, onSelect, onKeyDown }: WatchRowProps) {
  const flash = useRef<HTMLSpanElement>(null);
  const previous = useRef(price);
  // A tick flashes the price cell in the direction it moved: opacity only, fading from the moment of the change.
  useEffect(() => {
    const node = flash.current, before = previous.current;
    previous.current = price;
    if (!node || price === before) return;
    node.dataset.direction = price > before ? "up" : "down";
    node.getAnimations().forEach(animation => animation.cancel());
    node.animate(reduced ? [{ opacity: 1 }, { opacity: 1, offset: .99 }, { opacity: 0 }] : [{ opacity: 1 }, { opacity: 0 }], { duration: duration.considered * (reduced ? 1250 : 1900), easing: `cubic-bezier(${motionTokens.ease.standard.join(",")})` });
  }, [price, reduced]);
  const change = price - symbol.prevClose;
  const percent = (change / symbol.prevClose) * 100;
  const up = change >= 0;
  return <li className={styles.watchItem}>
    <button type="button" className={styles.watchRow} data-ticker={symbol.ticker} aria-current={selected ? "true" : undefined} onClick={onSelect} onKeyDown={onKeyDown}
      aria-label={`${symbol.ticker}, ${symbol.name}, ${formatPrice(price)}, ${up ? "up" : "down"} ${Math.abs(percent).toFixed(2)} percent today`}>
      {selected && <motion.span className={styles.watchSelected} layoutId="watch-selection" transition={reduced ? { duration: 0 } : spring.morph} aria-hidden="true" />}
      <span className={styles.watchName}>
        <span className={styles.watchTicker}>{symbol.ticker}</span>
        <span className={styles.watchCompany}>{symbol.name}</span>
      </span>
      <Sparkline points={points} base={symbol.prevClose} up={up} />
      <span className={styles.watchQuote}>
        <span className={styles.watchPrice}><span ref={flash} className={styles.flash} aria-hidden="true" />{formatPrice(price)}</span>
        <span className={styles.watchChange} data-direction={up ? "up" : "down"}>{formatPercent(percent)}</span>
      </span>
    </button>
  </li>;
}

/* ================================================================ Order ticket */

type Side = "buy" | "sell";
type OrderType = "market" | "limit";
type Phase = { kind: "idle" } | { kind: "pending" } | { kind: "done"; text: string } | { kind: "error"; text: string };

interface TicketProps {
  symbol: MarketSymbol;
  price: number;
  held: number;
  buyingPower: number;
  orders: OrderRecord[];
  side: Side; setSide: (side: Side) => void;
  type: OrderType; setType: (type: OrderType) => void;
  limit: number; setLimit: (value: number) => void;
  reduced: boolean;
  onSubmit: (request: OrderRequest) => Promise<string>;
  onCancel: (order: OrderRecord) => void;
}

function OrderTicket({ symbol, price, held, buyingPower, orders, side, setSide, type, setType, limit, setLimit, reduced, onSubmit, onCancel }: TicketProps) {
  const [shares, setShares] = useState(10);
  const [phase, setPhase] = useState<Phase>({ kind: "idle" });
  const execPrice = type === "limit" ? limit : price;
  const total = shares * execPrice;
  const problem = shares < 1 ? "Enter at least one share."
    : side === "buy" && total > buyingPower ? `This needs ${formatMoney(total)}. You have ${formatMoney(buyingPower)} to spend.`
      : side === "sell" && shares > held ? (held ? `You hold ${held} ${symbol.ticker} shares.` : `You hold no ${symbol.ticker} shares.`) : null;
  const heading = useId();

  useEffect(() => {
    if (phase.kind !== "done" && phase.kind !== "error") return;
    const timer = window.setTimeout(() => setPhase({ kind: "idle" }), 2400);
    return () => window.clearTimeout(timer);
  }, [phase]);

  const submit = async () => {
    if (problem || phase.kind === "pending") return;
    setPhase({ kind: "pending" });
    try { setPhase({ kind: "done", text: await onSubmit({ side, type, ticker: symbol.ticker, shares, price: execPrice }) }); }
    catch { setPhase({ kind: "error", text: "Order not placed. Try again." }); }
  };

  const label = phase.kind === "done" ? <><Check width={16} height={16} aria-hidden="true" />{phase.text}</> : `${side === "buy" ? "Buy" : "Sell"} ${shares} ${symbol.ticker}`;
  const visible = orders.slice(0, 4);
  const layout = reduced ? { duration: 0 } : spring.smooth;

  return <section className={styles.ticket} aria-labelledby={heading}>
    <div className={styles.panelHead}>
      <h2 id={heading} className={styles.panelTitle}>Trade {symbol.ticker}</h2>
      <span className={styles.panelMeta}>{held ? `${held} shares held` : "No position"}</span>
    </div>
    <div className={styles.ticketBody}>
      <div className={styles.ticketSegs}>
        <SegmentedControl label="Side" value={side} onValueChange={value => setSide(value as Side)} options={[{ value: "buy", label: "Buy" }, { value: "sell", label: "Sell" }]} />
        <SegmentedControl label="Order type" value={type} onValueChange={value => setType(value as OrderType)} options={[{ value: "market", label: "Market" }, { value: "limit", label: "Limit" }]} />
      </div>
      <div className={styles.fields}>
        <NumberField label="Shares" value={shares} onValueChange={setShares} min={0} max={100000} step={1} largeStep={10} />
        <AnimatePresence initial={false}>
          {type === "limit" && <motion.div key="limit" className={styles.limitField} initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0, transition: reduced ? { duration: 0 } : { duration: duration.exit, ease: [...motionTokens.ease.exit] } }} transition={layout}>
            <div className={styles.limitInner}>
              <NumberField label="Limit price" value={limit} onValueChange={setLimit} min={.01} max={100000} step={.01} largeStep={1} prefix="$" limitHint={false} />
            </div>
          </motion.div>}
        </AnimatePresence>
      </div>
      <dl className={styles.summary}>
        <div className={styles.summaryRow}><dt>Market price</dt><dd className={styles.num}>{formatMoney(price)}</dd></div>
        <div className={styles.summaryRow}><dt>{side === "buy" ? "Estimated cost" : "Estimated credit"}</dt><dd className={styles.num}>{formatMoney(total)}</dd></div>
        <div className={styles.summaryRow}><dt>Buying power</dt><dd className={styles.num}>{formatMoney(buyingPower)}</dd></div>
      </dl>
      <p className={styles.problem} role="status" data-visible={problem || phase.kind === "error" ? "" : undefined}>{phase.kind === "error" ? phase.text : problem ?? " "}</p>
      <Button className={styles.submit} size="lg" loading={phase.kind === "pending"} disabled={!!problem && phase.kind !== "pending"} onClick={submit}>{label}</Button>
      <p className={styles.simulated}>Paper trading. Prices and orders are simulated.</p>
    </div>
    <div className={styles.orders}>
      <h3 className={styles.ordersTitle}>Orders</h3>
      <ul className={styles.orderList}>
        <AnimatePresence initial={false}>
          {visible.map(order => <motion.li key={order.id} className={styles.orderItem} layout={reduced ? false : "position"} initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0, transition: { duration: reduced ? 0 : duration.exit } }} transition={layout}>
            <div className={styles.order} data-status={order.status}>
              <span className={styles.orderMain}>
                <span className={styles.orderTitle}>{order.side === "buy" ? "Buy" : "Sell"} {order.shares} {order.ticker}</span>
                <span className={styles.orderMeta}>{order.type === "limit" ? "Limit" : "Market"} at {formatMoney(order.price)}, {order.time}</span>
              </span>
              <span className={styles.orderStatus} data-status={order.status}>
                {order.status === "filled" ? "Filled" : order.status === "working" ? "Working" : "Canceled"}
              </span>
              {/* The cancel slot is always reserved, so status badges line up in one column and stay put when an order fills or is canceled. */}
              <span className={styles.orderAction}>
                {order.status === "working" && <button type="button" className={styles.iconButton} onClick={() => onCancel(order)} aria-label={`Cancel ${order.side} ${order.shares} ${order.ticker} at ${formatMoney(order.price)}`}>
                  <X width={16} height={16} aria-hidden="true" />
                </button>}
              </span>
            </div>
          </motion.li>)}
        </AnimatePresence>
      </ul>
    </div>
  </section>;
}

/* ================================================================ Terminal */

/** Series are generated on first use and kept, so live ticks keep extending the same bars across range and symbol switches. */
class SeriesStore {
  private map = new Map<string, Candle[]>();
  peek(ticker: string, range: RangeId) { return this.map.get(seriesKey(ticker, range)); }
  get(symbol: MarketSymbol, spec: RangeSpec): Candle[] {
    let series = this.peek(symbol.ticker, spec.id);
    if (!series) {
      series = generateSeries(symbol, spec);
      // Coarser ranges fold in the five minute session so today's bars agree everywhere.
      if (spec.id !== "1D") alignSession(series, this.get(symbol, rangeOf("1D")), spec.minutes);
      this.map.set(seriesKey(symbol.ticker, spec.id), series);
    }
    return series;
  }
}

/** The demo session opens at 14:05 New York time and runs on the viewer's clock from the moment the terminal mounts. */
const SESSION_START = 14 * 60 + 5;
const sessionClock = (mountedAt: number) => {
  const minute = Math.min(16 * 60, SESSION_START + Math.floor((Date.now() - mountedAt) / 60_000));
  return `${Math.floor(minute / 60)}:${String(minute % 60).padStart(2, "0")}`;
};
const gaussian = () => Math.sqrt(-2 * Math.log(Math.max(1e-9, Math.random()))) * Math.cos(2 * Math.PI * Math.random());

export function MarketTerminal({
  symbols = SYMBOLS,
  holdings: initialHoldings = HOLDINGS,
  buyingPower: initialBuyingPower = BUYING_POWER,
  orders: initialOrders = ORDERS,
  defaultTicker,
  defaultRange = "6M",
  defaultAverages = ["ma20", "ma50"],
  live = true,
  tickInterval = 1200,
  onPlaceOrder,
  onCancelOrder,
  className,
}: MarketTerminalProps) {
  const reduced = useReducedFlag();
  const [ticker, setTicker] = useState(defaultTicker ?? symbols[0]?.ticker ?? "");
  const [rangeId, setRangeId] = useState<RangeId>(defaultRange);
  const [averages, setAverages] = useState<AverageId[]>(defaultAverages);
  const [paused, setPaused] = useState(false);
  const [prices, setPrices] = useState<Record<string, number>>(() => Object.fromEntries(symbols.map(symbol => [symbol.ticker, symbol.price])));
  const [version, setVersion] = useState(0);
  const [holdings, setHoldings] = useState<Record<string, number>>(() => Object.fromEntries(initialHoldings.map(item => [item.ticker, item.shares])));
  const [buyingPower, setBuyingPower] = useState(initialBuyingPower);
  const [orders, setOrders] = useState(initialOrders);
  const [side, setSide] = useState<Side>("buy");
  const [orderType, setOrderType] = useState<OrderType>("market");
  const [limits, setLimits] = useState<Record<string, number>>({});
  const zoomRef = useRef<{ zoom: (factor: number) => void; reset: () => void } | null>(null);
  const titleId = useId();
  const mountedAt = useRef(0);
  useEffect(() => { mountedAt.current = Date.now(); }, []);

  const symbol = symbols.find(item => item.ticker === ticker) ?? symbols[0];
  const range = rangeOf(rangeId);
  const price = prices[symbol.ticker] ?? symbol.price;

  const [store] = useState(() => new SeriesStore());
  const bars = store.get(symbol, range);
  const session = store.get(symbol, rangeOf("1D")).filter(bar => bar.today);
  const dayOpen = session[0]?.o ?? symbol.prevClose;
  const dayHigh = Math.max(...session.map(bar => bar.h));
  const dayLow = Math.min(...session.map(bar => bar.l));
  const dayVolume = session.reduce((sum, bar) => sum + bar.v, 0);

  // Live ticks: a small random walk that leans back toward each symbol's anchor, written into every cached series of that symbol.
  const pricesRef = useRef(prices);
  const tickerRef = useRef(ticker);
  const ordersRef = useRef(orders);
  useEffect(() => { pricesRef.current = prices; tickerRef.current = ticker; ordersRef.current = orders; });
  const streaming = live && !paused;
  useEffect(() => {
    if (!streaming) return;
    const tick = () => {
      if (document.hidden) return;
      const next = { ...pricesRef.current };
      for (const item of symbols) {
        if (item.ticker !== tickerRef.current && Math.random() > .45) continue;
        const current = next[item.ticker] ?? item.price;
        const r = item.vol * .055 * gaussian() - .06 * Math.log(current / item.price);
        const value = Math.max(.01, Math.round(current * Math.exp(r) * 100) / 100);
        if (value === current) continue;
        next[item.ticker] = value;
        const volume = Math.round(item.avgVolume / 78 * .04 * (.5 + Math.random()));
        for (const spec of RANGES) {
          const series = store.peek(item.ticker, spec.id);
          const bar = series?.[series.length - 1];
          if (!bar) continue;
          bar.c = value; bar.h = Math.max(bar.h, value); bar.l = Math.min(bar.l, value); bar.v += volume;
        }
      }
      pricesRef.current = next;
      setPrices(next);
      setVersion(value => value + 1);
      // Working limit orders fill when the live price crosses them.
      const fills = ordersRef.current.filter(order => order.status === "working" && next[order.ticker] !== undefined && (order.side === "buy" ? next[order.ticker] <= order.price : next[order.ticker] >= order.price));
      if (fills.length) {
        const time = sessionClock(mountedAt.current);
        setOrders(list => list.map(order => fills.some(fill => fill.id === order.id) ? { ...order, status: "filled", time } : order));
        for (const fill of fills) {
          setHoldings(map => ({ ...map, [fill.ticker]: (map[fill.ticker] ?? 0) + (fill.side === "buy" ? fill.shares : -fill.shares) }));
          setBuyingPower(value => value + (fill.side === "buy" ? -1 : 1) * fill.shares * fill.price);
        }
      }
    };
    const timer = window.setInterval(tick, tickInterval);
    return () => window.clearInterval(timer);
  }, [streaming, symbols, tickInterval, store]);

  // A draft limit starts one percent through the market and then holds still while prices tick, until the side or symbol changes.
  const draftLimit = (item: string, nextSide: Side, map: Record<string, number> = prices) => Math.round((map[item] ?? price) * (nextSide === "buy" ? .99 : 1.01) * 100) / 100;
  const limit = limits[symbol.ticker] ?? draftLimit(symbol.ticker, side);
  const setLimit = (value: number) => setLimits(map => ({ ...map, [symbol.ticker]: value }));
  const seedLimit = (item: string, nextSide: Side) => setLimits(map => ({ ...map, [item]: draftLimit(item, nextSide, pricesRef.current) }));
  const changeSide = (next: Side) => { setSide(next); seedLimit(symbol.ticker, next); };
  const changeType = (next: OrderType) => { setOrderType(next); if (next === "limit" && limits[symbol.ticker] === undefined) seedLimit(symbol.ticker, side); };
  const selectTicker = (next: string) => { setTicker(next); if (orderType === "limit" && limits[next] === undefined) seedLimit(next, side); };

  const submit = async (request: OrderRequest) => {
    await Promise.all([onPlaceOrder?.(request), new Promise(resolve => window.setTimeout(resolve, 650))]);
    const now = pricesRef.current[request.ticker] ?? request.price;
    const marketable = request.type === "market" || (request.side === "buy" ? now <= request.price : now >= request.price);
    // A marketable limit fills at the better of the limit and the live price.
    const fillPrice = request.type === "market" ? now : !marketable ? request.price : request.side === "buy" ? Math.min(request.price, now) : Math.max(request.price, now);
    const record: OrderRecord = { id: `o-${Date.now()}`, side: request.side, type: request.type, ticker: request.ticker, shares: request.shares, price: Math.round(fillPrice * 100) / 100, status: marketable ? "filled" : "working", time: sessionClock(mountedAt.current) };
    setOrders(list => [record, ...list]);
    if (!marketable) return "Order placed";
    setHoldings(map => ({ ...map, [request.ticker]: (map[request.ticker] ?? 0) + (request.side === "buy" ? request.shares : -request.shares) }));
    setBuyingPower(value => value + (request.side === "buy" ? -1 : 1) * request.shares * record.price);
    return `Filled at ${formatMoney(record.price)}`;
  };
  const cancel = (order: OrderRecord) => {
    void onCancelOrder?.(order);
    setOrders(list => list.map(item => item.id === order.id ? { ...item, status: "canceled" } : item));
  };

  // Watchlist: arrows move between rows, like a list.
  const listRef = useRef<HTMLUListElement>(null);
  const onRowKey = (event: KeyboardEvent<HTMLButtonElement>) => {
    if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
    const rows = [...(listRef.current?.querySelectorAll<HTMLButtonElement>("button[data-ticker]") ?? [])];
    const index = rows.indexOf(event.currentTarget);
    const target = event.key === "Home" ? 0 : event.key === "End" ? rows.length - 1 : clamp(index + (event.key === "ArrowDown" ? 1 : -1), 0, rows.length - 1);
    event.preventDefault();
    rows[target]?.focus();
  };

  const toggleAverage = (id: AverageId) => setAverages(list => list.includes(id) ? list.filter(item => item !== id) : [...list, id]);
  const change = price - symbol.prevClose;
  const percent = (change / symbol.prevClose) * 100;
  const up = change >= 0;
  const Arrow = up ? ArrowUpRight : ArrowDownRight;
  const sparkPoints = useMemo(() => {
    const map: Record<string, number[]> = {};
    for (const item of symbols) map[item.ticker] = store.get(item, rangeOf("1D")).filter(bar => bar.today).map(bar => bar.c);
    return map;
    // The cached bars are extended in place on every tick; version marks that.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [symbols, store, version]);

  return <div className={`${styles.root} ${className ?? ""}`}>
    <div className={styles.shell}>
      <section className={styles.main} aria-labelledby={titleId}>
        <header className={styles.header}>
          <div className={styles.identity}>
            <h1 id={titleId} className={styles.title}><span className={styles.ticker}>{symbol.ticker}</span><span className={styles.company}>{symbol.name}</span></h1>
            <p className={styles.exchange}>{symbol.exchange}, USD</p>
          </div>
          <div className={styles.quote}>
            <span className={styles.price}><AnimatedCounter value={price} prefix="$" decimals={2} /></span>
            <span className={styles.change} data-direction={up ? "up" : "down"}>
              <Arrow width={16} height={16} aria-hidden="true" />
              <span className={styles.num}>{formatSigned(change)} ({formatPercent(percent)})</span>
              <span className={styles.changeLabel}>today</span>
            </span>
          </div>
          <dl className={styles.stats}>
            <div className={styles.stat}><dt>Open</dt><dd className={styles.num}>{formatPrice(dayOpen)}</dd></div>
            <div className={styles.stat}><dt>High</dt><dd className={styles.num}>{formatPrice(dayHigh)}</dd></div>
            <div className={styles.stat}><dt>Low</dt><dd className={styles.num}>{formatPrice(dayLow)}</dd></div>
            <div className={styles.stat}><dt>Volume</dt><dd className={styles.num}>{formatVolume(dayVolume)}</dd></div>
          </dl>
          <button type="button" className={styles.liveButton} aria-pressed={!streaming} onClick={() => setPaused(value => !value)} disabled={!live}
            aria-label={streaming ? "Pause live prices" : "Resume live prices"}>
            <span className={styles.liveDot} data-live={streaming ? "" : undefined} aria-hidden="true" />
            <span className={styles.liveText}>{streaming ? "Live" : "Paused"}</span>
            {streaming ? <Pause width={16} height={16} aria-hidden="true" /> : <Play width={16} height={16} aria-hidden="true" />}
          </button>
        </header>

        <div className={styles.toolbar}>
          <div className={styles.seg}>
            <SegmentedControl label="Time range" value={rangeId} onValueChange={value => setRangeId(value as RangeId)} options={RANGES.map(item => ({ value: item.id, label: item.label }))} />
          </div>
          <div className={styles.tools}>
            <div className={styles.toggles} role="group" aria-label="Moving averages">
              {AVERAGES.map(average => <button key={average.id} type="button" className={styles.toggle} data-average={average.id} aria-pressed={averages.includes(average.id)} onClick={() => toggleAverage(average.id)}>
                <span className={styles.swatch} aria-hidden="true" />{average.label}
              </button>)}
            </div>
            <div className={styles.zoom} role="group" aria-label="Zoom">
              <button type="button" className={styles.iconButton} onClick={() => zoomRef.current?.zoom(.7)} aria-label="Zoom in"><ZoomIn width={16} height={16} aria-hidden="true" /></button>
              <button type="button" className={styles.iconButton} onClick={() => zoomRef.current?.zoom(1.45)} aria-label="Zoom out"><ZoomOut width={16} height={16} aria-hidden="true" /></button>
              <button type="button" className={styles.iconButton} onClick={() => zoomRef.current?.reset()} aria-label="Reset view"><Maximize2 width={16} height={16} aria-hidden="true" /></button>
            </div>
          </div>
        </div>

        <PriceChart bars={bars} seriesId={seriesKey(symbol.ticker, range.id)} range={range} symbol={symbol} live={price} averages={averages} limit={orderType === "limit" ? limit : null} reduced={reduced} zoomRef={zoomRef} />
      </section>

      <aside className={styles.side} aria-label="Watchlist and order ticket">
        <section className={styles.watch} aria-labelledby={`${titleId}-watch`}>
          <div className={styles.panelHead}>
            <h2 id={`${titleId}-watch`} className={styles.panelTitle}>Watchlist</h2>
            <span className={styles.panelMeta}>{symbols.length} symbols</span>
          </div>
          <LayoutGroup id={`${titleId}-watchlist`}>
            <ul ref={listRef} className={styles.watchList}>
              {symbols.map(item => <WatchRow key={item.ticker} symbol={item} price={prices[item.ticker] ?? item.price} points={sparkPoints[item.ticker] ?? []} selected={item.ticker === symbol.ticker} reduced={reduced} onSelect={() => selectTicker(item.ticker)} onKeyDown={onRowKey} />)}
            </ul>
          </LayoutGroup>
        </section>
        <OrderTicket symbol={symbol} price={price} held={holdings[symbol.ticker] ?? 0} buyingPower={buyingPower} orders={orders} side={side} setSide={changeSide} type={orderType} setType={changeType} limit={limit} setLimit={setLimit} reduced={reduced} onSubmit={submit} onCancel={cancel} />
      </aside>
    </div>
  </div>;
}

export default MarketTerminal;
