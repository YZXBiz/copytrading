# Changelog

User-visible changes for each release are recorded here. Every GitHub release's notes come from its section. See [releases](docs/releases.md) for how a release is cut and [validation](docs/validation.md) for what is and is not proven.

## Unreleased

Every copying rule run against DeepSeek and Alpaca paper, and three ways copying could stop now fixed.

- **A ticker Alpaca does not list no longer stops copying.** A guru's typo or a delisted stock used to take the account offline until you restarted; the call is now skipped as a stock the broker does not support, and the next call trades.
- **A brief Alpaca outage no longer stops copying.** A dropped connection, a rate limit, or an outage on Alpaca's side used to stop the account for good; it now tries again on its own, first after a second and then less often, also while Start Copying connects. Rejected keys still stop it, because only you can fix those.
- **An order you placed on Alpaca yourself now says so.** The first time an account connects, CopyTrading records what it already holds, so an open order placed outside the app must be cancelled or filled first. Accounts and Start Copying now say "Cancel the orders open at Alpaca first" instead of "The account could not be reached".

## 0.1.0-alpha.5 — developer preview

The first release delivered through Check for Updates…, to confirm that updating from 0.1.0-alpha.4 works end to end. The app is otherwise unchanged.

## 0.1.0-alpha.4 — developer preview

Every button tested against the real app and Alpaca paper, and the ones that did not work now do.

- **Selling a lot works while the market is open.** Accounts → Sell… used to refuse every sale during market hours, because prices moved between Review Sale and Sell. Price movement no longer blocks it; your limits are still checked when you press Sell.
- **Ask me before sending orders works.** Approve… on a waiting call opens the call already filled in and sends it after Preview and Confirm; before, approving always failed. Review and Correct works for every post, not only the first one captured.
- **Backups and restore work for accounts connected to Alpaca.** Create Backup…, Restore from Backup…, and Restore This Backup all failed once an account had connected; they now back up and restore it, and messages say what happened in plain words.
- **"After a restart: Wait for me / Carry on by itself"** replaces "Recovery: Manual / Automatic" on each account.
- **"In stocks"** replaces "Copied exposure": the number includes shares you bought yourself, as the account's limit always did.
- **Switches have names for VoiceOver** in the account, guru, and review sheets, instead of "1, checkbox".
- **Updates come through Sparkle.** Check for Updates… (in the CopyTrading menu and Settings → Updates) shows what's new, downloads the release, checks its signature, and installs when you say so; the app also checks once a day, which you can turn off. Settings shows the full version, such as 0.1.0-alpha.4. Copies from before this release update once by hand ([ADR-0009](docs/adr/0009-updates-with-sparkle.md)).
- **A correction that cannot be recorded no longer stops the engine**; you see why instead ("Start copying first…" when copying is paused).

## 0.1.0-alpha.3 — developer preview

Simpler setup, a Mac that stays awake while copying, and a guide that follows one post from Discord to your account.

- **Getting Started follows a post from start to finish:** a guru posts, the AI reads it, your limits check it, the order goes to Alpaca, you see what happened, and the guru sells. Each step says what you control and what to keep in mind, then "Before you go" lists what to know first. Setup steps open their help only when you click them.
- **Keep this Mac awake while copying** (Settings → General, on by default). While copying is on, CopyTrading keeps the Mac from going to sleep on its own, so no post is missed; the screen can still turn off and lock. Closing a MacBook's lid still puts it to sleep unless it's plugged in with a display connected.
- **Removed: the guru's message prefix.** Each channel carries one guru, so every post in it is read and a guru no longer needs a prefix; chatter is still read as talk and ignored. Learn no longer drafts one.
- **Removed: Market move allowed.** A buy is no longer held when the price has moved away from the guru's price; Maximum above signal price still caps what you pay. Your saved setup is from an older version, so CopyTrading asks you to set up again.

## 0.1.0-alpha.2 — developer preview

Every guru's post is now read into one shape and plain rules turn it into orders ([ADR-0007](docs/adr/0007-one-reading-contract.md)), setup is one page that checks each connection as you add it, and an account can ask you to approve every order before it is sent ([ADR-0008](docs/adr/0008-optional-order-approval.md)).

### Setup

