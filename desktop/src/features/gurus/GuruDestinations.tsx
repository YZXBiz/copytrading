import { Badge } from "@/components/reui/badge"
import type { Guru } from "./model"

/** The accounts a guru's calls go to, from the saved routes. Only Live carries colour, since it is real money. */
export function GuruDestinations({ guru }: { guru: Guru }) {
  if (guru.accounts.length === 0) return null
  return (
    <ul aria-label="Copies into" className="flex flex-wrap items-center gap-1.5">
      {guru.accounts.map((account) => (
        <li key={account.id} className="flex items-center gap-1">
          <Badge variant="outline">{account.id}</Badge>
          {account.environment === "live" && <Badge variant="warning-light">Live</Badge>}
        </li>
      ))}
    </ul>
  )
}
