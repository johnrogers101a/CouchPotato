# Project Context

- **Owner:** John Rogers
- **Project:** CouchPotato — a WoW addon that detects gamepad input and dynamically loads a BG3-style radial-wheel controller UI
- **Stack:** Lua, WoW Addon API (TOC, XML, C_GamePad, taint/combat lockdown testing)
- **Created:** 2026-03-01

## Learnings

### 2026-03-01: Complete Test Suite Built
- **Mock Architecture**: Built comprehensive WoW API mock layer (spec/wow_mock.lua) simulating C_GamePad, C_AddOns, C_Timer, C_Spell, frame system, combat lockdown, override bindings, and full Ace3 library stack
- **Mock State Management**: All mocks include test helper methods (_SimulateConnect, _Reset, _FireEvent, etc.) to control state during tests; helpers.resetMocks() clears all state between tests
- **Combat Safety Testing**: Critical tests verify SetOverrideBinding/ClearOverrideBindings NEVER called during combat (wraps functions to detect taint violations)
- **Functional Mocks vs Stubs**: CreateFrame returns fully functional frame objects with working SetAttribute/GetAttribute (critical for SecureActionButton testing); C_GamePad tracks actual LED color state; C_Timer tracks scheduled callbacks
- **Event Simulation**: helpers.fireEvent() dispatches to both AceEvent-3.0 handlers and raw CreateFrame event listeners (Loader uses raw frames, not AceEvent)
- **Test Coverage**: 
  - gamepad_spec.lua: detection, vibration patterns, LED color setting, GAME_PAD_ACTIVE_CHANGED event handling
  - loader_spec.lua: C_AddOns mechanics (LoadAddOn, IsAddOnLoaded, EnableAddOn/DisableAddOn), gamepad detection logic
  - radial_spec.lua: wheel frame creation (8 wheels × 12 slots), visibility, cycling (wrap-around), peek vs lock, SetSlot combat blocking, SecureActionButton attributes
  - bindings_spec.lua: ApplyControllerBindings/ClearControllerBindings, combat queueing (pendingApply/pendingClear flags), PLAYER_REGEN_ENABLED post-combat execution, combat taint detection
  - led_spec.lua: spell school color mapping (Fire/Frost/Shadow/Holy/Nature/Arcane), multi-school spell handling (lowest bit), SetColorForSpell by spellID
- **Test Patterns Used**:
  - before_each: reset mocks, bootstrap addon, create fresh DB, load/enable modules
  - describe nesting: module → feature → edge cases
  - assertion helpers: assertBinding(), assertNoBindings(), assertColorEqual() for float comparison
  - error detection: assert.has_no.errors() wraps calls that should never crash
- **Edge Cases Covered**:
  - Combat lockdown violations (bindings, SetSlot)
  - Controller connect/disconnect sequences
  - Invalid wheel/slot indices
  - Unknown spell IDs and patterns
  - Multi-school spell color selection
  - Wheel cycling wrap-around (8→1, 1→8)
  - LED disabled state
  - Post-combat queued operations
- **Not Covered (Requires In-Game Testing)**:
  - Actual trigger axis analog values from real DualSense hardware
  - Real SecureActionButton click-through behavior in combat
  - Actual frame rendering (Show/Hide visual state)
  - Real C_GamePad.SetVibration hardware response
  - True spell cast events from WoW client (UNIT_SPELLCAST_SUCCEEDED with real combat log data)
  - SavedVariables serialization/persistence across sessions
  - TOC LoadOnDemand behavior with real WoW addon loader

<!-- Append new learnings below. Each entry is something lasting about the project. -->
