"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import type { CSSProperties, KeyboardEvent, PointerEvent, ReactNode } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { CircleCheckIcon as CircleCheck } from "../../../icons/CircleCheckIcon";
import { CircleDashedIcon as CircleDashed } from "../../../icons/CircleDashedIcon";
import { Mail01Icon as Mail } from "../../../icons/Mail01Icon";
import { TrendingUpIcon as TrendingUp } from "../../../icons/TrendingUpIcon";
import { TriangleAlertIcon as TriangleAlert } from "../../../icons/TriangleAlertIcon";
import { Button } from "../../button/button";
import { Switch } from "../../switch/switch";
import { PagerDutyMark, SlackMark } from "./spend-alert-marks";
import styles from "./spend-alert.module.css";

export type SpendAlertChannel = "email" | "slack" | "pagerduty";

export interface SpendAlertSettings {
  /** Monthly budget in whole currency units. */
  budget: number;
  /** Alert threshold as a percent of the budget, 10 to 100. */
  threshold: number;
  channels: Record<SpendAlertChannel, boolean>;
  /** Block new requests once spend reaches 100% of the budget. */
  hardStop: boolean;
}

export interface SpendAlertPeriod {
  /** Month name used in copy, e.g. "October". */
  label: string;
  /** Short month used in dates, e.g. "Oct". */
  short: string;
  /** Day of the period today (1-based). */
  day: number;
  /** Days in the period. */
  days: number;
  /** When the budget resets, e.g. "Nov 1". */
  resetsOn: string;
}

export interface SpendAlertProps {
  /** Card title. */
  title?: string;
  /** Project or workspace the budget applies to. Used in the subtitle and the Slack message. */
  project?: string;
  /** What is being metered, shown in the subtitle. */
  scope?: string;
  /** Spend so far this period. */
  spend?: number;
  /** Projected spend at period end. Defaults to a linear projection from `spend` and `period`. */
  forecast?: number;
  period?: SpendAlertPeriod;
  /** ISO 4217 currency code for formatting. */
  currency?: string;
  /** Initial settings. Anything left out falls back to the demo defaults. */
  defaultValue?: Partial<SpendAlertSettings>;
  /** Threshold markers on the bar. The slider snaps to them while dragging. */
  markers?: number[];
  /** Where each channel delivers. */
  destinations?: Partial<Record<SpendAlertChannel, string>>;
  /** Sender name in the Slack preview. */
  appName?: string;
  /** Footer copy while nothing has changed. */
  lastSaved?: string;
  /** Called on every change. */
  onChange?: (settings: SpendAlertSettings) => void;
  /** Persist the settings. Without it the save is simulated. Reject to show the error state. */
  onSave?: (settings: SpendAlertSettings, signal: AbortSignal) => Promise<void>;
  /** Send a test alert to the enabled channels. Without it the send is simulated. */
  onSendTest?: (settings: SpendAlertSettings, signal: AbortSignal) => Promise<void>;
  className?: string;
}

type Phase = "idle" | "saving" | "saved" | "testing" | "tested" | "error";
type Tone = "success" | "warning" | "danger" | "muted";

const defaultPeriod: SpendAlertPeriod = { label: "October", short: "Oct", day: 27, days: 31, resetsOn: "Nov 1" };
const defaultDestinations: Record<SpendAlertChannel, string> = { email: "finance@acme.com", slack: "#eng-spend", pagerduty: "Platform on-call" };
const defaultSettings: SpendAlertSettings = { budget: 5000, threshold: 80, channels: { email: true, slack: true, pagerduty: false }, hardStop: false };
const MIN = 10;
const enter = [0.16, 1, 0.3, 1] as const;

