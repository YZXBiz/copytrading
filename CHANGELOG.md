# Changelog

User-visible changes for each preview and release are recorded here. See [release instructions](docs/releases.md) for downloadable artifact details and [validation](docs/validation.md) for current evidence and remaining gates.

## 0.1.0-alpha.3 — developer preview

The engine runs on its own as a server, agent approvals are checked end to end in the real window, and the repository is reorganized for contributors.

### Run the engine without the app

- **`copytrading-server`** runs the trading engine on its own, on macOS or Linux, from a commented `copytrading.toml` (`copytrading-server init`) and keys in environment variables. `check` signs in to Discord, the model, and every account and reads each guru's examples without saving or trading anything; `run` starts copying and stops cleanly on Ctrl-C or SIGTERM. It composes the same engine as the app, so every limit, recovery rule, and record is the same.
- The owner controls a running server with `status`, `entries enable|disable ACCOUNT`, `pause`, `resume`, `proposals`, `approve` (which shows what it does and asks you to type yes), and `reject`. The `copytrading` CLI and MCP server find a running server on their own, at the access set in the file.
- A Docker image (`engine/Dockerfile`) runs the server as a non-root user with its state in a volume. `make check-linux` runs the engine's tests on Linux.

### The app

- Connections closes with **Setup Tips** (设置小贴士), the how-to cards for finding a channel ID, a token, a key, or a Telegram chat.

### For contributors

- The repository's public history starts at 0.1.0-alpha.2. Clone it again if yours was made before October 2, 2026.
- `engine/` is the only Python project: the root `pyproject.toml` and `uv.lock` are gone, and Ruff, Ty, and pytest are configured in `engine/pyproject.toml`. `make dev` syncs `engine/.venv`; `make check-editor` is removed.
- Journey J31 checks agent approval in the real window against Alpaca paper: a request runs only after Approve, exactly once, and a rejected one changes nothing.
- Pull requests are squash-merged, each titled with one plain sentence under 72 characters.

## 0.1.0-alpha.2 — developer preview

A redesigned app around the trader's questions, an in-app assistant, the whole app in English or 简体中文, a guided first run, positions that trace back to the posts that bought them, any model service to read posts, and diagnostics without a separate log server.

### The app

- **Assistant.** ⌘J (or the sparkle in the toolbar) opens a side panel where you ask about your trading in plain words: "Why was the last post skipped?", "How did my gurus do this week?", "What's in my paper account?", and how to set things up. Answers come from your real posts, accounts, and setup, with a quiet line for each thing it looked at, and posts and accounts link to where they live. It pauses copying, or one account's entries, when you ask. Anything that could trade is only a proposal: it appears as a card, and you approve it with Touch ID. It uses the model you chose for reading posts, including a local or custom one, and needs no other key. The conversation lives in memory and is forgotten when you lock or quit.
- The assistant's requests go through the same checks as an outside agent's and appear in Settings → Agent Access, and in the audit trail, as agent requests from the caller "CopyTrading Assistant". When it proposes something, the approval sheet is headed "The assistant is asking for approval".
- The assistant answers in the language you ask in (English or 简体中文), knows your gurus by name, and says plainly when something it tried was refused.
- **简体中文.** Settings → General → Language switches the whole app between English and 简体中文 and remembers the choice. Trading words read the way traders say them: 信号源 for gurus, AI 模型 for the interpreter, 盘前盘后 and 夜盘 for extended and overnight sessions.
- Every account limit, timing value, and behavior switch in the account editor says in one plain line what it does, in both languages.
- **Today** shows the day's change across accounts, the broker's equity curve, what happened to each post, and how close each account is to its limits. The chart draws a smooth line on chart paper across the hours with data, labelled from the opening bell. It also offers a range (1D, 1W, 1M, 3M, 1Y) or any past day, reads the value, change, and time under the pointer, and measures between two points when you drag. It ends at the live broker balance.
- **Activity** reads each post as what it asked for ("Buy NVDA at $121.40"), with each account's orders and fills. Technical details show the post's trip (Captured → Read → Delivered), who read it, any edits, and the Discord IDs with copy buttons.
- **People** shows each guru as a card in their own color, with their latest call, a trail of how their recent posts went, their record, and the accounts that copy them.
- **Accounts** shows the broker's balance, cash, buying power, limits, and holdings. Each position opens into its **lots**: one per copied buy, naming the guru, the post, and when it bought. **Sell…** sells a lot after showing the live quote and the order: a market order in regular hours, a limit at the quote outside them. Live accounts ask for Touch ID; paper accounts ask for a plain confirmation. A retried sale is never sent twice.
- **Diagnostics** reads the engine's private log directly: search it, filter by captures, trading, or problems, and open any record to see its payload with keys removed, even while the engine is stopped.
- Every screen with nothing to show yet draws what will appear there and how to get it set up, instead of an empty pane.
- Titles are set in New York. The sidebar shows the app's icon and the setup's state. The toolbar always shows Paper or Live, how fresh the numbers are (⌘R refreshes), and Start / Pause Copying. ⌘1–⌘6 jump between screens, and the menu bar shows today's change.

### First run and setup

