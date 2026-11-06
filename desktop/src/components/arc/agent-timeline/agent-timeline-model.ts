import type { ReactNode } from "react";

/** What an agent was doing during a span. */
export type AgentTimelineSpanKind = "thinking" | "tool" | "waiting";

export interface AgentTimelineAgent {
  /** Stable id that spans and handoffs refer to. */
  id: string;
  /** Short name shown on the row, such as "Researcher". */
  name: string;
  /** Model name shown under the name, such as "Claude Sonnet 5.5". Also picks the provider mark. */
  model?: string;
  /** One line about the agent's job, shown in the span card. */
  role?: string;
  /** Row color for spans, connectors and the legend dot. Defaults to neutral for the first agent and --series-1 to --series-4 after it. */
  color?: string;
  /** Provider mark. Inferred from the model name (Claude, GPT, Gemini) when left out. */
  mark?: ReactNode;
  /** Blended price in USD per million tokens, used for cost when a span has no cost of its own. */
  price?: number;
}

export interface AgentTimelineTool {
  /** Tool name, such as "GitHub". */
  name: string;
  /** Tool mark. GitHub, Web search, PostgreSQL and Notion have built-in marks. */
  mark?: ReactNode;
}

export interface AgentTimelineSpan {
  /** Stable id. Defaults to the agent id and the span's index. */
  id?: string;
  agentId: string;
  kind: AgentTimelineSpanKind;
  /** Seconds from the start of the run. */
  start: number;
  /** Seconds from the start of the run. Leave it out while the span is still open in a live run. */
  end?: number;
  /** What the agent did, in a short sentence. */
  label: string;
  /** Optional second line in the span card, such as an error message. */
  detail?: string;
  /** The tool for a tool call: a name with a built-in mark, or a name with your own mark. */
  tool?: string | AgentTimelineTool;
  tokens?: number;
  /** Cost in USD. Defaults to tokens times the agent's price. */
  cost?: number;
  /** A failed call shows a cross and a "Failed" label once it ends. */
  status?: "ok" | "failed";
  /** Marks a call that retried an earlier failure; it shows a retry icon once it ends. */
  retry?: boolean;
  /** When the step happened, in words. Shown in the span card and read aloud in place of the span's axis seconds. */
  meta?: string;
}

export interface AgentTimelineHandoff {
  /** Agent id that hands off work or returns a result. */
  from: string;
  to: string;
  /** Seconds from the start of the run. */
  at: number;
  /** What was handed over, shown in the span card. */
  label?: string;
}

export interface AgentTimelineRun {
  title?: string;
  /** Rows, top to bottom. The first agent is the orchestrator. */
  agents: AgentTimelineAgent[];
  spans: AgentTimelineSpan[];
  handoffs?: AgentTimelineHandoff[];
  /** Run length in seconds. Defaults to the last span end or handoff. */
  duration?: number;
  /** Epoch milliseconds when a live run started. The live clock counts from mount when left out. */
  startedAt?: number;
}

export interface TimelineAgent extends AgentTimelineAgent { index: number; color: string }
export interface TimelineSpan extends AgentTimelineSpan { id: string; index: number; row: number; open: boolean; toolInfo?: AgentTimelineTool; spanCost: number }
/** A connector between two rows. "out" leaves the source row vertically and enters the target span from the left; "in" leaves the
 *  source span's end horizontally and rises or drops into the target row; "line" is a plain vertical. */
export interface TimelineConnector {
  id: string;
  handoff: AgentTimelineHandoff;
  from: number;
  to: number;
  at: number;
  shape: "out" | "in" | "line";
  /** Start and end of the horizontal piece, in seconds. */
  x0: number;
  x1: number;
  up: boolean;
  color: string;
  sourceSpan?: string;
  targetSpan?: string;
}

export const SERIES = ["var(--series-1)", "var(--series-2)", "var(--series-3)", "var(--series-4)"];
export const LEAD_COLOR = "var(--text-secondary)";

const toolOf = (tool: AgentTimelineSpan["tool"]): AgentTimelineTool | undefined =>
  tool == null ? undefined : typeof tool === "string" ? { name: tool } : tool;

