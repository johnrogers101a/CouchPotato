# Team Decisions

Canonical decisions made by the CouchPotato team. Append-only. Maintained by Scribe.

<!-- Decisions appended below by Scribe. Format: ### {timestamp}: {topic} -->

## Architecture Foundation Decisions

**Author:** Mal (Lead)  
**Date:** 2026-03-01  
**Status:** Accepted

### Decision 1: Two-Component System (Loader + Main Addon)

**Decision:** Split the addon into two components:
- `CouchPotato_Loader`: Always enabled, ~150 lines, detects gamepad
- `CouchPotato`: LoadOnDemand: 1, full UI loaded only when needed

**Rationale:**
- **Memory efficiency**: Keyboard/mouse players don't load 1000+ lines of controller UI code
- **Fast startup**: Loader is tiny and runs instantly on login
- **Dynamic loading**: `C_AddOns.LoadAddOn("CouchPotato")` triggers on first gamepad input
- **Clean separation**: Loader is stable; main addon can iterate rapidly

**Consequences:**
- Two TOC files to maintain
- Loader must handle edge cases (addon disabled, missing files)
- SavedVariables split: `CouchPotatoLoaderDB` and `CouchPotatoDB`

### Decision 2: Ace3 Framework

**Decision:** Use Ace3 libraries: AceAddon-3.0, AceDB-3.0, AceEvent-3.0, AceConsole-3.0, AceTimer-3.0

**Rationale:**
- **Lifecycle management**: OnInitialize/OnEnable/OnDisable hooks at proper timing
- **Module system**: Clean NewModule pattern for GamePad, Bindings, LED, Radial, etc.
- **Profile support**: AceDB gives us profile switching and per-character data free
- **Event cleanup**: AceEvent auto-unregisters on disable, prevents leaks
- **Battle-tested**: Ace3 powers hundreds of major addons

**Consequences:**
- ~50KB of library code embedded (acceptable)
- Learning curve for contributors unfamiliar with Ace3
- Must use Ace3 patterns consistently across modules

### Decision 3: Functional Lib Stubs + .pkgmeta for Production

**Decision:** Ship functional Ace3 stubs in `libs/` for development/testing. Use `.pkgmeta` externals for production packaging.

**Rationale:**
- **Testability**: Busted tests can run without WoW environment using stubs
- **Development**: No external downloads needed to hack on the addon
- **Production**: BigWigs packager replaces stubs with real libraries automatically
- **Size**: Stubs are ~15KB vs ~50KB real libraries; production gets full power

**Consequences:**
- Must maintain stub compatibility with real Ace3 API surface
- Stubs must be clearly marked (header comments)
- CI must verify stubs work for test suite

### Decision 4: SetOverrideBinding (Never SetBinding)

**Decision:** All controller bindings use `SetOverrideBinding`, never `SetBinding`.

**Rationale:**
- **Keyboard restore**: Override bindings are temporary; original keybinds restore on `/reload`
- **Controller disconnect**: When gamepad disconnects, overrides clear automatically
- **No pollution**: We never touch the user's permanent keybind settings
- **Combat safe**: SetOverrideBinding works in combat (for existing frames)

**Consequences:**
- Bindings module must track owner frame for all overrides
- Must call `ClearOverrideBindings(owner)` on disable
- Cannot create new bindings during combat (use pre-created frames)

### Decision 5: Pre-Create SecureActionButton Pool at Load Time

**Decision:** Create all 96 SecureActionButtonTemplate frames (8 wheels × 12 slots) during addon load, before combat.

**Rationale:**
- **Combat lockdown**: `CreateFrame("Button", nil, nil, "SecureActionButtonTemplate")` is FORBIDDEN during combat
- **No lag**: Pre-creation means zero frame creation during gameplay
- **Dynamic binding**: We rebind buttons to different actions, not create/destroy
- **Memory**: 96 buttons is trivial (~50KB)

**Consequences:**
- Initial load slightly slower (imperceptible)
- Must have clear button pooling/recycling logic
- Action changes use SetAttribute, which IS allowed for pre-existing frames

