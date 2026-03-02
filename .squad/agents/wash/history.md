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

### 2026-03-01: Frameworkless Core — Ace3/LibStub Removal

**What Changed:**
- Removed all Ace3 and LibStub dependencies from CouchPotato.lua
- Replaced AceAddon-3.0, AceDB-3.0, AceEvent-3.0, AceConsole-3.0, AceTimer-3.0 with hand-rolled equivalents
- Updated all Core module files (GamePad, Bindings, Specs, BlizzardFrames) to drop mixin arguments from `CP:NewModule()` calls

**Architecture Design:**
- **Single event frame**: `CP._mainFrame` handles all event registration; `CP._eventCallbacks[event] = [{obj, fn}, ...]` table dispatches to registered objects
- **Event API injection**: `_injectEventAPI()` adds `RegisterEvent`, `UnregisterEvent`, `UnregisterAllEvents` to any object
- **Timer API injection**: `_injectTimerAPI()` adds `ScheduleTimer`, `ScheduleRepeatingTimer`, `CancelTimer` using `C_Timer.After` and `C_Timer.NewTicker`
- **Print API injection**: `_injectPrintAPI()` adds `Print()` method with CouchPotato-branded chat output
- **Module system**: `CP:NewModule(name)` creates module table with all APIs injected; `CP:GetModule(name, silent)` retrieves with optional error
- **SavedVariables**: Hand-rolled `deepMerge()` function merges defaults into `CouchPotatoDB.profile` and `CouchPotatoDB.char`; `db.ResetProfile()` helper for `/cp reset`
- **Slash commands**: `CP:RegisterChatCommand(cmd, handler)` sets global `SLASH_` and `SlashCmdList` directly

**Test Helper:**
- `CP._FireEvent(event, ...)` — public function for spec/helpers.lua to dispatch events directly to all callbacks without going through WoW frame system
- Enables unit testing of event handlers in Busted

**Timer Return Values:**
- `ScheduleTimer()` returns `{Cancel(), IsCancelled()}` table for proper timer cancellation
- Compatible with existing code that calls `self:CancelTimer(handle)` or `handle:Cancel()`

**API Surface Preserved:**
All production code unchanged — `CP:NewModule(name)`, `mod:RegisterEvent(event, handler)`, `mod:ScheduleTimer(fn, delay)`, `mod:Print(...)` work identically.

📌 Team update (2026-03-02T01:45:35Z): Frameworkless migration complete. All Core, UI, and spec files migrated. Mal's review approved. 70/70 tests passing. Decision consolidated into decisions.md. — consolidated by Scribe

### 2026-03-02: Controller Button Fix (GAME_PAD_ACTIVE_CHANGED Race Condition)

**Problem:** Face buttons (A/B/X/Y) stopped working after controller enabled. Right trigger opened menu and sticks worked, but face buttons did nothing.

**Root Causes:**
1. **Bug #1 (Primary)**: `Bindings:OnGamePadActiveChanged` cleared all face button bindings on `isActive=false`. The `GAME_PAD_ACTIVE_CHANGED` event fires on *every* input-source switch — including mouse moves and keypresses. So any mouse movement cleared the controller bindings, making face buttons unresponsive until the next `isActive=true` cycle.

2. **Bug #2 (Secondary)**: Multiple event handlers called `ApplyDirectBindings()` without checking `wheelOpen` flag. When the wheel was open, subsequent controller button presses triggered `GAME_PAD_ACTIVE_CHANGED(true)`, which overwrote wheel slot bindings with direct-mode spell bindings. This caused face buttons to fire spells directly (or do nothing if out of range) instead of clicking wheel slots.

3. **Bug #3 (Idempotency)**: `Radial:OnEnable()` was not idempotent. `OnControllerActivated()` called `mod:Enable()` on every `GAME_PAD_ACTIVE_CHANGED(true)`, which re-called `CreateWheelFrames()` and `InitGamePadButtonHandling()`. These created globally-named frames, causing Lua errors on duplicate names and corrupting setup.

