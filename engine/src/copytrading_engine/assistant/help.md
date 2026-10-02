# CopyTrading help

CopyTrading is a Mac app that reads Discord gurus' stock calls and copies them into the owner's
Alpaca accounts. This is the app's own setup help: Getting Started, then one short article for each
"Where do I find this?" link in Connections, People, and Accounts.

## Getting Started

Setup has five steps. The Getting Started guide ticks each one off as it is filled in.

1. **Connect Discord.** Enter the channel IDs your gurus post in, and your Discord token. CopyTrading reads the channels as you, and keeps the token in the Mac's Keychain.
2. **Choose an interpreter.** The interpreter is the AI model that turns each post into an exact order. Pick a service, make an API key, and enter a model name. A model on this Mac (Ollama) or any OpenAI-compatible server may need no key.
3. **Add a broker account.** Orders go to an Alpaca account. Start with an Alpaca paper account: it trades pretend money at real prices.
4. **Pick who to copy.** Add each guru, choose their channel, and learn how they write their calls with Learn from Channel. Choose how much each account puts into one of their calls.
5. **Check and start copying.** Check Setup tests every connection and reads the examples while you watch. Nothing is saved or traded before this. New accounts start with entries off, so nothing is bought until you choose Enable Entries in Accounts.

## Find a channel ID

1. In Discord, open **User Settings › Advanced** and turn on **Developer Mode**.
2. Right-click the channel your guru posts in and choose **Copy Channel ID**.
3. Paste it into **Channel IDs**. Separate several channels with commas.

## Find a guru's user ID

Only needed when several people post in the same channel.

1. With **Developer Mode** on, right-click the guru's name on one of their posts.
2. Choose **Copy User ID** and paste it here.

## Copy your Discord token

CopyTrading reads your gurus' channels as you, with your Discord account's token. It works like a password: anyone who has it can use your account.

1. Open **discord.com/app** in Chrome or Safari and sign in. In Safari, first turn on **Settings › Advanced › Show features for web developers**.
2. Open the developer tools with **⌥⌘I** and choose the **Network** tab.
3. Click any channel, then click a request named **messages** in the list.
4. Under **Request Headers**, copy the value next to **authorization** and paste it into **Discord token**.

Discord's terms don't allow automating personal accounts, and an account can be limited for it. A separate Discord account that only joins your gurus' servers keeps your main account out of it. CopyTrading keeps the token in your Mac's Keychain. Never paste it, or any code someone sends you, anywhere else.

## Get an Anthropic API key

The interpreter is the AI model that reads each post. Anthropic bills your account for what it reads.

1. Sign in at **platform.claude.com** and open **API Keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **claude-sonnet-5-5** under **Model**.

## Get an OpenAI API key

The interpreter is the AI model that reads each post. OpenAI bills your account for what it reads.

1. Sign in at **platform.openai.com** and open **API keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **gpt-5.5-mini** under **Model**.

## Get a Google Gemini API key

The interpreter is the AI model that reads each post. Google Gemini bills your account for what it reads.

1. Sign in at **aistudio.google.com** and open **Get API key**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **gemini-2.5-flash** under **Model**.

## Get a DeepSeek API key

The interpreter is the AI model that reads each post. DeepSeek bills your account for what it reads.

1. Sign in at **platform.deepseek.com** and open **API keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **deepseek-flash** under **Model**.

## Get an OpenRouter API key

OpenRouter reaches hundreds of models from many makers with one key, and bills your account for what they read.

1. Sign in at **openrouter.ai** and open **Keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **anthropic/claude-sonnet-5.5** under **Model**.

## Get a Groq API key

The interpreter is the AI model that reads each post. Groq bills your account for what it reads.

1. Sign in at **console.groq.com** and open **API Keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **llama-3.3-70b-versatile** under **Model**.

## Get an xAI API key

The interpreter is the AI model that reads each post. xAI bills your account for what it reads.

1. Sign in at **console.x.ai** and open **API Keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **grok-4** under **Model**.

## Get a Mistral API key

The interpreter is the AI model that reads each post. Mistral bills your account for what it reads.

1. Sign in at **console.mistral.ai** and open **API Keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **mistral-large-latest** under **Model**.

## Get a Together AI API key

The interpreter is the AI model that reads each post. Together AI bills your account for what it reads.

1. Sign in at **api.together.ai** and open **API Keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **meta-llama/Llama-3.3-70B-Instruct-Turbo** under **Model**.

## Get a Fireworks AI API key

The interpreter is the AI model that reads each post. Fireworks AI bills your account for what it reads.

1. Sign in at **fireworks.ai** and open **API Keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **accounts/fireworks/models/llama-v3p3-70b-instruct** under **Model**.

## Get a Cerebras API key

The interpreter is the AI model that reads each post. Cerebras bills your account for what it reads.

1. Sign in at **cloud.cerebras.ai** and open **API Keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **llama-3.3-70b** under **Model**.

## Get a Moonshot AI (Kimi) API key

The interpreter is the AI model that reads each post. Moonshot AI (Kimi) bills your account for what it reads.

1. Sign in at **platform.moonshot.ai** and open **API Keys**.
2. Create a key, name it CopyTrading, and copy it. Most services show a key only once.
3. Paste it into **API key**, and enter a model name such as **kimi-k2** under **Model**.

## Run a model with Ollama

Ollama runs the model on this Mac, so posts never leave it and nothing is billed. Reading posts well takes a capable model and a fast Mac.

1. Install **Ollama** and open it.
2. In Terminal, run **ollama pull llama3.2**, or pull any model you prefer.
3. Enter that model's name under **Model**. Leave **Base URL** and **API key** empty: CopyTrading finds Ollama at its usual address on this Mac.

## Use any OpenAI-compatible service

Many services and local servers, such as LM Studio, vLLM, and LiteLLM, answer the same way OpenAI does. CopyTrading can read posts through any of them.

1. Find the service's base URL. It usually ends in **/v1**.
2. Enter it under **Base URL**. It must start with **https://**, or **http://** for a server on this Mac.
3. Enter the model's name under **Model**, and a key under **API key** if the service asks for one.

## Get Alpaca paper keys

A paper account trades pretend money at real prices, so you can watch CopyTrading work before any real order. Live keys come from your live account the same way.

1. Sign up or sign in at **alpaca.markets**. Paper trading is free.
2. Make sure the account switcher at the top left shows your **Paper** account.
3. On the home page, find **API Keys** and choose **Generate New Keys**.
4. Copy the **Key** and the **Secret** into this account. The secret is shown only once.

## Get Telegram alerts

1. In Telegram, message **@BotFather**, send **/newbot**, and follow its steps.
2. Copy the token it gives you into **Bot token**.
3. Send your new bot any message, so it's allowed to message you back.
4. Message **@userinfobot** to get your chat ID, and paste it into **Chat ID**.

## Add a guru

1. In **People**, choose **Add Guru** and give them a name.
2. Pick the channel they post in, then choose **Learn from Channel**. CopyTrading reads their recent posts and drafts how they write buys, sells, and tickers.
3. Read the playbook and fix anything that's off. Under **Copies into**, choose how much each account puts into one of their calls.

## Check, then start

1. Choose **Check Setup**. CopyTrading signs in to Discord, your interpreter, and Alpaca, and reads each example the way it will read real posts.
2. Look over the results. Fix anything marked, then check again.
3. Choose **Start Copying**. New accounts start with entries off, so nothing is bought until you choose **Enable Entries** in **Accounts**.
