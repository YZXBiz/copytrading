import type { SourceActivity } from "../../../shared/contract"
import { AccountResults } from "./AccountResults"
import { PostQuote } from "./PostQuote"
import { PostSteps } from "./PostSteps"
import { ReadAs } from "./ReadAs"
import styles from "./post-detail.module.css"

/** One post in full: their own words, how the reader read them, what each account did, then every step in order. `accountId` narrows the accounts to one. */
export function PostDetail({ post, now, accountId = null }: { post: SourceActivity; now: Date; accountId?: string | null }) {
  return (
    <div className={styles.detail}>
      <PostQuote post={post} />
      <ReadAs post={post} />
      {post.decision !== "ignore" && <AccountResults post={post} now={now} accountId={accountId} />}
      <PostSteps post={post} accountId={accountId} />
    </div>
  )
}