**Fixes Applied:**
- **Bug #1**: Removed `else` branch from `OnGamePadActiveChanged`. Only `ApplyDirectBindings()` on `isActive=true` (with `wheelOpen` guard). Real deactivation is covered by `OnCVarUpdate(GamePadEnable=0)` and `OnGamePadDisconnected`.
- **Bug #2**: Added `if not self.wheelOpen then` guard before all `ApplyDirectBindings()` calls in 7 event handler locations: `OnGamePadActiveChanged`, `OnEnable`, `OnGamePadConnected`, `OnEnteringWorld`, `OnCVarUpdate`, `OnSpecChanged`, and `GamePad:OnGamePadActiveChanged`.
- **Bug #3**: Added idempotency guards to `CreateWheelFrames()` (`if self.centerFrame then return end`) and `InitGamePadButtonHandling()` (`if self.buttonFrame then return end`), matching the pattern used in `Bindings:OnEnable()`.

**Key Learnings:**
- **NEVER** perform state-clearing operations on `GAME_PAD_ACTIVE_CHANGED(isActive=false)`. This event fires on every mouse move/keypress (as documented in Loader.lua). Only use it to *activate* controller features, never to *deactivate*.
- **ALWAYS** check `wheelOpen` flag before calling `ApplyDirectBindings()` in event handlers. The wheel's transient bindings must not be clobbered by direct-mode reapplications.
- **Frame creation** in `OnEnable()` must be idempotent. Use existence checks (`if not self.frame then`) for all globally-named frames to prevent duplicate creation errors when `OnEnable()` is called multiple times.
- Combat lockdown and binding layer architecture remained untouched — all changes were event-handler-level guards.

**Test Results:** 91/91 tests passing after fixes.

### 2026-03-03: OPie-Style Stick-Based Interaction Model

**Problem:** John studied OPie addon and requested radial wheel use OPie's interaction pattern: hold right trigger to open, left stick angle selects slot, release trigger to confirm.

**Old Model (Broken):**
- Click trigger → wheel opens
- Press face buttons (A/B/X/Y) → select slots
- Click trigger again → close wheel
- Issues: Two-stage activation, requires mental mapping between button and slot position

**New Model (OPie-Style):**
1. Press and HOLD right trigger → wheel opens, OnUpdate polling starts
2. Move left stick → highlights slot based on stick angle (dead zone = 0.25)
3. Release right trigger → executes highlighted slot, closes wheel
4. L1/R1 bumpers → cycle wheels (resets highlight for new wheel)

**Implementation Changes:**

**Radial.lua:**
- Updated constants: `BUTTON_RADIUS=200` (was 120), `ICON_SIZE=64` (was 52), added `STICK_DEAD_ZONE=0.25`, `STICK_INDEX=1`
- Added `Radial.highlightedSlot` state variable
- Replaced `centerIcon` (showed warrior shield) with `selLabel` (shows highlighted slot name)
- Added `execute` functions to all INTERFACE_WHEEL_LAYOUTS slots using `btnClick()` helper
- **New functions:**
  - `GetStickAngle()` — reads C_GamePad.GetDeviceMappedState(), returns angle in degrees or nil if in dead zone
  - `AngleToSlot(angleDeg)` — OPie formula: `math.floor(((90 - angleDeg) * MAX_SLOTS / 360 + 0.5) % MAX_SLOTS) + 1`
  - `SetSlotHighlight(wheelIdx, slotIdx, state)` — gold border + 1.3x scale when highlighted
  - `UpdateSelectionLabel()` — center text shows highlighted slot name
  - `UpdateStickSelection()` — called every frame, polls stick and updates highlight
  - `StartStickPolling()` / `StopStickPolling()` — control OnUpdate loop on pollFrame
  - `OpenWheel()` — trigger press handler, shows wheel + starts polling
  - `ConfirmAndClose()` — trigger release handler, executes slot via `slotDef.execute()` or SecureActionButton click
