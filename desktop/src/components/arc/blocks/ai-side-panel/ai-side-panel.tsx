"use client";

import { useId } from "react";
import type { ReactNode } from "react";
import { motion, useReducedMotion } from "motion/react";
import { ArrowRightToLineIcon } from "@/components/icons/ArrowRightToLineIcon";
import { SparklesIcon } from "@/components/icons/SparklesIcon";
import { Tooltip } from "../../tooltip/tooltip";
import { motionTokens } from "../../lib/motion-tokens";
import styles from "./ai-side-panel.module.css";

/**
 * An assistant docked beside a page. The dock grows from the page's trailing edge, so the page narrows to make room, and the panel
 * inside keeps one width while it opens so its text never reflows. The header names the assistant and its model; the thread and the
 * composer are passed in, because the caller owns the conversation. Closed, the dock is inert and hidden from assistive tech.
 */
export interface AiSidePanelProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** The open width in pixels. */
  width: number;
  /** Defaults to "Assistant". */
  name?: string;
  /** The model that answers, in the header. Omit when none is chosen. */
  model?: string;
  /** Extra header controls, before Hide. */
  actions?: ReactNode;
  /** The thread and the composer. */
  children: ReactNode;
  className?: string;
}

export function AiSidePanel({ open, onOpenChange, width, name = "Assistant", model, actions, children, className }: AiSidePanelProps) {
  const reduced = Boolean(useReducedMotion());
  const panelId = useId();
  return <motion.div
    className={[styles.dock, className].filter(Boolean).join(" ")}
    initial={false}
    animate={{ width: open ? width : 0 }}
    transition={reduced ? { duration: 0 } : motionTokens.spring.smooth}
    aria-hidden={!open || undefined}
    inert={!open || undefined}
  >
    <div className={styles.dockInner} style={{ width }}>
      <aside id={panelId} className={styles.panel} aria-label={name} onKeyDown={event => { if (event.key === "Escape") onOpenChange(false); }}>
        <header className={styles.head}>
          <span className={styles.identity}>
            <SparklesIcon className={styles.mark} width={16} height={16} aria-hidden="true" />
            <span className={styles.name}>{name}</span>
            {model ? <span className={styles.model}>{model}</span> : null}
          </span>
          <div className={styles.headActions}>
            {actions}
            <Tooltip content="Hide">
              <button type="button" className={styles.iconButton} aria-label={`Hide ${name.toLowerCase()}`} aria-controls={panelId} aria-expanded={open} onClick={() => onOpenChange(false)}>
                <ArrowRightToLineIcon width={16} height={16} aria-hidden="true" />
              </button>
            </Tooltip>
          </div>
        </header>
        {children}
      </aside>
    </div>
  </motion.div>;
}

export default AiSidePanel;
