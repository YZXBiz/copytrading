import { useEffect } from "react"
import { toast } from "sonner"
import { Toaster } from "@/components/ui/sonner"

/** A copied order that fills shows as a toast, in the words of the macOS notification; View opens the account. Mounted once. */
export function FillToasts() {
  useEffect(
    () =>
      window.copytrading.engine.onFill((fill) =>
        toast.success(fill.title, { description: fill.body, duration: 6000, action: { label: "View", onClick: () => (window.location.hash = fill.route) } }),
      ),
    [],
  )
  return <Toaster position="bottom-right" />
}
