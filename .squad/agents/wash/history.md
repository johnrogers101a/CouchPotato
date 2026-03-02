# Project Context

- **Owner:** John Rogers
- **Project:** CouchPotato — a WoW addon that detects gamepad input and dynamically loads a BG3-style radial-wheel controller UI
- **Stack:** Lua, WoW Addon API (TOC, XML, C_GamePad, frame/widget system, event handlers)
- **Created:** 2026-03-01

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-03-01: Lua Backend Implementation

**Architecture Decisions:**
- **SetOverrideBinding pattern**: Bindings.lua NEVER modifies SavedBindings. All controller bindings use SetOverrideBinding() with ownerFrame, which can be instantly cleared with ClearOverrideBindings(). This ensures keyboard bindings are never corrupted.
- **LoadOnDemand pattern**: CouchPotato_Loader (always-on, ~180 lines) detects gamepad via events and dynamically loads the main addon. Main addon uses `LoadOnDemand: 1` to avoid startup cost.
- **Module isolation**: Each Core module is independent and uses Ace3's `CP:GetModule("ModuleName", true)` for optional dependencies. Modules can fail gracefully if others aren't loaded.
- **LED spell school mapping**: LED colors map to WoW spell school bitmasks (1=Physical, 2=Holy, 4=Fire, etc.). Multi-school spells use lowest set bit as primary.
- **Combat lockdown handling**: All binding operations check `InCombatLockdown()` and defer via `pendingApply`/`pendingClear` flags, resolved on `PLAYER_REGEN_ENABLED`.

**Key API Patterns:**
- `C_GamePad.SetVibration(type, intensity)` + `ScheduleTimer` for timed haptics
- `C_GamePad.SetLedColor(CreateColor(r,g,b))` for DualSense/DualShock LED control
- `C_GamePad.GetDeviceMappedState(deviceID)` for standardized trigger axis reading
- `SetOverrideBindingSpell(owner, true, "PAD2", spellName)` for spell bindings
- Event `GAME_PAD_ACTIVE_CHANGED` (Patch 9.1.5+) is most reliable for state changes

**Spec Data Structure:**
All 39 specs defined with 13 binding slots: primary/secondary/tertiary (face buttons), dpadUp/Down/Left/Right, interrupt/majorCD/defensiveCD/movement (shoulders/triggers). D-pad left/right currently nil, reserved for future modifier layer expansion.

**Caveats:**
- Modifier layer (LT hold) is stubbed but not fully wired; requires secure button implementation from Kaylee's RadialWheel.
- Spell name strings in Specs.lua may need adjustment based on actual WoW spell names (some may vary by rank or talent).
- LED color updates on spell cast assume `C_Spell.GetSpellInfo` API (Patch 10.0+); fallback to older `GetSpellInfo` included.
