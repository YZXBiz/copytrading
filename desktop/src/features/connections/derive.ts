import type { SetupState } from "./setup-store"
import { hasUnsavedChanges, isCopying, keysOf } from "./setup-store"
import { type Facts, type Progress, failedSubjects, setupProgress } from "./state"

export interface Derived {
  facts: Facts
  progress: Progress
  copying: boolean
  hasSaved: boolean
  hasUnsaved: boolean
}

/** What the screens read off a loaded setup: each row's facts, how far the setup has come, and whether copying holds it. Null until loaded. */
export function derive(s: SetupState): Derived | null {
  const keys = keysOf(s)
  if (s.load.status !== "ready" || !keys) return null
  const { saved, trading } = s.load.data
  return {
    facts: { draft: s.draft, saved: saved?.configuration ?? null, built: s.built, keys, trading, checks: s.checks },
    progress: setupProgress(s.draft, keys, Boolean(saved), failedSubjects(s.checks, s.draft)),
    copying: isCopying(s),
    hasSaved: Boolean(saved),
    hasUnsaved: hasUnsavedChanges(s),
  }
}
