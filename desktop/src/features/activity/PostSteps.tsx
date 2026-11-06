import { useMemo } from "react"
import type { SourceActivity } from "../../../shared/contract"
import { AgentTimeline } from "@/components/arc/agent-timeline/agent-timeline"
import { postTimeline } from "./post-timeline"

/** Each step of the post in order, the reader first and then every account, with the time each happened on its card. Nothing when no step is on record. */
export function PostSteps({ post, accountId }: { post: SourceActivity; accountId: string | null }) {
  const timeline = useMemo(() => postTimeline(post, accountId), [post, accountId])
  if (!timeline) return null
  return <AgentTimeline title="Step by step" agents={timeline.agents} spans={timeline.spans} handoffs={timeline.handoffs} summary={timeline.summary} />
}
