# InfoPanels Discord Bot

A Discord bot that generates InfoPanels import strings from natural-language descriptions using Claude Sonnet 4.6 via the Anthropic API.

## Prerequisites

- Node.js 18 or later
- A Discord bot token ([Discord Developer Portal](https://discord.com/developers/applications))
- An Anthropic API key ([Anthropic Console](https://console.anthropic.com/))

## Setup

1. Install dependencies:

```bash
cd discord-bot
npm install
```

2. Copy the environment template and fill in your credentials:

```bash
cp .env.example .env
```

Edit `.env` and set:
- `DISCORD_BOT_TOKEN` — your Discord bot token
- `ANTHROPIC_API_KEY` — your Anthropic API key

3. In the Discord Developer Portal, enable the following bot intents:
   - **Message Content Intent** (required to read message text)
   - **Server Members Intent** (optional)

4. Invite the bot to your server using an OAuth2 URL with the `bot` scope and `Send Messages` + `Read Message History` permissions.

## Running

```bash
npm start
```

The bot logs in and listens for:
- **Direct messages** — send any message describing the panel you want
- **Mentions** — mention the bot in a server channel with your panel description

## Usage Examples

> "show my haste and crit in a vertical list"

> "create a horizontal panel with my character name, level, and spec"

> "show companion level and season rank, only visible inside delves"

The bot responds with a code block containing the import string. In WoW, type `/ip import` and paste the string.

## How It Works

The bot sends your description to Claude Sonnet 4.6 with a system prompt containing the full InfoPanels profile string schema, all available data sources, layout options, and visibility conditions. Claude generates a valid Lua table definition, serializes it, and returns a base64-encoded import string prefixed with `IP1:`.

## Error Handling

- **Timeout**: Requests that take longer than 30 seconds return a friendly timeout message.
- **Rate limiting**: The bot informs users when the Anthropic API rate limit is hit.
- **Invalid output**: If Claude's response does not contain a valid `IP1:` string, the raw text response is forwarded (usually a clarification question).
