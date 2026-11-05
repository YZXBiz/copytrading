import { useCallback, useEffect, useRef, useState } from "react"
import { AnimatePresence, motion } from "motion/react"
import { CircleCheckIcon } from "@/components/icons/CircleCheckIcon"
import { Cancel01Icon as XIcon } from "@/components/icons/Cancel01Icon"
import type { FillAlert } from "../../../shared/contract"
import { Button } from "@/components/ui/button"
import { MAX_VISIBLE, TOAST_GAP, TOAST_HEIGHT, stackPose } from "./toast-stack"

const SHOWN_MS = 6000
const SPRING = { type: "spring", stiffness: 400, damping: 30 } as const

interface Fill extends FillAlert {
  id: number
}

/** One toast. Its timer runs only while the stack is not being hovered, so reading one never loses it. */
function FillToast({ fill, index, expanded, paused, onClose }: { fill: Fill; index: number; expanded: boolean; paused: boolean; onClose: (id: number) => void }) {
  const left = useRef(SHOWN_MS)
  const { id } = fill
  useEffect(() => {
    if (paused) return
    const started = Date.now()
    const timer = setTimeout(() => onClose(id), left.current)
    return () => {
      clearTimeout(timer)
      left.current -= Date.now() - started
    }
  }, [paused, onClose, id])
  const pose = stackPose(index, expanded)
  return (
    <motion.div
      role="status"
      className="bg-popover text-popover-foreground border-border absolute inset-x-0 bottom-0 flex items-center gap-3 rounded-lg border px-3 shadow-lg"
      style={{ height: TOAST_HEIGHT, zIndex: MAX_VISIBLE - index, transformOrigin: "center bottom", pointerEvents: index < MAX_VISIBLE ? "auto" : "none" }}
      initial={{ opacity: 0, y: 40, scale: 0.9 }}
      animate={pose}
      exit={{ opacity: 0, scale: 0.9, y: pose.y + 12, transition: { duration: 0.18, ease: "easeIn" } }}
      transition={{ ...SPRING, delay: expanded ? 0 : index * 0.02 }}
    >
      <CircleCheckIcon className="text-success size-4 shrink-0" aria-hidden="true" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium">{fill.title}</p>
        <p className="text-muted-foreground line-clamp-2 text-xs">{fill.body}</p>
      </div>
      <Button
        type="button"
        size="sm"
        variant="outline"
        onClick={() => {
          window.location.hash = fill.route
          onClose(id)
        }}
      >
        View
      </Button>
      <Button type="button" size="icon-sm" variant="ghost" aria-label="Dismiss" onClick={() => onClose(id)}>
        <XIcon aria-hidden="true" />
      </Button>
    </motion.div>
  )
}

/**
 * A copied order that fills shows as a toast, in the words of the macOS notification; View opens the account. Fills that
 * arrive together stack, newest in front, and spread open under the pointer. Mounted once.
 */
export function FillToasts() {
  const [fills, setFills] = useState<Fill[]>([])
  const [hovered, setHovered] = useState(false)
  const next = useRef(0)
  useEffect(
    () =>
      window.copytrading.engine.onFill((fill) => {
        setFills((current) => [{ ...fill, id: ++next.current }, ...current])
      }),
    [],
  )
  const close = useCallback((id: number) => setFills((current) => current.filter((f) => f.id !== id)), [])
  const spread = hovered && fills.length > 1
  return (
    <div
      role="region"
      aria-label="Fills"
      aria-live="polite"
      className="fixed right-4 bottom-4 z-50 w-80 max-w-[calc(100vw-2rem)]"
      style={{ height: TOAST_HEIGHT, pointerEvents: fills.length === 0 ? "none" : undefined }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      {/* Keeps the pointer inside the stack across the gaps between spread toasts. */}
      {spread && <div aria-hidden="true" className="absolute inset-x-0 bottom-0" style={{ height: Math.min(fills.length, MAX_VISIBLE) * (TOAST_HEIGHT + TOAST_GAP) }} />}
      <AnimatePresence initial={false}>
        {fills.slice(0, MAX_VISIBLE + 1).map((fill, index) => (
          <FillToast key={fill.id} fill={fill} index={index} expanded={spread} paused={hovered} onClose={close} />
        ))}
      </AnimatePresence>
    </div>
  )
}