- **Connections is the one place to set up**, in five numbered steps: Discord, the interpreter, broker accounts, gurus, and alerts (optional). Each number turns into a green check when its step is done. People and Accounts show what is saved and point back to Connections.
- **Connect checks the service there and then.** A row reads **Connected** once Discord, the model, Alpaca, or the alert channel answers. When one doesn't, its sheet stays open and says what to fix in plain words: a rejected key, a channel your account can't read, a server that isn't running.
- **A mistyped model name is caught** ("DeepSeek has no model called “dpeeseek-flash”") with a one-click **Use deepseek-flash**. Picking a service suggests a model only when you choose it.
- **One Start Copying** at the foot of Connections replaces Check Setup: it says how far the setup has come, checks everything, then saves and starts.
- **A connect sheet for each service**, with its logo, what it is for, a link to where its key lives, and step-by-step help. Every service in Connections shows its logo.
- **Account limits have an example behind each one**, and live accounts show where to get live keys. The broker poll interval is no longer a setting.
- Market hours are shown in New York time and your own.

### How a post becomes an order

- **One reading for every guru.** The model reads each post as a trade made, an instruction, a condition, a suggestion, or talk, with each buy and sell's price, size, and the buy a sell refers to, every value in the post's own words. A reading that cites words the post doesn't contain goes back to the model once with the reason.
- **One guru per account.** A guru's full position is its account's maximum per stock, so a 1/6 call buys a sixth of it and a call that names no size buys all of it (or waits, if you choose). The maximum per order trims a buy and says so. Fixed dollars per entry are gone; the app asks you to set up again.
- **How each guru trades.** Set whether a sell refers to the buy price it names (each buy is its own lot) or to the whole position (every buy of a stock is one lot), and how many batches make a full position.
- **Market moved.** If the price has moved more than 5% from the guru's price, up or down, the buy waits for you to decide. You set the percentage per account.
- **Sells are limit orders.** A copied sell is a limit order at all hours, no lower than 1% under the guru's price ("Maximum below signal price", set per account), where it used to sell at market in regular hours. A sell that hasn't filled by the order timeout is cancelled and the shares stay yours.

### Ask me before orders are sent

- **Optional, per account, off by default.** "Ask me before sending orders" (in an account's Behavior settings, paper or live) holds every order the account would have sent. It waits in Activity as "Waiting for your approval"; **Approve…** previews it fresh and sends it after Touch ID, and **Skip** drops it. A held call expires when its trading day ends ([ADR-0008](docs/adr/0008-optional-order-approval.md)).
- Sending an order by hand into a live account, or selling a lot from Accounts, asks for Touch ID. Paper accounts ask only when they have asked to approve orders.

### Waiting for you

- Conditions, suggestions, ranges, posts with no price, and buys the market has moved away from wait for you, with an alert. **Copy…** opens the call already filled in for you to check, then previews it in each account; **Skip** takes it off your list. A call can be copied until its trading day ends at 20:00 New York time, and only from an account that is still waiting on it, so a copy never doubles an order.

### Activity

- Each post is one card: the post with the words the reader took each value from marked, **Read as** in your language, and **Your account** with what happened and why. Every post ends **Traded**, **Traded smaller** (and by how much), **Waiting for you**, **Skipped** (which limit, with its numbers), or **Ignored**. **Needs Review** is now **Waiting for You**.

### Gurus

- **Try it on recent posts** reads a guru's last 15 posts with the settings you're editing and shows what each would have done, before you switch them on. Nothing is placed.

### Alerts and safety

- **Alerts can go to a Discord channel** through a webhook, as well as to Telegram. Mentions in alerts never ping anyone.
- **Live accounts ask for Touch ID** before copying starts and before entries are turned on.
- "Sell half of what's left" now sells half of what is left, not half of the original position.

### Engine

- **Fills arrive the moment they happen.** While Alpaca's order stream is live and nothing is waiting on a clock, each account checks the broker every 30 seconds instead of every 2. A new call is acted on at once.
- **Buys at the guru's same price are one position.** Two buys of a stock at one price join one lot, so a later "sell half of that lot" sells half of both instead of being skipped.
- **Prices written with a Chinese full stop are read.** A call like `386.2出一半381。3的gld` was held for review; it now trades.
- **Quotes work, including overnight.** Every quote failed to decode, so orders recorded none and manual sales had no price; overnight they now come from Alpaca's overnight venue instead of the last close.
- An unreachable model server is reported as unreachable, not as a model that misread a post.

### Look and feel

- Sheets carry serif titles, every switch is one compact size, and empty screens read as phrases.
- The README says up front that CopyTrading is not financial advice.
- Limits, reasons and messages are written in short plain sentences, in English and 简体中文, and the "You're copying" icon ripples a few times and rests instead of animating forever.


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
