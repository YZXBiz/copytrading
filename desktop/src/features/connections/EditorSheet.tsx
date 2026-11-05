import type { ReactNode } from "react"
import { Drawer, DrawerContent } from "@/components/arc/drawer/drawer"
import styles from "./connections.module.css"

/** The frame every editor shares: a drawer from the right with the kind's title and one line on it, a scrolling form, and a footer of actions. */
export function EditorSheet({ title, description, onClose, footer, children }: { title: string; description: string; onClose: () => void; footer: ReactNode; children: ReactNode }) {
  return (
    <Drawer open onOpenChange={(open) => !open && onClose()}>
      <DrawerContent side="right" title={title} description={description} style={{ ["--drawer-size" as string]: "30rem" }}>
        <div className={styles.sheet}>
          {children}
          <div className={styles.footer}>{footer}</div>
        </div>
      </DrawerContent>
    </Drawer>
  )
}
