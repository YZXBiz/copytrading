import { useSyncExternalStore } from "react"

// Which time zone the app shows times in: the Mac's own (the default, which follows the Mac), New York's
// market time, or any zone the owner picked. Stored in localStorage; format.ts reads it for every time it shows.

const KEY = "copytrading.timeZone"
export const NEW_YORK = "America/New_York"

const listeners = new Set<() => void>()

/** The saved zone, or undefined for "the Mac's own". */
export function getTimeZone(): string | undefined {
  try {
    const saved = localStorage.getItem(KEY)
    return saved && isZone(saved) ? saved : undefined
  } catch {
    return undefined
  }
}

export function setTimeZone(zone: string | undefined): void {
  if (zone === undefined) localStorage.removeItem(KEY)
  else if (isZone(zone)) localStorage.setItem(KEY, zone)
  listeners.forEach((listener) => listener())
}

export function useTimeZone(): string | undefined {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    getTimeZone,
  )
}

export function isZone(zone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone })
    return true
  } catch {
    return false
  }
}

export const macTimeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone

/** Every zone the platform knows, for the picker. */
export const allTimeZones = (): string[] => Intl.supportedValuesOf("timeZone")

/** "New York": the last part of the zone's name, spaced. */
export const city = (zone: string): string => (zone.split("/").pop() ?? zone).replaceAll("_", " ")

/** "Pacific Standard Time" for the zone as of `at`. */
export function zoneName(zone: string, at: Date = new Date()): string {
  const part = new Intl.DateTimeFormat("en-US", { timeZone: zone, timeZoneName: "long" }).formatToParts(at).find((p) => p.type === "timeZoneName")
  return part?.value ?? zone
}

/** What the picker and the General page call a choice. */
export function zoneLabel(zone: string | undefined, at: Date = new Date()): string {
  if (zone === undefined) return `Automatic (${zoneName(macTimeZone(), at)})`
  if (zone === NEW_YORK) return "New York (market time)"
  return `${city(zone)} (${zoneName(zone, at)})`
}