### Decision 6: Per-Character Wheel Layouts via AceDB Char Scope

**Decision:** Store `currentWheel` and `wheelLayouts` in `db.char`, not `db.profile`.

**Rationale:**
- **Spec-specific**: A Paladin's wheel layout differs completely from a Mage's
- **Alt-friendly**: Each character gets independent layouts without profile switching
- **Profile for prefs**: UI scale, alpha, vibration settings shared via profile
- **Char for state**: Current wheel, layouts, healer mode are character-specific

**Consequences:**
- Users cannot easily copy layouts between characters (future feature: export/import)
- Clear documentation needed on what's profile vs char scope

### Decision 7: Module System via AceAddon NewModule

**Decision:** Each system (GamePad, Bindings, LED, Radial, etc.) is an AceAddon module.

**Rationale:**
- **Clean separation**: Each module has its own file, OnEnable, OnDisable
- **Independent lifecycle**: Modules can be disabled individually for debugging
- **Shared access**: All modules get `CP` reference, can call each other
- **Event isolation**: Each module registers only the events it needs

**Consequences:**
- Consistent pattern across all files: `local MyMod = CP:NewModule("Name", ...)`
- Custom event system (`CP:NotifyModules`) for CouchPotato-specific events
- Modules must not assume order of initialization

## Backend Implementation Decisions

**Author:** Wash (Lua Developer)  
**Date:** 2026-03-01  
**Status:** Implementation Complete

### SetOverrideBinding Pattern (Non-Destructive Bindings)

**Decision:** Use `SetOverrideBinding()` exclusively for all controller bindings; never call `SetBinding()` or `SaveBindings()`.

**Rationale:**
- Override bindings sit "on top" of saved keyboard bindings
- `ClearOverrideBindings(ownerFrame)` instantly restores all original keyboard bindings
- Zero risk of corrupting user's keyboard setup
- No SavedVariables needed for bindings

**Implementation:**
- `Bindings.lua` creates a persistent `ownerFrame`
- All bindings registered to this frame
- On controller disconnect: single `ClearOverrideBindings()` call restores everything

### LoadOnDemand Architecture

**Decision:** Split into always-on loader (CouchPotato_Loader) and load-on-demand main addon (CouchPotato).

**Rationale:**
- Minimizes performance impact when controller not in use
- Loader is ~180 lines, negligible memory footprint
- Main addon only loads when gamepad detected
- Follows WoW best practices for optional UI

**Implementation:**
- Loader: registers 6 events, checks `C_GamePad.IsEnabled()`, calls `C_AddOns.LoadAddOn("CouchPotato")`
- Main addon: TOC has `LoadOnDemand: 1`, uses Ace3 for module system

### Combat Lockdown Deferral

**Decision:** All binding changes check `InCombatLockdown()` and defer operations using pending flags.

**Rationale:**
- WoW restricts secure frame operations during combat
- Attempting binding changes in combat throws errors
- Deferral ensures operations complete safely after combat

**Implementation:**
- `pendingApply` / `pendingClear` flags set when combat blocks operation
- `PLAYER_REGEN_ENABLED` event handler processes pending operations

### LED Spell School Mapping

**Decision:** Map LED colors to WoW spell school bitmasks; use lowest set bit for multi-school spells.

**Rationale:**
- Spell schools are core WoW data, stable across patches
- Physical=1, Holy=2, Fire=4, Nature=8, Frost=16, Shadow=32, Arcane=64
- Multi-school spells (e.g., Frostfire=20) → use primary school (Frost=16)

**Implementation:**
- `LED:GetSchoolFromMask()` iterates bits 1→64 to find lowest set
- Color table maps each school to thematic RGB values
- Fallback to class color when no spell context

### Module Independence (Optional Dependencies)

**Decision:** All inter-module calls use `CP:GetModule("Name", true)` with nil-check.

**Rationale:**
- Modules can fail to load without cascading failures
- Enables phased implementation (not all modules ready simultaneously)
- Ace3 pattern for optional module dependencies

