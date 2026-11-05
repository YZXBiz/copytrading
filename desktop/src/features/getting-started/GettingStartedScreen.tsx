import { useEffect } from "react"
import { Tick02Icon } from "@/components/icons/Tick02Icon"
import { Button } from "@/components/arc/button/button"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { StartControls } from "@/features/connections/StartBar"
import { derive } from "@/features/connections/derive"
import { refreshStatus, useSetup } from "@/features/connections/setup-store"
import { STEPS } from "@/features/connections/state"
import { SectionError } from "@/features/settings/SectionError"
import { navigate } from "@/features/shell/route"
import { BEFORE_YOU_GO } from "./before-you-go"
import styles from "./getting-started.module.css"

/** What is connected, what is left, and the one Start copying: the five setup steps as a checklist, then what to know before copying. */
export function GettingStartedScreen() {
  const s = useSetup()
  const derived = derive(s)

  useEffect(() => {
    const timer = setInterval(() => void refreshStatus(), 5000)
    return () => clearInterval(timer)
  }, [])

  if (s.load.status === "error") return <SectionError title="Getting started did not load" message={s.load.error} onRetry={s.retry} />
  if (!derived) return <div className={styles.page}><Skeleton label="Loading setup steps" lines={5} /></div>

  const { progress } = derived
  const done = STEPS.filter((step) => progress.done.has(step.id)).length
  const left = STEPS.length - done

  return (
    <div className={styles.page}>
      <section className={styles.release} aria-labelledby="setup-title">
        <header className={styles.header}>
          <h2 id="setup-title">Set up copying</h2>
          {progress.next && <p>About 10 minutes. Have your Discord, AI provider, and Alpaca logins at hand.</p>}
        </header>

        <div className={styles.progress}>
          <div className={styles.progressMeta}>
            <span aria-live="polite">{left ? `${left} ${left === 1 ? "step" : "steps"} left` : "Ready to copy"}</span>
            <span className={styles.count}>
              {done} of {STEPS.length}
            </span>
          </div>
          <div className={styles.track} role="progressbar" aria-label="Setup progress" aria-valuemin={0} aria-valuemax={STEPS.length} aria-valuenow={done}>
            <span className={styles.fill} style={{ transform: `translateX(${(done / STEPS.length - 1) * 100}%)` }} />
          </div>
        </div>

        <ol className={styles.tasks} aria-label="Setup steps" style={{ margin: 0, padding: 0, listStyle: "none" }}>
          {STEPS.map((step) => {
            const isDone = progress.done.has(step.id)
            return (
              <li key={step.id} className={styles.task} data-done={isDone || undefined}>
                <span className={styles.mark} aria-hidden="true">
                  {isDone && <Tick02Icon width={12} height={12} />}
                </span>
                <div className={styles.taskCopy}>
                  <span className={styles.taskLabel}>
                    {step.title}
                    <span className={styles.srOnly}>{isDone ? ", done" : ", to do"}</span>
                  </span>
                  <span className={styles.taskDetail}>{step.detail}</span>
                </div>
                {!isDone && step.id !== "start" && (
                  <Button type="button" variant="secondary" size="sm" onClick={() => navigate("settings", "connections")}>
                    Open Connections
                  </Button>
                )}
              </li>
            )
          })}
        </ol>

        <footer className={styles.footer}>
          <StartControls s={s} derived={derived} />
        </footer>
      </section>

      <section className={styles.notes} aria-labelledby="before-you-go">
        <h3 id="before-you-go">Before you go</h3>
        <ul>
          {BEFORE_YOU_GO.map((note) => (
            <li key={note.lead}>
              <strong style={{ fontWeight: 500 }}>{note.lead}</strong> <span>{note.rest}</span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}
