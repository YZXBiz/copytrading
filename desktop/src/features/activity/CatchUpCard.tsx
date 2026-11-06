import { useRef } from "react"
import { AnimatePresence } from "motion/react"
import type { SourceActivity } from "../../../shared/contract"
import { CatchUp } from "@/components/arc/blocks/catch-up/catch-up"
import { navigate } from "@/features/shell/route"
import { readClock } from "@/lib/clock"
import { catchUp } from "./catch-up"
import { dismissCatchUp, useCatchUpSince } from "./last-looked"

/**
 * What came in since the owner last looked: the card at the top of Activity, a short one on an account's page. Nothing when nothing is new.
 * `posts` is null while they are read again; the card keeps the posts it had, so a re-read never makes it leave and arrive again.
 */
export function CatchUpCard({ posts, now, nameOf, accountId = null, compact = false }: { posts: SourceActivity[] | null; now: Date; nameOf: (id: string | null) => string; accountId?: string | null; compact?: boolean }) {
  const since = useCatchUpSince(now)
  const last = useRef(posts)
  if (posts) last.current = posts
  const digest = since && last.current ? catchUp(last.current, since, now, nameOf, accountId) : null
  return (
    <AnimatePresence>
      {digest && (
        <CatchUp
          key="digest"
          items={digest.items}
          summary={digest.summary}
          compact={compact}
          onOpen={(item) => navigate("activity", item.id.split(":")[0])}
          onSeeAll={() => navigate("activity")}
          onDismiss={() => dismissCatchUp(readClock())}
        />
      )}
    </AnimatePresence>
  )
}
