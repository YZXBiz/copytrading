"use client";

import { useMemo, useState } from "react";
import type { ReactNode } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { ArrowUp02Icon as ArrowUp } from "../../../icons/ArrowUp02Icon";
import { AnimatedCounter } from "../../animated-counter/animated-counter";
import { Button } from "../../button/button";
import SegmentedControl from "../../segmented-control/segmented-control";
import { TextMorph } from "../../text-morph/text-morph";
import { motionTokens } from "../../lib/motion-tokens";
import styles from "./activity-feed.module.css";

/** One event of the feed. Items arrive newest first; a larger `order` is a newer one. */
export interface FeedItem {
  id: string;
  order: number;
  /** The filter options the item belongs to, besides the first, which keeps everything. */
  kinds: string[];
  dayKey: string;
  dayTitle: string;
  dayDate: string;
  /** Who did it, in bold, and the first letter that stands in for a picture. */
  actor: string;
  /** What they did, after the actor's name. */
  action: string;
  /** Their words, when there are some. */
  quote?: string;
  /** A picture that came with the post. */
  thumb?: ReactNode;
  /** The line under the words: a status and what it means. */
  meta?: ReactNode;
  /** One short line each, such as what an account did. */
  lines?: ReactNode[];
  /** The small mark on the avatar: a company logo or a glyph. */
  mark?: ReactNode;
  time: string;
  datetime: string;
}

export interface FeedFilter { value: string; label: string }

export interface ActivityFeedProps {
  items: FeedItem[];
  /** The type filter. The first option is the one that keeps everything. */
  filters: FeedFilter[];
  filter: string;
  onFilterChange: (value: string) => void;
  /** Called when a row is pressed, with its id. */
  onOpen: (id: string) => void;
  /** Starts the "new posts" mark over: a different key treats every item now loaded as already seen. */
  resetKey: string;
  title?: string;
  /** What the feed counts, as in "12 posts". */
  noun?: { one: string; other: string };
  /** Nothing to show for the chosen filter. */
  empty?: ReactNode;
  /** Controls at the right of the header. */
  tools?: ReactNode;
  /** Reads posts older than the ones loaded. */
  older?: { loading: boolean; error?: string; show: () => void } | null;
  className?: string;
}

/** Rows drawn at first and per press of "Show more": a month of posts is a long list. */
const STEP = 30;

function Row({ item, onOpen }: { item: FeedItem; onOpen: (id: string) => void }) {
  return <li className={styles.item}>
    <span className={styles.avatar} aria-hidden="true">{item.mark ?? [...item.actor][0]}</span>
    <div className={styles.body}>
      <button type="button" className={styles.head} data-sequence={item.id} aria-haspopup="dialog" onClick={() => onOpen(item.id)}>
        <span className={styles.headText}>
          <span className={styles.sentence}><strong>{item.actor}</strong> {item.action}</span>
          {item.quote && <span className={styles.quote}>“{item.quote}”</span>}
          {item.thumb && <span className={styles.thumb}>{item.thumb}</span>}
          {item.meta && <span className={styles.meta}>{item.meta}</span>}
          {item.lines && item.lines.length > 0 && <span className={styles.lines} role="list">{item.lines.map((line, index) => <span key={index} role="listitem">{line}</span>)}</span>}
        </span>
        <span className={styles.side}><time className={styles.time} dateTime={item.datetime}>{item.time}</time></span>
      </button>
    </div>
  </li>;
}

