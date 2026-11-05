import type { GuruPerformance, Result, TradingConfiguration } from "../../../shared/contract"
import { type Loaded, useResult } from "@/lib/use-result"
import { type Guru, guruDirectory } from "./model"

/** The gurus the saved setup copies. Until the setup is read, or when none is saved, there are none. */
export function useGurus(): { gurus: Guru[]; config: TradingConfiguration | null; setup: Loaded<unknown> & { retry: () => void } } {
  const setup = useResult(() => window.copytrading.read.getSetup(), "setup")
  const config = setup.status === "ready" ? (setup.data?.configuration ?? null) : null
  return { gurus: guruDirectory(config), config, setup }
}

/** Each guru's performance in the first account they are copied into (the one their page opens on); null for a guru with no account. One failed read fails only that guru. */
export function useGuruPerformances(gurus: Guru[]) {
  const key = gurus.map((g) => `${g.id}:${g.accounts[0]?.id ?? ""}`).join("|")
  return useResult<Record<string, Result<GuruPerformance | null>>>(
    async () => {
      const reads = await Promise.all(
        gurus.map(async (g): Promise<Result<GuruPerformance | null>> => {
          const account_id = g.accounts[0]?.id
          if (!account_id) return { ok: true, value: null }
          return window.copytrading.read.getGuruPerformance({ account_id, guru_id: g.id }).catch((e: unknown) => ({ ok: false as const, error: e instanceof Error ? e.message : "The request failed." }))
        }),
      )
      return { ok: true, value: Object.fromEntries(gurus.map((g, i) => [g.id, reads[i]!])) }
    },
    `performances:${key}`,
    60_000,
  )
}
