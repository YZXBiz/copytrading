import type { SourceActivity } from "../../../shared/contract"
import { AccountResults } from "./AccountResults"
import { PostQuote } from "./PostQuote"
import { ReadAs } from "./ReadAs"
import styles from "./post-detail.module.css"

/** One post in full: their own words, how the reader read them, then what each account did. `accountId` narrows the accounts to one. */
export function PostDetail({ post, now, accountId = null }: { post: SourceActivity; now: Date; accountId?: string | null }) {
  return (
    <div className={styles.detail}>
      <PostQuote post={post} />
      <ReadAs post={post} />
      {post.decision !== "ignore" && <AccountResults post={post} now={now} accountId={accountId} />}
    </div>
  )
}