const cx = (...names: Array<string | false | null | undefined>) => names.filter(Boolean).join(" ");
const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));
const parseBudget = (text: string) => { const value = parseFloat(text.replace(/[^0-9.]/g, "")); return Number.isFinite(value) ? Math.min(value, 10_000_000) : 0; };
const formatBudget = (value: number) => value.toLocaleString("en-US", { maximumFractionDigits: 2 });
const sameSettings = (a: SpendAlertSettings, b: SpendAlertSettings) => a.budget === b.budget && a.threshold === b.threshold && a.hardStop === b.hardStop && a.channels.email === b.channels.email && a.channels.slack === b.channels.slack && a.channels.pagerduty === b.channels.pagerduty;
const joinList = (items: string[]) => items.length <= 1 ? items.join("") : `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;

function wait(ms: number, signal: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    const timer = setTimeout(resolve, ms);
    signal.addEventListener("abort", () => { clearTimeout(timer); reject(new DOMException("Aborted", "AbortError")); }, { once: true });
  });
}

/** One crossfade per swap: the old line fades out in 100ms while the new one fades in over 160ms and rises 2px. Both share one grid cell, so nothing reflows. */
function Fade({ id, children, className }: { id: string; children: ReactNode; className?: string }) {
  const reduced = useReducedMotion();
  return (
    <span className={cx(styles.fade, className)}>
      <AnimatePresence initial={false}>
        <motion.span
          key={id}
          className={styles.fadeItem}
          initial={reduced ? { opacity: 0 } : { opacity: 0, y: 2 }}
          animate={{ opacity: 1, y: 0, transition: { duration: reduced ? 0.12 : 0.16, ease: enter } }}
          exit={{ opacity: 0, transition: { duration: 0.1 } }}
        >
          {children}
        </motion.span>
      </AnimatePresence>
    </span>
  );
}

const toneIcon: Record<Tone, typeof CircleCheck> = { success: CircleCheck, warning: TriangleAlert, danger: TriangleAlert, muted: CircleDashed };

function StatusLine({ tone, icon, children }: { tone: Tone; icon?: typeof CircleCheck; children: ReactNode }) {
  const Icon = icon ?? toneIcon[tone];
  return <><Icon width={14} height={14} className={styles.toneIcon} data-tone={tone} aria-hidden="true" /><span className={styles.ellipsis}>{children}</span></>;
}

interface BarProps {
  value: number;
  onChange: (value: number) => void;
  spendPct: number;
  forecastPct: number;
  markers: number[];
  labelId: string;
  valueText: string;
  disabled: boolean;
  over: boolean;
}

/** Threshold slider drawn on the spend bar: spend and forecast fill the track, the thumb sets the alert line, and spend past the line turns to warning. */
export function ThresholdBar({ value, onChange, spendPct, forecastPct, markers, labelId, valueText, disabled, over }: BarProps) {
  const reduced = useReducedMotion();
  const railRef = useRef<HTMLDivElement>(null);
  const thumbRef = useRef<HTMLDivElement>(null);
  const pointer = useRef<{ id: number; moved: boolean } | null>(null);
  const [dragging, setDragging] = useState(false);
  const [pressed, setPressed] = useState(false);
  // The fill grows in once, when the card first scrolls into view.
  const [seen, setSeen] = useState(false);
  const [intro, setIntro] = useState(false);

  useEffect(() => {
    const node = railRef.current;
    if (!node) return;
    if (reduced) return;
    if (typeof IntersectionObserver === "undefined") { const frame = requestAnimationFrame(() => setSeen(true)); return () => cancelAnimationFrame(frame); }
    const observer = new IntersectionObserver(([entry]) => {
      if (!entry?.isIntersecting) return;
      observer.disconnect();
      setIntro(true);
      requestAnimationFrame(() => setSeen(true));
    }, { threshold: 0.4 });
    observer.observe(node);
    return () => observer.disconnect();
  }, [reduced]);

  useEffect(() => {
    if (!intro) return;
    const timer = setTimeout(() => setIntro(false), 760);
    return () => clearTimeout(timer);
  }, [intro]);

  const sorted = useMemo(() => [...markers].sort((a, b) => a - b), [markers]);

  const fromX = (x: number) => {
    const rect = railRef.current?.getBoundingClientRect();
    if (!rect || rect.width === 0) return value;
    const raw = clamp(Math.round(((x - rect.left) / rect.width) * 100), MIN, 100);
    return sorted.find(marker => Math.abs(marker - raw) <= 2) ?? raw;
  };

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (disabled || event.button !== 0) return;
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    pointer.current = { id: event.pointerId, moved: false };
    setPressed(true);
    thumbRef.current?.focus({ preventScroll: true });
    onChange(fromX(event.clientX));
  };
  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const active = pointer.current;
    if (!active || active.id !== event.pointerId) return;
    if (!active.moved) { active.moved = true; setDragging(true); }
    onChange(fromX(event.clientX));
  };
  const release = () => { pointer.current = null; setDragging(false); setPressed(false); };

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    const step = event.shiftKey ? 10 : 1;
    let next: number | undefined;
    if (event.key === "ArrowRight" || event.key === "ArrowUp") next = value + step;
    else if (event.key === "ArrowLeft" || event.key === "ArrowDown") next = value - step;
    else if (event.key === "PageUp") next = sorted.find(marker => marker > value) ?? 100;
    else if (event.key === "PageDown") next = [...sorted].reverse().find(marker => marker < value) ?? MIN;
    else if (event.key === "Home") next = MIN;
    else if (event.key === "End") next = 100;
    if (next === undefined) return;
    event.preventDefault();
    onChange(clamp(next, MIN, 100));
  };

  const visible = seen || Boolean(reduced);
  const vars = { "--t": `${value}%`, "--spend": `${visible ? spendPct : 0}%`, "--forecast": `${visible ? forecastPct : 0}%` } as CSSProperties;

  return (
    <div className={styles.bar} style={vars} data-dragging={dragging || undefined} data-intro={intro || undefined} data-disabled={disabled || undefined} data-over={(visible && over) || undefined}>
      <div ref={railRef} className={styles.rail} onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={release} onPointerCancel={release} onLostPointerCapture={release}>
        <div className={styles.track} aria-hidden="true">
          <span className={styles.forecastFill} />
          <span className={styles.spendFill} />
          <span className={styles.overFill} />
          {sorted.filter(marker => marker < 100).map(marker => <span key={marker} className={styles.notch} style={{ left: `${marker}%` }} />)}
        </div>
        <div
          ref={thumbRef}
          className={styles.thumb}
          data-pressed={pressed || undefined}
          role="slider"
          tabIndex={disabled ? -1 : 0}
          aria-labelledby={labelId}
          aria-valuemin={MIN}
          aria-valuemax={100}
          aria-valuenow={value}
          aria-valuetext={valueText}
          aria-disabled={disabled || undefined}
          onKeyDown={disabled ? undefined : onKeyDown}
        />
      </div>
      <div className={styles.markers}>
        {sorted.map(marker => (
          <button
            key={marker}
            type="button"
            tabIndex={-1}
            className={styles.marker}
            data-edge={marker === 100 || undefined}
            data-active={marker === value || undefined}
            style={{ left: `${marker}%` }}
            disabled={disabled}
            onClick={() => onChange(marker)}
            aria-label={`Alert at ${marker}%`}
          >
            {marker}%
          </button>
        ))}
      </div>
    </div>
  );
}

/** Budget and spend alert settings in one card: a monthly budget, a threshold set on the live spend bar, delivery channels, a hard stop, and the Slack message the alert will post. */
export function SpendAlert({
  title = "Spend alerts",
  project = "Production",
  scope = "Model API usage",
  spend = 3412.8,
  forecast: forecastProp,
  period = defaultPeriod,
  currency = "USD",
  defaultValue,
  markers = [50, 80, 100],
  destinations: destinationsProp,
  appName = "Acme Billing",
  lastSaved = "Last edited Oct 24 by Maya Chen",
  onChange,
  onSave,
  onSendTest,
  className,
}: SpendAlertProps) {
  const uid = useId();
  const ids = { title: `${uid}-title`, budget: `${uid}-budget`, budgetMeta: `${uid}-budget-meta`, threshold: `${uid}-threshold`, hardStop: `${uid}-hardstop` };
  const destinations = { ...defaultDestinations, ...destinationsProp };
  const initial = useMemo<SpendAlertSettings>(() => ({ ...defaultSettings, ...defaultValue, channels: { ...defaultSettings.channels, ...defaultValue?.channels } }), []); // eslint-disable-line react-hooks/exhaustive-deps

  const [budgetText, setBudgetText] = useState(() => formatBudget(initial.budget));
  const [threshold, setThreshold] = useState(() => clamp(Math.round(initial.threshold), MIN, 100));
  const [channels, setChannels] = useState(initial.channels);
  const [hardStop, setHardStop] = useState(initial.hardStop);
  const [saved, setSaved] = useState(initial);
  const [phase, setPhase] = useState<Phase>("idle");
  const [testedTo, setTestedTo] = useState("");
  const [flash, setFlash] = useState(0);
  const controller = useRef<AbortController | null>(null);

  const budget = parseBudget(budgetText);
  const settings = useMemo<SpendAlertSettings>(() => ({ budget, threshold, channels, hardStop }), [budget, threshold, channels, hardStop]);
  const valid = budget > 0;
  const dirty = !sameSettings(settings, saved);
  const busy = phase === "saving" || phase === "testing";

  const money = useMemo(() => {
    const whole = new Intl.NumberFormat("en-US", { style: "currency", currency, maximumFractionDigits: 0 });
    const cents = new Intl.NumberFormat("en-US", { style: "currency", currency, minimumFractionDigits: 2, maximumFractionDigits: 2 });
    return (value: number, withCents = false) => (withCents ? cents : whole).format(value);
  }, [currency]);

  const daily = spend / Math.max(1, period.day);
  const forecast = forecastProp ?? daily * period.days;
  const alertAt = (budget * threshold) / 100;
  const spendPct = valid ? clamp((spend / budget) * 100, 0, 100) : 0;
  const forecastPct = valid ? clamp((forecast / budget) * 100, 0, 100) : 0;
  const daysLeft = period.days - period.day + 1;

  // Skip the first render so onChange only reports edits.
  const mounted = useRef(false);
  useEffect(() => {
    if (!mounted.current) { mounted.current = true; return; }
    onChange?.(settings);
    setPhase(current => (current === "saved" || current === "tested" || current === "error" ? "idle" : current));
  }, [settings]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => () => controller.current?.abort(), []);

  const status = ((): { key: string; tone: Tone; icon?: typeof CircleCheck; label: string } => {
    if (!valid) return { key: "none", tone: "muted", label: "No budget set" };
    if (spend >= budget) return { key: "over", tone: "danger", label: "Over budget" };
    if (spend >= alertAt) return { key: "past", tone: "warning", label: `Past ${threshold}%` };
    if (forecast >= alertAt) {
      const day = clamp(Math.ceil(alertAt / daily), period.day, period.days);
      return { key: "cross", tone: "warning", icon: TrendingUp, label: `Hits ${threshold}% ${period.short} ${day}` };
    }
    return { key: "ok", tone: "success", label: "On track" };
  })();

  const budgetMeta = ((): { key: string; tone?: Tone; label: string } => {
    if (!valid) return { key: "invalid", tone: "danger", label: `Enter a budget above ${money(0)}` };
    if (spend > budget) return { key: "over", tone: "warning", label: `Already ${money(spend - budget)} over this month` };
    return { key: "ok", label: `Resets ${period.resetsOn}, in ${daysLeft} ${daysLeft === 1 ? "day" : "days"}` };
  })();

  const enabled = (Object.keys(channels) as SpendAlertChannel[]).filter(channel => channels[channel]);
  const channelNames: Record<SpendAlertChannel, string> = { email: "email", slack: "Slack", pagerduty: "PagerDuty" };

  const run = async (kind: "save" | "test") => {
    controller.current?.abort();
    const ctrl = new AbortController();
    controller.current = ctrl;
    const snapshot = settings;
    setPhase(kind === "save" ? "saving" : "testing");
    try {
      const handler = kind === "save" ? onSave : onSendTest;
      if (handler) await handler(snapshot, ctrl.signal);
      else await wait(kind === "save" ? 700 : 900, ctrl.signal);
      if (ctrl.signal.aborted) return;
      if (kind === "save") { setSaved(snapshot); setPhase("saved"); }
      else { setTestedTo(joinList(enabled.map(channel => channelNames[channel]))); setFlash(count => count + 1); setPhase("tested"); }
    } catch (error) {
      if ((error as Error)?.name === "AbortError") return;
      setPhase("error");
    }
  };

  const simulated = !onSave;
  const footer = ((): { key: string; tone?: Tone; label: string } => {
    if (phase === "saving") return { key: "saving", label: "Saving" };
    if (phase === "testing") return { key: "testing", label: "Sending test alert" };
    if (phase === "error") return { key: "error", tone: "danger", label: "Could not save. Try again." };
    if (phase === "saved") return { key: "saved", tone: "success", label: simulated ? "Saved. Simulated, nothing was stored." : "Saved" };
    if (phase === "tested") return { key: "tested", tone: "success", label: `Test sent to ${testedTo}.${onSendTest ? "" : " Simulated, nothing was sent."}` };
    if (!valid) return { key: "invalid", label: "Enter a budget to save" };
    if (dirty) return { key: "dirty", label: "Unsaved changes" };
    return { key: "clean", label: lastSaved };
  })();

  // The Slack message the alert would post when spend crosses the threshold.
  const full = threshold === 100;
  const messageTone: Tone = full ? "danger" : "warning";
  const headline = full ? (hardStop ? `${project} used its budget. Requests paused` : `${project} used its full budget`) : `${project} passed ${threshold}% of budget`;
  const context = [
    channels.email ? `Also emailed ${destinations.email}` : null,
    full && channels.pagerduty ? `Paged ${destinations.pagerduty}` : null,
    full && hardStop ? `Blocked until ${period.resetsOn}` : null,
  ].filter(Boolean).join(" · ") || `Posted to ${destinations.slack} only`;

  const nudgeBudget = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return;
    event.preventDefault();
    const step = event.shiftKey ? 1000 : 100;
    const next = Math.max(0, Math.round((budget + (event.key === "ArrowUp" ? step : -step)) / step) * step);
    setBudgetText(formatBudget(next));
  };

  return (
    <section className={cx(styles.root, className)} aria-labelledby={ids.title}>
      <header className={styles.header}>
        <div className={styles.heading}>
          <h2 id={ids.title} className={styles.title}>{title}</h2>
          <p className={styles.meta}>{project} · {scope} in {period.label}</p>
        </div>
        <Fade id={status.key} className={styles.status}>
          <StatusLine tone={status.tone} icon={status.icon}>{status.label}</StatusLine>
        </Fade>
      </header>

      <div className={cx(styles.section, styles.budgetRow)}>
        <div className={styles.rowText}>
          <label htmlFor={ids.budget} className={styles.label}>Monthly budget</label>
          <Fade id={budgetMeta.key} className={styles.meta}>
            <span id={ids.budgetMeta} className={styles.metaLine}>
              {budgetMeta.tone ? <StatusLine tone={budgetMeta.tone}>{budgetMeta.label}</StatusLine> : <span className={styles.ellipsis}>{budgetMeta.label}</span>}
            </span>
          </Fade>
        </div>
        <div className={styles.field} data-invalid={!valid || undefined}>
          <span className={styles.affix} aria-hidden="true">$</span>
          <input
            id={ids.budget}
            className={styles.input}
            inputMode="decimal"
            autoComplete="off"
            spellCheck={false}
            value={budgetText}
            aria-invalid={!valid || undefined}
            aria-describedby={ids.budgetMeta}
            onChange={event => setBudgetText(event.target.value.replace(/[^0-9.,]/g, ""))}
            onBlur={() => { if (valid) setBudgetText(formatBudget(budget)); }}
            onKeyDown={nudgeBudget}
          />
          <span className={styles.affix} aria-hidden="true">{currency}</span>
        </div>
      </div>

      <div className={styles.section}>
        <div className={styles.rowHead}>
          <span id={ids.threshold} className={styles.label}>Alert at</span>
          <span className={styles.value} aria-hidden="true">
            <span className={styles.percent}>{threshold}%</span>
            <span className={styles.dot}>·</span>
            <span>{valid ? money(alertAt) : money(0)}</span>
          </span>
        </div>
        <ThresholdBar
          value={threshold}
          onChange={setThreshold}
          spendPct={spendPct}
          forecastPct={forecastPct}
          markers={markers}
          labelId={ids.threshold}
          valueText={`${threshold}%, ${money(alertAt)}`}
          disabled={!valid}
          over={valid && spend >= budget}
        />
        <div className={styles.legend}>
          <span className={styles.legendItem}><span className={styles.swatch} data-kind="spend" aria-hidden="true" /><span className={styles.ellipsis}>Spent {money(spend, true)}</span></span>
          <span className={styles.legendItem}><span className={styles.swatch} data-kind="forecast" aria-hidden="true" /><span className={styles.ellipsis}>Forecast {money(forecast)} by {period.short} {period.days}</span></span>
          <span className={styles.legendPct}>{valid ? `${Math.round((spend / budget) * 100)}% used` : "No budget"}</span>
        </div>
      </div>

      <div className={styles.section}>
        <span className={styles.label}>Notify</span>
        <ul className={styles.channels}>
          <li className={styles.channel}>
            <Mail width={16} height={16} className={styles.mailIcon} aria-hidden="true" />
            <span className={styles.channelText}><span className={styles.channelName}>Email</span><span className={cx(styles.muted, styles.ellipsis)}>{destinations.email}</span></span>
            <Switch checked={channels.email} onCheckedChange={next => setChannels(current => ({ ...current, email: next }))} aria-label="Email alerts" />
          </li>
          <li className={styles.channel}>
            <SlackMark className={styles.mark} />
            <span className={styles.channelText}><span className={styles.channelName}>Slack</span><span className={cx(styles.muted, styles.ellipsis)}>{destinations.slack}</span></span>
            <Switch checked={channels.slack} onCheckedChange={next => setChannels(current => ({ ...current, slack: next }))} aria-label="Slack alerts" />
          </li>
          <li className={styles.channel}>
            <PagerDutyMark className={styles.mark} />
            <span className={styles.channelText}><span className={styles.channelName}>PagerDuty</span><span className={cx(styles.muted, styles.ellipsis)}>{destinations.pagerduty} at 100%</span></span>
            <Switch checked={channels.pagerduty} onCheckedChange={next => setChannels(current => ({ ...current, pagerduty: next }))} aria-label="PagerDuty alerts" />
          </li>
        </ul>
      </div>

      <div className={cx(styles.section, styles.stopRow)}>
        <div className={styles.rowText}>
          <span id={ids.hardStop} className={styles.label}>Hard stop at 100%</span>
          <Fade id={hardStop ? "on" : "off"} className={styles.meta}>
            {hardStop
              ? <StatusLine tone="warning">Requests return 429 until {period.resetsOn}</StatusLine>
              : <span className={styles.ellipsis}>Keep serving past the budget</span>}
          </Fade>
        </div>
        <Switch checked={hardStop} onCheckedChange={setHardStop} aria-labelledby={ids.hardStop} />
      </div>

      <div className={styles.section}>
        <div className={styles.rowHead}>
          <span className={styles.label}>Slack preview</span>
          <span className={cx(styles.muted, styles.previewWhere)}><SlackMark width={14} height={14} />{destinations.slack}</span>
        </div>
        <div className={styles.preview} data-off={!channels.slack || undefined}>
          {flash > 0 ? <span key={flash} className={styles.flash} aria-hidden="true" /> : null}
          <div className={styles.message} aria-hidden={!channels.slack || undefined}>
            <span className={styles.avatar} aria-hidden="true">{appName.charAt(0)}</span>
            <div className={styles.messageBody}>
              <div className={styles.sender}>
                <span className={cx(styles.senderName, styles.ellipsis)}>{appName}</span>
                <span className={styles.badge}>App</span>
                <span className={styles.time}>{flash > 0 ? "Just now" : "9:41 AM"}</span>
              </div>
              <p className={styles.headline}>
                <TriangleAlert width={14} height={14} className={styles.toneIcon} data-tone={messageTone} aria-hidden="true" />
                <span className={styles.ellipsis}>{headline}</span>
              </p>
              <div className={styles.attachment} data-tone={messageTone}>
                <span className={styles.field2}><span className={styles.fieldLabel}>Used</span><span className={styles.ellipsis}><span className={styles.num}>{money(alertAt)}</span> of {money(budget)}</span></span>
                <span className={styles.field2}><span className={styles.fieldLabel}>Forecast</span><span className={styles.ellipsis}>{money(forecast)} by {period.short} {period.days}</span></span>
              </div>
              <p className={cx(styles.context, styles.ellipsis)}>{context}</p>
            </div>
          </div>
          <div className={styles.previewOff} aria-hidden={channels.slack || undefined}>
            <SlackMark width={16} height={16} />
            <span>Turn on Slack to preview this alert</span>
          </div>
        </div>
      </div>

      <footer className={styles.footer}>
        <div className={styles.footerStatus} role="status" aria-live="polite">
          <Fade id={footer.key} className={styles.meta}>
            {footer.tone ? <StatusLine tone={footer.tone}>{footer.label}</StatusLine> : <span className={styles.ellipsis}>{footer.label}</span>}
          </Fade>
        </div>
        <div className={styles.actions}>
          <Button variant="secondary" size="sm" loading={phase === "testing"} disabled={!valid || enabled.length === 0 || busy} onClick={() => run("test")}>Send test</Button>
          <Button variant="primary" size="sm" loading={phase === "saving"} disabled={!valid || !dirty || busy} onClick={() => run("save")}>Save</Button>
        </div>
      </footer>
    </section>
  );
}

export default SpendAlert;
