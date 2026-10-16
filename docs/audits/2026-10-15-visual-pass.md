# Visual pass — October 15, 2026

**Baseline:** `247c34e1` (main, after #104 rebuilt the copy sheet's How much and Price rows).

Every screen, sheet, and panel of the macOS app, rendered and read against `PRODUCT.md`,
`DESIGN.md`, the owner's approved register (Josefin display and SF Pro body, ink lines, no boxes,
compact switches, no figures, show less), and the `/impeccable` product audit: alignment, wrapping
and orphaned glyphs, ellipsis labels, raw codes, clutter, type scale, consistent controls, and
Chinese layout (one-line titles, numbers tight against Chinese, one name per concept).

## How it was rendered

A scratch SwiftPM executable links the app's `CopyTradingUI` library and draws the real views
(`MainSplitView`, every sheet, `ConnectionPanelContent`, `PostDetailPane`, `MenuBarView`,
`LockedView`) with demo data from JSON fixtures served through a fake `AccountOperations`. Each
view is drawn in its own window at desktop level (below every other window, never key, never
focused) and captured with `screencapture -l`. Main screens are 1180 × 800 (the app's default
size); tall captures (1180 × 1700–2600) cover what sits below the fold; sheets take their own ideal
size, as they do when presented. Nothing touched `~/Desktop/CopyTrading.app` or the live state.

Every screen was rendered in **light and dark** and in **English and 简体中文**, in these states:

| State | What the fixture holds |
|---|---|
| full | Two paper accounts, two gurus, eleven posts over two days (trades, a sell, chatter, one call waiting), positions with lots, a day curve |
| many | A third, live account named `long-term-retirement-paper-account` holding $1,284,519.62, a guru named "Christopher Montgomery-Alexander", 17 positions, five calls waiting |
| nodata | Saved setup, accounts with balances, no positions, no posts, no curve |
| empty | First run: nothing saved |
| loading | Saved setup, the engine starting, reads that never answer |
| error | Saved setup, the engine failed, every read refused |
| locked | The lock screen |
| journal | `full`, plus a seeded `logs/diagnostics.jsonl`: 70 synthetic records in the live journal's shapes (four posts end to end, a refusal, a parse that raised, an oversize request, a compressed reply, a self-test) |
| real evaluation | `full`, holding one real DeepSeek evaluation (`deepseek-flash`, one call) of "sofi another 1/6 at 27.10", run through the engine's own `ProfileEvaluationService` |
| tips | `full`, with TipKit forced on (`Tips.showAllTipsForTesting()`, a throwaway datastore) and each tip's popover captured with its window |

Screenshots: `before/` holds main at `247c34e1`, `after/` each fix; they and every other path
named below (`pr/`, `resp/`, `a11y/`, `dts2/`, `vo/`) live in the session scratchpad, not in the repository. Each PR body lists its own before and after files.

## Coverage