**Implementation:**
```lua
local LED = CP:GetModule("LED", true)
if LED then
    LED:UpdateForCurrentSpec()
end
```

## UI Implementation Decisions

**Author:** Kaylee (UI Developer)  
**Date:** 2026-03-01  
**Status:** Implementation Complete

### Radial Wheel Architecture

**Decision:** Use SecureActionButtonTemplate for all 96 radial slots (8 wheels × 12 slots)

**Rationale:**
- Combat safety: SecureActionButtonTemplate buttons remain functional during combat without tainting
- Parent frames (wheel containers) are regular frames — can show/hide freely without combat restrictions
- All frame creation happens at OnEnable (before first combat) to avoid combat lockdown issues

**Trade-offs:**
- More complex initial setup (96 buttons pre-created)
- Higher memory footprint (all frames exist even when hidden)
- **Benefit:** Zero combat restrictions on wheel visibility, robust in all game states

### Peek vs Lock Trigger Mechanics

**Decision:** Analog trigger depth controls wheel visibility with two thresholds
- Peek threshold: 0.35 (light pull) — shows wheel briefly (2s timeout)
- Lock threshold: 0.75 (full pull) — locks wheel open until release

**Rationale:**
- BG3-inspired interaction pattern feels natural on controller
- OnUpdate polling at 20Hz (50ms) detects threshold crossings accurately
- Separate peek/lock states allow "glance at options" vs "committed selection"

### Blizzard Frame Hiding Strategy

**Decision:** Queue hide/show operations if attempted during combat

**Rationale:**
- InCombatLockdown() protects all Blizzard frame operations from taint
- Event unregistration (e.g., ACTIONBAR_PAGE_CHANGED) prevents auto-re-showing
- Queueing via PLAYER_REGEN_ENABLED ensures deferred execution after combat

**Implementation detail:**
- Two flags: `pendingHide` and `pendingRestore`
- OnCombatLeave handler processes queued operations

### HUD Scaling for "Couch Distance"

**Decision:** All HUD elements scaled ~25% larger than default WoW UI

**Rationale:**
- Target audience: players on TV 8-10 feet away from screen
- GameFontNormalLarge minimum, cast bar 400×50px (vs default 195×13px)
- Semi-transparent dark backgrounds (alpha 0.7) for contrast without obscuring gameplay

**Specific values:**
- Health bar: 280×40px at bottom-left (40, 60)
- Cast bar: 400×50px centered at y=-150
- Target frame: 320×60px at top-center

### VirtualCursor Frame Detection

**Decision:** Simple ordered list of known UI frame names (GossipFrame, QuestFrame, etc.)

**Rationale:**
- No comprehensive API for "all interactable frames" in WoW
- Hard-coded list covers 95% of common UI interactions
- Spatial navigation (up/down/left/right) simplified to linear cycling for initial implementation

### HealMode Party Frame Integration

**Decision:** Detect healer addon frames in priority order: Cell > Grid2 > VuhDo > CompactPartyFrames

**Rationale:**
- Healer players typically use specialized addons with better frame layouts
- Fallback to default CompactPartyFrames ensures functionality without addons
- Overlay cursor matches detected frame dimensions for visual coherence

### Power Bar Auto-Coloring

**Decision:** Use WoW's built-in `PowerBarColor[powerType]` table for resource bar colors

**Rationale:**
- Consistent with player expectations (mana=blue, energy=yellow, rage=red)
- Automatically handles all 18+ power types (including new ones in future patches)
- No maintenance burden for color definitions

## Test Coverage Decisions

**Author:** Zoe (Tester/QA)  
**Date:** 2026-03-01  
**Status:** Test suite complete, ready for first run

### Comprehensive Mock Layer

**Decision:** Implement functional WoW API mocks in `spec/wow_mock.lua` for all critical systems

