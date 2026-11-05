/**
 * Sample market data for the market terminal. Everything is deterministic (seeded by ticker and range), so the server and the first
 * client render draw the same candles. The session is fixed at Thursday, September 24, 2026, 14:05 New York time.
 */

export type RangeId = "1D" | "5D" | "1M" | "6M" | "1Y";

export interface Candle {
  o: number;
  h: number;
  l: number;
  c: number;
  v: number;
  /** Full time for the readout, such as "Sep 24, 10:35" or "Sep 23, 2026". */
  label: string;
  /** Short axis label, such as "10:30", "Sep 23" or "Oct". */
  tick: string;
  /** Rank for axis labels: 2 starts a month (or a day on intraday ranges), 1 an ordinary slot. */
  rank: number;
  /** True for bars inside the current session, which live ticks update. */
  today: boolean;
}

export interface MarketSymbol {
  ticker: string;
  name: string;
  exchange: string;
  /** Last price at the start of the demo. */
  price: number;
  prevClose: number;
  /** Daily volatility as a fraction, such as .024. */
  vol: number;
  /** Average daily volume in shares. */
  avgVolume: number;
}

export interface RangeSpec {
  id: RangeId;
  label: string;
  /** Candle interval, spoken and shown in the chart description. */
  interval: string;
  /** Bars in the default view. */
  count: number;
  /** Extra history before the default view: moving averages start warm and panning left has somewhere to go. */
  warm: number;
  /** Minutes per bar, or 0 for daily bars. */
  minutes: number;
}

export interface Holding { ticker: string; shares: number; }

export interface OrderRecord {
  id: string;
  side: "buy" | "sell";
  type: "market" | "limit";
  ticker: string;
  shares: number;
  price: number;
  status: "filled" | "working" | "canceled";
  time: string;
}

export const SYMBOLS: MarketSymbol[] = [
  { ticker: "NVDA", name: "NVIDIA", exchange: "Nasdaq", price: 186.42, prevClose: 182.97, vol: .024, avgVolume: 182_000_000 },
  { ticker: "AAPL", name: "Apple", exchange: "Nasdaq", price: 238.15, prevClose: 239.02, vol: .014, avgVolume: 52_000_000 },
  { ticker: "MSFT", name: "Microsoft", exchange: "Nasdaq", price: 514.6, prevClose: 509.88, vol: .012, avgVolume: 21_000_000 },
  { ticker: "AMZN", name: "Amazon", exchange: "Nasdaq", price: 226.34, prevClose: 228.1, vol: .018, avgVolume: 41_000_000 },
  { ticker: "GOOGL", name: "Alphabet", exchange: "Nasdaq", price: 251.73, prevClose: 248.66, vol: .016, avgVolume: 31_000_000 },
  { ticker: "META", name: "Meta Platforms", exchange: "Nasdaq", price: 768.2, prevClose: 772.45, vol: .02, avgVolume: 12_000_000 },
  { ticker: "TSLA", name: "Tesla", exchange: "Nasdaq", price: 412.88, prevClose: 401.3, vol: .035, avgVolume: 94_000_000 },
  { ticker: "JPM", name: "JPMorgan Chase", exchange: "NYSE", price: 301.12, prevClose: 299.64, vol: .013, avgVolume: 9_000_000 },
];

export const RANGES: RangeSpec[] = [
  { id: "1D", label: "1D", interval: "5 minute", count: 56, warm: 40, minutes: 5 },
  { id: "5D", label: "5D", interval: "30 minute", count: 62, warm: 39, minutes: 30 },
  { id: "1M", label: "1M", interval: "daily", count: 21, warm: 50, minutes: 0 },
  { id: "6M", label: "6M", interval: "daily", count: 126, warm: 50, minutes: 0 },
  { id: "1Y", label: "1Y", interval: "daily", count: 252, warm: 50, minutes: 0 },
];

export const HOLDINGS: Holding[] = [
  { ticker: "NVDA", shares: 120 },
  { ticker: "AAPL", shares: 45 },
  { ticker: "MSFT", shares: 18 },
  { ticker: "TSLA", shares: 12 },
  { ticker: "JPM", shares: 30 },
];

export const BUYING_POWER = 24_860.35;

export const ORDERS: OrderRecord[] = [
  { id: "o-2", side: "sell", type: "limit", ticker: "MSFT", shares: 4, price: 516, status: "working", time: "11:18" },
  { id: "o-1", side: "buy", type: "market", ticker: "NVDA", shares: 20, price: 183.64, status: "filled", time: "10:42" },
];

