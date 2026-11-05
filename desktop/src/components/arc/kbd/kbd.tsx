"use client";

import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import type { HTMLAttributes, ReactNode } from "react";
import styles from "./kbd.module.css";

export type KbdSize = "sm" | "md" | "lg";
export type KbdPlatform = "auto" | "mac" | "pc";

export interface KbdProps extends Omit<HTMLAttributes<HTMLElement>, "children"> {
  /** The shortcut, as "mod+shift+p" or ["mod", "enter"]. mod reads ⌘ on Apple platforms and Ctrl elsewhere. */
  keys?: string | readonly string[];
  /** A single custom key cap, used when keys is not set. A plain string also works with listen. */
  children?: ReactNode;
  size?: KbdSize;
  /** Which symbols to draw. auto reads the platform after hydration. */
  platform?: KbdPlatform;
  /** Press each cap while its key is held anywhere on the page. */
  listen?: boolean;
  /** Press every cap, for example for a moment after the action runs from a click. */
  pressed?: boolean;
  /** Called on keydown when the whole shortcut matches while listen is on. The browser default is prevented. */
  onTrigger?: (event: KeyboardEvent) => void;
}

type Resolved = { platform: "mac" | "pc" };
type Key = { id: string; glyph: string; name: string; modifier?: "meta" | "ctrl" | "alt" | "shift"; match: (event: KeyboardEvent) => boolean };

const byKey = (...names: string[]) => (event: KeyboardEvent) => names.includes(event.key);
const byCode = (code: string, ...names: string[]) => (event: KeyboardEvent) => event.code === code || names.includes(event.key);

/** Key names are case insensitive. Letters and digits match the physical key, so Option and Shift combinations still land. */
function resolveKey(token: string, { platform }: Resolved): Key {
  const raw = token.trim();
  const id = raw.toLowerCase();
  const mac = platform === "mac";
  switch (id) {
    case "mod": return mac ? resolveKey("meta", { platform }) : resolveKey("ctrl", { platform });
    case "meta": case "cmd": case "command": case "win": case "super":
      return { id: "meta", glyph: mac ? "⌘" : "Win", name: mac ? "Command" : "Windows", modifier: "meta", match: byKey("Meta", "OS") };
    case "ctrl": case "control": return { id: "ctrl", glyph: mac ? "⌃" : "Ctrl", name: "Control", modifier: "ctrl", match: byKey("Control") };
    case "alt": case "option": case "opt": return { id: "alt", glyph: mac ? "⌥" : "Alt", name: mac ? "Option" : "Alt", modifier: "alt", match: byKey("Alt") };
    case "shift": return { id: "shift", glyph: mac ? "⇧" : "Shift", name: "Shift", modifier: "shift", match: byKey("Shift") };
    case "enter": case "return": return { id, glyph: mac ? "↵" : "Enter", name: mac ? "Return" : "Enter", match: byKey("Enter") };
    case "esc": case "escape": return { id: "esc", glyph: "Esc", name: "Escape", match: byKey("Escape", "Esc") };
    case "tab": return { id, glyph: mac ? "⇥" : "Tab", name: "Tab", match: byKey("Tab") };
    case "backspace": return { id, glyph: mac ? "⌫" : "Backspace", name: mac ? "Delete" : "Backspace", match: byKey("Backspace") };
    case "delete": case "del": return { id: "delete", glyph: mac ? "⌦" : "Del", name: mac ? "Forward delete" : "Delete", match: byKey("Delete") };
    case "space": return { id, glyph: "Space", name: "Space", match: byCode("Space", " ") };
    case "up": case "arrowup": return { id: "up", glyph: "↑", name: "Up arrow", match: byKey("ArrowUp") };
    case "down": case "arrowdown": return { id: "down", glyph: "↓", name: "Down arrow", match: byKey("ArrowDown") };
    case "left": case "arrowleft": return { id: "left", glyph: "←", name: "Left arrow", match: byKey("ArrowLeft") };
    case "right": case "arrowright": return { id: "right", glyph: "→", name: "Right arrow", match: byKey("ArrowRight") };
    case "pageup": return { id, glyph: "PgUp", name: "Page up", match: byKey("PageUp") };
    case "pagedown": return { id, glyph: "PgDn", name: "Page down", match: byKey("PageDown") };
    case "home": return { id, glyph: "Home", name: "Home", match: byKey("Home") };
    case "end": return { id, glyph: "End", name: "End", match: byKey("End") };
    case "plus": return { id, glyph: "+", name: "Plus", match: byKey("+", "=") };
    case "capslock": return { id, glyph: mac ? "⇪" : "Caps", name: "Caps lock", match: byKey("CapsLock") };
  }
  if (/^[a-z]$/.test(id)) return { id, glyph: id.toUpperCase(), name: id.toUpperCase(), match: byCode(`Key${id.toUpperCase()}`, id, id.toUpperCase()) };
  if (/^[0-9]$/.test(id)) return { id, glyph: id, name: id, match: byCode(`Digit${id}`, id) };
  if (/^f([1-9]|1[0-9]|2[0-4])$/.test(id)) return { id, glyph: id.toUpperCase(), name: id.toUpperCase(), match: byKey(id.toUpperCase()) };
  return { id, glyph: raw.length === 1 ? raw : raw.charAt(0).toUpperCase() + raw.slice(1), name: raw, match: (event: KeyboardEvent) => event.key.toLowerCase() === id };
}

function parseKeys(keys: string | readonly string[]) {
  if (typeof keys !== "string") return [...keys];
  // "mod++" and "mod+plus" both mean the plus key.
  return keys.replace(/\+\+$/, "+plus").split("+").filter(Boolean);
}

