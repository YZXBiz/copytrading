import { useEffect, useRef, useState } from "react"
import { motion, useReducedMotion } from "motion/react"
import { tickDirection } from "./live"

/** How long a row's flash lasts, at most. */
export const FLASH_MS = 600

/**
 * A faint green or red wash behind a row when its price ticks up or down, laid over the row's own box (the row is
 * `relative`). It fades in and out once, in opacity alone, and is gone by FLASH_MS; with Reduce motion it never shows.
 */
export function TickFlash({ price }: { price: number | null }) {
  const reduced = useReducedMotion()
  const last = useRef(price)
  const [flash, setFlash] = useState<{ direction: "up" | "down"; n: number } | null>(null)
  useEffect(() => {
    const direction = tickDirection(last.current, price)
    last.current = price
    if (!direction || reduced) return
    setFlash((f) => ({ direction, n: (f?.n ?? 0) + 1 }))
    const done = setTimeout(() => setFlash(null), FLASH_MS)
    return () => clearTimeout(done)
  }, [price, reduced])
  if (!flash) return null
  return (
    <motion.span
      key={flash.n}
      aria-hidden="true"
      className={`pointer-events-none absolute -inset-x-2 -inset-y-1 rounded-md ${flash.direction === "up" ? "bg-success/10" : "bg-destructive/10"}`}
      initial={{ opacity: 0 }}
      animate={{ opacity: [0, 1, 0] }}
      transition={{ duration: (FLASH_MS - 50) / 1000, ease: "easeOut" }}
    />
  )
}
