import type { TradingConfiguration } from "../../../shared/contract"
import { type Loaded, useResult } from "@/lib/use-result"
import { type Guru, guruDirectory } from "./model"

/** The gurus the saved setup copies. Until the setup is read, or when none is saved, there are none. */
export function useGurus(): { gurus: Guru[]; config: TradingConfiguration | null; setup: Loaded<unknown> & { retry: () => void } } {
  const setup = useResult(() => window.copytrading.read.getSetup(), "setup")
  const config = setup.status === "ready" ? (setup.data?.configuration ?? null) : null
  return { gurus: guruDirectory(config), config, setup }
}