const noop = () => () => {};
const detect = () => {
  const nav = navigator as Navigator & { userAgentData?: { platform?: string } };
  return /mac|iphone|ipad|ipod/i.test(nav.userAgentData?.platform || nav.platform || nav.userAgent) ? "mac" : "pc";
};

/** Resolves auto to mac or pc. The server renders Apple symbols; the client corrects them right after hydration. */
export function useKbdPlatform(platform: KbdPlatform = "auto"): "mac" | "pc" {
  const detected = useSyncExternalStore(noop, detect, () => "mac" as const);
  return platform === "auto" ? detected : platform;
}

function isEditable(target: EventTarget | null) {
  const node = target as HTMLElement | null;
  if (!node || !node.tagName) return false;
  return node.isContentEditable || node.tagName === "TEXTAREA" || node.tagName === "SELECT" || (node.tagName === "INPUT" && !["checkbox", "radio", "button", "submit", "range", "color"].includes((node as HTMLInputElement).type));
}

/**
 * Key caps for a key or a shortcut. Caps sit on a hairline ledge; with listen, each one sinks onto it while its key is held
 * and springs back on release, so the hint answers the hand that uses it.
 */
export function Kbd({ keys, children, size = "md", platform = "auto", listen = false, pressed = false, onTrigger, className, ...props }: KbdProps) {
  const resolvedPlatform = useKbdPlatform(platform);
  const tokens = keys !== undefined ? parseKeys(keys) : typeof children === "string" ? [children] : [];
  const parsed = tokens.map(token => resolveKey(token, { platform: resolvedPlatform }));
  const signature = parsed.map(key => key.id).join("+") + resolvedPlatform;
  const [held, setHeld] = useState<ReadonlySet<number>>(() => new Set());
  const latest = useRef({ parsed, onTrigger, mac: resolvedPlatform === "mac" });
  useEffect(() => { latest.current = { parsed, onTrigger, mac: resolvedPlatform === "mac" }; });

  useEffect(() => {
    if (!listen) return;
    const down = new Set<number>();
    const timers = new Map<number, number>();
    const commit = () => setHeld(new Set(down));
    const release = (index: number) => { window.clearTimeout(timers.get(index)); timers.delete(index); if (down.delete(index)) commit(); };
    const clear = () => { timers.forEach(timer => window.clearTimeout(timer)); timers.clear(); if (down.size) { down.clear(); commit(); } };
    const onKeyDown = (event: KeyboardEvent) => {
      const { parsed: current, onTrigger: trigger, mac } = latest.current;
      const hasCommand = current.some(key => key.modifier === "meta" || key.modifier === "ctrl" || key.modifier === "alt");
      // Plain keys stay quiet while someone types in a field; shortcuts with a command modifier still answer.
      if (!hasCommand && isEditable(event.target)) return;
      let changed = false;
      current.forEach((key, index) => {
        if (!key.match(event)) return;
        if (!down.has(index)) { down.add(index); changed = true; }
        // macOS swallows keyup for other keys while Command is held, so those caps lift on their own shortly after.
        if (mac && event.metaKey && !key.modifier) {
          window.clearTimeout(timers.get(index));
          timers.set(index, window.setTimeout(() => release(index), 170));
        }
      });
      if (changed) commit();
      if (!trigger || event.repeat || !current.length) return;
      const needs = { meta: false, ctrl: false, alt: false, shift: false };
      current.forEach(key => { if (key.modifier) needs[key.modifier] = true; });
      const main = current.filter(key => !key.modifier);
      const modifiersMatch = needs.meta === event.metaKey && needs.ctrl === event.ctrlKey && needs.alt === event.altKey && (needs.shift === event.shiftKey || (!needs.shift && main.length === 1 && main[0]!.glyph.length === 1 && !/[a-z0-9]/i.test(main[0]!.glyph)));
      const mainMatch = main.length ? main.every(key => key.match(event)) : current.some(key => key.match(event));
      if (modifiersMatch && mainMatch) { event.preventDefault(); trigger(event); }
    };
    const onKeyUp = (event: KeyboardEvent) => {
      const { parsed: current } = latest.current;
      if (event.key === "Meta" || event.key === "OS") { clear(); return; }
      current.forEach((key, index) => { if (key.match(event)) release(index); });
    };
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    window.addEventListener("blur", clear);
    document.addEventListener("visibilitychange", clear);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      window.removeEventListener("blur", clear);
      document.removeEventListener("visibilitychange", clear);
      timers.forEach(timer => window.clearTimeout(timer));
      setHeld(new Set());
    };
  }, [listen, signature]);

  const cap = (content: ReactNode, name: string | null, index: number) => <kbd key={index} className={styles.key} data-pressed={pressed || held.has(index) ? "" : undefined}>
    {name === null ? content : <><span className={styles.glyph} aria-hidden="true">{content}</span><span className={styles.hidden}>{name}</span></>}
  </kbd>;

  const classes = [styles.kbd, styles[size], className].filter(Boolean).join(" ");
  if (keys === undefined) {
    const single = parsed[0];
    const showsSymbol = single && single.glyph !== single.name;
    return <kbd {...props} className={classes}>{cap(showsSymbol ? single.glyph : children, showsSymbol ? single.name : null, 0)}</kbd>;
  }
  return <kbd {...props} className={classes}>
    {parsed.map((key, index) => <span key={`${key.id}-${index}`} className={styles.slot}>
      {index > 0 && <span className={styles.hidden}> </span>}
      {cap(key.glyph, key.glyph === key.name ? null : key.name, index)}
    </span>)}
  </kbd>;
}

export default Kbd;