export function ActivityFeed({ items, filters, filter, onFilterChange, onOpen, resetKey, title = "Posts", noun = { one: "post", other: "posts" }, empty, tools, older, className }: ActivityFeedProps) {
  const reduce = !!useReducedMotion();
  const newest = items.reduce((top, item) => Math.max(top, item.order), 0);
  const [seen, setSeen] = useState({ key: resetKey, order: newest });
  const [limit, setLimit] = useState({ key: resetKey + filter, count: STEP });
  if (seen.key !== resetKey) setSeen({ key: resetKey, order: newest });
  if (limit.key !== resetKey + filter) setLimit({ key: resetKey + filter, count: STEP });
  const mark = seen.key === resetKey ? seen.order : newest;

  // Posts that arrive while the feed is open wait behind the button; older pages never count as new.
  const shown = useMemo(() => items.filter(item => item.order <= mark), [items, mark]);
  const pending = useMemo(() => items.filter(item => item.order > mark && (filter === filters[0]?.value || item.kinds.includes(filter))), [items, mark, filter, filters]);
  const visible = useMemo(() => filter === filters[0]?.value ? shown : shown.filter(item => item.kinds.includes(filter)), [shown, filter, filters]);
  const rows = visible.slice(0, limit.count);
  const groups = useMemo(() => {
    const out: { key: string; title: string; date: string; items: FeedItem[] }[] = [];
    for (const item of rows) {
      const last = out.at(-1);
      if (last && last.key === item.dayKey) last.items.push(item);
      else out.push({ key: item.dayKey, title: item.dayTitle, date: item.dayDate, items: [item] });
    }
    return out;
  }, [rows]);
  const options = useMemo(() => filters.map((option, index) => {
    const count = index === 0 ? shown.length : shown.filter(item => item.kinds.includes(option.value)).length;
    return { value: option.value, label: option.label, accessory: <span className={styles.count}>{count}</span> };
  }), [filters, shown]);
  const hiddenRows = visible.length - rows.length;

  return <div className={`${styles.root} ${className ?? ""}`}>
    <div className={styles.frame}>
      <header className={styles.header}>
        <div className={styles.titleRow}>
          <h2>{title}</h2>
          <span className={styles.total}><span className={styles.inherit}><AnimatedCounter value={shown.length} /></span>&nbsp;{shown.length === 1 ? noun.one : noun.other}{older ? " so far" : ""}</span>
        </div>
        {tools && <div className={styles.tools}>{tools}</div>}
      </header>

      <div className={styles.filters}>
        <SegmentedControl className={styles.segment} options={options} value={filter} onValueChange={onFilterChange} label="Filter posts" />
      </div>

      <AnimatePresence initial={false}>
        {pending.length > 0 && <motion.div key="incoming" className={styles.incoming}
          initial={reduce ? { opacity: 0 } : { height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={reduce ? { opacity: 0 } : { height: 0, opacity: 0 }}
          transition={reduce ? { duration: motionTokens.duration.fast } : { height: motionTokens.spring.smooth, opacity: { duration: motionTokens.duration.standard } }}>
          <div className={styles.incomingInner}>
            <button type="button" className={styles.pill} onClick={() => setSeen({ key: resetKey, order: newest })}>
              <span className={styles.stack} aria-hidden="true">
                {pending.slice(0, 3).map(item => <span key={item.id} className={styles.stackItem}>{[...item.actor][0]}</span>)}
              </span>
              <span className={styles.pillText}><span className={styles.inherit}><AnimatedCounter value={pending.length} /></span>&nbsp;new&nbsp;<TextMorph>{pending.length === 1 ? noun.one : noun.other}</TextMorph></span>
              <ArrowUp width={16} height={16} aria-hidden="true" />
            </button>
          </div>
        </motion.div>}
      </AnimatePresence>

      <div className={styles.list}>
        {/* Switching the type filter crossfades the whole list, so rows never slide over each other. */}
        <AnimatePresence initial={false} mode="wait">
          <motion.div key={filter} initial={reduce ? { opacity: 0 } : { opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}
            transition={reduce ? { duration: motionTokens.duration.instant } : { opacity: { duration: motionTokens.duration.fast }, y: motionTokens.spring.smooth }}>
            {groups.map(group => <section key={group.key} className={styles.group} aria-label={group.title}>
              <h3 className={styles.day}><span>{group.title}</span><span className={styles.dayDate}>{group.date}</span></h3>
              <ol className={styles.items}>{group.items.map(item => <Row key={item.id} item={item} onOpen={onOpen} />)}</ol>
            </section>)}
            {groups.length === 0 && <div className={styles.empty}>{empty}</div>}
          </motion.div>
        </AnimatePresence>
        {(hiddenRows > 0 || older) && <div className={styles.more}>
          {older?.error && hiddenRows === 0 && <p role="alert">{older.error}</p>}
          {hiddenRows > 0
            ? <Button variant="secondary" size="sm" onClick={() => setLimit({ key: resetKey + filter, count: limit.count + STEP })}>Show more</Button>
            : older && <Button variant="secondary" size="sm" loading={older.loading} onClick={older.show}>{older.error ? "Try again" : "Show older"}</Button>}
        </div>}
      </div>
    </div>
  </div>;
}

export default ActivityFeed;
