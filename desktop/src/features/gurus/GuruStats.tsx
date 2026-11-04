import { Frame } from "@/components/reui/frame"
import { Stat } from "@/features/account/Stat"
import { duration } from "@/features/activity/amounts"
import type { Stats } from "./model"

/** Today's numbers for one guru, as the engine counted the owner's whole day. Before the day is read every count is a dash, never a zero it has not counted. */
export function GuruStats({ stats }: { stats: Stats }) {
  const count = (n: number | null) => (n === null ? "—" : n.toLocaleString("en-US"))
  return (
    <Frame spacing="sm" className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4">
      <Stat label="Posts today" value={count(stats.postsToday)} />
      <Stat label="Traded" value={count(stats.tradedToday)} />
      <Stat label="Waiting" value={stats.postsToday === null ? "—" : count(stats.waiting)} />
      <Stat label="Read in" value={stats.averageRead === null ? "—" : duration(stats.averageRead)} />
    </Frame>
  )
}
