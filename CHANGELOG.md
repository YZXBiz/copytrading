# Changelog

User-visible changes for each release are recorded here. Every GitHub release's notes come from its section. See [releases](docs/releases.md) for how a release is cut and [validation](docs/validation.md) for what is and is not proven.

## Unreleased

Every guru's post is now read into one shape, and plain rules turn it into orders ([ADR-0007](docs/adr/0007-one-reading-contract.md)).

### How a post becomes an order

- **One reading for every guru.** The model reads each post as a trade made, an instruction, a condition, a suggestion, or talk, with each buy and sell's price, size, and the buy a sell refers to, every value in the post's own words. A reading that cites words the post doesn't contain goes back to the model once with the reason.
- **One guru per account.** A guru's full position is its account's maximum per stock, so a 1/6 call buys a sixth of it and a call that names no size buys all of it (or waits, if you choose). The maximum per order trims a buy and says so. Fixed dollars per entry are gone; the app asks you to set up again.
- **How each guru trades.** Set whether a sell refers to the buy price it names (each buy is its own lot) or to the whole position (every buy of a stock is one lot), and how many batches make a full position.
- **Market moved.** If the price has moved more than 5% from the guru's price, up or down, the buy waits for you to decide. You set the percentage per account.
- **Sells are limit orders.** A copied sell is a limit order at all hours, no lower than 1% under the guru's price ("Maximum below signal price", set per account), where it used to sell at market in regular hours. A sell that hasn't filled by the order timeout is cancelled and the shares stay yours.

### Waiting for you

- Conditions, suggestions, ranges, posts with no price, and buys the market has moved away from wait for you, with an alert. **Copy…** opens the call already filled in for you to check, then previews it in each account; **Skip** takes it off your list. A call can be copied until its trading day ends at 20:00 New York time, and only from an account that is still waiting on it, so a copy never doubles an order.

### Activity

- Each post is one card: the post with the words the reader took each value from marked, **Read as** in your language, and **Your account** with what happened and why. Every post ends **Traded**, **Traded smaller** (and by how much), **Waiting for you**, **Skipped** (which limit, with its numbers), or **Ignored**. **Needs Review** is now **Waiting for You**.

### Gurus

- **Try it on recent posts** reads a guru's last 15 posts with the settings you're editing and shows what each would have done, before you switch them on. Nothing is placed.

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
