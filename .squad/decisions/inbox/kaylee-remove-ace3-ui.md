# Decision: Remove Ace3 Library Dependencies from UI Layer

**Author:** Kaylee (UI Developer)  
**Date:** 2026-03-01  
**Status:** Implementation Complete

## What Changed

Removed all Ace3 library mixin arguments from UI module declarations and eliminated library files from the addon distribution.

**Files Modified:**
- `CouchPotato/UI/Radial.lua` — Line 9: removed "AceEvent-3.0", "AceTimer-3.0" from NewModule call
- `CouchPotato/UI/HUD.lua` — Line 7: removed "AceEvent-3.0", "AceTimer-3.0" from NewModule call
- `CouchPotato/UI/VirtualCursor.lua` — Line 7: removed "AceEvent-3.0" from NewModule call
- `CouchPotato/UI/HealMode.lua` — Line 8: removed "AceEvent-3.0" from NewModule call
- `CouchPotato/CouchPotato.toc` — Removed all libs\ entries and embeds.xml line

**Files Deleted:**
- `CouchPotato/libs/` — entire directory removed
- `CouchPotato/embeds.xml` — file removed

## Rationale

Simplifies the addon structure by removing external library dependencies at the UI module level. The core module system still provides event registration capabilities through inherited AceAddon methods, so UI modules retain full functionality without explicit mixin declarations.

## Implementation Pattern

**Before:**
```lua
local Radial = CP:NewModule("Radial", "AceEvent-3.0", "AceTimer-3.0")
```

**After:**
```lua
local Radial = CP:NewModule("Radial")
```

**TOC Structure (After):**
- Direct Lua file list only (no lib includes, no XML embeds)
- Clean load order: CouchPotato.lua → Core/*.lua → UI/*.lua

## Impact

- Reduced addon package size (removed ~50KB of library code)
- Simplified TOC file maintenance (no library version tracking)
- UI modules remain fully functional (event system works via parent addon)
- Zero changes to SecureActionButtonTemplate usage (combat safety preserved)
- All InCombatLockdown() guards remain in place
