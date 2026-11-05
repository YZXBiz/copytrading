/** A limit in dollars is kept in the draft as the text typed ("250", "12.5", or "" for none); the money input counts cents. */
export function toCents(text: string): number | null {
  const trimmed = text.trim()
  if (trimmed === "") return null
  const value = Number(trimmed)
  return Number.isFinite(value) ? Math.round(value * 100) : null
}

/** What the money input reports (dollars, or null when emptied) as the draft's text. */
export const fromDollars = (major: number | null): string => (major === null ? "" : String(major))