/** Normalizes the run: resolves ids, colors, open spans, connector shapes and totals. */
export function buildModel(agents: AgentTimelineAgent[], spans: AgentTimelineSpan[], handoffs: AgentTimelineHandoff[], duration?: number) {
  const rows = new Map<string, number>();
  const list: TimelineAgent[] = agents.map((agent, index) => {
    rows.set(agent.id, index);
    return { ...agent, index, color: agent.color ?? (index === 0 ? LEAD_COLOR : SERIES[(index - 1) % SERIES.length]) };
  });
  const items: TimelineSpan[] = [];
  spans.forEach((span, index) => {
    const row = rows.get(span.agentId);
    if (row === undefined) return;
    const price = list[row].price ?? 0;
    items.push({ ...span, id: span.id ?? `${span.agentId}-${index}`, index: items.length, row, open: span.end === undefined, toolInfo: toolOf(span.tool), spanCost: span.cost ?? ((span.tokens ?? 0) * price) / 1e6 });
  });
  items.sort((a, b) => a.start - b.start || a.row - b.row);
  items.forEach((span, index) => { span.index = index; });
  const byRow: TimelineSpan[][] = list.map(() => []);
  items.forEach(span => byRow[span.row].push(span));
  const endOf = (span: TimelineSpan) => span.end ?? span.start;

  const last = Math.max(0, ...items.map(endOf), ...handoffs.map(h => h.at));
  const total = duration ?? last;

  const connectors: TimelineConnector[] = [];
  handoffs.forEach((handoff, index) => {
    const from = rows.get(handoff.from), to = rows.get(handoff.to);
    if (from === undefined || to === undefined || from === to) return;
    const { at } = handoff;
    const sourceRow = byRow[from], targetRow = byRow[to];
    // An open span (a live run) covers everything after its start.
    const covering = (row: TimelineSpan[]) => row.find(span => span.start <= at && (span.open || at < span.end!));
    // A result leaves from a span that just ended, but only when the source has nothing else running at that moment.
    const ending = covering(sourceRow) ? undefined : sourceRow.filter(span => !span.open && span.end! <= at + .01 && span.end! >= at - 1.5).at(-1);
    const starting = targetRow.find(span => span.start >= at - .01 && span.start <= at + 2);
    const leadIn = ending ? at - ending.end! : 0, leadOut = starting ? starting.start - at : 0;
    // A dispatch whose target has not started yet (a live run) is still a dispatch; its lead grows when the span arrives.
    const shape = leadIn > .05 && leadIn > leadOut ? "in" : leadOut > .05 || (!ending && !covering(targetRow)) ? "out" : "line";
    const color = shape === "in" ? list[from].color : list[to].color;
    connectors.push({
      id: `h${index}`, handoff, from, to, at, shape, up: to < from, color,
      x0: shape === "in" ? ending!.end! : at,
      x1: shape === "out" ? starting?.start ?? at : at,
      sourceSpan: (shape === "in" ? ending : covering(sourceRow) ?? ending)?.id,
      targetSpan: (starting ?? covering(targetRow))?.id,
    });
  });

  const done = items.filter(span => !span.open);
  const tokens = items.reduce((sum, span) => sum + (span.tokens ?? 0), 0);
  const cost = items.reduce((sum, span) => sum + span.spanCost, 0);
  const busy = done.filter(span => span.kind !== "waiting").reduce((sum, span) => sum + (span.end! - span.start), 0);
  return { agents: list, spans: items, byRow, connectors, duration: total, totals: { tokens, cost, speedup: total > 0 ? busy / total : 0 } };
}

export type TimelineModel = ReturnType<typeof buildModel>;

/** Progress of a span at time `t`, from 0 to 1. Open spans count as fully spent so far. */
export function progressAt(span: TimelineSpan, t: number) {
  if (t <= span.start) return 0;
  if (span.open) return 1;
  const length = span.end! - span.start;
  return length <= 0 ? 1 : Math.min(1, (t - span.start) / length);
}

/** Spans and connectors on a pinned span's handoff path. A subagent's path runs from the handoff that started its work, through
 *  every span of that stretch, to the result it returned. The orchestrator's path is the handoffs that touch the span. */
export function pathFor(model: TimelineModel, id: string | null) {
  if (!id) return null;
  const span = model.spans.find(item => item.id === id);
  if (!span) return null;
  const spans = new Set([span.id]);
  const links = new Set<string>();
  const end = span.end ?? Infinity;
  if (span.row === 0) {
    model.connectors.forEach(link => {
      if (link.sourceSpan !== span.id && link.targetSpan !== span.id) return;
      links.add(link.id);
      if (link.sourceSpan) spans.add(link.sourceSpan);
      if (link.targetSpan) spans.add(link.targetSpan);
    });
  } else {
    const inbound = model.connectors.filter(link => link.to === span.row && link.at <= span.start + .01).at(-1);
    const outbound = model.connectors.find(link => link.from === span.row && link.at >= end - .01);
    const from = inbound?.at ?? -Infinity, to = outbound?.at ?? Infinity;
    model.byRow[span.row].forEach(item => { if (item.start >= from - .01 && (item.end ?? Infinity) <= to + .01) spans.add(item.id); });
    [inbound, outbound].forEach(link => {
      if (!link) return;
      links.add(link.id);
      if (link.sourceSpan) spans.add(link.sourceSpan);
      if (link.targetSpan) spans.add(link.targetSpan);
    });
  }
  return { spans, links };
}

/** A tick step that keeps labels at least `minGap` pixels apart. */
export function tickStep(axis: number, width: number, minGap = 56) {
  const steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600];
  const perSecond = width / Math.max(axis, .001);
  return steps.find(step => step * perSecond >= minGap) ?? steps.at(-1)!;
}

export function formatTick(seconds: number) {
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60), rest = Math.round(seconds % 60);
  return rest ? `${minutes}m ${rest}s` : `${minutes}m`;
}

export function formatSeconds(seconds: number) {
  if (seconds < 100) return `${seconds.toFixed(1)}s`;
  const minutes = Math.floor(seconds / 60), rest = Math.floor(seconds % 60);
  return `${minutes}m ${String(rest).padStart(2, "0")}s`;
}

const integer = new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 });
export const formatTokens = (tokens: number) => integer.format(Math.round(tokens));
export const formatCost = (cost: number) => `$${cost.toFixed(2)}`;
export const formatDuration = (seconds: number) => seconds < 10 ? `${seconds.toFixed(1)}s` : formatSeconds(seconds);

/** Rounds an axis up to a calm length for a live run, so it grows in steps instead of every frame. */
export function liveAxis(now: number, last: number) {
  const need = Math.max(now + 4, last + 1, 10);
  const step = need <= 30 ? 10 : need <= 120 ? 30 : 60;
  return Math.ceil(need / step) * step;
}
