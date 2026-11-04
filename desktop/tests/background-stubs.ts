import type { AgentAccess } from "../shared/contract"
import type { Deps } from "../electron/main/api"
import { Prefs } from "../electron/main/prefs"

/** The agent socket, restore and preferences a test of something else does not use: they answer, and do nothing. */
export function unusedBackground(dir: string): Pick<Deps, "agents" | "restore" | "prefs" | "readers"> {
  return {
    readers: { attach: async () => {} },
    agents: {
      state: () => ({ access: "off", listening: false, problem: null }),
      set: async (access: AgentAccess) => ({ access, listening: access !== "off", problem: null }),
    },
    restore: { activate: async () => ({ status: "restored" }), rollback: async () => {} },
    prefs: new Prefs(dir),
  }
}
