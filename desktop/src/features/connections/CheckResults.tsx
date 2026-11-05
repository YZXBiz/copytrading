import type { TradingValidation } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { checkDetail, checkTitle } from "./words"
import styles from "./connections.module.css"

/** Each connection and what its test found, with what to do about a failure. */
export function CheckResults({ report, modelName }: { report: TradingValidation["report"]; modelName: string }) {
  return (
    <section className={styles.section} aria-label="Connection checks">
      <div className={styles.sectionHead}>
        <div>
          <h3>Connection checks</h3>
          <p>{report.cost_notice}</p>
        </div>
      </div>
      <ul className={styles.checks}>
        {report.checks.map((check, index) => {
          const detail = checkDetail(check, modelName)
          return (
            <li key={`${check.name}:${check.subject ?? index}`}>
              <div>
                <strong>{checkTitle(check)}</strong>
                {detail && <span data-problem={check.state === "failed" || undefined}>{detail}</span>}
              </div>
              <Badge tone={check.state === "ready" ? "info" : check.state === "failed" ? "warning" : "neutral"} outline={check.state !== "ready" && check.state !== "failed"} size="sm">
                {check.state === "ready" ? "Ready" : check.state === "failed" ? "Needs attention" : "Not configured"}
              </Badge>
            </li>
          )
        })}
      </ul>
    </section>
  )
}
