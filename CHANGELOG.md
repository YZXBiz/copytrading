# Changelog

User-visible changes for each release are recorded here. Every GitHub release's notes come from its section. See [releases](docs/releases.md) for how a release is cut and [validation](docs/validation.md) for what is and is not proven.

## 0.1.0-alpha.9 — developer preview

A new look, accounts and gurus as the app's two places, and copying that keeps going when you trade by hand.

### A calmer, clearer app

- **Accounts and gurus are the sidebar.** Each account is a page: its balance and the day's change, the equity curve, then one band with cash, buying power, today's loss and what is in stocks against their limits, and the caps with **Edit Limits** on one quiet line. Below it, **Positions** and **Activity**; Control-1 and Control-2 switch between them. Each guru is a page too: today's numbers and every post on one timeline, a day at a time, with what each account did.
- **A new look throughout.** Names and headings in a geometric display face, labels in tracked capitals, ink lines on white, and no boxes. Grey rules are gone: sections are set apart by space and their titles, and a text field sits on a dotted line that turns solid while you type. Colour carries meaning only: sage for what went through, blush for what failed, sky for an order still at the broker, butter where your eye should land.
- **A post opens beside the page** from Needs You, Activity, or a position, with the guru's words large, a price ruler for each order, and the post's journey as one line.
- **Positions read like a terminal.** Shares line up on the decimal point, and every row says whose shares they are: "from Zhao", "yours", or both. A lot opens to the post that bought it.
- **A new icon**: a white sheet with an ink ring and a butter disc.

### Always live

- **Accounts stay live while copying is paused.** Balances, positions and the equity curve are read from Alpaca whenever the app is unlocked; copying only decides whether orders go out. The keys stay in memory and are dropped when you lock. An account that hasn't been read yet shows dashes, never $0.
- **Fills announce themselves** with a notification and a sound (Settings → General → While Copying).
- **The menu bar shows today's change** and how many calls wait for you.
- **A recap after time away**: the first open after six hours shows what filled, how each account moved, and what waits.
- **Each guru's page says what you hold from their calls** and how it stands.

### Room to change your mind

- **A sale or a confirmed copy waits a few seconds with Undo** before it leaves for Alpaca (Off, 5 s or 10 s in Settings). A skipped call can be brought back for ten seconds, also with ⌘Z.
- **⌘K (or ⌘F) opens a palette** that finds any account, guru or page, a few safe actions, and posts by their words.
- **The window reopens where you left it**, on the same page and tab.

### Copying

- **Shares you buy or sell in Alpaca yourself sync on their own** ([ADR-0011](docs/adr/0011-holdings-sync-from-filled-counts.md)). Copied shares still held stay copied and the rest count as yours; a shortfall takes the oldest copied buys first. Activity says what happened in a sentence, and copying never stops for it. While an order you placed is still open in that stock, it waits for it.
- **A sell with no price sells at the market**, as a limit 1% under the bid ("sell wmt half"), instead of waiting for you. With no fresh bid it waits and tries again until the post is too old; a vague trim with no size still waits for you.
- **Changed limits reach running copying at once**, the moment the account sheet closes; Edit Limits opens straight on them.
- **Holdings questions read as plain rows** and say when an order placed outside the app has to fill or be cancelled first. Resuming entries says why it can't, in your language.
- **Review and Correct is plain choices**: buy or sell, the stocks you hold, how much, the price, the accounts, and one button that says what it will do.
- **The interpreter writes its summary in the post's language.**

### Setup

- **Import Setup…** (File menu) fills Connections from a key file you choose.
- **A guru's settings show what each call buys** in that account: the full position, a 1/6 and a 1/2 call, and a call with no size.
- **Times read on one clock**, with a time-zone setting, and a newer version is offered in the window.
- **A setup that can't start says why.** If another CopyTrading on this Mac is already copying into the same Alpaca account, Start Copying says so instead of a bare failure, and a first setup no longer mentions a previous one.

## 0.1.0-alpha.8 — developer preview

Changes to your setup apply while copying runs.

- **Apply Changes while copying.** A limit or anything else changed in Connections used to stay "Changed — not saved yet" until you paused copying and started again. While copying runs, Start Copying now reads **Apply Changes**: one press pauses copying for a moment, checks the new setup, and copies with it. Posts that arrive in between are read when copying resumes. Accounts offers Apply Changes beside an edited account. If the check fails, or you close the readings without starting, copying continues with your saved setup and says your changes weren't saved. You stay on the screen where you made the change.
- **A failed check no longer locks Start Copying.** A single "Discord didn't answer in time" used to grey out Start Copying while Discord read Connected. The button now needs only the setup filled in, since it checks every connection again.

## 0.1.0-alpha.7 — developer preview

Setup walks you through itself, the interpreter reads each post knowing what the guru already bought, and four per-guru switches are gone ([ADR-0010](docs/adr/0010-the-reader-reads-rules-pick-shares.md)).