**Coverage:**
- **C_GamePad API**: IsEnabled, GetActiveDeviceID, SetLedColor, SetVibration
- **C_AddOns API**: LoadAddOn, IsAddOnLoaded, EnableAddOn, DisableAddOn
- **C_Timer API**: After, NewTicker with callbacks
- **C_Spell API**: GetSpellInfo with school masks
- **CreateFrame**: Full frame mock with SetAttribute, RegisterEvent, Show/Hide
- **Override Bindings**: SetOverrideBinding, ClearOverrideBindings with lockdown enforcement
- **Ace3 Libraries**: Functional mocks for all 5 core libraries

**Rationale:**
- Enables Busted tests to run without WoW client
- Captures critical combat lockdown rules
- Fast iteration on logic without WoW startup

### Test Suite Structure

**Modules tested:**
- **GamePad** (spec/gamepad_spec.lua): Controller detection, vibration, LED
- **Loader** (spec/loader_spec.lua): Addon loading mechanics
- **Radial** (spec/radial_spec.lua): Wheel visibility, slot binding
- **Bindings** (spec/bindings_spec.lua): Combat safety, pending operations
- **LED** (spec/led_spec.lua): Spell school color mapping

**Test helpers:**
- `fireEvent()`: Dispatch to AceEvent + frame listeners
- `resetMocks()`: Clear state between tests
- `connectController()` / `disconnectController()`: Simulate hardware
- `assertBinding()` / `assertNoBindings()`: Validate override bindings
- `assertColorEqual()`: Float tolerance for RGB comparison

### Known Test Gaps

**In-game testing required for:**
- Real DualSense vibration feedback
- Real LED color accuracy
- SecureActionButton actual spell casting
- Frame rendering and visual appearance
- SavedVariables persistence across sessions
- Multiple controller edge cases

## Frameworkless Migration Decisions

**Date:** 2026-03-02  
**Status:** Complete & Approved

### 2026-03-02: Frameworkless Core Implementation (consolidated)

**By:** Wash, Kaylee, Zoe, Mal

**What:**
Replaced all Ace3 and LibStub dependencies with a hand-rolled frameworkless core. Core framework rewritten as 477 lines of pure Lua. All module files updated to remove mixin arguments from `CP:NewModule()` calls. UI layer, test layer, and spec files migrated to use new frameworkless API. All 16 changed files reviewed and approved.

**Why:**
- Eliminates ~50KB of external library code (Ace3 libraries)
- Gives full control over event dispatch, timer, and module systems
- Simplifies deployment (no .pkgmeta externals, no stub management)
- Preserves 100% of production API surface — all existing module code works unchanged
- Enables faster unit testing via `CP._FireEvent()` helper
- All 7 critical combat safety guards verified intact
- SecureActionButtonTemplate preserved for all 96 radial buttons

**Implementation:**
- **CouchPotato/CouchPotato.lua** — Complete rewrite with single event frame, API injection pattern, deepMerge for SavedVariables
- **Core modules** — GamePad, Bindings, Specs, BlizzardFrames: removed mixin args (1-line changes each)
- **UI modules** — Radial, HUD, VirtualCursor, HealMode: removed mixin args (1-line changes each)
- **TOC** — Removed all libs\ entries and embeds.xml line
- **Test layer** — spec/wow_mock.lua: removed ~200 lines of Ace3 mocks. spec/helpers.lua: rewrote to use CP._FireEvent(). All spec files updated with new bootstrap pattern.
- **Files deleted** — CouchPotato/libs/ and CouchPotato/embeds.xml

**Key design:**
- Single `CP._mainFrame` handles all event registration
- `_injectEventAPI()`, `_injectTimerAPI()`, `_injectPrintAPI()` apply to all modules
- Timer return values: `{Cancel(), IsCancelled()}` for safe cancellation
- CP._FireEvent() for test dispatch (snapshot iteration pattern)
- Event callbacks stored as `[{obj, fn}, ...]` arrays per event name

**Validation:**
- ✅ All InCombatLockdown() guards intact (7/7 critical functions)
- ✅ Event dispatch correctness verified
- ✅ Timer cancellation mechanics verified
- ✅ Module lifecycle flow correct
- ✅ TOC file ordering correct
- ✅ Zero Ace3 references remaining
- ✅ All 70 tests passing

