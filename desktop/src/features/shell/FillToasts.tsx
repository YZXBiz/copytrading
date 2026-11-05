import { useEffect } from "react"
import { ToastStack, useToastStack } from "@/components/arc/toast-stack/toast-stack"

/**
 * A copied order that fills shows as a toast, in the words of the macOS notification; View opens the account. Fills that
 * arrive together stack, newest in front, and spread open under the pointer. Mounted once, inside the toast provider.
 */
export function FillToasts() {
  const { toast } = useToastStack()
  useEffect(
    () =>
      window.copytrading.engine.onFill((fill) => {
        toast({
          type: "success",
          title: fill.title,
          description: fill.body,
          action: {
            label: "View",
            onClick: () => {
              window.location.hash = fill.route
            },
          },
        })
      }),
    [toast],
  )
  return <ToastStack label="Fills" visibleToasts={4} />
}