/** Moving averages the chart can overlay, in draw order. */
export const AVERAGES = [
  { id: "ma20", period: 20, label: "MA 20" },
  { id: "ma50", period: 50, label: "MA 50" },
] as const;
export type AverageId = (typeof AVERAGES)[number]["id"];

/* ---------------------------------------------------------------- Calendar */

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** US market holidays inside the generated history. */
const HOLIDAYS = new Set(["2025-09-01", "2025-11-27", "2025-12-25", "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25", "2026-06-19", "2026-07-03", "2026-09-07"]);
const TODAY = { y: 2026, m: 8, d: 24 };
/** The live session has printed up to 14:05. */
const NOW_MINUTE = 14 * 60 + 5;
const OPEN_MINUTE = 9 * 60 + 30;
const CLOSE_MINUTE = 16 * 60;

type Day = { y: number; m: number; d: number };
const dayKey = ({ y, m, d }: Day) => `${y}-${String(m + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
function previousTradingDay(day: Day): Day {
  const date = new Date(Date.UTC(day.y, day.m, day.d));
  do date.setUTCDate(date.getUTCDate() - 1);
  while (date.getUTCDay() === 0 || date.getUTCDay() === 6 || HOLIDAYS.has(date.toISOString().slice(0, 10)));
  return { y: date.getUTCFullYear(), m: date.getUTCMonth(), d: date.getUTCDate() };
}
const clock = (minute: number) => `${Math.floor(minute / 60)}:${String(minute % 60).padStart(2, "0")}`;

type Slot = { day: Day; minute: number };
/** Bar start times, newest first. Intraday bars run 9:30 to 16:00 and the current session stops at the live bar. */
function slotsFor(range: RangeSpec, total: number): Slot[] {
  const slots: Slot[] = [];
  let day: Day = TODAY;
  if (!range.minutes) {
    while (slots.length < total) { slots.push({ day, minute: 0 }); day = previousTradingDay(day); }
    return slots;
  }
  let minute = OPEN_MINUTE + Math.floor((NOW_MINUTE - OPEN_MINUTE) / range.minutes) * range.minutes;
  while (slots.length < total) {
    slots.push({ day, minute });
    minute -= range.minutes;
    if (minute < OPEN_MINUTE) { day = previousTradingDay(day); minute = CLOSE_MINUTE - range.minutes; }
  }
  return slots;
}

/* ---------------------------------------------------------------- Random */

function seedOf(text: string) {
  let hash = 2166136261;
  for (let index = 0; index < text.length; index++) hash = Math.imul(hash ^ text.charCodeAt(index), 16777619);
  return hash >>> 0;
}
function mulberry(seed: number) {
  let state = seed;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function gaussian(random: () => number) {
  const u = Math.max(1e-9, random()), v = random();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

/* ---------------------------------------------------------------- Series */

const round = (value: number) => Math.round(value * 100) / 100;

/** Intraday volume runs in a smile: heavy at the open, quiet at lunch, busy into the close. */
function smile(minute: number) {
  const t = (minute - OPEN_MINUTE) / (CLOSE_MINUTE - OPEN_MINUTE);
  return .62 + 1.5 * (t - .5) ** 2 * 4 * (t < .5 ? 1.25 : .9);
}

/**
 * Candles for one symbol and range, oldest first. The session's bars follow a Brownian bridge from the previous close to the
 * current price, so the day's change is exact; history walks backward from the previous close with a slow drift so trends read.
 */
export function generateSeries(symbol: MarketSymbol, range: RangeSpec): Candle[] {
  const total = range.count + range.warm;
  const slots = slotsFor(range, total).reverse();
  const random = mulberry(seedOf(`${symbol.ticker}:${range.id}`));
  const perDay = range.minutes ? (CLOSE_MINUTE - OPEN_MINUTE) / range.minutes : 1;
  const sigma = symbol.vol / Math.sqrt(perDay);
  const todayKey = dayKey(TODAY);
  const isToday = slots.map(slot => dayKey(slot.day) === todayKey);
  const firstToday = isToday.indexOf(true);
  const closes = new Array<number>(total);

  // Today: a bridge from the previous close to the live price.
  const steps = total - firstToday;
  const walk = [0];
  for (let index = 1; index <= steps; index++) walk.push(walk[index - 1] + gaussian(random));
  const drift = Math.log(symbol.price / symbol.prevClose);
  for (let index = 1; index <= steps; index++) {
    const bridge = walk[index] - (index / steps) * walk[steps];
    closes[firstToday + index - 1] = symbol.prevClose * Math.exp((index / steps) * drift + bridge * sigma * .9);
  }
  // History: walk backward from the previous close.
  const phase = random() * 10;
  let close = symbol.prevClose;
  for (let index = firstToday - 1; index >= 0; index--) {
    closes[index] = close;
    const trend = .32 * Math.sin(index / 19 + phase) + .18 * Math.sin(index / 7.3 + phase * 2);
    close = close / Math.exp(sigma * (gaussian(random) + trend * .6));
  }

  return slots.map((slot, index) => {
    const c = closes[index];
    const newDay = index === 0 || dayKey(slots[index - 1].day) !== dayKey(slot.day);
    const previous = index === 0 ? c / Math.exp(sigma * gaussian(random)) : closes[index - 1];
    const gap = range.minutes && !newDay ? 0 : sigma * (range.minutes ? 1.6 : .35) * gaussian(random);
    const o = index === firstToday ? symbol.prevClose * Math.exp(gap * .5) : previous * Math.exp(gap);
    const wick = sigma * .55;
    const h = Math.max(o, c) * Math.exp(Math.abs(gaussian(random)) * wick);
    const l = Math.min(o, c) * Math.exp(-Math.abs(gaussian(random)) * wick);
    const move = Math.abs(Math.log(c / o)) / sigma;
    const base = symbol.avgVolume / perDay * (range.minutes ? smile(slot.minute) : 1);
    const v = Math.round(base * Math.exp(.28 * gaussian(random)) * (.75 + .25 * move));
    const { y, m, d } = slot.day;
    const date = `${MONTHS[m]} ${d}`;
    const newMonth = index === 0 || slots[index - 1].day.m !== m;
    return {
      o: round(o), h: round(h), l: round(l), c: round(c), v,
      label: range.minutes ? `${date}, ${clock(slot.minute)}` : `${date}, ${y}`,
      tick: range.minutes ? (newDay ? date : clock(slot.minute)) : newMonth ? (m === 0 ? String(y) : MONTHS[m]) : date,
      rank: range.minutes ? (newDay ? 2 : slot.minute % 60 === 0 ? 1 : 0) : newMonth ? 2 : 1,
      today: isToday[index],
    };
  });
}

/** Folds today's five minute bars into the current bar of a coarser series so the session reads the same on every range. */
export function alignSession(series: Candle[], session: Candle[], minutes: number) {
  const today = session.filter(bar => bar.today);
  if (!today.length) return;
  const target = series.filter(bar => bar.today);
  const group = minutes ? minutes / 5 : today.length;
  target.forEach((bar, index) => {
    const slice = today.slice(index * group, (index + 1) * group);
    if (!slice.length) return;
    bar.o = slice[0].o;
    bar.c = slice[slice.length - 1].c;
    bar.h = Math.max(...slice.map(item => item.h));
    bar.l = Math.min(...slice.map(item => item.l));
    bar.v = slice.reduce((sum, item) => sum + item.v, 0);
  });
}

/** Simple moving average of closes; null until the window fills. */
export function movingAverage(bars: Candle[], period: number): (number | null)[] {
  const out: (number | null)[] = new Array(bars.length).fill(null);
  let sum = 0;
  for (let index = 0; index < bars.length; index++) {
    sum += bars[index].c;
    if (index >= period) sum -= bars[index - period].c;
    if (index >= period - 1) out[index] = sum / period;
  }
  return out;
}

/* ---------------------------------------------------------------- Format */

const priceFormat = new Intl.NumberFormat("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const moneyFormat = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 2 });
export const formatPrice = (value: number) => priceFormat.format(value);
export const formatMoney = (value: number) => moneyFormat.format(value);
export const formatSigned = (value: number) => `${value >= 0 ? "+" : "−"}${priceFormat.format(Math.abs(value))}`;
export const formatPercent = (value: number) => `${value >= 0 ? "+" : "−"}${Math.abs(value).toFixed(2)}%`;
export function formatVolume(value: number) {
  if (value >= 1e9) return `${(value / 1e9).toFixed(2)}B`;
  if (value >= 1e6) return `${(value / 1e6).toFixed(value >= 1e8 ? 0 : 1)}M`;
  if (value >= 1e3) return `${(value / 1e3).toFixed(0)}K`;
  return String(Math.round(value));
}

/** A tidy step for about `count` grid lines across `span`. */
export function niceStep(span: number, count: number) {
  const raw = span / Math.max(1, count);
  const power = 10 ** Math.floor(Math.log10(raw));
  const unit = raw / power;
  return (unit < 1.5 ? 1 : unit < 3 ? 2 : unit < 7 ? 5 : 10) * power;
}
