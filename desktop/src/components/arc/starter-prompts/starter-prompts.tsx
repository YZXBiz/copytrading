"use client";

import { useId } from "react";
import type { ReactNode } from "react";
import { motion, useReducedMotion } from "motion/react";
import { motionTokens } from "../lib/motion-tokens";
import styles from "./starter-prompts.module.css";

export interface StarterPrompt {
  id: string;
  /** The card's text. */
  title: string;
  /** One quiet line under the title. */
  description?: string;
}

export interface StarterPromptsProps {
  /** The heading. */
  greeting: ReactNode;
  /** One quiet line under the heading. */
  description?: ReactNode;
  prompts: StarterPrompt[];
  /** Called when a card is picked. The caller decides what picking does: here it sends the question. */
  onSelect: (prompt: StarterPrompt) => void;
  className?: string;
}

const cx = (...names: (string | false | null | undefined)[]) => names.filter(Boolean).join(" ");

/**
 * The empty state of an AI app: a greeting and starter cards. A card is a way in, so picking one hands its prompt to the caller;
 * the composer stays where the caller keeps it, so there is only ever one.
 */
export function StarterPrompts({ greeting, description, prompts, onSelect, className }: StarterPromptsProps) {
  const reduced = Boolean(useReducedMotion());
  const id = useId();
  return <section className={cx(styles.root, className)} aria-labelledby={`${id}-title`}>
    <header className={styles.header}>
      <h2 id={`${id}-title`} className={styles.greeting}>{greeting}</h2>
      {description ? <p className={styles.description}>{description}</p> : null}
    </header>
    <ul className={styles.grid} aria-label="Starters">
      {prompts.map((prompt, index) => <li key={prompt.id} className={styles.slot}>
        <motion.button type="button" className={styles.card} onClick={() => onSelect(prompt)}
          initial={reduced ? { opacity: 0 } : { opacity: 0, y: 2 }}
          animate={{ opacity: 1, y: 0, transition: reduced ? { duration: 0 } : { duration: motionTokens.duration.fast, ease: [...motionTokens.ease.enter], delay: .04 + index * .035 } }}>
          <span className={styles.title}>{prompt.title}</span>
          {prompt.description ? <span className={styles.cardDescription}>{prompt.description}</span> : null}
        </motion.button>
      </li>)}
    </ul>
  </section>;
}

export default StarterPrompts;
