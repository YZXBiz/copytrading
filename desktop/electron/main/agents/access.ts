import { lstatSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import type { AgentAccess } from "../../../shared/contract"

const ACCESS: readonly AgentAccess[] = ["off", "read_pause", "propose"]

/** What agents may do through the `copytrading` CLI and MCP server. A missing file means they never were allowed. */
export class AgentAccessStore {
  readonly path: string

  constructor(owner: string) {
    this.path = join(owner, "agent-access.json")
  }

  load(): AgentAccess {
    let stat
    try {
      stat = lstatSync(this.path)
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return "off"
      throw new Error("The saved agent access setting could not be read.")
    }
    if (!stat.isFile() || stat.uid !== process.getuid!()) throw new Error("The agent access setting is not in a private folder owned by this user.")
    try {
      const { access } = JSON.parse(readFileSync(this.path, "utf8")) as { access?: AgentAccess }
      if (access && ACCESS.includes(access)) return access
    } catch {
      // falls through to the same message as a value that is not one of the three
    }
    throw new Error("The saved agent access setting could not be read.")
  }

  save(access: AgentAccess): void {
    const temporary = `${this.path}.tmp`
    writeFileSync(temporary, JSON.stringify({ access }), { mode: 0o600 })
    renameSync(temporary, this.path)
  }
}