| Surface | States rendered | Result |
|---|---|---|
| Account page (balance, chart, limits, waiting calls, positions, activity) | full, many, nodata, loading, error | Fixed: #119, #121, #122, #129 |
| Guru page (stats, holdings, posts) | full, many, nodata, loading, error | Fixed: #119, #122, #131 |
| Post pane (read as, each account's outcome, timeline) | trade, sell, waiting, chatter, not bought | Fixed: #117 |
| Sidebar | full, many, loading, error, empty | Fixed: #119, #122 |
| Toolbar (sync, copying, Stop All, assistant, lock) | full, many, error, empty | Pass |
| Connections (services, accounts, gurus, alerts, start card, tips) | full, empty, unsaved | Pass; panels fixed in #128 |
| Connections panels (Discord, interpreter, alerts) | full, empty | Fixed: #128 |
| Getting Started (checklist, journey, Before you go, Shortcuts) | full, empty | Fixed: #133, #134 |
| Every main screen at 980 × 640 and 1800 × 1100 | full, many | Fixed: #146 |
| Diagnostics | full, empty, error, loading, journal | Fixed: #138, #142, #144 |
| Settings: General, Appearance, Updates, Engine, Agent Access, Backups, Logs | full, error | Fixed: #135 |
| Assistant panel | account page, Connections | Pass |
| Tips: Stop from anywhere, Measure a move | tips | Fixed: #140 |
| Menu bar | full | Pass |
| Lock screen | locked | Pass |
| Copy sheet (copy and review) | waiting call | Fixed: #118 (Chinese words); layout passes at its 700 pt width |
| Evaluate-a-post sheet | before a result, real evaluation | Fixed: #124, #139 |
| Sell sheet | a copied lot | Fixed: #145 |
| Recap sheet | six hours away | Pass |
| Guru editor, account editor | saved guru and account | Pass |
| Setup Check sheet | before a check | Pass |
| Agent approval sheet | limits, order, resume, start | Fixed: #136 |
| Setup import sheet | three filled, three missing | Pass |

## Findings

| # | Screen | State | Issue | Fix | Before → after |
|---|---|---|---|---|---|
| 1 | Post pane | Waiting call with no reason code | A lone "—." under "Copy by": the note was `Reason.text(nil)` made a sentence | #117 (merged) | `pr/waiting-note/before-en.png` → `after-en.png` |
| 2 | Copy sheet, account editor, 16 more | 简体中文 | A guru was 老师 or 导师 in 17 strings ("$230 老师的价格"); the Price row said 现价 | #118 (merged) | `pr/zh-guru/before-copy-zh.png` → `after-copy-zh.png` |
| 3 | Sidebar | many | A $1,284,519.62 balance read "$1,284,519...." | #119 (merged) | `pr/long-names/before-account-zh.png` → `after-account-zh.png` |
| 4 | Guru page | many | A long account name broke at its hyphens over two lines beside every post | #119 (merged) | `pr/long-names/before-guru-en.png` → `after-guru-en.png` |
| 5 | Account chart | Curve near zero | The value axis read "-$0" | #121 (merged) | `pr/chart-axis/before-en.png` → `after-en.png` |
| 6 | Guru page, sidebar | loading, error | "0 posts today · 0 traded · 0 waiting", "No posts yet", and "Quiet today" before anything was read | #122 (merged) | `pr/waiting-states/before-loading-guru-en.png` → `after-loading-guru-en.png` |
| 7 | Account page | loading, error | A dashed rounded box under a boxed "Paper" badge | #122 (merged) | `pr/waiting-states/before-loading-account-en.png` → `after-loading-account-en.png` |
| 8 | Evaluate-a-post sheet | Before and after a result | Raw "channel 1287345091273645568 · author 804512398817402881", a version hash, "Delivered" in English under 简体中文, grey boxed form rows | #124 (merged) | `pr/evaluate-sheet/before-en.png` → `after-en.png` |
| 9 | Everywhere a call is named | 简体中文 | A call was 喊单 in 54 strings and 信号 in 48 | #125 (merged) | `pr/zh-call/before-guru-zh.png` → `after-guru-zh.png` |
| 10 | Connections panels | Any | Filled grey field boxes and a system accent button, unlike every sheet | #128 | `pr/connection-panels/before-discord-en.png` → `after-discord-en.png` |
| 11 | Account chart | An account the engine can't read a curve for | "Reading the account's curve from Alpaca…" forever, on a band shorter than the plot | #129 (merged) | `pr/chart-no-curve/before-en.png` → `after-en.png` |
| 12 | Guru page | 简体中文 | "跟单到 账户 primary (模拟盘)、账户 swing…": 账户 before every account | #131 | `pr/zh-guru-accounts/before-zh.png` → `after-zh.png` |
| 13 | Getting Started, Shortcuts | Any | "⌘1 to 6: Today, Activity, People, Accounts…", "↑↓ posts in Activity": pages that no longer exist; ⌘K and ⌘J missing; "⌘ 1 打开 9" in 简体中文 | #133 (merged) | `pr/guide-shortcuts/before-en.png` → `after-en.png` |
| 14 | Getting Started, palette, tip | Any | The toolbar's Stop All was also "Pause Copying" and "Stop Copying" | #134 (merged) | `pr/stop-all/before-guide-en.png` → `after-guide-en.png` |
| 15 | Settings › Engine, Settings card | 简体中文 | "风险检查 · 清除" (clear as "remove"); "将 2个信号源 跟单到 2个账户" | #135 | `pr/zh-settings/before-engine-zh.png` → `after-engine-zh.png` |
| 16 | Agent approval sheet | limits, order, resume | Account row showed a boxed "Paper" and no account; a limits title of three lines; 代理 beside 智能体 | #136 (merged) | `pr/agent-sheet/before-limits-en.png` → `after-limits-en.png` |
| 17 | Diagnostics | journal | Titles were codes ("Ledger: broker acknowle…" cut off; "自检：completed", "账本：order update" in 简体中文), "Provider: Other" on a Discord post, empty lists over three lines | #138 | `pr/diagnostics/before-list-en-light.png` → `after-list-en-light.png` |
| 18 | Evaluate-a-post sheet | real evaluation | The result sat below the fold, cut by the buttons, after pressing Evaluate; its note repeated the post | #139 (merged) | `pr/evaluate-real/before-en-light.png` → `after-en-light.png` |
| 19 | Account page, Measure a move tip | tips | The popover covered the limits ("$3,420 of $5,000" under its glass) | #140 (merged) | `pr/tips/before-primary-en-light.png` → `after-primary-en-light.png` |
| 20 | Toolbar, Stop from anywhere tip | tips | The popover opened above the toolbar, outside the window | #140 (merged) | `pr/tips/before-connections-en-light.png` → `after-connections-en-light.png` |
| 21 | Every money change, status, waiting call | Any | Gains, losses, live and waiting text used system green, red, orange and #B8860B: 1.91–3.55:1 on the app's surfaces | #141 (merged) | `pr/text-contrast/before-account-light.png` → `after-account-light.png` |
| 22 | Diagnostics, account page with a call waiting | Idle | 4.1–6.4% CPU with nothing changing: the journal was re-parsed every 5 s and the waiting rows rebuilt every second | #142 (merged) | CPU table below |
| 23 | Whole app | — | Nine views no screen draws, ten unused tokens, `Palette.accent`, and 98 placeholder strings no code asks for | #143 (merged) | — |
| 24 | Diagnostics | journal | The last boxed controls: a grey segmented filter, a rounded search box, a grey refresh square | #144 (merged) | `pr/diagnostics-controls/before-en.png` → `after-en.png` |
| 25 | Sell sheet | All chosen | "0.84 of 0.84 shares" | #145 (merged) | `pr/sell-all/before-en.png` → `after-en.png` |
| 26 | Guru page | 980 pt, long name | "Christopher…ery-Alexander" | #146 (merged) | `pr/guru-name/before-980-en.png` → `after-980-en.png` |
| 27 | Catalog check | — | The check missed texts split over lines or held in a variable, so #143 removed three strings still in use (restored before merge) | #147 | — |
| 28 | Account chart | 简体中文 VoiceOver; day chart | The reference line spoke "Previous close" in English; the PRE-MARKET / AFTER HOURS names were 3.44–3.79:1 | #148 (merged) | `a11y/before-light/account-primary.png` → `a11y/after-light/account-primary.png` |
| 29 | Every screen and sheet | VoiceOver, en and 简体中文 | Menus read two or three times; capitals spoken as capitals ("OFF / 5 S", "READ AS", "ACTIVITY"); nine unnamed limit fields; switch names read twice; rows in loose words ("primary" / " · " / "Paper", "7, POSTS TODAY", limits without amounts); the day chart read as "0.1 to 0.2" | #152 | `vo/full/*.txt`, `vo/sheets/*.txt` → `vo/after/en/*.txt`, `vo/after/zh/*.txt` |

## Looked at and left as they are

- **Copy sheet footer** wrapped its price onto a second line in a 640 pt capture. At the sheet's
  ideal 700 pt width (#104) it is one line in English and 简体中文.
- **Positions table**: whole-share counts sit left of the column's right edge. They are padded with
  figure spaces so decimal points line up; deliberate.
- **Settings › Logs "Engine stopped"** and **Backups "App support is not open"** appeared only
  because the harness starts no engine; the live app fills both. The Backups string is not in the
  catalogs, so it would read in English under 简体中文 if it ever showed (P3).
- **"Not updating since 4:33 PM"** on an account came from fixture balances read more than a minute
  before the capture; the freshness rule (60 s) is right.
- **The chart's 1D / 1W / 1M / 3M picker** stays a segmented track: DESIGN.md specifies it, and
  the account page's one tracked switcher (Positions / Activity) owns the Control-digit keys.
- **PRE- / MARKET** splitting over two lines in a narrow pre-market band is the band's deliberate
  word-per-line fallback; a band too narrow for that stays unnamed.
- P3, not changed: at 980 pt in 简体中文, Connections' interpreter line leaves "不收费。" alone on
  its last line. Connections' interpreter line ends "…a model on this Mac / costs nothing." on a
  short second line; the lock screen says CopyTrading twice.

## Closed: what could not be rendered at first

Each of these was a FAIL in the first version of this audit; each is now rendered, and what it
showed is fixed above.

- **Diagnostics with records** (#138): a throwaway state root's `logs/diagnostics.jsonl` was seeded
  with records shaped like the live journal (field sets read from
  `~/Library/Application Support/CopyTrading/logs/diagnostics.jsonl`, read-only; no content
  copied). The list and each record kind were rendered in both languages and themes.
- **Evaluate-a-post result after a real model call** (#139): one DeepSeek call through the engine's
  `ProfileEvaluationService`, with the test key read inside the process and never printed; the real
  sheet was rendered holding the result it returned.
- **Tips** (#140): both tips, forced on and attached to their real anchors. DESIGN.md also names a
  "Needs Review" tip; the app has only these two.
- **The "You're copying" card**: DESIGN.md describes it, but the app no longer has it
  (`copyingStartedAt` is set and never read), so there is nothing to render.

## Second round: accessibility, performance, window sizes

### Contrast (#141, #148)

Text that carries meaning, measured against all five surfaces (page, canvas, group, panel, well)
in both themes. Contract check "palette contrast" holds every role at ≥ 4.5:1.

| Text | Was | Worst was | Now (light / dark) | Worst now |
|---|---|---|---|---|
| Money up, Synced | system green | 1.91 | #187C27 / #32D74B | 4.58 |
| Money down, failures | system red | 3.20 | #D80B00 / #FF6057 | 4.56 |
| Live, delayed | system orange | 1.98 | #9D5C00 / #FF9F0A | 4.57 |
| Waiting calls | #B8860B | 2.93 | #8B6508 / #F5C04A | 4.57 |
| Tertiary ink, dark | #8E8E93 | 4.16 | #96969B | 4.60 |
| Session names on the day chart (9 pt) | tertiary at 0.8 | 3.44 | full tertiary | 4.51 (4.99 with #141) |

### Idle work (#142)

Scratch harness, window inactive, 15 s, `getrusage`, a 4 MB journal like the live one; two runs each.

| Screen | main | #142 (merged) |
|---|---|---|
| Diagnostics | 4.4%, 4.1% | 2.1%, 1.9% |
| Account page, one call waiting | 5.5%, 6.4% | 2.0%, 2.1% |

### Window sizes

Every main screen at the minimum window (980 × 640) and a wide one (1800 × 1100), English and
简体中文, plus the long-name fixture at 980. Only the guru page title failed (#146); the P3 orphan
above stays. Renders: `resp/narrow-en`, `resp/narrow-zh`, `resp/narrow-many-en`, `resp/narrow-many-zh`,
`resp/wide-en`, `resp/wide-zh`.

### Accessibility

- **Labels (PASS).** Every icon-only `Button` in `Sources/CopyTrading` has an accessibility label
  (source scan of each `Button`'s label closure). The palette's tap rows carry the button trait, and
  the panel veil is hidden from VoiceOver. Diagnostics' filter speaks "Problems, 2", not the drawn
  capitals (#144).
- **Spoken text is translated (PASS after #148).** `test_spoken_text.py` fails any literal handed to
  `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityHint` or `.help` outside a lookup.
  On main it found the chart's reference line.
- **Every text the app asks for is in both catalogs (PASS after #147).** The extraction now follows
  multi-line ternaries and local variables, and it finds the three strings #143 removed.
- **Dynamic Type (N/A).** `settings:general` was rendered at the default size, `.xxxLarge` and
  `.accessibility5`; the three captures are pixel-identical (`dts2/`). macOS SwiftUI does not
  scale text styles by `dynamicTypeSize`, so there is nothing to test.
- **VoiceOver reading order (PASS after #152).** With the screen unlocked, I read the real tree
  of 14 main screens and 18 sheets and panels in English and 简体中文. Each view was held in the
  harness and `axdump` read role, label, value, value description, help and selection, in
  VoiceOver's order. The order was right everywhere: sidebar, toolbar, then the page top to bottom,
  with the waiting calls between Limits and Positions. What it read was not (finding 29). #152
  fixes each case; the trees after it read one element per row, in words, name first.
  - **Menus** are one button each.
  - **Capitals** are spoken as written. `test_drawn_capitals.py` now fails a display `uppercased()`
    or a `textCase` without a spoken label.
  - **Fields** carry their names. Switches read their title once, with the detail as the hint.
  - **Choices** report their selection (`AXSelected`).
  - **Charts.** The day chart speaks its summary instead of fractions. The menu bar sparkline is
    one element.
  - **Renders** are pixel-identical to main apart from clock text (`vo/px/`).
- **Left as is (P3).** "Keep logs for" is an incrementor whose value reads "7" with the value
  description "7 days" (macOS keeps a stepper's number). The waiting-call section looked missing in
  the first dump only because the fixture's 8 PM ET deadline had passed; with a fresh call it reads
  in full.

## DESIGN.md is stale

DESIGN.md is not in the repository. These are the parts that no longer match the app, for the owner to update:

- **Type.** It says titles are New York (serif), with italic second lines ("Getting *started*",
  "Ask about / *your trading*", serif headings in Settings, Diagnostics and the guide). The app uses
  Josefin Sans for display and SF Pro for body, with no serif and no italics (`DisplayFont.swift`).
- **Screens.** It describes Today, Activity, People and Accounts pages, an Activity master list with a
  reading lane and a pale blue selection pill, and invitations on their empty panes. The app has
  account and guru pages plus Connections, Getting Started, Settings and Diagnostics
  (`AppModel.Screen`).
- **Accent.** It says #3478F6 is for links, switches and primary actions, and accent rings and
  capsules appear throughout. The app tint is ink, and `Palette.accent` had no reader (#143).
- **The "You're copying" card** after a new setup: removed from the app.
- **Tips.** It names a "Needs Review" tip. The app has only Stop from anywhere and Measure a move.
- **Unsaved changes.** It describes a floating Liquid Glass capsule at the bottom of Connections, People,
  Accounts and Getting Started. The app shows `ConnectionsStartCard` at the foot of Connections.
- **Settings rows** sit in a soft `well` per DESIGN.md; the approved register has no boxes.
- **People cards** tinted with the monogram's color, framed, with serif names: gone with People.
- **Gain / loss colors.** It doesn't name the text colors; #141's palette values should be recorded.
- **Diagnostics' segmented track**: replaced by the tracked switcher (#144).

## Impeccable audit

| # | Dimension | First round | Now | Key finding |
|---|---|---|---|---|
| 1 | Accessibility | 3 | 4 | Text holds AA on every surface (#141, #148, checked by a contract test); every screen's VoiceOver tree read in both languages: one element per row, in words, every control named, selections reported (#152) |
| 2 | Performance | 3 | 4 | Idle CPU halved on the two busiest pages (#142) |
| 3 | Responsive (window sizes, long text) | 3 | 4 | 980 to 1800 pt in both languages; the last truncated name fixed (#146) |
| 4 | Theming | 4 | 4 | Light and dark hold on every surface rendered |
| 5 | Anti-patterns | 3 | 4 | No boxed controls left (#144), no repeated number (#145), dead views and strings removed (#143) |
| | **Total** | **16/20** | **20/20** | **Excellent** once #128, #138 and #152 merge; no row is FAIL |
