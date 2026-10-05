# Changelog

User-visible changes for each release are recorded here. Every GitHub release's notes come from its section. See [releases](docs/releases.md) for how a release is cut and [validation](docs/validation.md) for what is and is not proven.

## 0.1.0-alpha.2 — developer preview

Setting up is now one page, top to bottom, and every connection is checked the moment you add it.

### Setup

- **Connections is the one place to set up**, in five numbered steps: Discord, the interpreter, broker accounts, gurus, and alerts (optional). Each number turns into a green check when its step is done. People and Accounts show what is saved and point back to Connections.
- **Connect checks the service there and then.** A row reads **Connected** once Discord, the model, Alpaca, or the alert channel answers. When one doesn't, its sheet stays open and says what to fix in plain words: a rejected key, a channel your account can't read, a server that isn't running.
- **A mistyped model name is caught** ("DeepSeek has no model called “dpeeseek-flash”") with a one-click **Use deepseek-flash**. Picking a service suggests a model only when you choose it.
- **One Start Copying** at the foot of Connections replaces Check Setup: it says how far the setup has come, checks everything, then saves and starts.
- **A connect sheet for each service**, with its logo, what it is for, a link to where its key lives, and step-by-step help. Every service in Connections shows its logo.
- **Account limits have an example behind each one**, and live accounts show where to get live keys. The broker poll interval is no longer a setting.
- Market hours are shown in New York time and your own.

### Alerts and safety

- **Alerts can go to a Discord channel** through a webhook, as well as to Telegram. Mentions in alerts never ping anyone.
- **Live accounts ask for Touch ID** before copying starts and before entries are turned on.
- "Sell half of what's left" now sells half of what is left, not half of the original position.

### Engine

- **Fills arrive the moment they happen.** While Alpaca's order stream is live and nothing is waiting on a clock, each account checks the broker every 30 seconds instead of every 2. A new call is acted on at once.
- An unreachable model server is reported as unreachable, not as a model that misread a post.

### Look and feel

- Sheets carry serif titles, every switch is one compact size, and empty screens read as phrases.
- The README says up front that CopyTrading is not financial advice.

## 0.1.0-alpha.1 — developer preview

The first developer preview. CopyTrading reads the stock calls traders post on Discord, turns each one into an exact order, checks it against per-account limits, and places it with Alpaca. A native macOS app supervises a local Python engine that owns every decision.

### The app

- **Today** shows the day's change across accounts, the broker's equity curve, what happened to each post, and how close each account is to its limits. The chart draws a smooth line on chart paper across the hours with data, offers a range (1D, 1W, 1M, 3M, 1Y) or any past day, reads the value under the pointer, measures between two points when you drag, and ends at the live broker balance. **By account** compares each account's change on one percent scale.
- **Activity** reads each post as what it asked for ("Buy NVDA at $121.40"), with each account's orders and fills. Technical details show the post's trip (Captured → Read → Delivered), who read it, any edits, and the Discord IDs.
- **People** shows each guru as a card in their own color, with their latest call, a trail of how their recent posts went, their record, and the accounts that copy them.
- **Accounts** shows the broker's balance, cash, buying power, limits, and holdings. Each position opens into its **lots**: one per copied buy, naming the guru, the post, and when it bought. **Sell…** sells a lot after showing the live quote and the order. Live accounts ask for Touch ID, and a retried sale is never sent twice.
- **Assistant.** ⌘J opens a panel where you ask about your trading in plain words: why a post was skipped, how a guru did this week, what an account holds. Answers come from your real posts, accounts, and setup. It pauses copying when you ask; anything that could trade is only a proposal you approve with Touch ID. It uses the model you chose for reading posts and forgets the conversation when you lock or quit.
- **Diagnostics** reads the engine's private log directly: search it, filter by captures, trading, or problems, and open any record with keys removed, even while the engine is stopped.
- **English and 简体中文.** Settings → General → Language switches the whole app, and the assistant answers in the language you ask in.
- The toolbar always shows Paper or Live, how fresh the numbers are (⌘R refreshes), and Start / Pause Copying. ⌘1–⌘6 jump between screens, and the menu bar shows today's change.

### First run and setup

- **Getting Started** is a guide with a five-step checklist that ticks itself as you go, steps for finding every key and ID, pictures of each screen, the safety controls, and every shortcut.
- **Connections** holds Discord, the model that reads posts, and Telegram alerts, closing with **Setup Tips**. Gurus are added in **People** and broker accounts in **Accounts**. **Check Setup** tests the real services before **Start Copying** saves anything, and a failed check keeps everything you typed.
- **Learn from Channel** reads a guru's recent posts and drafts a playbook and examples for you to edit.
- **Any model service** reads posts: Anthropic, OpenAI, Google Gemini, DeepSeek, OpenRouter, Groq, xAI, Mistral, Together AI, Fireworks AI, Cerebras, Moonshot AI (Kimi), Ollama on this Mac, or any OpenAI-compatible address (https unless it runs on this Mac).
- New accounts start with entries off. Keys live in the macOS Keychain, and locking wipes anything typed but not saved.

### Engine and trading

- Every ticker, price, and fraction must appear in the post itself, so a model cannot invent a number. A post that fails those checks, arrives too late, or carries images goes to review without stopping copying.
- Daily loss, per-order, per-symbol, and total exposure limits are checked on every order. Each guru-to-account link has its own sizing: fixed dollars per entry, or a share of a full-position budget.
- Accounts take the same post side by side. Decisions and orders are stored durably in SQLite and reconciled with the broker after a crash or sleep, so a signal that expires while the app is closed never becomes a late order. Alpaca's live order updates reconcile an account as soon as a fill lands.
- Exits copy outside regular hours when the account allows extended or overnight trading.

### Run the engine without the app

- **`copytrading-server`** runs the same engine on macOS or Linux from a commented `copytrading.toml` and keys in environment variables. `check` tests every service without trading; `run` starts copying and stops cleanly on Ctrl-C or SIGTERM. A Docker image is included.

### Command line and agents

- The `copytrading` CLI and MCP server let you, a script, or a coding agent read the running app and pause it. Anything that could trade becomes a proposal the owner approves with Touch ID, and every request is written to an audit log.
