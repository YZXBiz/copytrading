/** How many toasts show; older ones wait behind them, unseen. */
export const MAX_VISIBLE = 4
/** One toast's height and the space between toasts when the stack is spread open. */
export const TOAST_HEIGHT = 72
export const TOAST_GAP = 8

/** Where toast number `index` (0 is the newest, in front) rests: tucked behind the front one, or spread open in a column. */
export function stackPose(index: number, expanded: boolean): { y: number; scale: number; opacity: number } {
  const visible = index < MAX_VISIBLE
  if (expanded) return { y: -index * (TOAST_HEIGHT + TOAST_GAP), scale: 1, opacity: visible ? 1 : 0 }
  return { y: -index * 10, scale: 1 - index * 0.06, opacity: visible ? 1 - index * 0.1 : 0 }
}
