import type { Tone } from "../../../shared/copying-state"

// The menu bar's picture, drawn in code (loose image files would not ship in the app): the line rising to a dot, as in the app
// icon. A template image is tinted by macOS and cannot hold a colour, and the bar's own tint follows the wallpaper, not the
// system appearance, so the whole mark is drawn in the state's colour, which reads on a light bar and a dark one.

const COLOUR: Record<Tone, [number, number, number]> = { success: [52, 199, 89], warning: [255, 159, 10], destructive: [255, 69, 58], idle: [142, 142, 147] }
const LINE: [number, number][] = [[4, 24], [10, 17], [15, 21], [21, 11]]
const DOT_AT: [number, number] = [26, 7]
const DOT_RADIUS = 4.4
const LINE_HALF_WIDTH = 1.7
/** The grid the shapes are placed on, so one image serves any size. */
const GRID = 32
const SAMPLES = 4

const near = ([px, py]: [number, number], [ax, ay]: [number, number], [bx, by]: [number, number]) => {
  const [dx, dy] = [bx - ax, by - ay]
  const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy))
}

/** BGRA, premultiplied, `size` px square: what nativeImage.createFromBitmap takes. */
export function drawMark(size: number, tone: Tone): Buffer {
  const out = Buffer.alloc(size * size * 4)
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let [r, g, b, a] = [0, 0, 0, 0]
      for (let sy = 0; sy < SAMPLES; sy++) {
        for (let sx = 0; sx < SAMPLES; sx++) {
          const p: [number, number] = [((x + (sx + 0.5) / SAMPLES) / size) * GRID, ((y + (sy + 0.5) / SAMPLES) / size) * GRID]
          const inDot = Math.hypot(p[0] - DOT_AT[0], p[1] - DOT_AT[1]) <= DOT_RADIUS
          const inLine = LINE.slice(1).some((to, i) => near(p, LINE[i]!, to) <= LINE_HALF_WIDTH)
          if (!inDot && !inLine) continue
          const [cr, cg, cb] = COLOUR[tone]
          r += cr
          g += cg
          b += cb
          a += 255
        }
      }
      const n = SAMPLES * SAMPLES
      const i = (y * size + x) * 4
      // Colour averaged over the covered samples, then scaled by coverage (premultiplied).
      const covered = a / 255
      out[i] = covered ? Math.round((b / covered) * (a / n / 255)) : 0
      out[i + 1] = covered ? Math.round((g / covered) * (a / n / 255)) : 0
      out[i + 2] = covered ? Math.round((r / covered) * (a / n / 255)) : 0
      out[i + 3] = Math.round(a / n)
    }
  }
  return out
}