- **Getting Started** opens until a setup is saved. It is a guide with a five-step checklist that ticks itself as you fill things in, steps for finding every key and ID (Discord channel and token, your model service's key, Alpaca paper keys, Telegram), pictures of each screen, the safety controls, and every shortcut. The sidebar shows its progress ring.
- Setup is split by subject. **Connections** holds Discord, the interpreter, and alerts, each edited in a panel that opens from its card. Gurus are added in **People** and broker accounts in **Accounts**. Unsaved gurus and accounts show as their own cards, and a bar at the bottom checks the changes (**Check Setup**) and starts copying (**Start Copying**) from any of those screens.
- A failed check keeps every key you typed. Its results open in a Setup Check sheet, and editing anything after a check discards it. Starting copying takes you to Today, which says who is copied into which accounts and reminds you that new accounts start with entries off.
- **Learn from Channel** reads a guru's recent posts and drafts a playbook, prefix, and examples for you to edit. Ticker aliases and "unsupported convention" are gone; setups saved by earlier versions must be entered again.
- "Where do I find this?" beside every key and ID shows the same steps as the guide. Tips point out Pause Copying, measuring on the chart, and Needs Review once each, after setup. The Help menu opens the guide, its shortcuts, Show Tips Again, and Report a Problem.
- A README in 简体中文 ([README.zh-CN.md](README.zh-CN.md)) with screenshots of the Chinese app.
- Setup keeps what you typed when you switch screens; locking still wipes it, keys included. Messages use plain words, with no "candidate", "revision", or "route", and a guru is named rather than given an ID.

- **Choose any model to read posts.** Besides Anthropic and DeepSeek: OpenAI, Google Gemini, OpenRouter, Groq, xAI, Mistral, Together AI, Fireworks AI, Cerebras, Moonshot AI (Kimi), Ollama on this Mac, or any OpenAI-compatible address. A custom address must use https unless the model runs on this Mac, and only a local or custom model may go without a key.

### Settings

- **Settings** (⌘, or the gear) is a page with its own sidebar:
  - **General**: turn off Ask for Touch ID (confirmed once with Touch ID; Lock still locks), and start copying automatically for paper-only setups. Automatic starts retry a failed connection check a few times after launch.
  - **Appearance**: System, Light, or Dark for the whole app.
  - **Updates**.
  - **Engine**: the engine's state, the way a post travels, and the self-test.
  - **Agent Access**.
  - **Backups**: the data folder, backup, and restore.
  - **Logs**: log health, how many days to keep and how much disk to use, and saving the log for support.

### Engine and trading

- Diagnostics no longer run a separate log server. The engine keeps a private log file on this Mac. The app is about two-thirds smaller, starts faster, and no longer creates a disk image, a local certificate, or a diagnostics password.
- Each copied buy is recorded as a lot under the post that bought it. Selling a lot goes through the same guarded submit path as other manual orders and is recorded under that post.
- The engine reports each account's balance as the broker values it, each order's average fill price, each post's understood instructions, and the day or month equity curve.
- Exits copy outside regular hours when the account allows extended or overnight trading. They sell with a limit no further below the guru's price than entries may buy above it.
- Fixed:
  - A post whose reading fails the evidence checks (or arrives too late, or carries images) goes to review without stopping copying.
  - A guru route without an author filter now hands its posts to the accounts.
  - "Sold the whole lot" posts with no amount are read as a close, not as a reduce that went to review.
  - "6分之一" (1/6) is no longer sent to review because of how the fraction was written.
  - "出…剩下一半" (sell the remaining half) is recognized as a close.
  - After a restart, an account waiting for a manual resume shows Resume Entries.
- Fixed: a model on this Mac (Ollama) or a custom OpenAI-compatible address can learn a playbook and review examples without a key.
- Removing an old setup revision blanks its saved keys before deleting them.
- The engine no longer records an empty diagnostics operation for every source poll.
- **Faster from post to order.** A captured post wakes the engine at once instead of on the next half-second tick, every account receives it side by side, a decision's independent broker reads go out together (about 2.3 s down to 0.7 s on a real post), and Alpaca's live order updates reconcile an account as soon as a fill lands. Every check still runs against the same data, in the same order; the 2-second broker check stays as the backup.

### Agent control (CLI and MCP)

- `copytrading accounts` and the `list_accounts` tool list each position's lots: the post that bought it (`source_id`, `guru_id`, `posted_at`, and its text as `untrusted_source_text`), when, how many shares remain, and the average price. Selling a lot stays with the owner in Accounts.
- Dollar amounts in the CLI's text output show cents ($25.10).

### Testing

- Journey J30 drives the real panel against a scripted local OpenAI-compatible model: a status check, an answer, and Esc to close.
- A scenario suite drives the whole engine with a mock guru's posts against a broker that keeps real books. It covers spending all the cash (the next buy never reaches the broker), selling and buying again, trims and closes by lot, shares held outside the app, every limit, paused entries, late posts, resting limits, reposts, several accounts, fraction sizing, and selling lots from Accounts.

- `make coverage` measures engine line and branch coverage (83% when alpha.2 shipped) and fails under 80%. Tests now cover the Telegram notifier (it never lets the bot token escape in an error), Discord channel history, and the notification and queue value types.
- A catalog test keeps the English and 简体中文 files in step.

### Building

- Local builds sign with the owner's Apple Development identity when there is one, so a rebuild keeps its Keychain access.

## 0.1.0-alpha.1 — developer preview

- Initial Apple Silicon macOS app package with a bundled local Python engine.
- Discord stock-alert capture, model-assisted parsing and review, and controlled Alpaca execution workflows.
- Local SQLite persistence, diagnostics, restore, and user-invoked update workflows.
- Unsigned build for macOS 26 or later. This preview is not qualified for production or live trading.
