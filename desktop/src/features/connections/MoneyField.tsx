import { MoneyInput } from "@/components/arc/money-input/money-input"
import { fromDollars, toCents } from "./money-field"

/** A dollar limit. The draft keeps the text; the input counts cents and reports dollars, empty as none. */
export function MoneyField({ label, hint, value, onChange }: { label: string; hint?: string; value: string; onChange: (value: string) => void }) {
  return <MoneyInput label={label} description={hint} value={toCents(value)} currency="USD" currencies={["USD"]} quickAdd={[]} onValueChange={(_, details) => onChange(fromDollars(details.major))} />
}
