/** The `d` of a line through `values`, spread across `width` and scaled into `height` with `pad` to spare. Flat data runs along the bottom when it is zero and along the middle otherwise; fewer than two values draw nothing. */
export function sparkPath(values: number[], width: number, height: number, pad = 3): string {
  if (values.length < 2) return ""
  const min = Math.min(...values)
  const span = Math.max(...values) - min
  const step = width / (values.length - 1)
  return values
    .map((v, i) => {
      const y = span === 0 ? (min === 0 ? height - pad : height / 2) : height - pad - ((v - min) / span) * (height - pad * 2)
      return `${i === 0 ? "M" : "L"}${+(i * step).toFixed(2)},${+y.toFixed(2)}`
    })
    .join(" ")
}
