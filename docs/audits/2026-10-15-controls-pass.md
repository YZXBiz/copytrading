# Controls pass — October 15, 2026

**Baseline:** `be54732f` (main). **Fixes:** this branch, `YZXBiz/test-pass-controls` (PR #PR).

Every button, switch, link, menu item, tab, sheet, toolbar item, context menu, keyboard shortcut,
and ⌘K action was pressed, in English and in 简体中文. Each was checked against three questions:
does it do what its label says, is the result right, and is there a way back. Counts were checked
against the lists they count, and every error message for naming its subject and what to do next.

**How it ran.** A debug copy of the app ("CopyTrading Controls", its own bundle id) ran on a
throwaway state root, driven in the background through the accessibility API. It never took
keyboard focus, and the installed app and the live paper accounts were never touched. Screens
that need a saved setup (account page, guru page, post detail, sell sheet) ran in a fixture
harness: the real `MainSplitView` on seeded accounts, positions, posts, and an equity curve, with no
engine. The assistant talked to the journeys' scripted local model. Updates came from a local
appcast offering version 99.0, and external links were checked with `curl`. Screenshots stay with
the run, not the repository.

**Result.** 43 defects found and fixed, each with a regression test where code can hold one
(`app/Tests/CopyTradingContractTests/ControlsPassTests.swift`, contract check `controls pass`).
Three findings are left open with reasons, and four groups of controls could not run here.

## Fixed

| # | Screen | Control | What was wrong | Fix |
|---|---|---|---|---|
| 1 | Toolbar | Back | Enabled on a fresh window; it went to a screen the launch never showed, because the launch's first-screen choice was recorded as history | History lives in the model, starts empty after launch, and skips screens that are gone |
| 2 | Setup tour | Counter | "1 OF 8" on a card that says "Five steps" | "Stop 1 of 8" / 导览 1/8: stops of the tour, not setup steps |
| 3 | Connections | Discord, interpreter Connect with nothing typed | Closed silently | Says what it needs ("Enter a channel ID and your Discord token to connect.") |
| 4 | Connections | Connect when the check can't run | Closed as if the check passed | A failed check: "CopyTrading couldn't run this check because its engine isn't answering. Start it in Settings → Engine, then try again." |
| 5 | Connections | Anthropic | Model field empty; every other service prefills its model | The starting service's model is suggested too |
| 6 | Connections | ⋯ › Import Setup… | Duplicate of the button beside it | Only in ⋯ once a setup is saved (the button is gone then) |
| 7 | Connections | Discord channel alerts panel | Titled "Connect to Discord", same as the token panel | "Connect to Discord alerts" / "Telegram alerts" |
| 8 | Connections | Alerts step | ✓ while its check had failed | Done only while no failed check stands |
| 9 | Account editor | Nine limit fields, re-post minutes, time zone search | No accessibility label | Labelled |
| 10 | Account editor | Account name | "my acct!" accepted; the engine rejects it | The row reads "Needs a valid name" and the sheet says why |
| 11 | Account editor | Done after Alpaca refuses the keys | No way out but deleting the account | A second Done closes and keeps the account to fix later |
| 12 | Account editor | "Ask me before sending orders" | Said orders wait "in Activity" | They wait on the account's page |
| 13 | Guru editor | Example actions | BUY / REDUCE / CLOSE ("Close" read as closing the sheet) | Buy / Sell part / Sell all |
| 14 | Guru editor | Channel picker | Listed the same channel twice | Once |
| 15 | Getting Started | "Your account" stops before setup | Dead (opened the guide itself) | Open Connections until an account exists |
| 16 | Getting Started | Show Tips Again | Nothing visible | "Tips will show again once copying is set up, each beside what it points at." |
| 17 | Getting Started | Shortcuts | Named Today, Activity, People screens that are gone; ⌘K, ⌘J missing | Rewritten from the bound shortcuts |
| 18 | Settings sidebar | Steps count | "1 of 5" while Connections said "1 of 4" | "n of 5 steps done" everywhere |
| 19 | Settings › General | Start copying automatically (off) | Gave the wrong reason | "Once a setup is saved and every account is paper. Lock still locks." |
| 20 | Account page | Stop/Start Copying, After a restart, holdings fix | Did nothing and said nothing with no engine | "Nothing was sent: the engine isn't running. Start it in Settings → Engine, then try again." |
| 21 | ⌘K Find | Choosing a post | Opened the guru, not the post | Opens the post; rows are real buttons |
| 22 | ⌘K Find, guide | "Pause Copying" | The control is called Stop Copying | Stop Copying |
| 23 | Setup error | Invalid guru | Asked for a "message prefix", which no longer exists | Names what is invalid |
| 24 | Settings › Updates | Check for updates automatically | Turned the setting off but kept showing on | The switch follows Sparkle's setting |
| 25 | Settings › Engine | Run Self-Test while stopped | Pressable; said "Start it in Settings → Engine" on that page | Disabled with "Start the engine to run the self-test." |
| 26 | Settings › Logs | Note after a further edit | "Saved." beside an enabled Save | "Saved." only while nothing is unsaved |
| 27 | Settings › Agent Access | Copy Setup Command | No confirmation; the row showed only the helper's path | Shows the command it copies and a check once copied |
| 28 | Settings › Backups | Help text | "Pauses and drains trading writers"; "until you activate it" | "Copying waits a moment while it runs."; "until you restore it" |
| 29 | Menu bar, locked screen | Engine stopped note | "The engine acknowledged its graceful drain. Broker-accepted orders may remain open." and raw process names | "The engine finished what it was doing and stopped. Orders the broker already accepted may stay open until they fill or expire." |
| 30 | Assistant | Suggestions before setup | Asked about gurus, a paper account, and posts that don't exist yet | Four setup questions until a setup is saved |
| 31 | Message banner | VoiceOver | "Platform status: …" | "Message: …" |
| 32 | Account page | Error VoiceOver | "Account command error: …" | "primary: …" |
| 33 | Account page | 1W, 1M, 3M with no engine | Did nothing and said nothing | "The chart can't change while the engine is stopped. Start it in Settings → Engine." |
| 34 | Toolbar | Stop All with no engine | Did nothing and said nothing | Says the engine isn't running |
| 35 | ⌘K Find | Search field | No accessibility label | "Find" / 查找 |
| 36 | Connections | Fireworks AI key page link | Redirected to a 404 | `app.fireworks.ai/settings/users/api-keys` |
| 37 | 简体中文 › Engine | Risk checks "Clear" | 清除 ("erase") | "Nothing waiting" / 无待处理 |
| 38 | 简体中文 › Diagnostics | Self-test records | Raw engine codes: "自检：completed", "parsed", status "Parsed" | 自检：已完成 / 已读取 / 已捕获 |
| 39 | 简体中文 › Agent Access | Command name | "CopyTrading 命令" for the `copytrading` command | `copytrading` 命令 |
| 40 | 简体中文 › Tour | Name | 导览, 结束引导, 设置引导 for one tour | 导览 throughout |
| 41 | Journeys | J26 | Expected a shortcut line that no longer exists | Follows the new list |
| 42 | Journeys | Updates | No journey | J43 |
| 43 | Journeys | ⌘K Find, Back, Forward | No journey | J44 |

## Open

| Screen | Control | Finding | Why left |
|---|---|---|---|
| Assistant | Panel over an open Connect panel | The assistant floats over the page and cuts the centered panel ("Connect to Other (Op…") | A layout decision (push the page or float); for the visuals pass |
| Settings › Engine | Status heading | VoiceOver reads "Local engine, Ready" while the page shows "Running" | Synonyms; five journeys wait on the label |
| ⌘K Find | ⌘F "Find a Post…" | Opens the same Find as ⌘K | A second door, not a second control; kept |

## Not run here

| Controls | Why | Covered by |
|---|---|---|
| Needs you: Copy…, Skip, Undo, the copy review sheet | Need a waiting call; the fixture has none | J36 (live paper) |
| Stop Copying / Start Copying with a running engine, menu bar Stop/Start Copying | Need a saved, running setup on a real broker | J9, J10, J35 |
| Setup Check sheet's live checks | Need real Alpaca, Discord, and model keys | J31 |
| Guru page stat strip | Computed by the engine; the harness has none | Engine tests |

Open CopyTrading, the menu bar's Settings…, and Show in Finder were checked in code, not pressed:
pressing them brings an app to the front.

## Passed

### Launch, toolbar, sidebar

| Control | Evidence |
|---|---|
| Back, Forward on a fresh window | Both disabled (after fix) |
| Back, Forward after moving | Back returns to the previous screen, Forward returns; a removed guru is skipped |
| Refresh ("Not copying" / "Synced …") | Rereads |
| Ask the Assistant | Opens and closes the panel; the label becomes "Close the Assistant" |
| Lock | Locks at once; with typed setup asks "Lock and discard your unsaved setup changes?"; Cancel keeps the typing, Discard and Lock clears it |
| Unlock | Returns to the screen that was open |
| Hide/Show Sidebar | Toggles; the page menu (Connections ✓, Getting Started, Settings, Diagnostics) takes its place and each item navigates |
| Diagnostics (sidebar foot) | Opens Diagnostics |

### Setup tour and Getting Started

| Control | Evidence |
|---|---|
| Tour Help, End Tour | Help opens the stop's articles; End Tour ends and is remembered |
| Show Me Around, Pick Up Where I Left Off | Start the tour on Connections at the first unfinished stop |
| Journey stops 1–6, Previous, Next | Each card "STEP n OF 6"; Previous disabled at 1, Next at 6 |
| Stop and step buttons | Open Connections (and the account once one exists) |

### Connections

| Control | Evidence |
|---|---|
| Discord panel: open, Step by step, ✕ | Panel, guide, close keeps typing ("Discord, 1 channel, anyone who posts · Needs a token") |
| Discord with a made-up token | "Discord didn't accept the token, or can't find a channel. Check both." |
| OpenAI, Gemini, DeepSeek, Ollama, Other, eight more services, Fewer services | Each panel opens with its model prefilled |
| Other at the scripted model | "The model answered, but couldn't read a test post. Try another model." |
| Telegram empty Connect; Discord webhook empty and made-up | "Enter the chat ID and the bot token to connect."; "Discord didn't accept the webhook URL. It may have been deleted." |
| Turn Off Alerts | Both alert offers return |
| ⋯ Hide Ideas / Show Ideas / Open Getting Started; four idea cards | Each does what it says |
| Account editor: Where do I find this?, nine examples, Paper/Live, four switches, Remove Account | Each verified; extended hours off turns overnight off |
| Account editor with made-up keys | "Alpaca didn't accept these keys. Check that they are for a paper or live account as chosen." |
| Guru editor: Learn, Replay (no model), Add Example, Skip re-posted calls, Account, Remove Guru | "Choose a model under Interpreter first."; others verified |
| Import Setup… (button and File menu) | Open panel; Cancel returns (import covered by J41) |

### Settings

| Control | Evidence |
|---|---|
| General: App language, Show times in, Choose Another Time Zone…, three switches, Hold my orders | Each saves (`appTimeZone`, `orders.holdSeconds`, …) |
| Appearance: System, Light, Dark | Saves `appearance` |
| Updates: Check for Updates…, automatic switch | Sparkle window with release notes; switch follows the setting (after fix) |
| Engine: Run Self-Test, Stop Engine, Start Engine (page, banner, menu bar) | Captured, Read, Delivered; Stopped; Ready |
| Agent Access: Nothing, Read and pause, Read, pause, and ask | Status Off ↔ Listening; the chosen row reports itself selected |
| Backups: Create Backup…, Restore from Backup… | Save and open panels; Cancel returns (writing covered by J13, J33) |
| Logs: Keep logs for, Storage limit (64 MB–2 GB), Save, Save Log… | "Saved. Applies when the engine next starts."; save panel |
| In-page Back, Close Settings | Back retraces pages and disappears at the start; Close returns where Settings opened |

### Diagnostics

| Control | Evidence |
|---|---|
| All, Captures, Trading, Problems | Each filters; an empty filter says what is missing |
| Search, Refresh, selecting a record | "parsed" → 2 rows; "zzz" → "No records match “zzz”."; fields shown |

### Account page, guru page, post detail (fixture)

| Control | Evidence |
|---|---|
| Positions count | "POSITIONS 5" = 5 rows; In stocks $3,420 = $3,419.86 of rows |
| Position row, lot Sell…, ¼ ½ ¾ All, Cancel | Expands; "0.21 of 0.84 shares, About $39.15"; no engine disables Sell and says why |
| ⋯ Edit in Connections, After a restart, Edit Limits | Opens the account's sheet; Done returns |
| Chart day picker, Done, Draw It Again, Refresh, Activity tab | Each verified; Activity agrees with positions |
| Guru filters All 9 / Traded 5 / Waiting / Not traded 4 | Each count equals its rows |
| Post detail: Technical details, copy Message ID, ✕; guru Edit | ID on the clipboard; closes; editor opens |

### Assistant, menus, menu bar, update banner

| Control | Evidence |
|---|---|
| Suggestion, composer + Send, New Conversation, Close, Open Connections (no model) | Scripted model answered; reset and close verified |
| Go: Find…, Find a Post…, Connections, Getting Started, Diagnostics | Each opens; "sett" + Return opens Settings |
| CopyTrading: About, Check for Updates…, Settings…; Assistant: Ask the Assistant; File: Import Setup… | Each verified |
| Help: Getting Started, Keyboard Shortcuts, Show Tips Again, Report a Problem… | Guide top; shortcuts; message; issues page 200 |
| Every shortcut the guide lists | Bound in code (keystrokes need focus) |
| Menu bar extra: status, Start Engine, Quit | "Engine stopped" and its note; starts the engine; Quit exits and leaves no engine running |
| Update banner: Later, Install Update… | Later puts it away; Install opens Sparkle's window; Remind Me Later withdraws the banner |
| External links (25) | All reachable but Fireworks (fixed); 403s are bot walls, the webhook prefix is not a link |

### 简体中文

Every Settings page, Connections, Getting Started, the tour, Diagnostics, the account page, the sell
sheet, the guru page, and the post detail were rendered in Chinese and read in full. Apart from the
fixes above (#37–#40), every label is translated and every title fits on one line. J44's steps were
run in Chinese.

## Verification

- `swift build` strict (`-strict-concurrency=complete -warnings-as-errors`): clean.
- `swift test`: DesktopCore 26 cases, 18 tests, contracts 30 cases, all passed, including `controls pass`.
- `make lint-swift`: clean. `ruff check`, `ruff format --check`, `ty check` on `app/scripts`: clean.
- `app/scripts/tests`: 105 passed, including the localization catalog checks.
- J43 and J44 were added but not run through the journey runner: it types with real keystrokes
  and brings the app to the front. Each of their steps was run through background accessibility.
