/** Types for the catch up block: what happened while someone was away, in the sections it is told in. */

export type CatchUpSectionId = "needs-you" | "copied" | "skipped";

export interface CatchUpPerson {
  name: string;
}

export interface CatchUpItem {
  id: string;
  section: CatchUpSectionId;
  /** One sentence. */
  text: string;
  /** Where it happened: an account, a channel. */
  context?: string;
  /** A short time label ("1:41 PM"). */
  when?: string;
  people?: CatchUpPerson[];
}

export const sectionOrder: CatchUpSectionId[] = ["needs-you", "copied", "skipped"];
export const sectionNames: Record<CatchUpSectionId, string> = { "needs-you": "Needs you", copied: "Copied", skipped: "Skipped" };
