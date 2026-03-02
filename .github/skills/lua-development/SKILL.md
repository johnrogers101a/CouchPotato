---
name: lua-development
description: |
  Best practices, syntax reference, and patterns for building World of Warcraft addons in Lua.
  Use this skill when asked to create, modify, debug, or review WoW addon code, TOC files,
  SavedVariables, UI frames, event handlers, or Ace3-based addon architecture.
license: MIT
status: active
version: 3.0.0
---

# WoW Addon Development in Lua

Reference skill for building World of Warcraft addons using the Lua scripting API. Covers file structure, syntax, events, UI frames, persistence, performance, testing, API discovery, and publishing.

> **Current as of 2026** — WoW Midnight expansion, Patch 12.0.1, Interface `120001`.

---

## Sources & Official Documentation

| # | Source | URL |
|---|--------|-----|
| 1 | **Wowpedia: World of Warcraft API** (primary API reference) | https://wowpedia.fandom.com/wiki/World_of_Warcraft_API |
| 2 | **Wowpedia: Create a WoW AddOn in 15 Minutes** | https://wowpedia.fandom.com/wiki/Create_a_WoW_AddOn_in_15_Minutes |
| 3 | **Wowpedia: TOC Format** | https://wowpedia.fandom.com/wiki/TOC_format |
| 4 | **Wowpedia: Saving Variables Between Sessions** | https://wowpedia.fandom.com/wiki/Saving_variables_between_game_sessions |
| 5 | **Wowpedia: SavedVariables** | https://wowpedia.fandom.com/wiki/SavedVariables |
| 6 | **Wowpedia: Interface Customization** | https://wowpedia.fandom.com/wiki/Wowpedia:Interface_customization |
| 7 | **Warcraft Wiki: TOC Format** (canonical, actively maintained) | https://warcraft.wiki.gg/wiki/TOC_format |
| 8 | **WoWWiki: Getting Started with Writing AddOns** | https://wowwiki-archive.fandom.com/wiki/Getting_started_with_writing_AddOns |
| 9 | **WowAce: Ace3 Getting Started Guide** | https://www.wowace.com/projects/ace3/pages/getting-started |
| 10 | **Wowhead: Comprehensive Beginner's Guide for WoW Addon Coding in Lua** | https://www.wowhead.com/guide/comprehensive-beginners-guide-for-wow-addon-coding-in-lua-5338 |
| 11 | **Blizzard: Official WoW Web API Docs (GitHub)** | https://github.com/Blizzard/api-wow-docs |
| 12 | **Blizzard Developer Portal: World of Warcraft APIs** | https://develop.battle.net/documentation/world-of-warcraft |
| 13 | **AddOn Studio: UI XML Tutorial** | https://addonstudio.org/wiki/WoW:UI_XML_tutorial |

> **Note:** The Blizzard Developer Portal (sources 11–12) covers the *web/REST API* for external sites. The *in-game Lua API* is documented on Wowpedia (source 1) and Warcraft Wiki (source 7). | https://github.com/lunarmodules/busted |
| 15 | **LuaUnit Documentation** | https://luaunit.readthedocs.io/ |
| 16 | **DragonToast — real-world CI/test example (2026)** | https://github.com/DragonAddons/DragonToast |
| 17 | **Lua Busted GitHub Action** | https://github.com/marketplace/actions/lua-busted |
| 18 | **Warcraft Wiki: Alphabetic API Index** | https://warcraft.wiki.gg/wiki/World_of_Warcraft_API/Alphabetic |
| 19 | **Warcraft Wiki: API Namespaces Category** | https://warcraft.wiki.gg/wiki/Category:API_namespaces |
| 20 | **Warcraft Wiki: Widget API** | https://warcraft.wiki.gg/wiki/Widget_API |
| 21 | **Warcraft Wiki: Events Index** | https://warcraft.wiki.gg/wiki/Events |
| 22 | **Warcraft Wiki: Patch 12.0.0 API Changes** | https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes |
| 23 | **ApiExplorer In-Game API Browser** | https://www.curseforge.com/wow/addons/apiexplorer |
| 24 | **Gethe's WoW UI Source Mirror** | https://github.com/Gethe/wow-ui-source |
| 25 | **Ketho BlizzardInterfaceResources (IDE stubs)** | https://github.com/Ketho/BlizzardInterfaceResources |
| 26 | **VS Code WoW API Extension** | https://marketplace.visualstudio.com/items?itemName=ketho.wow-api |

---

## Addon File Structure

```
Interface/AddOns/
└── MyAddon/
    ├── MyAddon.toc        # Required: manifest / metadata
    ├── MyAddon.lua        # Main Lua entry point
    ├── Core.lua           # Optional: additional modules
    ├── UI.xml             # Optional: frame/widget definitions
    └── libs/              # Optional: embedded libraries (Ace3, etc.)
        └── AceAddon-3.0/
```

The folder name, `.toc` filename, and `## Title` tag **must all match** for WoW to load the addon.

---

## TOC File Format

