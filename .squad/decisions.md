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