- Updated `InitGamePadButtonHandling()` — trigger now registers for AnyDown + AnyUp, dispatches to OpenWheel/ConfirmAndClose
- Updated `ShowCurrentWheel()` — resets `highlightedSlot` and selection label on show
- Updated `HideCurrentWheel()` — calls `StopStickPolling()` first
- Updated `CycleWheelNext/Prev()` — clear highlight before changing wheels
- Added `OnEnteringWorld()` — re-applies interface layouts after world load

**Bindings.lua:**
- Simplified `ApplyWheelBindings()` — removed face button bindings (PAD1-4), only bumpers + trigger remain
- Face buttons are no longer bound during wheel mode (stick controls selection directly)
- `wheelIdx` parameter kept for API compatibility but unused

**Tests Updated:**
- `spec/bindings_spec.lua` — updated two tests to expect NO face button bindings in wheel mode, check bumpers instead
- `spec/wow_mock.lua` — added `SetScale()` and `GetScale()` to frame mock

**Key Design Decisions:**
- **OnUpdate polling:** Stick reads every frame while wheel is open (OPie pattern). No combat lockdown issues since it's read-only.
- **No SetAttribute in UpdateStickSelection:** Highlight is purely visual (border + scale), not secure binding changes.
- **execute functions:** Wheels 1-2 use `btnClick()` to click Blizzard buttons directly. Wheels 3+ click SecureActionButtons (combat-safe).
- **Dead zone:** 0.25 magnitude threshold prevents jitter, matches OPie's behavior.
- **Angle formula:** Standard math convention (0°=right, 90°=up) with clockwise slot numbering starting at top.

**Test Results:** 89/89 tests passing (2 tests updated to reflect new model).

**Benefits:**
- **One-handed operation:** Stick + trigger on same hand (no face button reaching)
- **Intuitive spatial selection:** Point at what you want
- **Faster activation:** Single trigger press+release cycle
- **Bigger wheel:** 200px radius (was 120), 64px icons (was 52) — readable from couch distance
- **Proven UX:** OPie's pattern battle-tested over 10+ years in WoW community

### 2026-03-04: Universal A/B Button Semantics

**What Changed:**
- `PAD1` (A button) now maps to `CouchPotatoConfirmBtn` when wheel is open → executes the highlighted slot + closes wheel (`ConfirmAndClose()`).
- `PAD2` (B button) now maps to `CouchPotatoCloseBtn` when wheel is open → cancels/closes without executing (`CloseWheel()`).
- Right trigger **release** (`AnyUp`) now calls `CloseWheel()` instead of `ConfirmAndClose()`. Release = cancel, A press = confirm.
- Added `Radial:CloseWheel()` — thin wrapper around `HideCurrentWheel()`, cancels without executing.
- `CouchPotatoConfirmBtn` and `CouchPotatoCloseBtn` are created in `InitGamePadButtonHandling()` as plain Buttons with `RegisterForClicks("AnyDown")`.
- `Bindings:ApplyWheelBindings()` now calls `SetOverrideBindingClick` for PAD1 and PAD2 (added alongside existing bumper and trigger overrides).
- `ClearOverrideBindings` in `RestoreDirectBindings` already clears all overrides including PAD1/PAD2 — no extra code needed.
- PAD3 and PAD4 remain unbound during wheel mode; stick still controls selection.

**Key Design Points:**
- PAD1/PAD2 are ONLY bound inside `ApplyWheelBindings` (called from `OpenWheel` → `ShowCurrentWheel`). They are never bound when wheel is closed — WoW's normal bindings take over.
- `ClearOverrideBindings` on the owner frame clears PAD1 + PAD2 overrides automatically on both confirm and close paths (both call `HideCurrentWheel` → `RestoreDirectBindings`).
- Trigger release no longer executes — this prevents accidental execution when releasing after deciding to cancel.

**Test Results:** 94/94 tests passing (5 new tests added, 1 test description + 2 assertions updated).

