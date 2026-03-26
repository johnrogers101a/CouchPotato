// InfoPanels Discord Bot
// Generates InfoPanels import strings from natural-language panel descriptions
// using Claude Sonnet 4.6 via the Anthropic API.
//
// Usage: Mention the bot or DM it with a description of what panel you want.
// Example: "show my haste and crit in a vertical list that only appears in dungeons"

require('dotenv').config();
const { Client, GatewayIntentBits, Partials } = require('discord.js');
const Anthropic = require('@anthropic-ai/sdk');

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const DISCORD_TOKEN = process.env.DISCORD_BOT_TOKEN;
const ANTHROPIC_KEY = process.env.ANTHROPIC_API_KEY;
const MODEL = 'claude-sonnet-4-6-20250514';
const MAX_RESPONSE_TIMEOUT = 30000; // 30s

if (!DISCORD_TOKEN) {
  console.error('ERROR: DISCORD_BOT_TOKEN not set. Copy .env.example to .env and fill in your token.');
  process.exit(1);
}
if (!ANTHROPIC_KEY) {
  console.error('ERROR: ANTHROPIC_API_KEY not set. Copy .env.example to .env and fill in your key.');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Anthropic client
// ---------------------------------------------------------------------------
const anthropic = new Anthropic({ apiKey: ANTHROPIC_KEY });

// ---------------------------------------------------------------------------
// System prompt — teaches Claude about the InfoPanels profile string format
// ---------------------------------------------------------------------------
const SYSTEM_PROMPT = `You are an expert on the InfoPanels World of Warcraft addon. Your job is to generate valid InfoPanels import strings based on user descriptions.

## InfoPanels Profile String Format

A profile string has the format: IP1:<base64_encoded_data>

The encoded data is a Lua table serialized as a string with these fields:
- _v (number): Version, always 1
- id (string): Unique panel ID, use "user_" prefix + descriptive name
- title (string): Display name for the panel
- layout (string): "vertical" or "horizontal"
- bindings (table): Array of data source bindings, each with:
  - sourceId (string): Data source identifier
  - label (string): Human-readable label
  - format (string, optional): Printf format for numbers

## Available Data Sources

Player Stats:
- player.strength — Strength rating
- player.agility — Agility rating
- player.stamina — Stamina rating
- player.intellect — Intellect rating
- player.haste — Haste percentage
- player.crit — Critical Strike percentage
- player.mastery — Mastery percentage
- player.versatility — Versatility percentage
- player.health — Current health
- player.healthmax — Max health

Player Info:
- player.name — Character name
- player.level — Character level
- player.class — Character class
- player.spec — Active specialization

Delve Info:
- delve.companion.level — Companion level
- delve.season.rank — Season rank
- delve.season.xp — Season XP (current/max)
- delve.indelve — Whether in a delve (boolean)

## Visibility Conditions

Panels can have visibility conditions:
- { type = "delve_only" } — Only show inside delves
- { type = "always" } — Always visible (default)

## Example

For "show my haste and crit in a vertical list":

Serialized Lua:
{_v=1,id="user_haste_crit",title="Haste & Crit",layout="vertical",bindings={{sourceId="player.haste",label="Haste"},{sourceId="player.crit",label="Crit"}}}

## Instructions

1. Parse the user's description to determine what data they want displayed
2. Select appropriate data sources from the list above
3. Build the Lua table definition
4. Serialize it as a compact Lua table literal (no newlines, minimal whitespace)
5. Base64 encode it with the IP1: prefix
6. Return ONLY the import string, no explanation needed
7. If the user's description is unclear, explain what you need and give an example

## Base64 Encoding

Use standard base64 (A-Z, a-z, 0-9, +, /) with = padding.
The payload is the raw Lua table literal string, prefixed with byte 0x01 (compression marker).

IMPORTANT: Always validate that your output is a properly formatted string starting with "IP1:".`;

// ---------------------------------------------------------------------------
// Discord client
// ---------------------------------------------------------------------------
const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.DirectMessages,
  ],
  partials: [Partials.Channel], // Required for DM support
});

client.once('ready', () => {
  console.log(`InfoPanels Bot logged in as ${client.user.tag}`);
});

client.on('messageCreate', async (message) => {
  // Ignore own messages
  if (message.author.bot) return;

  // Respond to DMs or mentions
  const isDM = !message.guild;
  const isMentioned = message.mentions.has(client.user);

  if (!isDM && !isMentioned) return;

  // Extract the user's request (strip mention)
  let userMessage = message.content;
  if (isMentioned) {
    userMessage = userMessage.replace(/<@!?\d+>/g, '').trim();
  }

  if (!userMessage) {
    await message.reply(
      'Hi! Describe the panel you want and I\'ll generate an InfoPanels import string for you.\n\n' +
      'Example: "show my haste and crit rating in a compact horizontal panel"'
    );
    return;
  }

  // Show typing indicator
  try {
    await message.channel.sendTyping();
  } catch (_) {
    // Ignore typing errors
  }

  try {
    // Call Claude API with timeout
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), MAX_RESPONSE_TIMEOUT);

    const response = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: [{ role: 'user', content: userMessage }],
    });

    clearTimeout(timeout);

    if (!response || !response.content || response.content.length === 0) {
      await message.reply('I had trouble generating that panel. Could you try rephrasing your request?');
      return;
    }

    const text = response.content[0].text;

    // Validate: check if the response contains an IP1: string
    const importMatch = text.match(/IP1:[A-Za-z0-9+/=]+/);
    if (importMatch) {
      // Send just the import string in a code block for easy copying
      await message.reply(
        'Here\'s your InfoPanels import string:\n\n' +
        '```\n' + importMatch[0] + '\n```\n\n' +
        'In WoW, type `/ip import` and paste this string.'
      );
    } else {
      // Claude responded with text (probably asking for clarification)
      // Truncate if too long for Discord
      const reply = text.length > 1900 ? text.substring(0, 1900) + '...' : text;
      await message.reply(reply);
    }
  } catch (error) {
    console.error('Error processing message:', error.message);

    if (error.name === 'AbortError' || error.message?.includes('timeout')) {
      await message.reply(
        'Sorry, the request timed out (30s limit). Try a simpler panel description.'
      );
    } else if (error.status === 429) {
      await message.reply(
        'I\'m being rate-limited. Please wait a moment and try again.'
      );
    } else {
      await message.reply(
        'Something went wrong generating your panel. Please try again in a moment.'
      );
    }
  }
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
client.login(DISCORD_TOKEN).catch((err) => {
  console.error('Failed to log in to Discord:', err.message);
  process.exit(1);
});