### Setup

- **A first launch walks you through setup.** CopyTrading opens on Connections with a short tour: it points at the next thing to do, from the Discord row to its Channel IDs and token, an AI service and its key, a paper account, a guru, and Start Copying, and moves on by itself as each is done. Inside a connect sheet the field and its hint share one outlined card, so it never covers the sheet's buttons or a failed check. End Tour is remembered; Getting Started's **Show Me Around** starts it again.
- **Getting Started is a guide, not a checklist.** It opens with Show Me Around, then draws how a post becomes a trade, one SOUN call from the guru's post to the sale: click a step for one card on what happens there and what you control, with a link to where you set it. Today and Activity's **Continue Setup** starts the tour.
- **Less work in the background.** The engine heartbeat in Settings pauses while the window is in the background, and animations stop when they have shown their change, instead of running forever.
- **Start Copying in Setup Check starts copying.** It used to check everything again and reopen the same sheet, until you found **These Readings Look Right** above the examples. Pressing Start Copying beside the readings now approves them, and Start Copying on Connections opens them for a look first. Fractions read as 1/6, a sell example no longer warns that nothing is held, and each connection check says what it found in words ("Signed in to Discord", "Alpaca paper account found") instead of the engine's raw IDs. A connect sheet reads **Connect** until its service has connected.
- **No more "Public Discord authorization: Unsupported".** Connection checks showed this row and a "Release gate" warning on every check, though neither ever stopped a start; both are gone.
- **An account left by an older version no longer blocks setup.** Connection checks said "Configuration: Couldn't check this connection" when an older version had left an empty account behind that the app doesn't show; it is now checked and set aside.
- **Claude models connect again.** Connect for Anthropic said "The model answered, but couldn't read a test post" for every Claude model; Sonnet 5.5, Opus 5.5, and Haiku 4.5 now connect and read posts.
- **Another copy of CopyTrading is named.** When an installed copy and another build both run, the second one's engine cannot start; the banner now says so and offers **Quit the Other Copy**, instead of "stopped because of an error".

### How a post becomes an order

- **The interpreter sees the guru's recent calls.** Beside each post it is shown every buy the guru still holds and the last ten closed calls (stock, price, and size only, never old posts), and your own corrections in place of its readings. So "sold half of the 39.5 IREN" sells from that buy, "out of IREN" sells from every IREN buy, and a re-post of a call already copied is recognised.
- **Every buy of a stock joins one position**, which remembers each buy's price. A sell that names a buy price sells from the buys at that price; one that names none sells the same share of every buy. A named price you hold no buy at waits for you.
- **Removed: four switches per guru**: what a sell refers to, buys in batches, the default share, and whether "half" counts from the first buy. Write the guru's habits in the playbook instead ("第二批 means 1/3"; "Sell fractions count from the original buy"); Learn drafts them. A post with no size buys the full position, trimmed by your maximum per order. A batch or a vague trim ("took some off") that the playbook gives no size waits for you. Your saved setup is from an older version, so CopyTrading asks you to set up again.
- **Re-posted calls, read rather than matched.** With Skip re-posted calls on, a call the interpreter reads as restating one of the guru's within the time you set counts once; a restatement after that waits for you, and Activity's "Read as" says "A re-post of an earlier call". Turn the setting off to copy every post.
- **Guru examples can state the price and the buy a sell comes from**, and the check compares them with what the interpreter reads.
- **Copying a call by hand:** a sell may leave "Sells from the buy at" empty to sell from every buy.

## 0.1.0-alpha.6 — developer preview

Every copying rule run against DeepSeek and Alpaca paper, in regular hours and overnight; the ways copying could stop or buy twice are fixed, and skipping re-posted calls is now your choice per guru.

- **A ticker Alpaca does not list no longer stops copying.** A guru's typo or a delisted stock used to take the account offline until you restarted; the call is now skipped as a stock the broker does not support, and the next call trades.
- **A brief Alpaca outage no longer stops copying.** A dropped connection, a rate limit, or an outage on Alpaca's side used to stop the account for good; it now tries again on its own, first after a second and then less often, also while Start Copying connects. Rejected keys still stop it, because only you can fix those.
- **Skip re-posted calls is now a setting for each guru** (Connections → the guru → How they trade). On by default at 10 minutes: the same call again (same stock, price, and size, as the interpreter reads it) within that time counts once, and a repeated sell counts once all day. Choose any time from 1 minute to a day, or turn it off to copy every post.
- **A stock mismatch clears itself.** When shares you traded outside CopyTrading are gone again, the red "ownership mismatch" warning on Accounts now goes away by itself, and the stock is copied again. It used to stay until a restart, and every call for that stock was refused meanwhile.
- **A call you approved is approved once.** An approved call used to stay under Waiting for You until 20:00, and approving it again bought again. It now leaves the list as soon as you approve it, and the engine refuses a second order for the same post and stock while the first is open or filled.
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