Source: [Wowpedia TOC Format](https://wowpedia.fandom.com/wiki/TOC_format) · [Warcraft Wiki TOC Format](https://warcraft.wiki.gg/wiki/TOC_format)

```
## Interface: 120001
## Title: My Addon
## Notes: A helpful description of what this addon does.
## Author: YourName
## Version: 1.0.0
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB

libs\LibStub\LibStub.lua
libs\AceAddon-3.0\AceAddon-3.0.lua
Core.lua
UI.xml
```

**Key tags:**

| Tag | Purpose |
|-----|---------|
| `## Interface` | WoW client build number (e.g. `110107` for 11.1.7). Run `/dump select(4, GetBuildInfo())` in-game to find the current value. |
| `## SavedVariables` | Account-wide persistent globals. |
| `## SavedVariablesPerCharacter` | Per-character persistent globals. |
| `## Dependencies` | Comma-separated list of addons that must load first. |
| `## OptionalDeps` | Soft dependencies (loaded first if present). |

**Multi-flavor TOC** (Retail vs Classic): Name separate TOC files `MyAddon_Mainline.toc`, `MyAddon_Wrath.toc`, etc. WoW will pick the correct one automatically.

---

## Lua Syntax Essentials for WoW

WoW uses Lua 5.1 with a sandboxed subset of the standard library. Some standard Lua functions (`io`, `os`, `debug`, etc.) are **not available**.

### Variables & Scoping

```lua
-- Always prefer locals for performance — global access is ~30% slower
local myVar = "hello"
local MAX_RETRIES = 5

-- Namespace your addon to avoid global pollution
local MyAddon = {}
_G["MyAddon"] = MyAddon   -- expose globally only what's needed
```

### Tables (the core data structure)

```lua
-- Array-style
local items = { "sword", "shield", "potion" }

-- Dictionary-style
local player = {
    name = "Arthas",
    level = 60,
    class = "PALADIN",
}

-- Nested
local config = {
    display = { scale = 1.0, alpha = 0.8 },
    behavior = { autoHide = true },
}

-- Iteration
for i, item in ipairs(items) do
    print(i, item)  -- ordered
end

for key, value in pairs(player) do
    print(key, value)  -- unordered
end
```

### Functions

```lua
-- Standard function
local function greet(name)
    return "Hello, " .. name
end

-- Method syntax (colon = implicit self parameter)
function MyAddon:OnEnable()
    print("Addon enabled for: " .. UnitName("player"))
end

-- Varargs
local function sum(...)
    local total = 0
    for _, v in ipairs({...}) do total = total + v end
    return total
end
```

### String Operations

```lua
local name = UnitName("player")
local msg = string.format("Player: %s, Level: %d", name, UnitLevel("player"))

-- WoW color codes (hex AARRGGBB)
local red = "|cFFFF0000Red Text|r"
local gold = "|cFFFFD100" .. name .. "|r"

-- Pattern matching (Lua regex subset)
local realm = GetRealmName():gsub("%s+", "-"):lower()
```

---

## Event System

Source: [Wowpedia WoW API](https://wowpedia.fandom.com/wiki/World_of_Warcraft_API) · [WoWWiki Getting Started](https://wowwiki-archive.fandom.com/wiki/Getting_started_with_writing_AddOns)

### Basic Event Registration

```lua
local frame = CreateFrame("Frame")

-- Register one or more events
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "MyAddon" then
            MyAddon:Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        MyAddon:OnPlayerLogin()
    elseif event == "PLAYER_LOGOUT" then
        MyAddon:SaveData()
    end
end)
```

### Critical Lifecycle Events

| Event | When it fires | Use for |
|-------|--------------|---------|
| `ADDON_LOADED` | When your addon's saved vars are ready | Initialize SavedVariables, defaults |
| `PLAYER_LOGIN` | After all addons loaded, player in world | Final UI setup, first-run logic |
| `PLAYER_ENTERING_WORLD` | On login AND zone change | Zone-sensitive UI updates |
| `PLAYER_LOGOUT` | Before the client writes SavedVars | Last-minute data cleanup |
| `COMBAT_LOG_EVENT_UNFILTERED` | Every combat log entry | Damage/heal tracking (use `CombatLogGetCurrentEventInfo()`) |
| `BAG_UPDATE` | Bag contents changed | Inventory addons |

> ⚠️ **Never initialize SavedVariables at the top level of a Lua file.** The globals aren't populated until `ADDON_LOADED` fires for your addon.

### Unregistering Events

```lua
-- Unregister when no longer needed to avoid wasted CPU
frame:UnregisterEvent("PLAYER_LOGIN")
frame:UnregisterAllEvents()
```

---

## UI Frames & Widgets

Source: [AddOn Studio UI XML Tutorial](https://addonstudio.org/wiki/WoW:UI_XML_tutorial) · [Wowpedia Interface Customization](https://wowpedia.fandom.com/wiki/Wowpedia:Interface_customization)

### Creating a Frame in Lua

```lua
local f = CreateFrame("Frame", "MyAddonFrame", UIParent, "BasicFrameTemplateWithInset")
f:SetSize(300, 200)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)

-- Title text
f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 5, 0)
f.title:SetText("My Addon")

-- Close button (provided by BasicFrameTemplateWithInset)
f.CloseButton:SetScript("OnClick", function() f:Hide() end)
```

### Common Widget Types

| Widget | CreateFrame type | Notes |
|--------|-----------------|-------|
| Generic container | `"Frame"` | Base for all UI |
| Clickable button | `"Button"` | Use `SetText`, `SetScript("OnClick")` |
| Text input | `"EditBox"` | Use `GetText()` / `SetText()` |
| Scrollable list | `"ScrollFrame"` | Requires child frame |
| Progress bar | `"StatusBar"` | Use `SetValue`, `SetMinMaxValues` |
| Check box | `"CheckButton"` | Use `GetChecked()` / `SetChecked()` |
| Slider | `"Slider"` | Use `SetMinMaxValues`, `SetValue` |
| Texture/Icon | N/A — use `frame:CreateTexture()` | `SetTexture`, `SetTexCoord` |
| Text label | N/A — use `frame:CreateFontString()` | `SetText`, `SetTextColor` |

### Frame Strata & Level

```lua
f:SetFrameStrata("MEDIUM")  -- BACKGROUND, LOW, MEDIUM, HIGH, DIALOG, FULLSCREEN, TOOLTIP
f:SetFrameLevel(10)          -- higher = drawn on top within same strata
```

---

## SavedVariables (Persistence)

Source: [Wowpedia: SavedVariables](https://wowpedia.fandom.com/wiki/SavedVariables) · [Wowpedia: Saving Variables Between Sessions](https://wowpedia.fandom.com/wiki/Saving_variables_between_game_sessions)

### Declare in TOC

```
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB
```

### Initialize Safely

```lua
local DEFAULTS = {
    showOnLogin = true,
    scale = 1.0,
    messages = {},
}

local function InitDB()
    -- Merge defaults for any missing keys
    if not MyAddonDB then MyAddonDB = {} end
    for k, v in pairs(DEFAULTS) do
        if MyAddonDB[k] == nil then
            MyAddonDB[k] = v
        end
    end
end

-- Must be called in ADDON_LOADED handler, not top-level
frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "MyAddon" then
        InitDB()
    end
end)
```

> Use **AceDB-3.0** for profile support, default values, and per-character vs account-wide separation automatically.

---

## Ace3 Framework

Source: [WowAce: Getting Started](https://www.wowace.com/projects/ace3/pages/getting-started) · [Wowhead Lua Guide](https://www.wowhead.com/guide/comprehensive-beginners-guide-for-wow-addon-coding-in-lua-5338)

Ace3 is the standard modular framework. Embed only what you need via `embeds.xml`.

### Core Addon Skeleton

```lua
-- MyAddon.lua
local MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon",
    "AceConsole-3.0",
    "AceEvent-3.0"
)

local defaults = {
    profile = {
        enabled = true,
        scale = 1.0,
    },
}

function MyAddon:OnInitialize()
    -- Called when SavedVariables are available
    self.db = LibStub("AceDB-3.0"):New("MyAddonDB", defaults, true)
    self:RegisterChatCommand("myaddon", "ChatCommand")
end

function MyAddon:OnEnable()
    -- Called when addon is enabled
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function MyAddon:OnDisable()
    -- Called when addon is disabled
end

function MyAddon:PLAYER_ENTERING_WORLD()
    if self.db.profile.enabled then
        self:Print("Hello, " .. UnitName("player") .. "!")
    end
end

function MyAddon:ChatCommand(input)
    if input == "show" then
        MyAddonFrame:Show()
    elseif input == "hide" then
        MyAddonFrame:Hide()
    else
        self:Print("Usage: /myaddon show|hide")
    end
end
```

### Key Ace3 Modules

| Module | Purpose |
|--------|---------|
| `AceAddon-3.0` | Core lifecycle (OnInitialize, OnEnable, OnDisable) |
| `AceDB-3.0` | SavedVariables with profiles, defaults, migrations |
| `AceEvent-3.0` | Event registration with automatic cleanup |
| `AceConsole-3.0` | Slash commands and `Print()` helper |
| `AceConfig-3.0` | Options table → auto-generated config UI |
| `AceGUI-3.0` | Pre-built UI widget library |
| `AceTimer-3.0` | Safe, cancellable timers |
| `AceHook-3.0` | Safe function hooking with cleanup |
| `AceComm-3.0` | Addon messaging over chat channels |

---

## Performance Best Practices

Source: [Wowhead Lua Guide](https://www.wowhead.com/guide/comprehensive-beginners-guide-for-wow-addon-coding-in-lua-5338) · [WoWAddonDevGuide on GitHub](https://github.com/Amadeus-/WoWAddonDevGuide)

### 1. Localize Globals

```lua
-- Bad: hits the global table every access
local function tick()
    math.floor(GetTime())
end

-- Good: local reference is ~30% faster
local floor = math.floor
local GetTime = GetTime

local function tick()
    floor(GetTime())
end
```

### 2. Avoid OnUpdate Abuse

```lua
-- Bad: runs every frame (~60x/sec) regardless
frame:SetScript("OnUpdate", function(self, elapsed)
    MyAddon:UpdateEverything()  -- expensive!
end)

-- Good: throttle manually
local elapsed_total = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    elapsed_total = elapsed_total + elapsed
    if elapsed_total >= 0.5 then  -- run at most every 0.5s
        elapsed_total = 0
        MyAddon:UpdateIfNeeded()
    end
end)

-- Best: use AceTimer-3.0 for interval work
self:ScheduleRepeatingTimer("UpdateIfNeeded", 0.5)
```

### 3. Minimize Table Churn

```lua
-- Bad: creates a new table every call
local function getStats()
    return { health = UnitHealth("player"), mana = UnitMana("player") }
end

-- Good: reuse a table
local statsCache = {}
local function getStats()
    statsCache.health = UnitHealth("player")
    statsCache.mana = UnitMana("player")
    return statsCache
end
```

### 4. String Concatenation

```lua
-- Bad: creates intermediate strings
local result = "Player: " .. name .. " Level: " .. level .. " Class: " .. class

-- Good: use string.format
local result = string.format("Player: %s Level: %d Class: %s", name, level, class)
```

### 5. Event Hygiene

```lua
-- Only register events you need, and unregister when done
self:RegisterEvent("UNIT_HEALTH")

-- In combat, UNIT_HEALTH fires very frequently — filter by unit
function MyAddon:UNIT_HEALTH(event, unit)
    if unit ~= "player" and unit ~= "target" then return end
    self:UpdateHealthDisplay(unit)
end
```

---

## Debugging

```lua
-- Enable Lua errors in-game
/console scriptErrors 1

-- Print to default chat
print("Debug:", myValue)

-- Inspect a table
DevTools_Dump(myTable)        -- built-in WoW dev tool
/dump MyAddon.db.profile      -- same via slash command

-- Reload UI to pick up code changes
/reload

-- View all loaded addons
/framestack            -- identify frames under cursor
/eventtrace            -- trace events firing in real time
```

**Recommended tools:**
- [BugGrabber + BugSack](https://www.curseforge.com/wow/addons/bug-grabber) — captures and displays Lua errors
- [Ace3 DevTools](https://www.wowace.com/projects/ace3) — integrated debugging utilities
- VS Code + [lua-language-server](https://github.com/LuaLS/lua-language-server) + [wow-api stubs](https://github.com/Ketho/vscode-wow-api) for local development with IntelliSense

---

## WoW API Quick Reference

Source: [Wowpedia WoW API](https://wowpedia.fandom.com/wiki/World_of_Warcraft_API)

```lua
-- Unit info
UnitName("player")              -- "Arthas"
UnitClass("player")             -- "Paladin", "PALADIN"
UnitLevel("player")             -- 80
UnitHealth("player")            -- current HP
UnitHealthMax("player")         -- max HP
UnitPower("player", Enum.PowerType.Mana)

-- Targeting
UnitExists("target")
UnitIsFriend("player", "target")
UnitIsEnemy("player", "target")

-- Items
GetItemInfo(itemID)             -- name, link, quality, level, ...
GetContainerItemID(bag, slot)   -- item in bag slot

-- Spells
IsSpellKnown(spellID)
GetSpellInfo(spellID)           -- name, rank, icon, castTime, minRange, maxRange, spellID

-- Combat
IsInCombat() -- returns true/false
InCombatLockdown()              -- true when UI is protected (can't modify action bars)

-- Chat
SendChatMessage("Hello!", "SAY")
SendChatMessage("Hi raid", "RAID")

-- Slash commands
SLASH_MYADDON1 = "/myaddon"
SlashCmdList["MYADDON"] = function(msg) MyAddon:HandleSlash(msg) end
```

---

## Security: Protected vs. Tainted Code

WoW enforces a **combat lockdown** that restricts what addons can do during combat to prevent automation abuse.

- **Protected frames/functions** — part of Blizzard's UI; cannot be modified by addons during combat.
- **Tainted code** — addon code that has touched a protected value taints it, causing "Tainted: X" errors.
- **Never call** `CastSpellByName`, `UseAction`, `TargetUnit`, etc. from unsecured code.
- Use **SecureActionButton** templates for click-to-cast and macro interactions:

```lua
local btn = CreateFrame("Button", "MySecureBtn", UIParent, "SecureActionButtonTemplate")
btn:SetAttribute("type", "spell")
btn:SetAttribute("spell", "Fireball")
btn:RegisterForClicks("AnyUp")
```

---

## Testing WoW Addons

Sources: [Busted GitHub](https://github.com/lunarmodules/busted) · [LuaUnit Docs](https://luaunit.readthedocs.io/) · [DragonToast CI example](https://github.com/DragonAddons/DragonToast) · [Lua Busted GitHub Action](https://github.com/marketplace/actions/lua-busted)

WoW's sandbox means you **cannot run addon code directly in a Lua interpreter** — the game client provides all the global functions (`UnitName`, `CreateFrame`, etc.). The standard approach is:

1. **Isolate business logic** into pure Lua modules with no direct WoW API calls
2. **Mock the WoW API** for the parts that must interact with it
3. **Run tests outside the game** using Busted or LuaUnit

### Architecture for Testability

```lua
-- Bad: WoW API baked directly into logic — untestable outside game
function MyAddon:GetPlayerSummary()
    return UnitName("player") .. " - " .. UnitLevel("player")
end

-- Good: inject dependencies so logic can be tested with mocks
function MyAddon:GetPlayerSummary(getName, getLevel)
    getName = getName or UnitName
    getLevel = getLevel or UnitLevel
    return getName("player") .. " - " .. getLevel("player")
end
```

### Busted (Recommended — BDD style)

Install via LuaRocks:
```bash
luarocks install busted
```

Write tests in `spec/` directory:
```lua
-- spec/player_spec.lua
local MyAddon = require("MyAddon")

describe("GetPlayerSummary", function()
    it("formats name and level correctly", function()
        local result = MyAddon:GetPlayerSummary(
            function() return "Arthas" end,   -- mock UnitName
            function() return 80 end          -- mock UnitLevel
        )
        assert.equals("Arthas - 80", result)
    end)

    it("returns unknown for nil name", function()
        local result = MyAddon:GetPlayerSummary(
            function() return nil end,
            function() return 1 end
        )
        assert.is_not_nil(result)
    end)
end)
```

Run all tests:
```bash
busted --output=plain spec/
```

### WoW API Mock Layer

Create a `spec/wow_mock.lua` that stubs the globals WoW normally provides:

```lua
-- spec/wow_mock.lua
-- Minimal WoW API stubs for testing outside the game client

_G.UnitName = function(unit) return "MockPlayer" end
_G.UnitLevel = function(unit) return 80 end
_G.UnitHealth = function(unit) return 100000 end
_G.UnitHealthMax = function(unit) return 100000 end
_G.GetTime = function() return 0 end
_G.print = print  -- already exists in Lua

-- Stub CreateFrame to return a minimal table
_G.CreateFrame = function(frameType, name, parent, template)
    local frame = {
        scripts = {},
        SetScript = function(self, event, fn) self.scripts[event] = fn end,
        RegisterEvent = function(self, event) end,
        SetSize = function(self, w, h) end,
        SetPoint = function(self, ...) end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
    return frame
end
```

Load the mock at the top of your test files:
```lua
require("spec/wow_mock")
local MyAddon = require("MyAddon")
```

### LuaUnit (xUnit style, single-file)

```lua
-- test_mymodule.lua
local luaunit = require("luaunit")
require("spec/wow_mock")
local MyAddon = require("MyAddon")

TestPlayerSummary = {}

function TestPlayerSummary:testFormat()
    local result = MyAddon:GetPlayerSummary(
        function() return "Thrall" end,
        function() return 60 end
    )
    luaunit.assertEquals(result, "Thrall - 60")
end

os.exit(luaunit.LuaUnit.run())
```

Run:
```bash
lua test_mymodule.lua
```

### GitHub Actions CI

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Lua
        uses: leafo/gh-actions-lua@v10
        with:
          luaVersion: "5.1"   # WoW uses Lua 5.1

      - name: Setup LuaRocks
        uses: leafo/gh-actions-luarocks@v4

      - name: Install Busted
        run: luarocks install busted

      - name: Run Tests
        uses: lunarmodules/busted@v1   # https://github.com/marketplace/actions/lua-busted
        with:
          args: --output=plain spec/
```

### What You Can and Cannot Test Outside the Game

| ✅ Testable outside game | ❌ Requires in-game testing |
|--------------------------|----------------------------|
| Business logic / calculations | Actual UI rendering |
| SavedVariables initialization | Frame positioning / anchors |
| Event handler logic (mocked) | Secure/protected API calls |
| String formatting | Combat lockdown behavior |
| Data transformations | Real network/combat events |
| Slash command parsing | Texture loading |

### In-Game Smoke Testing

Even with unit tests, always verify in-game:
```lua
-- Quick in-game assertions (dev builds only)
local function assert_eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("[TEST FAIL] %s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
    print(string.format("[TEST PASS] %s", label))
end

-- Run via /run MyAddon:RunSmokeTests()
function MyAddon:RunSmokeTests()
    assert_eq(type(self.db), "table", "db initialized")
    assert_eq(self.db.profile.enabled, true, "default enabled")
    print("All smoke tests passed!")
end
```

---

## Discovering Every Available API

Sources: [Warcraft Wiki WoW API](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API) · [Wowpedia API Namespaces](https://wowpedia.fandom.com/wiki/Category:API_namespaces) · [Warcraft Wiki Alphabetic Index](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API/Alphabetic) · [ApiExplorer CurseForge](https://www.curseforge.com/wow/addons/apiexplorer) · [Patch 12.0.0 API Changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)

### Method 1: In-Game `/api` Command (Most Authoritative)

Blizzard ships a `Blizzard_APIDocumentation` addon with WoW that exposes the **complete, version-exact** API for your current client build.

```
/api                        -- opens the in-game API browser
/api UnitHealth             -- jump directly to a function
/api C_Item                 -- browse a namespace
```

The browser shows function signatures, parameter types, return values, and whether a function is protected/secure. **This is the ground truth** — if it's not here, it doesn't exist in your client version.

### Method 2: Dump the API Documentation Programmatically

```lua
-- List all documented API namespaces in-game
/run for k in pairs(C_) do print(k) end

-- List all functions in a namespace
/run for k, v in pairs(C_Item) do if type(v) == "function" then print(k) end end

-- Dump the full APIDocumentation data
/run for i = 1, APIDocumentation:GetNumFunctions() do
    local info = APIDocumentation:GetFunctionByIndex(i)
    print(info.Name)
end
```

### Method 3: Read Blizzard's Source Files

WoW ships its own UI source in your installation directory:

```
World of Warcraft/_retail_/Interface/AddOns/
├── Blizzard_APIDocumentation/     ← generated API docs (Lua tables)
├── Blizzard_APIDocumentationGenerated/  ← auto-exported function signatures
└── FrameXML/                      ← all Blizzard UI source code
```

These files are plain Lua/XML — read them to understand any Blizzard UI pattern or to find undocumented APIs. Also mirrored on GitHub:
- https://github.com/Gethe/wow-ui-source (community mirror, updated each patch)
- https://github.com/Ketho/BlizzardInterfaceResources (API stubs for IDE use)

### Method 4: Community Index (Out-of-Game Reference)

| Resource | URL | Notes |
|----------|-----|-------|
| **Warcraft Wiki API Index** | https://warcraft.wiki.gg/wiki/World_of_Warcraft_API | Primary reference, 180+ `C_` namespaces |
| **Alphabetic Function List** | https://warcraft.wiki.gg/wiki/World_of_Warcraft_API/Alphabetic | Every function A–Z |
| **API Namespaces Category** | https://warcraft.wiki.gg/wiki/Category:API_namespaces | Browse by `C_` namespace |
| **API Functions Category** | https://warcraft.wiki.gg/wiki/Category:API_functions | All global functions |
| **API Types / Enums** | https://warcraft.wiki.gg/wiki/API_types | Structs, enums, mixins |
| **Widget API** | https://warcraft.wiki.gg/wiki/Widget_API | Frame/widget methods |
| **Events Index** | https://warcraft.wiki.gg/wiki/Events | All events by category |
| **Patch 12.0.0 API Changes** | https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes | What changed in Midnight |
| **Pedia API Namespaces** | https://wowpedia.fandom.com/wiki/Category:API_namespaces | Legacy/Classic reference |

### Method 5: ApiExplorer Addon (In-Game Visual Browser)

Install [ApiExplorer](https://www.curseforge.com/wow/addons/apiexplorer) from CurseForge for a searchable, filterable, visual API browser inside WoW. Features:
- Search by function name, namespace, or keyword
- Filter by type (function, event, table, enum)
- See deprecation flags and patch-introduced markers
- One-click `/run` snippet generation for testing

### Method 6: VS Code IntelliSense (Local Development)

Install the [WoW API VS Code extension](https://marketplace.visualstudio.com/items?itemName=ketho.wow-api) (`ketho.wow-api`) for full autocomplete, type hints, and inline docs sourced directly from `Blizzard_APIDocumentation`:

```json
// .vscode/settings.json
{
    "Lua.workspace.library": ["path/to/BlizzardInterfaceResources"],
    "Lua.runtime.version": "Lua 5.1",
    "Lua.diagnostics.globals": ["C_Item", "C_AuctionHouse", "UIParent"]
}
```

### C_ Namespace Quick Reference (Midnight / 12.x)

Major namespaces available as of Patch 12.0.1:

| Namespace | Domain |
|-----------|--------|
| `C_AchievementInfo` | Achievement data |
| `C_ActionBar` | Action bar slots and state |
| `C_AuctionHouse` | Auction house browsing/posting |
| `C_Bank` | Bank/Warbank access |
| `C_Calendar` | In-game calendar events |
| `C_CharacterServices` | Character boost/services |
| `C_Club` | Communities and guilds |
| `C_Container` | Bags and inventory (replaces old `GetContainerItem*`) |
| `C_CurrencyInfo` | Currency data |
| `C_DateAndTime` | Date/time utilities |
| `C_EquipmentSet` | Equipment manager sets |
| `C_GossipInfo` | NPC gossip/dialog |
| `C_Item` | Item info, tooltips, location |
| `C_Map` | Map/minimap data |
| `C_MountJournal` | Mount collection |
| `C_NewItems` | New item highlighting |
| `C_PetBattles` | Pet battle system |
| `C_PlayerInfo` | Player data |
| `C_PvP` | PvP match and honor data |
| `C_QuestLog` | Quest tracking and data |
| `C_Spell` | Spell info and casting |
| `C_Timer` | Safe timers (`C_Timer.After`, `C_Timer.NewTicker`) |
| `C_TooltipInfo` | Tooltip data without showing UI |
| `C_TradeSkillUI` | Professions/crafting |
| `C_UnitAuras` | Buffs/debuffs (replaces `UnitAura` in 10.0+) |
| `C_WeeklyRewards` | Great Vault / weekly rewards |

> **Full list:** https://warcraft.wiki.gg/wiki/Category:API_namespaces (180+ namespaces)

### Key API Changes to Know (Midnight / 12.x)

- `C_Container.*` fully replaces old `GetContainerItem*` global functions
- `C_UnitAuras.GetAuraDataByIndex` replaces deprecated `UnitAura`
- `C_Item.GetItemInfo` is the preferred replacement for `GetItemInfo`
- `C_Spell.GetSpellInfo` replaces `GetSpellInfo`
- Always check [Patch API Changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) when upgrading an older addon

---



- **CurseForge** — https://www.curseforge.com/wow/addons (most widely used)
- **WoWInterface** — https://www.wowinterface.com
- Use [BigWigsMods/packager](https://github.com/BigWigsMods/packager) or [GitHub Actions release workflow](https://github.com/marketplace/actions/wow-addon-packager) to automate packaging
- Include a `CHANGELOG.md` and tag releases semantically (`v1.2.3`)
- Always bump `## Interface` on major WoW patches

---

## Keeping This Skill Up to Date

When a new WoW patch drops, run through the steps below to refresh the skill. The Blizzard developer portal is a JavaScript SPA — `web_fetch` returns a blank shell. **Always use Playwright** to scrape it.

### Step 1 — Check the current interface version

```
/dump select(4, GetBuildInfo())   -- run in-game, note the 6-digit number
```

Update the header and TOC example in this skill to match.

### Step 2 — Scrape the official Blizzard REST API docs with Playwright

Navigate each of the three official pages and capture all endpoint buttons:

```
https://community.developer.battle.net/documentation/world-of-warcraft/game-data-apis
https://community.developer.battle.net/documentation/world-of-warcraft/profile-apis
https://community.developer.battle.net/documentation/world-of-warcraft-classic
```

For each page, after navigation wait ~3 seconds for the SPA to render, then extract content:

```js
// Playwright snippet — run via playwright-browser_run_code
async (page) => {
  await page.goto('https://community.developer.battle.net/documentation/world-of-warcraft/game-data-apis');
  await page.waitForTimeout(3000);
  return await page.evaluate(() => document.body.innerText);
}
```

Parse the output for lines matching the pattern `GET|POST <Name> /data/wow/...` and update the **Blizzard REST API Index** section below.

### Step 3 — Check patch API changes on Warcraft Wiki

```
https://warcraft.wiki.gg/wiki/Patch_<X.Y.Z>/API_changes
```

Look for:
- New `C_` namespaces or functions
- Deprecated/removed functions (especially old globals replaced by `C_*` equivalents)
- New events
- Protected function changes

Update the **C_ Namespace Quick Reference** table and the **Key API Changes** section.

### Step 4 — Update the `## Interface` version in the TOC example

Change the 6-digit number in the TOC format section to match the current build.

### Step 5 — Update version metadata in this file

Bump the `version:` field in the YAML front matter and note what changed.

---

## Blizzard REST API Index (Web API — requires OAuth)

> These are the **web/REST APIs** at `https://community.developer.battle.net` — used for external websites and tools, **not** in-game addon Lua code. Requires a Battle.net OAuth client ID/secret from https://develop.battle.net/access/clients.
>
> Base URL: `https://{region}.api.blizzard.com` (regions: `us`, `eu`, `kr`, `tw`, `cn`)
> Auth: OAuth 2.0 client credentials — `POST https://oauth.battle.net/token`

### Game Data APIs (`/data/wow/...`)

| Endpoint | Path |
|----------|------|
| **Achievement Category Index** | `GET /data/wow/achievement-category/index` |
| **Achievement Category** | `GET /data/wow/achievement-category/{achievementCategoryId}` |
| **Achievement Index** | `GET /data/wow/achievement/index` |
| **Achievement** | `GET /data/wow/achievement/{achievementId}` |
| **Achievement Media** | `GET /data/wow/media/achievement/{achievementId}` |
| **Auction House Index** | `GET /data/wow/connected-realm/{connectedRealmId}/auctions/index` |
| **Auctions** | `GET /data/wow/connected-realm/{connectedRealmId}/auctions/{auctionHouseId}` |
| **Commodities** | `GET /data/wow/auctions/commodities` |
| **Azerite Essence Index** | `GET /data/wow/azerite-essence/index` |
| **Azerite Essence** | `GET /data/wow/azerite-essence/{azeriteEssenceId}` |
| **Azerite Essence Media** | `GET /data/wow/media/azerite-essence/{azeriteEssenceId}` |
| **Connected Realm Index** | `GET /data/wow/connected-realm/index` |
| **Connected Realm** | `GET /data/wow/connected-realm/{connectedRealmId}` |
| **Covenant Index** | `GET /data/wow/covenant/index` |
| **Covenant** | `GET /data/wow/covenant/{covenantId}` |
| **Covenant Media** | `GET /data/wow/media/covenant/{covenantId}` |
| **Conduit Index** | `GET /data/wow/covenant/conduit/index` |
| **Conduit** | `GET /data/wow/covenant/conduit/{conduitId}` |
| **Soulbind Index** | `GET /data/wow/covenant/soulbind/index` |
| **Soulbind** | `GET /data/wow/covenant/soulbind/{soulbindId}` |
| **Creature Families Index** | `GET /data/wow/creature-family/index` |
| **Creature Family** | `GET /data/wow/creature-family/{creatureFamilyId}` |
| **Creature Family Media** | `GET /data/wow/media/creature-family/{creatureFamilyId}` |
| **Creature Types Index** | `GET /data/wow/creature-type/index` |
| **Creature Type** | `GET /data/wow/creature-type/{creatureTypeId}` |
| **Creature** | `GET /data/wow/creature/{creatureId}` |
| **Creature Display Media** | `GET /data/wow/media/creature-display/{creatureDisplayId}` |
| **Guild Crest Components Index** | `GET /data/wow/guild-crest/index` |
| **Guild Crest Border Media** | `GET /data/wow/media/guild-crest/border/{borderId}` |
| **Guild Crest Emblem Media** | `GET /data/wow/media/guild-crest/emblem/{emblemId}` |
| **Heirloom Index** | `GET /data/wow/heirloom/index` |
| **Heirloom** | `GET /data/wow/heirloom/{heirloomId}` |
| **Item Classes Index** | `GET /data/wow/item-class/index` |
| **Item Class** | `GET /data/wow/item-class/{itemClassId}` |
| **Item Sets Index** | `GET /data/wow/item-set/index` |
| **Item Set** | `GET /data/wow/item-set/{itemSetId}` |
| **Item Subclass** | `GET /data/wow/item-class/{itemClassId}/item-subclass/{itemSubclassId}` |
| **Item** | `GET /data/wow/item/{itemId}` |
| **Item Media** | `GET /data/wow/media/item/{itemId}` |
| **Item Search** | `GET /data/wow/search/item` |
| **Journal Expansions Index** | `GET /data/wow/journal-expansion/index` |
| **Journal Expansion** | `GET /data/wow/journal-expansion/{journalExpansionId}` |
| **Journal Encounters Index** | `GET /data/wow/journal-encounter/index` |
| **Journal Encounter** | `GET /data/wow/journal-encounter/{journalEncounterId}` |
| **Journal Encounter Search** | `GET /data/wow/search/journal-encounter` |
| **Journal Instances Index** | `GET /data/wow/journal-instance/index` |
| **Journal Instance** | `GET /data/wow/journal-instance/{journalInstanceId}` |
| **Journal Instance Media** | `GET /data/wow/media/journal-instance/{journalInstanceId}` |
| **Modified Crafting Index** | `GET /data/wow/modified-crafting/index` |
| **Modified Crafting Category Index** | `GET /data/wow/modified-crafting/category/index` |
| **Modified Crafting Category** | `GET /data/wow/modified-crafting/category/{categoryId}` |
| **Modified Crafting Reagent Slot Type Index** | `GET /data/wow/modified-crafting/reagent-slot-type/index` |
| **Modified Crafting Reagent Slot Type** | `GET /data/wow/modified-crafting/reagent-slot-type/{reagentSlotTypeId}` |
| **Mount Index** | `GET /data/wow/mount/index` |
| **Mount** | `GET /data/wow/mount/{mountId}` |
| **Mount Search** | `GET /data/wow/search/mount` |
| **Mythic Keystone Affix Index** | `GET /data/wow/keystone-affix/index` |
| **Mythic Keystone Affix** | `GET /data/wow/keystone-affix/{keystoneAffixId}` |
| **Mythic Keystone Affix Media** | `GET /data/wow/media/keystone-affix/{keystoneAffixId}` |
| **Mythic Keystone Dungeon Index** | `GET /data/wow/mythic-keystone/dungeon/index` |
| **Mythic Keystone Dungeon** | `GET /data/wow/mythic-keystone/dungeon/{dungeonId}` |
| **Mythic Keystone Index** | `GET /data/wow/mythic-keystone/index` |
| **Mythic Keystone Period Index** | `GET /data/wow/mythic-keystone/period/index` |
| **Mythic Keystone Period** | `GET /data/wow/mythic-keystone/period/{periodId}` |
| **Mythic Keystone Season Index** | `GET /data/wow/mythic-keystone/season/index` |
| **Mythic Keystone Season** | `GET /data/wow/mythic-keystone/season/{seasonId}` |
| **Mythic Raid Leaderboard** | `GET /data/wow/leaderboard/hall-of-fame/{raid}/{difficulty}` |
| **Pet Index** | `GET /data/wow/pet/index` |
| **Pet** | `GET /data/wow/pet/{petId}` |
| **Pet Media** | `GET /data/wow/media/pet/{petId}` |
| **Pet Abilities Index** | `GET /data/wow/pet-ability/index` |
| **Pet Ability** | `GET /data/wow/pet-ability/{petAbilityId}` |
| **Pet Ability Media** | `GET /data/wow/media/pet-ability/{petAbilityId}` |
| **Playable Class Index** | `GET /data/wow/playable-class/index` |
| **Playable Class** | `GET /data/wow/playable-class/{classId}` |
| **Playable Class Media** | `GET /data/wow/media/playable-class/{playableClassId}` |
| **PvP Talent Slots** | `GET /data/wow/playable-class/{classId}/pvp-talent-slots` |
| **Playable Race Index** | `GET /data/wow/playable-race/index` |
| **Playable Race** | `GET /data/wow/playable-race/{playableRaceId}` |
| **Playable Specialization Index** | `GET /data/wow/playable-specialization/index` |
| **Playable Specialization** | `GET /data/wow/playable-specialization/{specId}` |
| **Playable Specialization Media** | `GET /data/wow/media/playable-specialization/{specId}` |
| **Power Types Index** | `GET /data/wow/power-type/index` |
| **Power Type** | `GET /data/wow/power-type/{powerTypeId}` |
| **Profession Index** | `GET /data/wow/profession/index` |
| **Profession** | `GET /data/wow/profession/{professionId}` |
| **Profession Media** | `GET /data/wow/media/profession/{professionId}` |
| **Profession Skill Tier** | `GET /data/wow/profession/{professionId}/skill-tier/{skillTierId}` |
| **Recipe** | `GET /data/wow/profession/{professionId}/skill-tier/{skillTierId}/recipe/{recipeId}` |
| **Recipe Media** | `GET /data/wow/media/recipe/{recipeId}` |
| **PvP Season Index** | `GET /data/wow/pvp-season/index` |
| **PvP Season** | `GET /data/wow/pvp-season/{pvpSeasonId}` |
| **PvP Leaderboards Index** | `GET /data/wow/pvp-season/{pvpSeasonId}/pvp-leaderboard/index` |
| **PvP Leaderboard** | `GET /data/wow/pvp-season/{pvpSeasonId}/pvp-leaderboard/{pvpBracket}` |
| **PvP Rewards Index** | `GET /data/wow/pvp-season/{pvpSeasonId}/pvp-reward/index` |
| **PvP Tiers Index** | `GET /data/wow/pvp-tier/index` |
| **PvP Tier Media** | `GET /data/wow/media/pvp-tier/{pvpTierId}` |
| **PvP Tier** | `GET /data/wow/pvp-tier/{pvpTierId}` |
| **Quest Index** | `GET /data/wow/quest/index` |
| **Quest** | `GET /data/wow/quest/{questId}` |
| **Quest Categories Index** | `GET /data/wow/quest/category/index` |
| **Quest Category** | `GET /data/wow/quest/category/{questCategoryId}` |
| **Quest Areas Index** | `GET /data/wow/quest/area/index` |
| **Quest Area** | `GET /data/wow/quest/area/{questAreaId}` |
| **Quest Types Index** | `GET /data/wow/quest/type/index` |
| **Quest Type** | `GET /data/wow/quest/type/{questTypeId}` |
| **Realm Index** | `GET /data/wow/realm/index` |
| **Realm** | `GET /data/wow/realm/{realmSlug}` |
| **Realm Search** | `GET /data/wow/search/realm` |
| **Region Index** | `GET /data/wow/region/index` |
| **Region** | `GET /data/wow/region/{regionId}` |
| **Reputations Factions Index** | `GET /data/wow/reputation-faction/index` |
| **Reputation Faction** | `GET /data/wow/reputation-faction/{reputationFactionId}` |
| **Reputation Tiers Index** | `GET /data/wow/reputation-tiers/index` |
| **Reputation Tiers** | `GET /data/wow/reputation-tiers/{reputationTiersId}` |
| **Spell** | `GET /data/wow/spell/{spellId}` |
| **Spell Media** | `GET /data/wow/media/spell/{spellId}` |
| **Spell Search** | `GET /data/wow/search/spell` |
| **Talent Tree Index** | `GET /data/wow/talent-tree/index` |
| **Talent Tree** | `GET /data/wow/talent-tree/{talentTreeId}/playable-specialization/{specId}` |
| **Talent Tree Nodes** | `GET /data/wow/talent-tree/{talentTreeId}` |
| **Talents Index** | `GET /data/wow/talent/index` |
| **Talent** | `GET /data/wow/talent/{talentId}` |
| **PvP Talents Index** | `GET /data/wow/pvp-talent/index` |
| **PvP Talent** | `GET /data/wow/pvp-talent/{pvpTalentId}` |
| **Tech Talent Tree Index** | `GET /data/wow/tech-talent-tree/index` |
| **Tech Talent Tree** | `GET /data/wow/tech-talent-tree/{techTalentTreeId}` |
| **Tech Talent Index** | `GET /data/wow/tech-talent/index` |
| **Tech Talent** | `GET /data/wow/tech-talent/{techTalentId}` |
| **Tech Talent Media** | `GET /data/wow/media/tech-talent/{techTalentId}` |
| **Title Index** | `GET /data/wow/title/index` |
| **Title** | `GET /data/wow/title/{titleId}` |
| **Toy Index** | `GET /data/wow/toy/index` |
| **Toy** | `GET /data/wow/toy/{toyId}` |
| **WoW Token Index (US/EU/KR/TW)** | `GET /data/wow/token/index` |
| **WoW Token Index (CN)** | `GET /data/wow/token/index` |

### Profile APIs (`/profile/wow/...`)

> Profile APIs require user-level OAuth scope (`wow.profile`). The character must authorize your app.

| Endpoint | Path |
|----------|------|
| **Account Profile Summary** | `GET /profile/user/wow` |
| **Protected Character Profile Summary** | `GET /profile/user/wow/protected-character/{realmId}-{characterId}` |
| **Account Collections Index** | `GET /profile/user/wow/collections` |
| **Account Mounts Collection** | `GET /profile/user/wow/collections/mounts` |
| **Account Pets Collection** | `GET /profile/user/wow/collections/pets` |
| **Account Heirlooms Collection** | `GET /profile/user/wow/collections/heirlooms` |
| **Account Toys Collection** | `GET /profile/user/wow/collections/toys` |
| **Character Achievements Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/achievements` |
| **Character Achievement Statistics** | `GET /profile/wow/character/{realmSlug}/{characterName}/achievements/statistics` |
| **Character Appearance Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/appearance` |
| **Character Collections Index** | `GET /profile/wow/character/{realmSlug}/{characterName}/collections` |
| **Character Mounts Collection** | `GET /profile/wow/character/{realmSlug}/{characterName}/collections/mounts` |
| **Character Pets Collection** | `GET /profile/wow/character/{realmSlug}/{characterName}/collections/pets` |
| **Character Heirlooms Collection** | `GET /profile/wow/character/{realmSlug}/{characterName}/collections/heirlooms` |
| **Character Toys Collection** | `GET /profile/wow/character/{realmSlug}/{characterName}/collections/toys` |
| **Character Dungeons** | `GET /profile/wow/character/{realmSlug}/{characterName}/dungeons` |
| **Character Encounters Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/encounters` |
| **Character Raids** | `GET /profile/wow/character/{realmSlug}/{characterName}/encounters/raids` |
| **Character Equipment Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/equipment` |
| **Character Hunter Pets Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/hunter-pets` |
| **Character Media Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/character-media` |
| **Character Mythic Keystone Profile Index** | `GET /profile/wow/character/{realmSlug}/{characterName}/mythic-keystone-profile` |
| **Character Mythic Keystone Season Details** | `GET /profile/wow/character/{realmSlug}/{characterName}/mythic-keystone-profile/season/{seasonId}` |
| **Character Professions Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/professions` |
| **Character Profile Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}` |
| **Character Profile Status** | `GET /profile/wow/character/{realmSlug}/{characterName}/status` |
| **Character PvP Bracket Statistics** | `GET /profile/wow/character/{realmSlug}/{characterName}/pvp-bracket/{pvpBracket}` |
| **Character PvP Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/pvp-summary` |
| **Character Quests** | `GET /profile/wow/character/{realmSlug}/{characterName}/quests` |
| **Character Completed Quests** | `GET /profile/wow/character/{realmSlug}/{characterName}/quests/completed` |
| **Character Reputations Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/reputations` |
| **Character Soulbinds** | `GET /profile/wow/character/{realmSlug}/{characterName}/soulbinds` |
| **Character Specializations Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/specializations` |
| **Character Statistics Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/statistics` |
| **Character Titles Summary** | `GET /profile/wow/character/{realmSlug}/{characterName}/titles` |
| **Guild** | `GET /data/wow/guild/{realmSlug}/{nameSlug}` |
| **Guild Activity** | `GET /data/wow/guild/{realmSlug}/{nameSlug}/activity` |
| **Guild Achievements** | `GET /data/wow/guild/{realmSlug}/{nameSlug}/achievements` |
| **Guild Roster** | `GET /data/wow/guild/{realmSlug}/{nameSlug}/roster` |

### Required Query Parameters (all REST endpoints)

```
namespace=static-us    # or dynamic-us, profile-us — varies per endpoint
locale=en_US
access_token=<token>   # OAuth bearer token
```

Namespace prefixes by type:
- `static-{region}` — static game data (items, spells, realms)
- `dynamic-{region}` — live data (auctions, connected realms, M+ seasons)
- `profile-{region}` — character profile data

---

## Success Criteria

When implementing or reviewing a WoW addon:

✅ TOC file has correct `## Interface` version  
✅ SavedVariables initialized only in `ADDON_LOADED` handler  
✅ Globals minimized — addon code uses a single namespace table  
✅ OnUpdate handlers are throttled or replaced with AceTimer  
✅ Events unregistered when no longer needed  
✅ No tainted code paths in combat  
✅ `/reload` works cleanly without Lua errors  
✅ Lua errors shown via `/console scriptErrors 1` and resolved  
