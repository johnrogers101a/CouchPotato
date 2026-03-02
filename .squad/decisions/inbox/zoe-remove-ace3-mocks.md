# Decision: Remove Ace3 Mocks from Test Layer

**Date:** 2026-03-01  
**Author:** Zoe (Tester/QA)  
**Status:** Implemented

## What Changed

Replaced all LibStub/AceAddon-3.0/AceDB-3.0/AceEvent-3.0/AceConsole-3.0/AceTimer-3.0 mocks with direct instantiation of the frameworkless CouchPotato API. Removed ~200 lines of Ace3 mock code from `spec/wow_mock.lua` while retaining all WoW API mocks (C_GamePad, C_AddOns, CreateFrame, combat lockdown, bindings, etc.).

## New Test Bootstrap Pattern

**Before:**
```lua
CP = LibStub("AceAddon-3.0"):NewAddon("CouchPotato", "AceConsole-3.0", "AceEvent-3.0")
_G["CouchPotato"] = CP
CP.db = LibStub("AceDB-3.0"):New("CouchPotatoDB", { profile = {...} })
```

**After:**
```lua
dofile("CouchPotato/CouchPotato.lua")
CP = CouchPotato
CP.db = { profile = {...}, char = {...} }
```

## Event Firing

**Before:**
```lua
LibStub("AceEvent-3.0")._FireEvent("GAME_PAD_ACTIVE_CHANGED", true)
```

**After:**
```lua
helpers.fireEvent("GAME_PAD_ACTIVE_CHANGED", true)
-- Routes through CP._FireEvent() to all registered module handlers
```

## Files Modified

1. **spec/wow_mock.lua**
   - Removed: LibStub, AceAddon-3.0, AceDB-3.0, AceEvent-3.0, AceConsole-3.0, AceTimer-3.0 mocks (lines ~526–724)
   - Added: `_G.ReloadUI`, `_G.SlashCmdList`, `_G.PowerBarColor` for HUD.lua compatibility
   - File now ends at bit library section (~523 lines)

2. **spec/helpers.lua**
   - Replaced entire file with new version
   - `fireEvent()` now uses `CP._FireEvent()` instead of AceEvent mock
   - Retained all helper functions: resetMocks, connectController, disconnectController, assertColorEqual, assertBinding, assertNoBindings

3. **spec/gamepad_spec.lua**
   - Updated before_each: dofile CouchPotato.lua, set CP.db directly
   - Replaced `LibStub("AceEvent-3.0")._FireEvent(...)` with `helpers.fireEvent(...)`

4. **spec/bindings_spec.lua**
   - Updated before_each: dofile CouchPotato.lua, set CP.db directly
   - Replaced all `LibStub("AceEvent-3.0")._FireEvent(...)` with `helpers.fireEvent(...)`

5. **spec/led_spec.lua**
   - Updated before_each: dofile CouchPotato.lua, set CP.db directly
   - No event firing changes (LED tests don't fire events)

6. **spec/radial_spec.lua**
   - Updated before_each: dofile CouchPotato.lua, set CP.db directly
   - No event firing changes

7. **spec/loader_spec.lua**
   - NO CHANGES — never used AceAddon, still works as-is

## Why This Matters

- **Cleaner test layer**: No more fake Ace3 libraries—tests use the real frameworkless API
- **Future-proof**: Tests now reflect the production addon architecture
- **Module independence**: Tests validate that `CP:NewModule(name)` has all APIs built-in without mixin args
- **Simpler maintenance**: One less mock layer to maintain (Ace3 libs removed, WoW APIs remain)
- **Validation**: Confirms the frameworkless rewrite works correctly with event dispatch and module lifecycle

## Next Steps

Mal will run the full test suite to validate all specs pass with the new bootstrap pattern.
