import { Fragment } from "react"
import type { Guru } from "./model"

/** Where a guru's calls go, from the saved routes: "Copies into primary (Paper) and ira (Live)". Only Live carries colour, since it is real money. */
export function GuruDestinations({ guru }: { guru: Guru }) {
  if (guru.accounts.length === 0) return null
  return (
    <p className="text-muted-foreground text-sm">
      Copies into{" "}
      {guru.accounts.map((account, index) => (
        <Fragment key={account.id}>
          {index > 0 && (index === guru.accounts.length - 1 ? " and " : ", ")}
          {account.id}
          {account.environment && (
            <>
              {" ("}
              <span className={account.environment === "live" ? "text-warning-foreground font-medium" : undefined}>
                {account.environment === "live" ? "Live" : "Paper"}
              </span>
              {")"}
            </>
          )}
        </Fragment>
      ))}
    </p>
  )
}
