import { useRef, useState } from "react"

/** An overlay trigger's hint, quiet while focus returns as the overlay closes
 *  (a focus alone can open a tooltip) until the pointer or focus moves on. */
export function useTriggerTooltip(overlayOpen: boolean) {
  const [open, setOpen] = useState(false)
  const [quiet, setQuiet] = useState(false)
  const [wasOpen, setWasOpen] = useState(overlayOpen)
  // Set by the trigger's pointer handlers, so a hover wakes the hint by the
  // time the tooltip asks to open.
  const pointerOver = useRef(false)
  if (wasOpen !== overlayOpen) {
    setWasOpen(overlayOpen)
    setOpen(false)
    if (!overlayOpen) setQuiet(true)
  }
  return {
    tooltip: {
      open: open && !overlayOpen,
      onOpenChange: (next: boolean) => {
        if (next && quiet && !pointerOver.current) return
        if (next) setQuiet(false)
        setOpen(next)
      },
    },
    triggerProps: {
      onPointerEnter: () => {
        pointerOver.current = true
      },
      onPointerLeave: () => {
        pointerOver.current = false
      },
      onBlur: () => setQuiet(false),
    },
  }
}