**Verdict:** APPROVED — Ship it.
# Decision: GAME_PAD_ACTIVE_CHANGED Event Handling Pattern

**Author:** Wash (Lua Developer)  
**Date:** 2026-03-02  
**Status:** Implemented

## Problem

Face buttons (A/B/X/Y) stopped working after controller was enabled. The right trigger opened the radial menu and sticks controlled movement, but pressing A/B/X/Y did nothing.

## Root Causes

Three distinct bugs caused this failure:

### Bug #1: Clearing Bindings on Every Input Switch (Primary Bug)

`Bindings:OnGamePadActiveChanged` was clearing all face button override bindings on `isActive=false`. The `GAME_PAD_ACTIVE_CHANGED` event fires on *every* input-source switch — including every mouse move or keypress. The Loader.lua contains an explicit warning about this:

> "Fires whenever WoW switches between gamepad/mouse/keyboard input modes — including on every mouse move or keypress. Only use it to *load* the addon; never call RestoreKeyboardMode() here."

The Bindings module violated this principle by calling `ClearControllerBindings()` on every `isActive=false`, which cleared all face button bindings whenever the user touched the mouse. Buttons remained unresponsive until the next `isActive=true` cycle.

### Bug #2: Direct Bindings Clobbering Wheel Bindings

Multiple event handlers called `ApplyDirectBindings()` without checking the `wheelOpen` flag:
- `Bindings:OnGamePadActiveChanged(isActive=true)`
- `Bindings:OnEnable()` 
- `Bindings:OnGamePadConnected()`
- `Bindings:OnEnteringWorld()`
- `Bindings:OnCVarUpdate(GamePadEnable=1)`
- `Bindings:OnSpecChanged()`
- `GamePad:OnGamePadActiveChanged(isActive=true)`

When the wheel was open (`Bindings.wheelOpen == true`), `ApplyWheelBindings()` set face buttons → wheel slot buttons. But any subsequent controller button press fired `GAME_PAD_ACTIVE_CHANGED(true)`, triggering these handlers to overwrite the wheel slot bindings with direct-mode spell bindings. This caused face buttons to fire spells directly (or do nothing if out of range) instead of clicking wheel slots.

### Bug #3: Non-Idempotent Frame Creation

`Radial:OnEnable()` called `CreateWheelFrames()` and `InitGamePadButtonHandling()` unconditionally. These created globally-named frames (`CouchPotatoRadialCenter`, `CouchPotatoWheel1`…`CouchPotatoWheel8`, `CouchPotatoRadialInput`). Calling `CreateFrame` with duplicate global names throws a Lua error in WoW, causing subsequent setup steps to be skipped or run with corrupted state.

Since `OnControllerActivated()` calls `mod:Enable()` on every `GAME_PAD_ACTIVE_CHANGED(true)`, frame creation errors occurred on every input switch.

## Decision

### Fix #1: Remove `else` Branch from `OnGamePadActiveChanged`

**Change:** Remove the `ClearControllerBindings()` call on `isActive=false`.

**Rationale:** 
- `GAME_PAD_ACTIVE_CHANGED(isActive=false)` fires on every mouse move/keypress and is NOT a signal of controller disconnection.
- Real deactivation is properly covered by:
  - `OnCVarUpdate(GamePadEnable=0)` — user disabled controller in settings
  - `OnGamePadDisconnected` — hardware disconnect

**Implementation:**
```lua
function Bindings:OnGamePadActiveChanged(event, isActive)
    if isActive and not self.wheelOpen then
        self:ApplyDirectBindings()
    end
    -- Bug fix: Do NOT clear bindings on isActive=false.
    -- Real deactivation covered by OnCVarUpdate and OnGamePadDisconnected.
end
```

### Fix #2: Add `wheelOpen` Guards to All Event Handlers

**Change:** Add `if not self.wheelOpen then` guard before calling `ApplyDirectBindings()` in all 7 event handler locations.

