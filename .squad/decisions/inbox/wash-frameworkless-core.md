# Decision: Frameworkless Core — Remove Ace3/LibStub Dependencies

**Author:** Wash (Lua Developer)  
**Date:** 2026-03-01  
**Status:** Implemented

## Decision

Replace all Ace3 and LibStub dependencies in `CouchPotato/CouchPotato.lua` with a hand-rolled frameworkless implementation. Remove mixin library arguments from all `CP:NewModule()` calls in Core modules.

## Rationale

- **Zero external dependencies**: Eliminates ~50KB of Ace3 library code and LibStub stub management
- **Full control**: Custom event dispatch, timer, and module systems tailored exactly to CouchPotato's needs
- **Test-friendly**: Built-in `CP._FireEvent()` helper for unit testing event handlers without WoW frame system
- **Simpler deployment**: No .pkgmeta externals, no stub vs. real library management
- **Preserved API surface**: All production module code unchanged — `CP:NewModule()`, `RegisterEvent()`, `ScheduleTimer()`, `Print()` work identically

## Key Design Decisions

### Single Event Frame Architecture
- One `CP._mainFrame` handles ALL event registration
- `CP._eventCallbacks[event]` table stores `[{obj, fn}, ...]` for each event
- Frame's `OnEvent` handler dispatches to all registered callbacks with snapshot pattern (safe iteration during modification)

### API Injection Pattern
Three factory functions inject APIs onto objects:
- `_injectEventAPI(obj)` → `RegisterEvent`, `UnregisterEvent`, `UnregisterAllEvents`
- `_injectTimerAPI(obj)` → `ScheduleTimer`, `ScheduleRepeatingTimer`, `CancelTimer`
- `_injectPrintAPI(obj)` → `Print(...)` with CouchPotato branding

Applied to both `CP` itself and all modules created via `CP:NewModule(name)`.

### SavedVariables — deepMerge Pattern
- Hand-rolled `deepMerge(target, source)` recursively merges defaults into `CouchPotatoDB.profile` and `CouchPotatoDB.char`
- `CP.db.ResetProfile()` helper clears profile and re-merges defaults
- No AceDB profile switching (not needed for CouchPotato)

### Timer Return Values
- `ScheduleTimer()` returns `{Cancel(), IsCancelled()}` table for proper cancellation
- Compatible with both `self:CancelTimer(handle)` and `handle:Cancel()` patterns

### Test Helper — CP._FireEvent
- Public function for `spec/helpers.lua` to dispatch events directly to all callbacks
- Bypasses WoW frame system for fast Busted unit testing
- Same snapshot iteration pattern as production `OnEvent` handler

## Files Changed

### Complete Rewrite
- **CouchPotato/CouchPotato.lua** — 477 lines of pure Lua, no external dependencies

### Module Updates (one-line changes each)
- **Core/GamePad.lua** — `CP:NewModule("GamePad")` (removed "AceEvent-3.0", "AceTimer-3.0")
- **Core/Bindings.lua** — `CP:NewModule("Bindings")` (removed "AceEvent-3.0")
- **Core/Specs.lua** — `CP:NewModule("Specs")` (removed "AceEvent-3.0")
- **Core/BlizzardFrames.lua** — `CP:NewModule("BlizzardFrames")` (removed "AceEvent-3.0")

### No Change Required
- **Core/LED.lua** — Already `CP:NewModule("LED")` with no mixins

## Lifecycle Behavior

### Initialization (ADDON_LOADED)
- `CP._eventCallbacks["ADDON_LOADED"]` pre-populated with core handler
- Calls `CP:_OnAddonLoaded()` when `addonName == "CouchPotato"`
- Initializes SavedVariables via `_initDB()`, registers slash commands

### Enable (PLAYER_LOGIN)
- `CP._eventCallbacks["PLAYER_LOGIN"]` pre-populated with core handler
- Calls `CP:_OnPlayerLogin()` on login
- Registers core events (`PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_DISABLED/ENABLED`)
- Enables all modules via `mod:Enable()` loop
- Notifies modules of `CONTROLLER_CONNECTED` if gamepad detected

## Module API Contract (Unchanged)

All existing module code works without modification:

```lua
local CP = CouchPotato
local MyMod = CP:NewModule("MyModule")

function MyMod:OnEnable()
    self:RegisterEvent("SOME_EVENT")
    self:ScheduleTimer("DelayedTask", 2.0)
end

function MyMod:SOME_EVENT(event, ...)
    self:Print("Event fired")
end

function MyMod:DelayedTask()
    self:Print("Timer fired")
end
```

## Consequences

### Positive
- **Smaller footprint**: ~50KB removed (Ace3 libraries)
- **Faster tests**: `CP._FireEvent()` enables direct event testing
- **Simpler codebase**: No LibStub, no .pkgmeta externals
- **Full control**: Can optimize event dispatch, timer handling, etc.

### Neutral
- **Maintenance responsibility**: We now own all framework code (but it's ~150 lines total)
- **No AceDB profile switching**: Not needed for CouchPotato (char-specific layouts already in `db.char`)

### Risks Mitigated
- **API compatibility**: All production APIs preserved exactly
- **InCombatLockdown guards**: All existing guards remain untouched
- **Module isolation**: Each module still gets its own event/timer/print APIs
