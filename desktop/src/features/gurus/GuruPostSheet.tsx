import type { SourceActivity } from "../../../shared/contract"
import { Drawer, DrawerContent, useDrawerItem } from "@/components/arc/drawer/drawer"
import { OutcomeBadge } from "@/features/activity/OutcomeBadge"
import { PostDetail } from "@/features/activity/PostDetail"
import { cardOutcome } from "@/features/activity/outcome"
import { postTime } from "@/features/activity/time"
import styles from "@/features/activity/post-detail.module.css"

/** One post in full, in a drawer beside the page: who and when, how it ended, then the post and what each account did. */
export function GuruPostSheet({ post, guruName, now, onClose }: { post: SourceActivity | undefined; guruName: string; now: Date; onClose: () => void }) {
  // The post stays on screen while the drawer slides out.
  const shown = useDrawerItem(post)
  const outcome = shown ? cardOutcome(shown, now) : null
  return (
    <Drawer open={post !== undefined} onOpenChange={(next) => !next && onClose()}>
      <DrawerContent title={guruName} description={shown ? postTime(shown.source_at) : undefined} aria-label="The post in full">
        {shown && outcome && (
          <div className={styles.sheet}>
            <div className={styles.outcome}>
              <OutcomeBadge title={outcome.title} tone={outcome.tone} />
            </div>
            <PostDetail post={shown} now={now} />
          </div>
        )}
      </DrawerContent>
    </Drawer>
  )
}
