# Decision: Universal A/B Button Semantics for Radial Wheel

**Author:** Wash (Lua Developer)  
**Date:** 2026-03-04  
**Status:** Accepted

## Context

The original OPie-style interaction model (hold trigger → select with stick → release trigger → execute) worked but had a critical usability flaw: releasing the trigger always confirmed the selection. There was no way to cancel an accidental wheel open without executing a slot.

John requested a more standard game UI pattern where:
- **A button** = confirm/execute (universal "accept" semantic)
- **B button** = cancel/dismiss (universal "back/cancel" semantic)
- **Trigger release** = cancel (same as B — non-destructive, safe to release)

## Decision

### Interaction Model

1. Hold right trigger → wheel opens
2. Move left stick → selects a slot (highlighted)
3. Press **A (PAD1)** → executes the highlighted slot + closes wheel (`ConfirmAndClose`)
4. Press **B (PAD2)** OR release trigger → cancels/closes without executing (`CloseWheel`)

### Implementation

**`Bindings:ApplyWheelBindings()`** — when wheel opens, two new overrides are added:
- `PAD1` → `SetOverrideBindingClick(..., "CouchPotatoConfirmBtn", "LeftButton")`
- `PAD2` → `SetOverrideBindingClick(..., "CouchPotatoCloseBtn", "LeftButton")`

These are cleared automatically by `ClearOverrideBindings` in `RestoreDirectBindings`. No separate clear logic needed.

**`Radial:InitGamePadButtonHandling()`** — two new Button frames created at load time:
- `CouchPotatoConfirmBtn` (`RegisterForClicks("AnyDown")`) → `Radial:ConfirmAndClose()`
- `CouchPotatoCloseBtn` (`RegisterForClicks("AnyDown")`) → `Radial:CloseWheel()`

**`CouchPotatoTriggerBtn` `AnyUp`** — changed from `ConfirmAndClose()` to `CloseWheel()`.

**`Radial:CloseWheel()`** — new function, wraps `HideCurrentWheel()` without executing.

### What Does NOT Change

- PAD3 (X) and PAD4 (Y) remain unbound during wheel mode (stick controls selection)
- PAD1/PAD2 are NOT bound when the wheel is closed (WoW's normal bindings untouched)
- `ConfirmAndClose()` behavior is unchanged — it still executes + closes
- Combat lockdown safety unchanged — `ApplyWheelBindings` is only called outside combat

## Rationale

- Matches universal game UI conventions (A=accept, B=back)
- Trigger release as cancel is safer — prevents accidental execution when picking up controller or repositioning grip
- No taint risk — new buttons are plain non-secure Buttons (no SecureActionButtonTemplate needed since they just call Lua functions)
- `ClearOverrideBindings` on the owner frame atomically removes all wheel-mode overrides including PAD1/PAD2 — single call covers all paths

## Consequences

- PAD1 and PAD2 no longer fall through to WoW's action bar while the wheel is open
- Players who relied on B-button action bar slot while using the wheel will need to close the wheel first
- This is acceptable: the wheel intentionally takes over controller input while open
