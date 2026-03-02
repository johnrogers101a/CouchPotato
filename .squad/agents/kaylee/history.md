# Project Context

- **Owner:** John Rogers
- **Project:** CouchPotato — a WoW addon that detects gamepad input and dynamically loads a BG3-style radial-wheel controller UI
- **Stack:** Lua, WoW Addon API (TOC, XML, CreateFrame, SecureHandlerTemplate, widget mixins)
- **Created:** 2026-03-01

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-03-01: UI System Architecture

**SecureActionButtonTemplate Pattern:**
- All radial wheel buttons use SecureActionButtonTemplate to remain functional during combat
- Parent frames (wheel containers) are regular frames and can show/hide freely
- Only the button children are protected — they inherit combat safety from the template
- All frame creation MUST happen outside combat (OnEnable, before first PLAYER_REGEN_DISABLED)

**Blizzard Frame Management:**
- All Hide/Show calls on Blizzard UI frames MUST check InCombatLockdown()
- Queue operations for PLAYER_REGEN_ENABLED if attempted during combat
- Must unregister frame events (e.g., ACTIONBAR_PAGE_CHANGED) to prevent auto-re-showing
- Party frames are indexed 1-4 as PartyMemberFrame1, PartyMemberFrame2, etc.

**Radial Wheel Design:**
- 8 wheels × 12 slots (96 total ability slots)
- Circular layout: 30° spacing, slot 1 at top (90°), clockwise
- Peek (light trigger 0.35) vs Lock (hard trigger 0.75) for BG3-style interaction
- L1/R1 (PADLSHOULDER/PADRSHOULDER) for wheel cycling
- Wheel indicator dots show current wheel position (BG3 pattern)

**HUD Scaling:**
- Controller HUD elements ~25% larger than default WoW UI for "couch distance" readability
- Cast bar centered at y=-150, health bars bottom-left starting at (40, 60)
- All fonts use GameFontNormalLarge or larger
- Semi-transparent dark backgrounds (0, 0, 0, 0.7) for contrast

**Power Type Colors:**
- Use PowerBarColor[powerType] table for auto-coloring resource bars
- Mana=blue, Energy=yellow, Rage=red, handled by WoW's built-in color table
- Class colors from RAID_CLASS_COLORS table for player health bar

**VirtualCursor Navigation:**
- D-pad cursor uses frame strata "TOOLTIP" to always appear on top
- Golden border (1.0, 0.85, 0.0) uses ADD blend mode for visibility
- Navigates between common UI frames: GossipFrame, QuestFrame, MerchantFrame, etc.
- L3 (stick click) toggles free cursor mode via SetGamePadCursorControl()

**HealMode Party Frame Detection:**
- Check healer addons in order: Cell, Grid2, VuhDo, CompactPartyFrames (default)
- Party unit tokens: party1, party2, party3, party4, player
- Heal mode cursor uses green border (0.2, 0.9, 0.2) to differentiate from target selection
- Spell prompts show button→spell mapping for focused party member

**Combat Safety:**
- Bindings can only be changed outside combat (SetOverrideBinding requires !InCombatLockdown)
- HealMode stores currentHealUnit for post-combat re-application
- Frame visibility changes are safe during combat, but attribute changes are not

### 2026-03-01: Ace3 Removal from UI Layer

**Module Declaration Pattern:**
- Changed all 4 UI modules from `CP:NewModule("Name", "AceEvent-3.0", ...)` to `CP:NewModule("Name")`
- Removed mixin library arguments from: Radial, HUD, VirtualCursor, HealMode
- Core module system still provides event registration via inherited AceAddon methods

**TOC File Structure:**
- Removed all libs\ entries (LibStub, AceAddon, AceDB, AceEvent, AceConsole, AceTimer)
- Removed embeds.xml line completely
- TOC now lists only Lua files directly: CouchPotato.lua, Core/*.lua, UI/*.lua
- Dependencies still properly declared: `LoadOnDemand: 1`, `Dependencies: CouchPotato_Loader`

**Cleaned Up:**
- Deleted entire CouchPotato/libs/ directory
- Deleted CouchPotato/embeds.xml file
- UI modules now have zero external library dependencies at declaration time

📌 Team update (2026-03-02T01:45:35Z): Frameworkless migration complete. All Core, UI, and spec files migrated. Mal's review approved. 70/70 tests passing. Decision consolidated into decisions.md. — consolidated by Scribe
