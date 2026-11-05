import { NumberField } from "@/components/arc/number-field/number-field"

/** A whole-number limit such as seconds or entries a day; a typed value that is not a number is ignored, as before. */
export function NumberInput({ label, hint, value, onChange }: { label: string; hint?: string; value: number; onChange: (value: number) => void }) {
  return <NumberField label={label} description={hint} value={value} min={0} max={1_000_000} step={1} onValueChange={(next) => Number.isFinite(next) && onChange(next)} limitHint={false} />
}
