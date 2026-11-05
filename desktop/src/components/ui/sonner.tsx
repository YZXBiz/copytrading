import { useTheme } from "next-themes"
import { Toaster as Sonner, type ToasterProps } from "sonner"
import { CancelCircleIcon } from "@/components/icons/CancelCircleIcon"
import { CheckmarkCircle02Icon } from "@/components/icons/CheckmarkCircle02Icon"
import { InformationCircleIcon } from "@/components/icons/InformationCircleIcon"
import { LoaderCircleIcon } from "@/components/icons/LoaderCircleIcon"
import { TriangleAlertIcon } from "@/components/icons/TriangleAlertIcon"

const Toaster = ({ ...props }: ToasterProps) => {
  const { theme = "system" } = useTheme()

  return (
    <Sonner
      theme={theme as ToasterProps["theme"]}
      className="toaster group"
      icons={{
        success: (
          <CheckmarkCircle02Icon className="size-4" />
        ),
        info: (
          <InformationCircleIcon className="size-4" />
        ),
        warning: (
          <TriangleAlertIcon className="size-4" />
        ),
        error: (
          <CancelCircleIcon className="size-4" />
        ),
        loading: (
          <LoaderCircleIcon className="size-4 animate-spin" />
        ),
      }}
      style={
        {
          "--normal-bg": "var(--popover)",
          "--normal-text": "var(--popover-foreground)",
          "--normal-border": "var(--border)",
          "--border-radius": "var(--radius)",
        } as React.CSSProperties
      }
      toastOptions={{
        classNames: {
          toast: "cn-toast",
        },
      }}
      {...props}
    />
  )
}

export { Toaster }
