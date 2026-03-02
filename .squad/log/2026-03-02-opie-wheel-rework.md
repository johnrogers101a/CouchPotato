# Session Log: OPie Wheel Rework
**Date:** 2026-03-02  
**Timestamp:** 2026-03-02T08:52:56Z  
**Agent:** Wash (Lua Developer)  
**Duration:** Full rework session

## Overview

Completed implementation of OPie-style stick-based radial wheel interaction for CouchPotato, addressing John Rogers' feedback on usability and readability from couch distance.

## Problem Statement

Old interaction model was clunky and difficult to use from TV distance:
- Two-stage activation (trigger to open, face buttons to select, trigger to close)
- Wheel radius only 120px, icons 52px — unreadable from 8-10 feet away
- Non-intuitive mapping between button positions (diamond) and slot positions (circle)
- Required hand repositioning to reach non-cardinal slots

John's feedback:
> "right trigger opens the wheel, the direction from the analog stick after hitting the right trigger is what selects it. Make the menu bigger too, right now the square is way too small and it's unreadable."

## Solution Implemented

**OPie-style stick-based interaction model:**

1. Player presses and holds right trigger → wheel opens, stick polling begins
2. Player moves left stick → slot highlights based on angle (with 0.25 dead zone)
3. Player releases right trigger → executes highlighted slot, wheel closes
4. L1/R1 bumpers while wheel open → cycle wheels

**Visual improvements:**
- Wheel radius: 200px (67% larger)
- Icon size: 64px (23% larger)
- Highlighted slot: gold border + 1.3x scale
- Center text: shows highlighted slot name

**Code architecture:**
- `GetStickAngle()` — reads C_GamePad, calculates angle with dead zone
- `AngleToSlot()` — maps angle to slot (OPie's proven formula)
- `UpdateStickSelection()` — OnUpdate polling, updates highlight
- `OpenWheel()` / `ConfirmAndClose()` — trigger handlers
- `SetSlotHighlight()` — applies/removes visual styling
- Bindings simplified: removed face button bindings, kept only bumpers + trigger

## Key Outcomes

✅ **All 89 tests passing** (2 updated for new binding model)  
✅ **Combat safety maintained** (all polling read-only)  
✅ **Backward compatibility** (API signatures preserved)  
✅ **John's requirements met** (exact OPie behavior)  

## Decisions Logged

- Left stick for selection (right stick = camera in WoW)
- Single trigger cycle (simpler than peek/lock)
- Visual-only highlight (no SetAttribute in OnUpdate)
- Interface wheels call buttons directly; user wheels use SecureActionButtons

## Follow-Up Tasks

- In-game testing on real controllers
- Stick drift tuning (may adjust dead zone)
- Optional animation on highlight transition (future)
- Left-handed user option (swap stick)

## Files Changed

- CouchPotato/UI/Radial.lua (new functions, constants, event flow)
- CouchPotato/Core/Bindings.lua (simplified ApplyWheelBindings)
- spec/bindings_spec.lua (updated tests)
- spec/wow_mock.lua (added SetScale/GetScale)

## References

- OPie addon: https://www.curseforge.com/wow/addons/opie
- WoW API: C_GamePad.GetDeviceMappedState() (Patch 9.1.5+)
- John's original feedback: .squad/agents/wash/history.md