**Rationale:**
- When the wheel is open, face buttons MUST remain bound to wheel slot clicks, not direct spell casts.
- `ApplyDirectBindings()` clears all overrides and sets direct-mode bindings, which clobbers wheel bindings.
- The `OnUpdateBindings` handler already had this guard and worked correctly.

**Implementation:**
Applied guard to:
1. `Bindings:OnGamePadActiveChanged(isActive=true)`
2. `Bindings:OnEnable()` (the `if C_GamePad.IsEnabled() then` block)
3. `Bindings:OnGamePadConnected()`
4. `Bindings:OnEnteringWorld()`
5. `Bindings:OnCVarUpdate(GamePadEnable=1)`
6. `Bindings:OnSpecChanged()`
7. `GamePad:OnGamePadActiveChanged(isActive=true)` (before calling `Bindings:ApplyControllerBindings()`)

### Fix #3: Add Idempotency Guards to Frame Creation

**Change:** Add existence checks to prevent duplicate frame creation.

**Rationale:**
- `OnEnable()` can be called multiple times (on every `GAME_PAD_ACTIVE_CHANGED(true)` via `OnControllerActivated()`).
- WoW throws errors when creating frames with duplicate global names.
- Mirrors the pattern already used in `Bindings:OnEnable()` (`if not self.ownerFrame then`).

**Implementation:**
```lua
function Radial:CreateWheelFrames()
    -- Guard: prevent duplicate frame creation
    if self.centerFrame then return end
    -- ... rest of function
end

function Radial:InitGamePadButtonHandling()
    -- Guard: prevent duplicate frame creation
    if self.buttonFrame then return end
    -- ... rest of function
end
```

## Consequences

### Positive
- Face buttons now work reliably after controller activation
- Wheel slot bindings are preserved during wheel-open state
- No frame creation errors on repeated `OnEnable()` calls
- All existing tests pass (91/91)
- Zero changes to combat lockdown guards or binding layer architecture

### Negative
- None identified

## Alternatives Considered

### Alternative 1: Debounce `GAME_PAD_ACTIVE_CHANGED`
**Rejected:** Would add complexity and latency. The root problem is architectural misuse of the event, not firing frequency.

### Alternative 2: Track `isActive` State and Only Clear on Transitions
**Rejected:** Still violates the principle that `isActive=false` should not trigger state clearing. Mouse moves are not controller deactivation.

### Alternative 3: Remove `GAME_PAD_ACTIVE_CHANGED` Handler Entirely
**Rejected:** The event is needed for LED updates and ensuring bindings are applied when controller becomes active.

## Validation

- All 91 Busted tests passing
- Manual testing confirmed face buttons work in both direct and wheel modes
- No frame creation errors in multiple Enable/Disable cycles
- Combat lockdown guards verified intact
- `GetBindingAction` queries show correct binding layer state

## Pattern for Future Development

**Event Handler Pattern for `GAME_PAD_ACTIVE_CHANGED`:**
```lua
function Module:OnGamePadActiveChanged(event, isActive)
    if isActive then
        -- Safe to ACTIVATE features here
        -- Always check wheelOpen before ApplyDirectBindings
    end
    -- NEVER deactivate features on isActive=false
    -- Use OnGamePadDisconnected and OnCVarUpdate instead
end
```

**Frame Creation Pattern:**
```lua
function Module:CreateFrames()
    -- Always guard with existence check
    if self.mainFrame then return end
    
    self.mainFrame = CreateFrame("Frame", "GlobalName", UIParent)
    -- ... rest of setup
end
```

## References

- `CouchPotato_Loader/Loader.lua` — comments on `GAME_PAD_ACTIVE_CHANGED` behavior
- `CouchPotato/Core/Bindings.lua` — all seven event handlers modified
- `CouchPotato/Core/GamePad.lua` — wheelOpen check added
- `CouchPotato/UI/Radial.lua` — idempotency guards added
- `spec/bindings_spec.lua` — existing tests validate fix
