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

Screenshots: `before/` holds main at `247c34e1`, `after/` each fix; both live in the session
scratchpad, not in the repository. Each PR body lists its own before and after files.

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
| Diagnostics | full, empty, error, loading, journal | Fixed: #138 |
| Settings: General, Appearance, Updates, Engine, Agent Access, Backups, Logs | full, error | Fixed: #135 |
| Assistant panel | account page, Connections | Pass |
| Tips: Stop from anywhere, Measure a move | tips | Fixed: #140 |
| Menu bar | full | Pass |
| Lock screen | locked | Pass |
| Copy sheet (copy and review) | waiting call | Fixed: #118 (Chinese words); layout passes at its 700 pt width |
| Evaluate-a-post sheet | before a result, real evaluation | Fixed: #124, #139 |
| Sell sheet | a copied lot | Pass |
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
| 9 | Everywhere a call is named | 简体中文 | A call was 喊单 in 54 strings and 信号 in 48 | #125 | `pr/zh-call/before-guru-zh.png` → `after-guru-zh.png` |
| 10 | Connections panels | Any | Filled grey field boxes and a system accent button, unlike every sheet | #128 | `pr/connection-panels/before-discord-en.png` → `after-discord-en.png` |
| 11 | Account chart | An account the engine can't read a curve for | "Reading the account's curve from Alpaca…" forever, on a band shorter than the plot | #129 (merged) | `pr/chart-no-curve/before-en.png` → `after-en.png` |
| 12 | Guru page | 简体中文 | "跟单到 账户 primary (模拟盘)、账户 swing…": 账户 before every account | #131 | `pr/zh-guru-accounts/before-zh.png` → `after-zh.png` |
| 13 | Getting Started, Shortcuts | Any | "⌘1 to 6: Today, Activity, People, Accounts…", "↑↓ posts in Activity": pages that no longer exist; ⌘K and ⌘J missing; "⌘ 1 打开 9" in 简体中文 | #133 | `pr/guide-shortcuts/before-en.png` → `after-en.png` |
| 14 | Getting Started, palette, tip | Any | The toolbar's Stop All was also "Pause Copying" and "Stop Copying" | #134 (merged) | `pr/stop-all/before-guide-en.png` → `after-guide-en.png` |
| 15 | Settings › Engine, Settings card | 简体中文 | "风险检查 · 清除" (clear as "remove"); "将 2个信号源 跟单到 2个账户" | #135 | `pr/zh-settings/before-engine-zh.png` → `after-engine-zh.png` |
| 16 | Agent approval sheet | limits, order, resume | Account row showed a boxed "Paper" and no account; a limits title of three lines; 代理 beside 智能体 | #136 | `pr/agent-sheet/before-limits-en.png` → `after-limits-en.png` |
| 17 | Diagnostics | journal | Titles were codes ("Ledger: broker acknowle…" cut off; "自检：completed", "账本：order update" in 简体中文), "Provider: Other" on a Discord post, empty lists over three lines | #138 | `pr/diagnostics/before-list-en-light.png` → `after-list-en-light.png` |
| 18 | Evaluate-a-post sheet | real evaluation | The result sat below the fold, cut by the buttons, after pressing Evaluate; its note repeated the post | #139 | `pr/evaluate-real/before-en-light.png` → `after-en-light.png` |
| 19 | Account page, Measure a move tip | tips | The popover covered the limits ("$3,420 of $5,000" under its glass) | #140 | `pr/tips/before-primary-en-light.png` → `after-primary-en-light.png` |
| 20 | Toolbar, Stop from anywhere tip | tips | The popover opened above the toolbar, outside the window | #140 | `pr/tips/before-connections-en-light.png` → `after-connections-en-light.png` |

## Looked at and left as they are

- **Copy sheet footer** wrapped its price onto a second line in a 640 pt capture. At the sheet's
  ideal 700 pt width (#104) it is one line in English and 简体中文.
- **Positions table**: whole-share counts sit left of the column's right edge. They are padded with
  figure spaces so decimal points line up; deliberate.
- **Settings › Logs "Engine stopped"** and **Backups "App support is not open"** appeared only
  because the harness starts no engine; the live app fills both. The Backups string is not in the
  catalogs, so it would read in English under 简体中文 if it ever showed (P3).
- **Diagnostics** keeps its segmented filter and search field; DESIGN.md lists segmented tracks
  among the controls.
- **"Not updating since 4:33 PM"** on an account came from fixture balances read more than a minute
  before the capture; the freshness rule (60 s) is right.
- P3, not changed: Connections' interpreter line ends "…a model on this Mac / costs nothing." on a
  short second line; the sell sheet reads "0.84 of 0.84 shares" with All chosen; the lock screen
  says CopyTrading twice.

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

## Impeccable audit

| # | Dimension | Score | Key finding |
|---|---|---|---|
| 1 | Accessibility | 3 | Labels and identifiers are kept through every change; gains and losses keep sign and arrow; tips no longer cover the limits |
| 2 | Performance | 3 | Nothing here changed motion or redraws |
| 3 | Responsive (window sizes, long text) | 3 | Long names and seven-figure balances were the gaps (#119) |
| 4 | Theming | 4 | Light and dark hold on every surface rendered |
| 5 | Anti-patterns | 3 | The last boxed form, filled fields, and dashed frame are gone (#122, #124, #128); no code names left in Diagnostics (#138) |
| | **Total** | **16/20** | **Good**; with the open PRs merged, every row above is PASS or a fixed FAIL |
