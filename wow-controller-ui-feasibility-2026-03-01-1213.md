# WoW Controller UI Addon Feasibility Report: A BG3-Inspired Experience

**Report Generated:** March 1, 2026 12:13 PST  
**Topic:** Feasibility of creating a World of Warcraft addon that detects when a gamepad is enabled and dynamically loads a secondary addon (disabled by default) that replaces the UI with a BG3-style controller-friendly interface.

---

## Summary

This report assesses the technical and practical feasibility of building a two-component WoW addon system that:
1. **Detects** when a gamepad/controller is enabled (via native WoW events and CVars)
2. **Dynamically loads** a secondary UI addon (disabled by default) that transforms the WoW interface to match the gold-standard controller experience established by Baldur's Gate 3

The conclusion is that such a system is **technically feasible** using existing WoW addon APIs. The detection and dynamic loading mechanisms are well-documented and already used in production addons. The BG3-style radial-wheel UI can be approximated in WoW Lua. The primary constraints are WoW's combat lockdown security model, Blizzard's evolving addon API policy (particularly with Patch 12.0 "Midnight"), and the inherent complexity of mapping WoW's thousands of abilities to a controller layout comparable to BG3's 600 spells/actions.

---

## Findings

### 1. The BG3 Gold Standard: What the Target UX Looks Like

Baldur's Gate 3 established what is considered the premier controller RPG interface as of 2023–2026. Larian Studios designed the PS5 and console version from scratch with a radial-menu-first philosophy [1][2][3].

#### Core BG3 Controller Layout (Xbox/PS5):

| Input | Action |
|-------|--------|
| **R2 / RT** | Main shortcut radial: Character Sheet, Journal, Combat Log, Long/Short Rest, Camp, Map, Alchemy, Level Up |
| **L1/R1 / LB/RB** | Cycle through action wheels (attacks, spells, items) |
| **L2 / LT** | Manage Party: cycle members, group/ungroup |
| **D-Pad Up** | Jump (hold = toggle light source) |
| **D-Pad Left/Right** | Previous/Next Target |
| **D-Pad Down** | Examine (hold = Hide/Stealth all party) |
| **A / X** | Interact / Confirm (hold = show all interactables in AoE) |
| **B / Circle** | Cancel/Back |
| **Y / Triangle** | End Turn (BG3 turn-based combat only — not applicable to WoW) |
| **X / Square** | Context Menu |
| **L3** | Switch to cursor mode (left-stick as mouse) |
| **R3 (hold)** | Highlight world objects and NPC vision cones |
| **View/Touchpad** | Map (hold = Journal) |
| **Menu/Options** | Game Menu |

Source: Gamepur controller guide [3], Hardcore Gamer shortcut reference [4], PlayStation Blog deep-dive [1].

#### BG3 Radial Menu Design Principles [1][2][5]:

- **Cascading wheels**: The game manages hundreds of abilities across multiple radial wheels. L1/R1 cycles between them.
- **Customizable**: Players can reorganize, add, or remove wheels and individual slots
- **Peek vs. Lock**: On PS5 DualSense, a light trigger pull peeks the wheel; a hard pull locks it open [2]
- **Adaptive triggers**: The DualSense adaptive trigger resistance conveys a sense of weight when switching menus [2]
- **Light bar**: Reflects current spell color and intensity with haptic feedback [2]
- **Cursor Mode**: L3 switches to a free cursor, allowing mouse-like precision for complex UI interactions [1][3]
- **Total spell count**: BG3 ships with 600 spells and actions — comparable in scope to a max-level WoW character [1]

The BG3 team referenced their work on Divinity: Original Sin 2's controller scheme as a predecessor, iterating significantly for BG3's larger scope [2][3].

#### BG3 Nexus Mods Community

The BG3 modding community created "Radial Hotbar Customization" (Nexus Mods) to extend the base game's radial management — allowing locked wheels, filtering, and organization tools for heavy spell-casters who found the auto-generated wheels unwieldy [6][7]. This signals that even the best-in-class implementation has room for user customization, a consideration for any WoW equivalent.

---

### 2. Current State of WoW Controller Support

#### 2a. Native WoW Gamepad Support (Shadowlands+)

Blizzard introduced native gamepad support in **Patch 9.0.1 (Shadowlands, October 2020)** [8]. Prior to this, controller play required third-party software (Xpadder, JoyToKey, etc.). As of Midnight (Patch 12.0.1, 2026), the native system supports:

- Xbox controllers (wired/wireless via XInput)
- PlayStation DualShock 4, DualSense
- Steam Deck (native + emulated)
- Nintendo Switch Pro Controller (partial, via XInput) [9]

Enabling requires: `/console GamePadEnable 1` or the in-game settings panel [9][10].

#### 2b. WoW's C_GamePad API Surface [11]

The full `C_GamePad` namespace was added in Patch 9.0.1 and includes:

**Detection & State:**
- `C_GamePad.IsEnabled()` — returns whether gamepad mode is active
- `C_GamePad.GetActiveDeviceID()` — returns ID of the active device
- `C_GamePad.GetAllDeviceIDs()` — returns all connected device IDs
- `C_GamePad.GetDeviceMappedState(deviceID)` — current button states
- `C_GamePad.GetDeviceRawState(deviceID)` — raw analog values

**Configuration:**
- `C_GamePad.GetConfig(configID)` / `C_GamePad.SetConfig(config)` / `C_GamePad.ApplyConfigs()`
- `C_GamePad.GetAllConfigIDs()`

**Vibration** (added Patch 9.1.5):
- `C_GamePad.SetVibration(vibrationType, intensity)` — `vibrationType` is string: `"Low"`, `"High"`, `"LTrigger"`, `"RTrigger"`; `intensity` is `0.0–1.0`
- `C_GamePad.StopVibration()`

**LED** (added Patch 9.0.1):
- `C_GamePad.SetLedColor(color)` — takes a single `colorRGB` ColorMixin object; available on DualSense/DualShock
- `C_GamePad.GetLedColor()` / `C_GamePad.ClearLedColor()`

**Cursor & FreeLook:**
- `SetGamePadCursorControl(enabled)` — toggle cursor control mode
- `SetGamePadFreeLook(enabled)` — toggle freelook
- `IsGamePadCursorControlEnabled()` / `IsGamePadFreelookEnabled()`

**Per-Frame Input:**
- `Frame:EnableGamePadButton(enable)` — receive `OnGamePadButtonDown`/`Up` events on that frame
- `Frame:EnableGamePadStick(enable)` — receive `OnGamePadStick` events
- `UIHANDLER_OnGamePadButtonDown`, `OnGamePadButtonUp`, `OnGamePadStick` script handlers

**Button Identifiers [11]:**
- Face buttons: `PAD1`–`PAD6`
- Shoulders/Triggers: `PADLSHOULDER`, `PADLTRIGGER`, `PADRSHOULDER`, `PADRTRIGGER`
- D-pad: `PADDUP`, `PADDRIGHT`, `PADDDOWN`, `PADDLEFT`
- Sticks: `PADLSTICK`, `PADRSTICK`, directional variants
- Back/paddle buttons: `PADBACK`, `PADFORWARD`, `PADPADDLE1`–`PADPADDLE4`

#### 2c. Key Events for Controller Detection [11][12]

| Event | Fires When |
|-------|-----------|
| `GAME_PAD_CONNECTED` | A gamepad is physically connected |
| `GAME_PAD_DISCONNECTED` | A gamepad is physically disconnected |
| `GAME_PAD_ACTIVE_CHANGED` | Gamepad active state changes (payload: `isActive: bool`) — added Patch 9.1.5; preferred event for enable/disable detection |
| `GAME_PAD_CONFIGS_CHANGED` | Button configuration changes |
| `GAME_PAD_POWER_CHANGED` | Battery level changes |
| `CVAR_UPDATE` | Any CVar changes, including `GamePadEnable` |

**Minimum detection code:**
```lua
local frame = CreateFrame("Frame")
frame:RegisterEvent("GAME_PAD_CONNECTED")
frame:RegisterEvent("GAME_PAD_DISCONNECTED")
frame:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")  -- preferred: fires when toggled via Settings panel
frame:RegisterEvent("CVAR_UPDATE")
frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "GAME_PAD_CONNECTED" then
        -- Controller physically plugged in
    elseif event == "GAME_PAD_ACTIVE_CHANGED" then
        local isActive = arg1  -- boolean payload (Patch 9.1.5+)
        if isActive then
            -- Gamepad mode activated (Settings panel toggle or physical connect)
        else
            -- Gamepad mode deactivated
        end
    elseif event == "CVAR_UPDATE" and arg1 == "GamePadEnable" then
        if arg2 == "1" then
            -- User enabled gamepad mode (fallback for pre-9.1.5 clients)
        else
            -- User disabled gamepad mode
        end
    end
end)
-- Also check on startup:
if C_GamePad.IsEnabled() then ... end
```

Key CVars available [11][13]:
- `GamePadEnable` — master on/off switch
- `GamePadEmulateCtrl`, `GamePadEmulateShift`, `GamePadEmulateAlt` — modifier mappings
- `GamePadEmulateEsc` — escape key mapping
- `GamePadCursorAutoEnable`, `GamePadCursorLeftClick`, `GamePadCursorRightClick`
- `GamePadVibrationStrength`, `GamePadFactionColor`
- Camera: `GamePadCameraYawSpeed`, `GamePadCameraPitchSpeed`, `GamePadTurnWithCamera`
- Movement: `GamePadAnalogMovement`, `GamePadFaceMovementMaxAngle`

---

### 3. Dynamic Addon Loading Mechanism

#### 3a. LoadOnDemand TOC Directive [14][15]

WoW's addon system supports `LoadOnDemand` addons — addons that are installed but **not loaded at startup** unless explicitly triggered. This is the exact mechanism needed for the secondary UI addon.

In the secondary addon's `.toc` file:
```
## Interface: 120001
## Title: ConsoleUI
## LoadOnDemand: 1
## Dependencies: ConsoleUILoader
ConsoleUI.lua
```

The loader addon (always active, tiny footprint) detects the controller state and calls:
```lua
C_AddOns.LoadAddOn("ConsoleUI")  -- Modern API (Patch 10.2.0+); always use C_AddOns form — bare LoadAddOn() alias is unconfirmed in 12.0
```

`C_AddOns.LoadAddOn()` returns `loaded, reason`. If `reason == "DISABLED"`, the addon can call `C_AddOns.EnableAddOn(name)` first, then retry [15]. Note: the second parameter to `EnableAddOn` is an optional character name (for per-character enabling), not a boolean.

#### 3b. LoadWith Directive [14]

An alternative is using `LoadWith` in the secondary addon's TOC:
```
## LoadWith: ConsolePortLoader
```
This causes the secondary addon to load whenever the named addon loads — but `LoadOnDemand` with explicit `C_AddOns.LoadAddOn()` gives finer control.

#### 3c. Event Sequence After Dynamic Load [16]

After `C_AddOns.LoadAddOn("ConsoleUI")` fires:
1. `ADDON_LOADED` event fires with `addonName == "ConsoleUI"` — primary initialization point
2. SavedVariables for the secondary addon become available
3. The secondary addon's Lua/XML files execute in TOC order

**Important**: The secondary addon must check `InCombatLockdown()` before manipulating any secure frames. Any out-of-combat initialization should complete before the first combat.

---

### 4. Existing Art: ConsolePort Architecture

ConsolePort (GitHub: seblindfors/ConsolePort, CurseForge: console-port) is the most mature controller addon for WoW, with 234+ GitHub stars and active development since Shadowlands [17][18][19]. It demonstrates that a comprehensive controller UI transformation is achievable. Its modular architecture is directly applicable:

| Module | Function |
|--------|----------|
| `ConsolePort` | Core framework: gamepad event handling, binding system, profile management |
| `ConsolePort_Bar` | Controller-optimized action bars with modifier combos (40+ mappable actions) |
| `ConsolePort_Config` | In-game configuration UI for controller setup wizard |
| `ConsolePort_Cursor` | Virtual cursor — D-pad/stick snaps to interactive UI elements |
| `ConsolePort_Keyboard` | On-screen virtual keyboard for chat/text input |
| `ConsolePort_Menu` | Custom radial and context menus replacing dropdown lists |
| `ConsolePort_Rings` | Radial flyout "rings" for utility/ability quick access (BG3-equivalent feature) [20] |
| `ConsolePort_World` | World interaction, targeting, context-sensitive actions |
| `GamepadTool` | Gamepad configuration utility |

ConsolePort's `ConsolePort_Rings` module is the closest existing WoW equivalent to BG3's action wheels — circular menus activated by button combos, populated with abilities, macros, or items, navigated via stick/D-pad [20][21].

**ConsolePort status**: Development paused in late 2025 pending resolution of Blizzard API changes introduced in Midnight pre-patch. Midnight has now shipped (Patch 12.0.1, February 2026) — ConsolePort compatibility with 12.x should be verified against the current GitHub repository before treating it as a functional reference [22][23].

**WoWXIV** (github.com/vaxherd/WoWXIV) attempted an FFXIV-style controller UI for WoW but was discontinued due to Patch 12.0 "Midnight" API restrictions that blocked its feature set — specifically, Blizzard's stated intent to prevent addons from adding features absent from the base UI [24]. This is a material constraint for any new UI overhaul addon.

---

### 5. Technical Architecture: Proposed Two-Addon System

Based on the research, the proposed architecture is:

#### Component 1: Loader Addon (ConsoleUI_Loader)
- **Always enabled** by the user
- Extremely lightweight — a single Lua file
- Registers for: `GAME_PAD_CONNECTED`, `GAME_PAD_DISCONNECTED`, `CVAR_UPDATE`
- On detection trigger, calls `C_AddOns.LoadAddOn("ConsoleUI")` or `C_AddOns.EnableAddOn` + `C_AddOns.LoadAddOn`
- Stores state in SavedVariables: last known controller state, user preferences
- No UI elements of its own

#### Component 2: Controller UI Addon (ConsoleUI)
- **Disabled by default** (marked `LoadOnDemand: 1` in TOC)
- Loaded on demand by Component 1
- Implements BG3-inspired UI:
  - Radial action wheels (replacing action bars)
  - D-pad navigation for targeting
  - Shortcut radial for game menus
  - Virtual cursor mode
  - Context-sensitive menus
- Uses `SecureActionButtonTemplate` for action buttons (combat-safe)
- Uses `SecureHandlers` for in-combat attribute-driven UI logic
- Hides default Blizzard frames on load (out of combat only)

**Detection flow:**
```
User plugs in controller
    → GAME_PAD_CONNECTED fires
    → Loader checks C_GamePad.IsEnabled()
    → If enabled: C_AddOns.LoadAddOn("ConsoleUI")
    → ConsoleUI initializes, transforms UI

User enables GamePadEnable via Settings panel
    → GAME_PAD_ACTIVE_CHANGED fires (isActive = true)
    → C_AddOns.LoadAddOn("ConsoleUI")

User enables GamePadEnable via /console
    → CVAR_UPDATE fires for "GamePadEnable"
    → value == "1": C_AddOns.LoadAddOn("ConsoleUI")

User disables GamePadEnable
    → CVAR_UPDATE fires for "GamePadEnable"
    → value == "0": ConsoleUI hides its elements, restores default UI
```

---

### 6. BG3 → WoW Feature Mapping

The following table maps BG3 controller features to their WoW implementation equivalents:

| BG3 Feature | WoW Implementation |
|-------------|-------------------|
| R2 Shortcut Radial (Map, Journal, etc.) | `ConsolePort_Menu`-style radial with `SetAttribute` driven secure buttons |
| L1/R1 cycle action wheels | Frame cycling with `OnGamePadButtonDown` on `PADLSHOULDER`/`PADRSHOULDER`, each wheel is a set of `SecureActionButtonTemplate` buttons |
| Customizable wheel slots | SavedVariables per character/spec, drag-and-drop interface out of combat |
| L3 Cursor Mode | `SetGamePadCursorControl(true)` — native WoW API |
| D-Pad targeting | `SetCVar("GamePadEmulateCtrl")` or custom secure macros for `TargetNearestEnemy`, cycle targets |
| D-Pad Up Jump | Standard keybind assignment via `SetBinding` |
| D-Pad Down stealth | Macro: `/cast Stealth` or party stealth cycle |
| Haptic feedback | `C_GamePad.SetVibration(vibrationType, intensity)` — `vibrationType`: `"Low"/"High"/"LTrigger"/"RTrigger"`; added 9.1.5 |
| LED color by spell | `C_GamePad.SetLedColor(color)` — takes a `colorRGB` ColorMixin; available on DualSense |
| Peek vs Lock wheel | Light trigger press shows radial briefly; implemented via `OnGamePadButtonDown`/`Up` hold detection |
| Context Menu | `SecureMenuTemplate` with `OnGamePadButtonDown` |
| End Turn equivalent | In WoW context: Leave Combat, Cancel Casting, or Stance swap |
| Cursor mode | `SetGamePadCursorControl(true/false)` — already native |

---

### 7. Technical Constraints and Challenges

#### 7a. Combat Lockdown [25][26]

**The most significant constraint.** When a player enters combat (`PLAYER_REGEN_DISABLED`), WoW's addon security model prevents:

- Showing or hiding **protected frames** (action buttons, unit frames, ability buttons)
- Changing protected frame **attributes** (`SetAttribute()`)
- Moving/anchoring protected frames
- Changing keybindings or macros

This means the radial wheel interface **must be built entirely before combat begins**, using `SecureActionButtonTemplate` for all action-executing buttons, with `SetAttribute()` used out-of-combat to define what each slot does.

**SecureHandlers** (introduced Patch 3.0) allow limited in-combat logic via a restricted environment — enabling pre-defined attribute-driven visibility and state changes without direct Lua calls during combat [25]. This is how addons like Bartender4 and Dominos function during combat.

**InCombatLockdown()** must be checked before any frame manipulation [25]:
```lua
if not InCombatLockdown() then
    frame:SetAttribute("type", "spell")
    frame:SetAttribute("spell", "Fireball")
    frame:Show()
end
```

#### 7b. Patch 12.0 "Midnight" API Restrictions [27][28][29][30]

Blizzard's Patch 12.0 (Midnight expansion, 2025–2026) introduced the largest addon API overhaul in WoW history. Key points:

- **Restricted**: Real-time combat parsing, automation, boss mod logic in instanced content
- **Restricted**: Addon-to-addon communication in instances
- **Still allowed**: Cosmetic and visual customizations, UI skinning, accessibility tools [31]
- **Still allowed**: Controller/gamepad UI enhancements [31]
- **At risk**: Addons that "add features not in the base UI" — this was the stated reason WoWXIV was discontinued [24]

**Critical distinction**: A BG3-style controller UI that reorganizes and reskins the existing WoW interface (action bars, menus) should fall under permitted "cosmetic and accessibility" modifications. An addon that adds entirely new mechanics would be at risk. Blizzard has softened some restrictions post-beta, but the policy continues to evolve [29][32].

#### 7c. Default UI Frame Hiding [33][34]

Hiding Blizzard's default frames (action bars, unit frames) must be done **out of combat only**. Frames like `MainMenuBar`, `PlayerFrame`, `TargetFrame` can be hidden with `:Hide()` but may re-show on specific events. Persistent suppression requires:
```lua
frame:SetScript("OnEvent", nil) -- disable event re-show
frame:Hide()
```
Or use `UnregisterAllEvents()` on the frame. Major UI replacement addons (ElvUI, Bartender4) already do this successfully [33][34].

#### 7d. Action Count vs. WoW's Ability Pool

BG3 handles 600 spells/actions across multiple radial wheels [1]. WoW max-level characters can have 30–100+ abilities. The FFXIV cross-hotbar system supports 40+ actions per setup via modifier layers [35][36]. ConsolePort supports 40+ hotkeys via trigger modifiers [19][21]. WoW's ability pool, while large, is addressable within the BG3 wheel framework.

#### 7e. Secure Action Buttons [25]

All action-executing buttons in the radial wheels must use `SecureActionButtonTemplate` with attributes:
- `type` = "spell" / "item" / "macro" / "stop"
- `spell` / `item` / `macro` = target action

This is exactly how ConsolePort_Rings implements clickable radial slots. The pattern is proven and production-tested [17][20].

#### 7f. Reload Requirement for Dynamic Enable

`C_AddOns.LoadAddOn()` can load a `LoadOnDemand` addon at runtime without a reload. However, a full UI disable (when the user disconnects the controller) currently requires hiding addon frames rather than truly unloading — WoW has no `UnloadAddOn()` API. This means the secondary addon, once loaded, stays in memory. A visual "restore default" that re-shows Blizzard frames is the practical approach.

---

### 8. FFXIV Cross-Hotbar as Secondary Reference

Final Fantasy XIV's Cross Hotbar (XHB) system is also directly applicable [35][36][37]:

- Holding L2 or R2 shows a 16-slot action cross on screen
- L2+R2 doubles the available slots
- "Expanded" and "Hybrid" modes allow triple-layering
- Purpose-built for controllers from launch
- Supports per-job loadouts

WoW's ConsolePort_Bar already implements a cross-hotbar-style layout [18][19]. This is a validated approach for WoW's complex ability count.

---

### 9. Implementation Scope Assessment

#### What Is Straightforward:
- **Detection mechanism** (Loader Addon): GAME_PAD_CONNECTED + CVAR_UPDATE = well-documented, small code footprint [12][13]
- **Dynamic loading**: LoadOnDemand + `C_AddOns.LoadAddOn()` = proven, used in production (e.g., Deadly Boss Mods sub-modules) [14][15]
- **Radial menus**: ConsolePort_Rings demonstrates this is achievable [17][20]
- **Hiding default UI**: Documented technique used by every major UI overhaul addon [33][34]
- **Virtual cursor**: `SetGamePadCursorControl()` = native global API [11]
- **Vibration feedback**: C_GamePad.SetVibration() = native API [11]
- **LED color**: C_GamePad.SetLedColor() = native API [11]

#### What Is Complex:
- **In-combat frame safety**: All radial buttons must be SecureActionButtonTemplate-based; all combat-time interactions must be pre-programmed via SecureHandlers [25]
- **Ability slot auto-population**: Scanning the player's spellbook and auto-filling radial slots requires spell/ability discovery logic
- **Wheel cycling**: Smooth wheel transitions mimicking BG3's L1/R1 cycle, using hardware button events, while keeping buttons secure
- **Partial trigger peek**: The BG3 "peek on light pull, lock on hard pull" requires axis-level trigger input detection via `OnGamePadStick` or trigger axis reading — feasible but non-trivial
- **DualSense LED by spell school**: Spell school detection (Fire = red, Frost = blue, etc.) and `SetLedColor()` mapping is doable but requires a color lookup table per spell/school

#### What Is Not Possible:
- **Adaptive trigger resistance programming**: WoW's `C_GamePad` does not expose PS5 DualSense adaptive trigger actuation point control — this is below the WoW API layer
- **Unloading the secondary addon at runtime**: `UnloadAddOn()` does not exist; the secondary addon remains in memory once loaded
- **Bypassing combat lockdown** for frame manipulation: This is a hard engine-level restriction

---

### 10. Prior Art Summary

| Addon/Project | Relevance | Status |
|--------------|-----------|--------|
| ConsolePort (seblindfors) | Complete controller UI transformation; modular; radial rings | Active (paused pending API fixes) [17][18] |
| WoWXIV (vaxherd) | FFXIV-style UI for controller players | Discontinued (12.0 restrictions) [24] |
| Bartender4 | Custom action bars; proves secure frame replacement is achievable | Active [34] |
| ElvUI | Complete UI replacement framework | Active (adapting to 12.0) [33] |
| ConsolePort_Rings | Radial flyout menus for controller | Active as ConsolePort sub-module [20] |
| BG3 Radial Hotbar Customization (Nexus) | Extends BG3's own radial system | Active [6][7] |
| Mike Wurster Console UI (design study) | UI design exploration for WoW console mode | Concept only [38] |
| FFXIV Cross Hotbar | Reference design for controller MMO action bar | Native to FFXIV [35][36] |

---

### 11. Keybinding Profile Switching: Zero-Impact Keyboard Restore

A stated requirement is that disabling or disconnecting the controller must restore the player's original keyboard layout and keybindings automatically, with no remapping required by the user. WoW's override binding system satisfies this requirement completely.

#### 11a. SetOverrideBinding / ClearOverrideBindings [61][62]

WoW provides a dedicated temporary binding API built exactly for this pattern:

- **`SetOverrideBinding(owner, isPriority, key, action)`** — Assigns a temporary binding that overrides (but does not replace) the user's saved binding. The original binding is preserved by the engine and automatically restored when the override is cleared.
- **`ClearOverrideBindings(owner)`** — Removes ALL override bindings registered to the specified owner frame. Every original keyboard binding is instantly restored. No `SaveBindings()` call is required.

Override bindings are **never written to disk**. They exist only in memory, attached to the owner frame. If the UI is reloaded, they are wiped and the player's saved bindings load as normal. No snapshot of original bindings is needed, and there is no risk of permanently overwriting the player's keybinding file.

Operational flow:
- Controller **enabled** → call `SetOverrideBinding(controllerFrame, true, key, gamepadAction)` for each controller mapping
- Controller **disabled or disconnected** → call `ClearOverrideBindings(controllerFrame)` — all original keyboard bindings restored instantly

#### 11b. Trigger Events for Keybinding Switch [12][13]

The binding swap fires on the same events used for UI loading/unloading:

```lua
local owner = CreateFrame("Frame")
owner:RegisterEvent("GAME_PAD_CONNECTED")
owner:RegisterEvent("GAME_PAD_DISCONNECTED")
owner:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")  -- preferred: fires on Settings panel toggle
owner:RegisterEvent("CVAR_UPDATE")
owner:RegisterEvent("PLAYER_REGEN_ENABLED") -- for queued combat restores

local pendingRestore = false

owner:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "GAME_PAD_CONNECTED" then
        if not InCombatLockdown() then ApplyControllerBindings(self)
        else pendingRestore = false end
    elseif event == "GAME_PAD_DISCONNECTED" then
        if not InCombatLockdown() then ClearOverrideBindings(self)
        else pendingRestore = true end
    elseif event == "GAME_PAD_ACTIVE_CHANGED" then
        local isActive = arg1  -- boolean payload (Patch 9.1.5+)
        if isActive then
            if not InCombatLockdown() then ApplyControllerBindings(self) end
        else
            if not InCombatLockdown() then ClearOverrideBindings(self)
            else pendingRestore = true end
        end
    elseif event == "CVAR_UPDATE" and arg1 == "GamePadEnable" then
        if arg2 == "1" then
            if not InCombatLockdown() then ApplyControllerBindings(self) end
        else
            if not InCombatLockdown() then ClearOverrideBindings(self)
            else pendingRestore = true end
        end
    elseif event == "PLAYER_REGEN_ENABLED" and pendingRestore then
        ClearOverrideBindings(self)
        pendingRestore = false
    end
end)
```

#### 11c. Out-of-Combat Constraint [25][26]

`SetOverrideBinding` is a NOCOMBAT function and cannot be called during combat lockdown. If the player disconnects the controller **during active combat**, the restore must be queued as shown above. The controller mapping remains active until the first safe out-of-combat window (`PLAYER_REGEN_ENABLED`), at which point `ClearOverrideBindings` fires automatically. This is the correct behavior: the player retains a functional input method throughout the combat encounter.

#### 11d. Specialized Override Variants [62]

For direct one-off bindings (mount, interact, menu), WoW also provides:
- `SetOverrideBindingSpell(owner, isPriority, key, spellName)` — key fires a spell directly
- `SetOverrideBindingItem(owner, isPriority, key, itemName)` — key uses an item directly
- `SetOverrideBindingMacro(owner, isPriority, key, macroName)` — key runs a macro directly

These are useful for "quick mount" or "interact with NPC" bindings that do not need a full secure button frame.

---

### 12. Blocked and Restricted APIs: Complete UX Impact Analysis

#### 12a. Combat Lockdown: Frame Manipulation Restrictions [25][26][63]

All restrictions below apply when `InCombatLockdown()` returns `true` (player in combat).

| Blocked Action | API Affected | BG3 UX Impact | Workaround |
|---|---|---|---|
| Show / Hide protected frames | `:Show()`, `:Hide()` on SecureActionButton parents | Cannot open or close radial wheel mid-combat | Pre-build all wheel frames; use SecureHandlers `_onshow`/`_onhide` attribute logic instead |
| Move / reposition protected frames | `:SetPoint()`, `:ClearAllPoints()` | Cannot reposition wheels mid-combat | Fix all wheel anchor positions before combat begins |
| Change button action assignments | `:SetAttribute("spell", ...)` | Cannot reassign radial slots in combat; player is locked to their pre-combat loadout | All slot assignments made out-of-combat; a "lock" indicator during combat is appropriate UX |
| Create or destroy secure frames | `CreateFrame(..., "SecureActionButtonTemplate")` | Cannot spawn additional wheel slots on the fly | Pre-create the maximum number of wheel slots at addon load time; hide unused slots |
| Switch keybinding profile | `SetOverrideBinding()`, `SetBinding()` | Cannot swap controller↔keyboard mid-combat | Queue the swap; apply on `PLAYER_REGEN_ENABLED` |
| Reparent protected frames | `:SetParent()` | Cannot reorganize wheel hierarchy in combat | Wheel hierarchy is fixed at startup |
| Modify macros | `CreateMacro()`, `EditMacro()` | Cannot update macro content in combat | Pre-write all controller macros on addon load |

#### 12b. Always Protected: Require Secure Context or Hardware Event [64][65]

These functions cannot be called from addon (tainted) code at any time. They require either a direct player button press (hardware event) or execution inside a secure template:

| Function | Purpose | UX Impact | Workaround |
|---|---|---|---|
| `UseAction(slot)` | Use an action bar slot | Cannot trigger spells programmatically | All action execution goes through `SecureActionButtonTemplate` with `type`, `spell`, `item` attributes |
| `CastSpellByName(name)` | Cast spell by name | Cannot autocast | Same SecureActionButtonTemplate pattern |
| `CastSpellByID(id)` | Cast spell by ID | Same | Same |
| `UseContainerItem(bag, slot)` | Use / equip a bag item | Inventory use requires secure button | `SecureActionButtonTemplate` with `type=item` |
| `PickupAction(slot)` | Pick up action bar slot | Drag-and-drop customization blocked during combat | Allow wheel customization only out of combat |
| `StartAttack()` | Begin auto-attack | Cannot auto-trigger | Bind to a `SecureActionButtonTemplate` macro button |

#### 12c. NOCOMBAT-Only Functions [64][65]

Callable freely in any non-combat context; fail silently or error during combat:

| Function | Purpose | UX Impact |
|---|---|---|
| `SetBinding(key, command)` | Permanently remap a key | Do not use for controller mode — use `SetOverrideBinding` instead to avoid this restriction |
| `SaveBindings(which)` | Write bindings to disk | Not needed with override binding pattern |
| `PickupSpell(spellID)` | Begin spell drag | Wheel slot customization (drag-and-drop) is an out-of-combat-only feature |
| `CreateMacro()` | Create a macro | All controller macros must be pre-created before first combat |
| `C_AuctionHouse.*` | Auction operations | No impact on controller UI |

#### 12d. Patch 12.0 "Midnight" Policy Restrictions [27][28][29][31]

| Restriction | Scope | UX Impact for This Addon |
|---|---|---|
| Combat parsing / automation | Instanced content | No impact — BG3-style UI has no combat automation |
| Addon cross-communication in instances | Instanced content | No impact — single-addon architecture |
| "Adding features not in base UI" | All content (enforced case-by-case) | Risk area; the WoWXIV discontinuation is the cautionary example. Staying in cosmetic/accessibility framing mitigates this |
| Real-time unit frame automation | All content | No impact — unit frames remain informational |
| Controller / accessibility addons | **Explicitly still allowed** | This addon is in the explicitly protected category |

#### 12e. Adaptive Trigger Resistance [Not Possible — Below WoW API Layer]

The PS5 DualSense adaptive trigger actuation point (the BG3 "peek vs. lock" physical resistance feel) is not exposed by WoW's `C_GamePad` API. The trigger axis value (0.0–1.0) can be read via `GetDeviceRawState()`, allowing threshold-based peek detection (e.g., trigger > 0.3 = peek, trigger > 0.8 = activate), but the physical haptic resistance sensation cannot be replicated from within WoW addon code.

#### 12f. Summary: What This Means for the BG3 Experience

The core BG3 controller experience — radial menus, wheel cycling, D-pad navigation, face-button interactions, cursor mode, NPC dialog, quest journal, map, inventory, mount — is **not blocked** by any of the above restrictions. The restrictions apply primarily to in-combat frame manipulation, which must be pre-built before combat begins. The pre-built, SecureHandler-driven architecture sidesteps every blocked API.

---

### 13. Controller-Friendly Windows for Non-Combat Interactions

The BG3 gold standard requires that every interaction — not just combat — is navigable with only the controller. The following analysis covers each WoW non-combat window and its controller replaceability.

#### 13a. NPC Dialog / Gossip Window [66][67]

**WoW default**: `GossipFrame` — vertical text list, mouse-only.

**BG3 reference**: D-pad scrolls dialogue options; face button selects; large text, clear focus highlight, one option per line.

**Feasibility**: ✅ Full replacement is possible and already proven by production addons.

- Hide default: `GossipFrame:Hide()` + `GossipFrame:UnregisterAllEvents()`
- Data API: `C_GossipInfo.GetOptions()` returns all options as a Lua table
- Selection API: `C_GossipInfo.SelectOption(optionIndex)` — selects the option (requires hardware event; use `SecureActionButtonTemplate`)
- Trigger events: `GOSSIP_SHOW`, `GOSSIP_CLOSED`
- Navigation: `OnGamePadButtonDown` with `PADDDOWN`/`PADDUP` to move focus; `PAD1` (A/cross) to confirm
- The **Immersion** and **Dialogue UI** addons both perform full GossipFrame replacement today, validating the pattern [66][67]

#### 13b. Quest Accept / Turn-In Window [66][67]

**WoW default**: `QuestFrame` — scrollable text, Accept/Decline buttons.

**BG3 reference**: Full quest text with large font; shoulder buttons scroll; face button accepts/declines.

**Feasibility**: ✅ Full replacement is possible.

- Trigger events: `QUEST_DETAIL` (new quest), `QUEST_PROGRESS` (in-progress), `QUEST_COMPLETE` (turn-in)
- Text APIs: `GetQuestText()`, `GetRewardText()`, `GetRewardMoney()`, `GetNumQuestRewards()` — ⚠️ verify these globals still exist in 12.0; they follow the same pre-10.0 pattern that Blizzard migrated to `C_QuestLog.*` for other functions. Check [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) before use.
- Confirm APIs: `AcceptQuest()`, `CompleteQuest()`, `DeclineQuest()` — **not protected**; callable directly
- Navigation: shoulder buttons scroll text; `PAD1` accepts; `PAD2` declines (maps to B/circle = BG3 cancel)

#### 13c. Quest Log / Journal [66]

**BG3 reference**: Journal from radial menu; L1/R1 cycles tabs; quest list on left, details on right; face button sets waypoint.

**Feasibility**: ✅ Achievable.

- `C_QuestLog.GetNumQuestLogEntries()`, `C_QuestLog.GetInfo(index)` enumerate all quests
- `C_QuestLog.SetSelectedQuest(questID)` selects a quest for display
- `C_QuestLog.GetQuestObjectives(questID)` fetches current objectives and completion counts
- `C_Navigation.SetUserWaypoint(uiMapPoint)` sets a waypoint on the map
- Navigation: D-pad up/down scrolls quest list; L1/R1 cycles tabs (Active / Completed); `PAD1` sets waypoint

#### 13d. Mounting [68]

**BG3 reference**: Mount accessible from radial; press summons random appropriate mount; hold opens full browser.

**Feasibility**: ✅ Fully achievable.

- `C_MountJournal.SummonByID(0)` — summons a random appropriate favorite mount (ground, flying, or aquatic auto-selected based on zone)
- "Quick mount" radial slot: `SecureActionButtonTemplate` with `type=macro`, macro body `/run C_MountJournal.SummonByID(0)`
- Full browser: `C_MountJournal.GetMountIDs()`, `C_MountJournal.GetMountInfoByID(id)` (returns name, icon, isUsable, isFavorite)
- Favorite toggle: `C_MountJournal.SetIsFavorite(mountID, bool)` — out of combat
- Navigation: D-pad navigates mount grid; L1/R1 pages; `PAD1` summons; `PAD4` (Y/triangle) toggles favorite

#### 13e. Loot Window [69]

**BG3 reference**: Loot panel near character; D-pad cycles items; face button takes selected; shoulder button takes all.

**Feasibility**: ✅ Full replacement is possible.

- Trigger event: `LOOT_OPENED`
- Data APIs: `GetNumLootItems()`, `GetLootSlotInfo(slot)` (name, icon, quantity, quality)
- Action API: `LootSlot(slot)` — loots a specific item (requires hardware event; wrap in secure button)
- Hide default: `LootFrame:Hide()`
- Navigation: D-pad up/down cycles items; `PAD1` loots focused item; `PADLSHOULDER` + `PAD1` = loot all

#### 13f. Bag / Inventory Window [69]

**BG3 reference**: Single unified inventory; D-pad grid navigation; face buttons to use/equip; L1/R1 cycles categories.

**Feasibility**: ✅ Achievable (complex; proven by BetterBags open-source codebase).

- `C_Container.GetContainerNumSlots(bagID)` enumerates bag sizes
- `C_Container.GetContainerItemInfo(bagID, slot)` returns a **single struct** (changed in Patch 10.0 — not multi-return):
  ```lua
  local info = C_Container.GetContainerItemInfo(bagID, slot)
  if info then
      local icon = info.iconFileID
      local count = info.stackCount
      local quality = info.quality
  end
  ```
- Item use: `C_Container.UseContainerItem(bagID, slot)` — protected; must use `SecureActionButtonTemplate` with `type=item`
- BetterBags (open source, actively maintained) provides a complete reference implementation for unified bag replacement [69]
- Navigation: D-pad navigates item grid; L1/R1 cycles bag/category tabs; `PAD1` uses/equips focused item

#### 13g. Map Window [66]

**BG3 reference**: Map from radial (R2); zoom with triggers; pan with left stick; waypoint with face button.

**Feasibility**: ✅ Achievable.

- `WorldMapFrame` is not a protected frame — it can be focused and made fully gamepad-navigable
- `C_Map.GetBestMapForUnit("player")` gets current map ID
- `C_Navigation.SetUserWaypoint(uiMapPoint)` sets a custom waypoint
- When map is open: remap left stick to `ScrollLeft`/`ScrollRight`/`ScrollUp`/`ScrollDown` via override bindings; L2/R2 = zoom; `PAD1` = set waypoint at cursor; `PAD2` = close

#### 13h. Vendor / Shop Window [67]

**BG3 reference**: Shop accessible from NPC dialog flow; D-pad navigates items; face button buys; trigger held = sell mode.

**Feasibility**: ✅ Achievable.

- Trigger events: `MERCHANT_SHOW`, `MERCHANT_CLOSED`
- Data APIs: `GetMerchantNumItems()`, `GetMerchantItemInfo(index)` (name, texture, price, quantity) — ⚠️ verify these globals still exist in 12.0; check [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) before use.
- Buy API: `BuyMerchantItem(index, quantity)` — requires hardware event; use secure button
- Navigation: D-pad up/down cycles items; `PAD1` buys; `PADRTRIGGER` held activates sell mode (opens bag grid overlay)

#### 13i. Character Sheet / Equipment [66]

**BG3 reference**: Character sheet from radial; face buttons navigate equipment slots; L1/R1 cycles tabs.

**Feasibility**: ✅ Achievable.

- `CharacterFrame` is non-protected (display-only); no secure template required
- Equipment slot APIs: `GetInventoryItemID("player", slotID)`, `GetInventoryItemTexture()`, `GetInventoryItemStats()` — ⚠️ verify these globals still exist in 12.0; Blizzard migrated this category to `C_Item.*`/`C_Equipment.*` in 10.0+. Check [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) before use.
- Slot IDs: 1 = Head, 2 = Neck, 3 = Shoulder, 5 = Chest, ... 16 = Main Hand, 17 = Off Hand
- Navigation: D-pad navigates slot grid; L1/R1 cycles tabs (Equipment / Stats / Talents); `PAD4` compares item in slot

#### 13j. Summary: Non-Combat Window Replaceability

| Window | BG3 Analog | Controller Replaceable | Key Constraint |
|---|---|---|---|
| NPC Gossip | Dialogue selection | ✅ Full | Option selection requires secure button |
| Quest Accept / Turn-In | Quest prompts | ✅ Full | No constraints; accept/decline APIs are unprotected |
| Quest Journal | Journal (L2 long press) | ✅ Full | None |
| Mount Browser | — (not in BG3) | ✅ Full | Mount summon via macro/secure button |
| Loot Window | Loot screen | ✅ Full | LootSlot requires hardware event |
| Bags / Inventory | Inventory (Start button) | ✅ Full | Item use requires secure button |
| World Map | Map (View button) | ✅ Full | None; WorldMapFrame is unprotected |
| Vendor / Shop | Trader NPCs | ✅ Full | Buy requires hardware event |
| Character Sheet | Character info | ✅ Full | None; informational frame only |
| Trade Window | Trading | ⚠️ Partial | Item pickup for trade is protected; complex |
| Auction House | — | ⚠️ Partial | C_AuctionHouse APIs have rate limits and restrictions |

---

### 14. Healing Interface Design for Controller Play

Healing in WoW is "whack-a-mole" — react to any of 4–24 party members taking damage, identify the priority target, cast the right spell, repeat under pressure. Mouse-based healing solves this with click-to-cast: hover over a health bar, click. This section describes a controller healing design that works **on top of the player's existing healer frame addon** (VuhDo, Grid2, Cell, etc.) rather than replacing it.

#### 14a. Design Principle: Overlay, Not Replace [83][84][85]

The player already has a healer frame addon configured to their preference. That addon owns the health bar display — the controller addon does not render its own party frames. Instead it adds two things on top:

1. A **D-pad cursor** — a lightweight highlight overlay that navigates between the existing healer frames when heal mode is active
2. **Context-swapped face buttons** — when the cursor lands on a frame, the four face buttons instantly remap to healing spells for that unit

The healer frame addon continues doing everything it already does: health bars, debuff icons, HoT tracking, incoming heal prediction. The controller addon only adds navigation and button remapping.

#### 14b. Interaction Flow [76][78][79]

`PADDLEFT` press → enter heal mode. The D-pad cursor appears on the first frame. D-pad navigates between frames. Face buttons cast heals on whoever is focused. `PADDLEFT` again (or `PAD2` / B / Circle) → exit heal mode, all buttons revert instantly via `ClearOverrideBindings`.

```
NORMAL MODE                      HEAL MODE  (entered via PADDLEFT)
────────────────────             ────────────────────────────────────
PADDUP    = Jump                 PADDUP    = cursor up / prev frame
PADDDOWN  = Stealth              PADDDOWN  = cursor down / next frame
PADDLEFT  = [Enter Heal Mode]    PADDLEFT  = [Exit Heal Mode]
PADDRIGHT = Interact             PADDRIGHT = cursor right (raid columns)
PAD1 (A)  = Interact/Confirm     PAD1 (A)  = Cast Heal 1 on focused frame
PAD2 (B)  = Cancel               PAD2 (B)  = Exit Heal Mode
PAD3 (X)  = Ability / Menu       PAD3 (X)  = Cast Heal 2 / HoT on focused
PAD4 (Y)  = Ability / AoE        PAD4 (Y)  = Dispel (if debuff) or Heal 3
PADLSHOULDER                     PADLSHOULDER = Emergency cooldown
PADRSHOULDER                     PADRSHOULDER = AoE heal
```

The existing healer frame addon's frames are the navigation targets — the cursor moves between them. No custom health bar rendering is required.

#### 14c. D-Pad Cursor: How It Works [81][82]

The cursor is a **non-protected visual frame** — a thin highlight border — that is parented to whichever healer frame is currently focused. It has no secure attributes and is never involved in spell casting. It can move freely at any time including during combat.

The cursor maintains an internal index (1–5 for parties, 1–25 for raids) representing the current position in the party/raid unit list. D-pad up/down increments/decrements the index. The cursor frame is then re-anchored to the screen position of the corresponding healer addon frame:

```lua
-- Pseudo-code: move cursor to match the healer addon's frame for partyN
local targetFrame = GetHealerAddonFrame("party" .. cursorIndex)
cursor:ClearAllPoints()
cursor:SetAllPoints(targetFrame)  -- cursor exactly overlays that frame
```

Locating the healer addon's frames uses `_G` (the global frame table) — VuhDo, Grid2, and Cell all expose named frames accessible by unit token. The cursor anchors itself to whatever frame corresponds to the current index.

#### 14d. Face Button Auto-Swap [61][62]

When the cursor moves to a new frame, `SetOverrideBinding` remaps the four face buttons to `[@partyX]` macros for that specific unit. The player's hard target (boss) never changes.

```lua
local unit = "party" .. cursorIndex  -- e.g. "party1", "party2", "player"

SetOverrideBinding(healFrame, true, "PAD1",
    "MACRO HealMode_Heal1_" .. unit)   -- e.g. /cast [@party1] Flash Heal
SetOverrideBinding(healFrame, true, "PAD3",
    "MACRO HealMode_HoT_" .. unit)     -- e.g. /cast [@party1] Renew
SetOverrideBinding(healFrame, true, "PAD4",
    "MACRO HealMode_Util_" .. unit)    -- Dispel or lesser heal
```

The visual labels on screen (small button prompt icons near the healer frames) update to show the current spell assignments as the cursor moves. If the focused unit has a dispellable debuff, PAD4's label shows "Dispel" with a colored border matching the debuff type. These are purely visual — non-protected texture/text updates.

| Condition on focused member | PAD1 (A) | PAD3 (X) | PAD4 (Y) |
|---|---|---|---|
| Below 40% health | Emergency heal | Shield / Barrier | Dispel (if debuff) or AoE |
| Below 70% health, no debuff | Standard single-target heal | HoT | AoE heal |
| Dispellable debuff present | Standard heal | HoT | **Dispel** (highlighted) |
| Dead / Ghost | Resurrect (out of combat only) | — | — |
| Full health, no debuff | Lesser heal / Buff | Mana regen | AoE heal |

#### 14e. Comparison: Controller Healing Across Games

| Game | Approach | Target-Switch Free? | Presses to Heal |
|---|---|---|---|
| FFXIV (native controller) | D-pad cycles party list → XHB heal → snaps back to boss | ✅ Yes | 2 |
| WoW + ConsolePort | Modifier + face button combos mapped to `[@partyX]` macros | ✅ Yes | 3 (chord) |
| **WoW + this addon (proposed)** | **PADDLEFT toggle → D-pad over existing frames → face buttons auto-swap** | ✅ **Yes** | **2–3** |
| Throne & Liberty | D-pad cycle + face button | ✅ Yes | 2–3 |

#### 14f. Addon Reference: Cell [83]

Cell (GitHub: enderneko/Cell) is actively maintained, open source, and updated for Patch 12.0. Its frame naming conventions and unit token exposure are the most straightforward to target with the cursor overlay approach. VuhDo and Grid2 are also compatible. The player configures their preferred healer addon independently; the controller addon only needs to locate the frames at runtime.

---

### 15. Combat Button Layout: Universal Framework and Per-Class Ability Mappings

This section defines the complete combat controller layout. The non-combat (menus, vendor, map, etc.) design from Sections 1–14 remains unchanged — the BG3-style menu approach is retained. **Combat layout is WoW-native: real-time, reaction-based, no turn-based elements.**

Sources: Wowhead Midnight rotation guides (all specs, updated 2026-02-25), scraped 2026-03-02. Interface version 120001 (Patch 12.0.1).

#### 15a. Universal Button Framework

The same physical button always does the same **category** of thing regardless of class. Only the specific spell changes per spec. This makes the layout learnable once, not 39 times.

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   LT (movement)         [Y] Ability 3    RT (major CD)  │
│   LB (defensive CD)   [X]   [B] Primary  RB (interrupt) │
│                             [A] JUMP                    │
│                                                         │
│   Left Stick: Move          Right Stick: Camera         │
│   LS click: Auto-run        RS click: Target nearest    │
│                                                         │
│   D-pad: see 15b (role-specific)                        │
│   Start: Radial menu                                    │
│   Back:  Map                                            │
└─────────────────────────────────────────────────────────┘
```

| Button | Universal Role | DPS Example | Tank Example | Healer Example |
|--------|---------------|-------------|--------------|----------------|
| **A** | Jump | Jump | Jump | Jump |
| **B** | Primary filler / builder | Fireball | Shield Slam | Holy Shock |
| **X** | Spender / secondary | Pyroblast | Thunder Clap | Flash of Light |
| **Y** | 3rd priority / proc spender | Fire Blast | Ignore Pain | Word of Glory |
| **RB** | **Interrupt** | Counterspell | Pummel | Dispel (see §15c) |
| **RT** | **Major offensive CD** | Combustion | Avatar | Avenging Wrath |
| **LB** | **Major defensive CD** | Ice Block | Shield Wall | Divine Shield |
| **LT** | **Movement / gap closer** | Blink | Charge | Divine Steed |
| **D-pad** | Role-specific (§15b) | 4 extra abilities | Taunt + 3 extras | Party targeting |
| **Start** | Radial menu | ← same → | ← same → | ← same → |
| **Back** | Map | ← same → | ← same → | ← same → |
| **RS click** | Tab-target next enemy | ← same → | ← same → | ← same → |

#### 15b. D-Pad by Role

**DPS and Tank — 4 additional abilities:**

| D-pad | DPS use | Tank use |
|-------|---------|----------|
| ↑ Up | AoE version of primary / DoT application | **Taunt** (single target) |
| ↓ Down | Reactive proc ability (priority spender) | **AoE Taunt** (Challenging Shout etc.) |
| ← Left | Self-buff / short cooldown | Minor cooldown (Revenge, Impending Victory) |
| → Right | Crowd control / utility | Utility (interrupt target, throw) |

**Healer — Party targeting mode:**

Any D-pad direction press enters Heal Mode. D-pad navigates the party/raid frames (using the overlay system from §14). Face buttons cast heals on the focused member. D-pad center-click or B exits Heal Mode. The controller vibrates briefly (§2b `C_GamePad.SetVibration`) when Heal Mode activates/deactivates as tactile confirmation.

```
Heal Mode D-pad:
  ↑ Up    = Party member 1 (typically tank)
  → Right = Party member 2
  ↓ Down  = Party member 3
  ← Left  = Party member 4
  RS click = Self

While in Heal Mode, face buttons:
  A (B) = Primary heal (Flash Heal / Healing Wave / Vivify etc.)
  X     = HoT (Renew / Riptide / Rejuvenation / Renewing Mist)
  Y     = Emergency / big heal (Greater Heal / Regrowth / Enveloping Mist)
  RB    = Dispel (highlighted in red if target has dispellable debuff)
  RT    = Major single-target CD (Guardian Spirit / Pain Suppression etc.)
  LB    = Major raid-wide CD (Divine Hymn / Healing Tide / Tranquility)
```

The healer's DPS rotation (Crusader Strike → Judgment, Lightning Bolt, Smite etc.) remains on B/X/Y when NOT in Heal Mode — healers do meaningful DPS between heal casts in Midnight Season 1.

#### 15c. Interrupt / Dispel Mapping

Most DPS and tank specs have a direct interrupt on RB. Healers and some ranged DPS replace RB with Dispel (equally urgent in a controller context — a slow dispel in M+ is a wipe).

| Class | DPS Interrupt | Tank Interrupt | Healer Dispel (RB in heal mode) |
|-------|--------------|----------------|----------------------------------|
| Warrior | Pummel | Pummel | — |
| Paladin | Rebuke | Avenger's Shield | Purify (magic + disease) |
| Hunter | Counter Shot / Muzzle | — | — |
| Rogue | Kick | — | — |
| Priest | Silence (talent; ranged) | — | Purify (magic + disease) |
| Death Knight | Mind Freeze | Mind Freeze | — |
| Shaman | Wind Shear | — | Cleanse Spirit / Purify Spirit (magic + curse) |
| Mage | Counterspell | — | — |
| Warlock | Spell Lock (Felhunter pet) | — | — |
| Monk | Spear Hand Strike | Spear Hand Strike | Spear Hand Strike |
| Druid | Skull Bash (Cat/Bear) | Skull Bash | Remove Corruption (poison + curse) |
| Demon Hunter | Consume Magic | Consume Magic | — |
| Evoker | Quell | — | Naturalize (magic + poison) |

**Note on Warlock:** Felhunter must be active for Spell Lock. Demonology must use Felguard's Axe Toss instead. The addon should track the active pet and swap the RB macro accordingly using a `UNIT_PET` event listener.

**Note on Balance Druid:** No traditional interrupt — Typhoon (knockback) and Incapacitating Roar (disorient) are the only interrupt-adjacent tools. RB maps to Typhoon. The player must be aware this is a positional knockback, not a lockout.

#### 15d. Per-Spec Ability Mapping Table (All 39 Specs, Midnight 12.0.1)

Sources: Wowhead rotation guides, all updated 2026-02-25 for Patch 12.0.1.

> Button assignments reflect the **#1 priority in the rotation** — the ability that, when available, is always pressed first. This is the single most important thing a new controller player needs to know per spec.

**WARRIOR**

| Spec | B (primary) | X (secondary) | Y (3rd) | D↑ (AoE/DoT) | D↓ (proc/reactive) | RB | RT | LB | LT |
|------|-------------|---------------|---------|--------------|---------------------|----|----|----|-----|
| Arms | Mortal Strike | Overpower | Colossus Smash | Sweeping Strikes | Execute (Sudden Death proc) | Pummel | Avatar | Die by the Sword | Charge |
| Fury | Bloodthirst | Raging Blow | Rampage | Whirlwind | Execute | Pummel | Recklessness | Enraged Regeneration | Charge |
| Protection | Shield Slam | Thunder Clap | Ignore Pain | Revenge | Execute (≤20% HP) | Pummel | Avatar | Shield Wall | Charge |

**PALADIN**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Retribution | Crusader Strike | Judgment | Templar's Verdict | Divine Storm (AoE) | Wake of Ashes | Rebuke | Avenging Wrath | Divine Shield | Divine Steed |
| Protection | Shield of the Righteous | Judgment | Hammer of the Righteous | Consecration | Word of Glory | Avenger's Shield | Avenging Wrath | Ardent Defender | Divine Steed |
| Holy | Holy Shock | Flash of Light | Word of Glory | Light of Dawn | Crusader Strike (DPS filler) | Rebuke | Avenging Wrath | Divine Shield | Divine Steed |

**HUNTER**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Beast Mastery | Kill Command | Barbed Shot | Cobra Shot | Multi-Shot (AoE) | Kill Shot (≤20%) | Counter Shot | Bestial Wrath | Survival of the Fittest | Disengage |
| Marksmanship | Aimed Shot | Arcane Shot | Rapid Fire | Multi-Shot | Kill Shot | Counter Shot | Trueshot | Exhilaration | Disengage |
| Survival | Kill Command | Raptor Strike | Wildfire Bomb | Carve (AoE) | Kill Shot | Muzzle | Coordinated Assault | Exhilaration | Disengage |

**ROGUE**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Assassination | Mutilate | Envenom | Rupture | Fan of Knives | Garrote | Kick | Deathmark | Evasion | Sprint |
| Outlaw | Sinister Strike | Between the Eyes | Roll the Bones | Blade Flurry | Dispatch (≤20%) | Kick | Adrenaline Rush | Evasion | Sprint |
| Subtlety | Shadowstrike | Eviscerate | Shadow Dance | Shuriken Storm | Symbols of Death | Kick | Shadow Dance + Symbols | Evasion | Shadowstep |

**PRIEST**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Shadow | Mind Blast | Vampiric Touch | Shadow Word: Pain | Void Eruption / Void Bolt | Devouring Plague | Silence (talent) | Dark Ascension | Dispersion | Fade |
| Discipline | Penance | Power Word: Shield | Atonement (target via heal mode) | Spirit Shell | Mind Blast (DPS) | — | Evangelism | Pain Suppression | Angelic Feather |
| Holy | Flash Heal | Heal | Holy Word: Serenity | Holy Word: Sanctify | Prayer of Mending | — | Apotheosis | Guardian Spirit | Angelic Feather |

**DEATH KNIGHT**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Blood (Tank) | Heart Strike | Blood Boil | Death Strike | Death and Decay | Bone Shield / Crimson Scourge | Mind Freeze | Empower Rune Weapon | Vampiric Blood | Death's Advance |
| Frost | Obliterate | Frost Strike | Howling Blast | Remorseless Winter | Pillar of Frost | Mind Freeze | Pillar of Frost + Empower Rune | Icebound Fortitude | Wraith Walk |
| Unholy | Festering Strike | Scourge Strike | Death Coil | Epidemic (AoE) | Apocalypse | Mind Freeze | Dark Transformation | Anti-Magic Shell | Wraith Walk |

**SHAMAN**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Elemental | Lava Burst | Earth Shock | Lightning Bolt | Chain Lightning | Flame Shock | Wind Shear | Stormkeeper | Astral Shift | Gust of Wind |
| Enhancement | Stormstrike | Lava Lash | Lightning Bolt (Maelstrom) | Chain Lightning | Flame Shock | Wind Shear | Feral Spirit | Astral Shift | Gust of Wind |
| Restoration | Riptide | Chain Heal | Healing Wave | Healing Rain | Healing Surge (emergency) | Wind Shear | Healing Tide Totem | Spirit Link Totem | Gust of Wind |

**MAGE**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Arcane | Arcane Blast | Arcane Barrage | Arcane Missiles (proc) | Arcane Explosion | Arcane Surge | Counterspell | Touch of the Magi | Ice Block | Shimmer |
| Fire | Fireball | Pyroblast | Fire Blast (Hot Streak proc) | Flamestrike | Phoenix Flames | Counterspell | Combustion | Ice Block | Shimmer |
| Frost | Frostbolt | Ice Lance | Frozen Orb | Blizzard | Fingers of Frost / Brain Freeze proc | Counterspell | Icy Veins | Ice Block | Shimmer |

**WARLOCK**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Affliction | Unstable Affliction | Malefic Rapture | Agony | Seed of Corruption | Corruption | Spell Lock (Felhunter) | Summon Darkglare | Unending Resolve | Demonic Circle |
| Demonology | Shadow Bolt | Call Dreadstalkers | Hand of Gul'dan | Implosion | Summon Demonic Tyrant | Spell Lock (Felhunter) | Summon Demonic Tyrant | Unending Resolve | Demonic Circle |
| Destruction | Incinerate | Chaos Bolt | Immolate | Rain of Fire | Conflagrate | Spell Lock (Felhunter) | Summon Infernal | Unending Resolve | Demonic Circle |

**MONK**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Windwalker | Tiger Palm | Blackout Kick | Rising Sun Kick | Fists of Fury | Strike of the Windlord | Spear Hand Strike | Storm Earth and Fire | Touch of Karma | Roll |
| Brewmaster (Tank) | Keg Smash | Blackout Kick | Breath of Fire | Spinning Crane Kick | Purifying Brew | Spear Hand Strike | Invoke Niuzao | Celestial Brew | Roll |
| Mistweaver | Renewing Mist | Vivify | Enveloping Mist | Sheilun's Gift | Rising Sun Kick (DPS) | Spear Hand Strike | Invoke Yu'lon | Life Cocoon | Roll |

**DRUID**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Balance | Starsurge | Wrath / Starfire | Starfall (AoE) | Sunfire / Moonfire | Celestial Alignment | Typhoon (knockback) | Incarnation / Celestial Alignment | Barkskin | Wild Charge |
| Feral | Rake | Shred | Rip | Swipe | Ferocious Bite | Skull Bash | Berserk | Survival Instincts | Wild Charge |
| Guardian (Tank) | Mangle | Thrash | Ironfur | Maul | Frenzied Regeneration | Skull Bash | Berserk / Incarnation | Barkskin | Wild Charge |
| Restoration | Riptide / Regrowth | Wild Growth | Swiftmend | Rejuvenation | Tranquility | Cyclone (CC only) | Flourish / Convoke | Barkskin | Wild Charge |

**DEMON HUNTER**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Havoc | Chaos Strike | Blade Dance | Eye Beam | Fel Rush (AoE reposition) | Metamorphosis | Consume Magic | Metamorphosis | Blur | Vengeful Retreat |
| Vengeance (Tank) | Shear | Soul Cleave | Sigil of Flame | Fel Devastation | Fiery Brand | Consume Magic | Metamorphosis | Demon Spikes | Fel Rush |

**EVOKER**

| Spec | B | X | Y | D↑ | D↓ | RB | RT | LB | LT |
|------|---|---|---|----|----|----|----|----|----|
| Devastation | Disintegrate | Eternity Surge | Fire Breath (charged) | Shattering Star | Living Flame | Quell | Dragonrage | Obsidian Scales | Hover |
| Preservation | Spiritbloom | Dream Breath | Emerald Blossom | Reversion | Living Flame (DPS) | Quell | Rewind | Renewing Blaze | Hover |
| Augmentation | Ebon Might | Prescience | Eruption | Breath of Eons | Living Flame | Quell | Breath of Eons | Obsidian Scales | Hover |

#### 15e. Implementation: Per-Spec Button Configuration

Each spec's button assignments are stored in `ConsoleUI_DB.specs[specID]` (SavedVariables). The addon reads the player's current spec via `GetSpecialization()` and applies the matching `SetOverrideBinding` set on `PLAYER_SPECIALIZATION_CHANGED`.

```lua
-- On PLAYER_SPECIALIZATION_CHANGED or initial ADDON_LOADED:
local specID = GetSpecialization()  -- returns 1,2,3 (position in class)
local classID = select(3, UnitClass("player"))
local key = classID .. "_" .. specID

local layout = ConsoleUI_DB.specs[key]
if layout and not InCombatLockdown() then
    ApplyControllerLayout(layout)
end
```

The layout table for each spec contains all button→spell mappings. Players can edit them in the out-of-combat settings UI without reloading. The default tables use the assignments from §15d.

#### 15f. Modifier Layer: LT as Shift

For specs that need more than 7 abilities accessible (B/X/Y + 4 D-pad), **holding LT acts as a modifier** (LT is bound to the movement spell by default, but a *tap* triggers movement while a *hold* activates the modifier layer). This doubles the D-pad to 8 total slots.

```
LT tap          = movement ability (Charge, Blink, Disengage, etc.)
LT hold + D↑   = Ability 8 (secondary AoE, second DoT, etc.)
LT hold + D↓   = Ability 9
LT hold + D←   = Ability 10
LT hold + D→   = Ability 11
```

This is implemented via `GAME_PAD_BUTTON_DOWN` / `GAME_PAD_BUTTON_UP` events on the LT (`PADLTRIGGER`) button. A 200ms timer distinguishes tap from hold — if LT is released within 200ms, fire the movement spell; if held, enable the modifier layer overlay.

---

## Data Gaps and Limitations

1. **Patch 12.0 API surface**: Midnight has shipped (Patch 12.0.1, February 2026) but the API surface continues to evolve through seasonal patches. The exact allowed API for cosmetic/controller addons remains subject to change. Blizzard has repeatedly revised restrictions based on community feedback [29][32].

2. **ConsolePort development status**: Development paused in late 2025; Midnight has now shipped. Verify current 12.x compatibility on GitHub before relying on it as prior art for API patterns [22][23].

3. **Axis trigger detection**: Whether WoW's `OnGamePadStick` events provide sufficient granularity to detect a "light" vs. "hard" trigger pull (as in BG3's DualSense implementation) was not fully confirmed from available documentation. The `GetDeviceRawState()` API suggests raw axis data is available, but the resolution and responsiveness for this use case is untested.

4. **Memory overhead of the secondary addon**: The report does not quantify the RAM footprint of a full UI replacement addon. WoW addons that breach saved variable limits trigger `SAVED_VARIABLES_TOO_LARGE` [16]. A large radial UI with per-character spell layout data could approach this.

5. **Nexus Mods BG3 mod #4925**: The specific feature set of this mod (listed in the research request) was not retrievable from public web sources at the time of this report.

6. **WoW console port plans**: Blizzard has not officially announced a console (PS5/Xbox) port of WoW. Any such announcement would dramatically change the native controller support landscape and the regulatory risk for such an addon.

---

## Sources

1. Gera, Emily. "How Baldur's Gate 3 adapts its expansive RPG gameplay for your DualSense controller." PlayStation Blog. September 5, 2023. https://blog.playstation.com/2023/09/05/how-baldurs-gate-3-adapts-its-expansive-rpg-gameplay-for-your-dualsense-controller/

2. GamingBolt. "Baldur's Gate 3 Controller UI, DualSense Features Explained." GamingBolt. September 2023. https://gamingbolt.com/baldurs-gate-3-controller-ui-dualsense-features-explained

3. Baird, Scott. "Baldur's Gate 3 Controller Guide: Button Layout, Shortcuts, & More." Gamepur. September 5, 2023. https://www.gamepur.com/guides/baldurs-gate-3-controller-guide-button-layout-shortcuts-more

4. HardcoreGamer. "Baldur's Gate 3 – All Controller Shortcuts." HardcoreGamer. August 4, 2023. https://hardcoregamer.com/db/bg3/baldurs-gate-3-all-controller-shortcuts/459724/

5. Larian Studios Forums. "Radial Menu (controller) customization." Larian Forums. 2023. https://forums.larian.com/ubbthreads.php?ubb=showflat&Number=880972

6. Nexus Mods. "Radial Hotbar Customization." Baldur's Gate 3 Nexus. https://www.nexusmods.com/baldursgate3/mods/18194

7. Steam Community. "Any way to make Controller UI better?" Steam Discussions: Baldur's Gate 3. 2023. https://steamcommunity.com/app/1086940/discussions/0/4289187252714137439/

8. Duff (Blizzard). "Guide to the new gamepad/controller support in 9.0.1!" WoW US Forums. October 16, 2020. https://us.forums.blizzard.com/en/wow/t/guide-to-the-new-gamepadcontroller-support-in-901/683913

9. MMonster. "How to Play WoW with a Controller in 2025." mmonster.co. March 26, 2025. https://mmonster.co/blog/how-to-play-with-controller-in-wow

10. Blizzard Entertainment EU. "Controller DF Setup (Quick No add-ons)." EU WoW Forums. 2022. https://eu.forums.blizzard.com/en/wow/t/controller-df-setup-quick-no-add-ons/408392

11. Warcraft Wiki. "Game Pad buttons." Warcraft Wiki. Updated 2020+. https://warcraft.wiki.gg/wiki/Game_Pad_buttons

12. Warcraft Wiki. "GAME_PAD_CONNECTED." Warcraft Wiki. https://warcraft.wiki.gg/wiki/GAME_PAD_CONNECTED

13. Wowpedia. "Console variables." Wowpedia. https://wowpedia.fandom.com/wiki/Console_variables

14. Wowpedia. "TOC format." Wowpedia. https://wowpedia.fandom.com/wiki/TOC_format

15. Wowpedia. "API LoadAddOn." Wowpedia. https://wowpedia.fandom.com/wiki/API_LoadAddOn

16. Wowpedia. "AddOn loading process." Wowpedia. https://wowpedia.fandom.com/wiki/AddOn_loading_process

17. Lindfors, Sebastian. "ConsolePort – Game Controller Addon for World of Warcraft." GitHub. https://github.com/seblindfors/ConsolePort

18. CurseForge. "ConsolePort – World of Warcraft Addons." CurseForge. https://www.curseforge.com/wow/addons/console-port

19. WowInterface. "ConsolePort." WowInterface. https://www.wowinterface.com/downloads/info23536-ConsolePort.html

20. GitHub. "ConsolePort_Rings source directory." ConsolePort repo. https://github.com/seblindfors/ConsolePort/tree/master/ConsolePort_Rings

21. Lindfors, Sebastian. "ConsolePort Releases." GitHub. https://github.com/seblindfors/ConsolePort/releases

22. Lindfors, Sebastian. "Sebastian | creating ConsolePort for World of Warcraft." Patreon. https://www.patreon.com/consoleport

23. WowVendor. "WoW controller support guide in 2025." WowVendor. https://wowvendor.com/media/wow/playing-wow-with-a-controller-how-to-guide-and-overview/

24. Vaxherd. "WoWXIV – Final Fantasy XIV-style UI tweaks for World of Warcraft." GitHub. https://github.com/vaxherd/WoWXIV

25. Wowpedia. "Secure Execution and Tainting." Wowpedia. https://wowpedia.fandom.com/wiki/Secure_Execution_and_Tainting

26. Wowpedia. "API InCombatLockdown." Wowpedia. https://wowpedia.fandom.com/wiki/API_InCombatLockdown

27. Warcraft Wiki. "Patch 12.0.0/API changes." Warcraft Wiki. https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes

28. Polygon. "WoW addon changes split players as 12.0 patch begins Blizzard..." Polygon. 2026. https://www.polygon.com/world-of-warcraft-midnight-prepatch-12-0-mods-addons/

29. Icy Veins. "Blizzard Relaxing More Addon Limitations in Midnight." Icy Veins. 2025. https://www.icy-veins.com/wow/news/blizzard-relaxing-more-addon-limitations-in-midnight/

30. WarcraftTavern. "Ion Hazzikostas Addresses Midnight's Addon Apocalypse Again." WarcraftTavern. 2025. https://www.warcrafttavern.com/wow/news/ion-hazzikostas-addresses-midnights-addon-apocalypse-again/

31. EpicCarry. "Top Addons For The WoW Midnight Pre-Patch Era." EpicCarry. 2025. https://epiccarry.com/blogs/wow-midnight-pre-patch-addons/

32. Wowhead. "Blizzard Continues to Loosen Addon API Restrictions and Whitelist Select Spells." Wowhead. 2025. https://www.wowhead.com/news/blizzard-continues-to-loosen-addon-api-restrictions-and-whitelist-select-spells-379691

33. Wowhead. "ElvUI Addon Guide – Updated for The War Within." Wowhead. https://www.wowhead.com/guide/elvui-addon-setup-customization

34. CurseForge. "Bartender4." CurseForge Addons. https://www.curseforge.com/wow/addons/bartender4

35. Final Fantasy XIV Official. "Mastering the UI / Cross Hotbar." FFXIV Promotional Site. https://na.finalfantasyxiv.com/uiguide/know/know-xhb/uiguide_know_xhb_q00198.html

36. AkhMorning. "PC Setup Controller Guide – FFXIV 7.0." AkhMorning. https://www.akhmorning.com/resources/controller-guide/pc-setup/

37. XIVBARS. "Final Fantasy XIV Cross Hotbar Setup and Layout Keybinding Tool." xivbars.com. https://www.xivbars.com/

38. Wurster, Mike. "World of Warcraft – Console UI." mikewursterdesign.com. https://www.mikewursterdesign.com/world-of-warcraft-console-ui/

39. Wowpedia. "World of Warcraft API." Wowpedia. https://wowpedia.fandom.com/wiki/World_of_Warcraft_API

40. Wowpedia. "Widget API." Wowpedia. https://wowpedia.fandom.com/wiki/Widget_API

41. AddOn Studio. "WoW:Removing Blizzard default frames." AddOn Studio. https://addonstudio.org/wiki/WoW:Removing_Blizzard_default_frames

42. WoWWiki Archive. "Removing Blizzard default frames." WoWWiki Fandom Archive. https://wowwiki-archive.fandom.com/wiki/Removing_Blizzard_default_frames

43. WoWWiki Archive. "SecureHandlers." WoWWiki Fandom Archive. https://wowwiki-archive.fandom.com/wiki/SecureHandlers

44. AddOn Studio. "WoW:SecureHandlers." AddOn Studio Wiki. https://addonstudio.org/wiki/WoW:SecureHandlers

45. WoWWiki Archive. "AddOn." WoWWiki Fandom Archive. https://wowwiki-archive.fandom.com/wiki/AddOn

46. Blizzard Entertainment. "Showing Elements in Combat Lockdown." WoW US Forums. https://us.forums.blizzard.com/en/wow/t/showing-elements-in-combat-lockdown/614762

47. WoWInterface. "Show/Hide Custom Frame in Combat Lockdown." WoWInterface Forums. https://www.wowinterface.com/forums/showthread.php?t=58808

48. Game Rant. "World of Warcraft Explains Why it is Killing Many Addons in Midnight." Game Rant. 2025. https://gamerant.com/world-of-warcraft-midnight-addon-changes-dev-comment/

49. Blizzard Watch. "Get your addons ready and kiss some old favorites goodbye before the [Midnight] pre-patch." Blizzard Watch. January 13, 2026. https://blizzardwatch.com/2026/01/13/addon-apocalypse-midnight/

50. Escapist Magazine. "World of Warcraft's Midnight pre-patch addon lists reignite community debate." Escapist Magazine. 2026. https://www.escapistmagazine.com/news-pre-patch-wow-addons-lists-suggests-blizzards-add-on-crusade-has-already-failed/

51. WoWVendor. "DBM and other combat addons disabled in Midnight." WoWVendor. 2025. https://wowvendor.com/media/wow/midnight-addons-ban/

52. Wowhead. "What Other Addons Will Be Broken in End-Game Content in Midnight." Wowhead. 2025. https://www.wowhead.com/news/what-other-addons-will-be-broken-in-end-game-content-in-midnight-378735

53. Blizzard US Forums. "No Controller Support – The War Within Patch 11.0.5 PTR." WoW US Forums. 2024. https://us.forums.blizzard.com/en/wow/t/no-controller-support/1974697

54. Wowhead. "Blizzard Announces Updates to User Interface in The War Within." Wowhead. 2024. https://www.wowhead.com/news/blizzard-announces-updates-to-user-interface-in-the-war-within-345343

55. AddOn Studio. "WoW:Events/System." AddOn Studio Wiki. https://addonstudio.org/wiki/WoW:Events/System

56. Warcraft Wiki. "API C_CVar.SetCVar." Warcraft Wiki. https://warcraft.wiki.gg/wiki/API_C_CVar.SetCVar

57. CurseForge. "ConsolePort – 2.9.0 release." CurseForge. https://www.curseforge.com/wow/addons/console-port/files/5463836

58. CurseForge. "RingMenuReborn." CurseForge. https://www.curseforge.com/wow/addons/ringmenureborn

59. ResetEra. "Baldur's Gate 3 controller tips & tricks for PlayStation 5 & Xbox players." ResetEra. 2023. https://www.resetera.com/threads/baldurs-gate-3-controller-tips-tricks-for-playstation-5-xbox-players.760275/

60. Prima Games. "All Controller Shortcuts in Baldur's Gate 3 (BG3)." Prima Games. 2023. https://primagames.com/tips/all-controller-shortcuts-in-baldurs-gate-3-bg3

61. Wowpedia. "API SetOverrideBinding." Wowpedia. https://wowpedia.fandom.com/wiki/API_SetOverrideBinding

62. AddOn Studio. "WoW:API SetOverrideBinding." AddOn Studio Wiki. https://addonstudio.org/wiki/WoW:API_SetOverrideBinding

63. Healbot Help. "Using UI Lockdown." Healbot Wiki. https://healbot.dpm15.net/wiki/doku.php/using:uilockdown

64. Wowpedia. "Category:API functions/restricted." Wowpedia. https://wowpedia.fandom.com/wiki/Category:API_functions/restricted

65. AddOn Studio. "Category:World of Warcraft API/Protected Functions." AddOn Studio Wiki. https://addonstudio.org/wiki/Category:World_of_Warcraft_API/Protected_Functions

66. AddonStudio / Icy-Veins Forums. "Introducing Dialogue UI: A Modern Makeover for Quest Interfaces." Icy-Veins Forums. https://www.icy-veins.com/forums/topic/78153-introducing-dialogue-ui-a-modern-makeover-for-quest-interfaces/

67. Addonswow.com. "WoW Immersion Addon." Addonswow.com. https://addonswow.com/immersion

68. Wowpedia. "API C_MountJournal.SummonByID." Wowpedia. https://wowpedia.fandom.com/wiki/API_C_MountJournal.SummonByID

69. GitHub. "BetterBags – A total replacement AddOn for World of Warcraft bags." GitHub. https://github.com/Cidan/BetterBags

70. Wowpedia. "API GetBinding." Wowpedia. https://wowpedia.fandom.com/wiki/API_GetBinding

71. Wowpedia. "API SaveBindings." Wowpedia. https://wowpedia.fandom.com/wiki/API_SaveBindings

72. CurseForge. "KeyBindProfiles." CurseForge Addons. https://www.curseforge.com/wow/addons/keybindprofiles

73. GitHub. "GossipChatter – Prints gossip/quest text to chat." GitHub. https://github.com/keyboardturner/GossipChatter

74. Warcraft Wiki. "Secret Values." Warcraft Wiki. https://warcraft.wiki.gg/wiki/Secret_Values

75. CurseForge. "ApiExplorer." CurseForge Addons. https://www.curseforge.com/wow/addons/apiexplorer

76. Blizzard Watch. "Dragonflight adds new Soft Target mode." Blizzard Watch. August 25, 2022. https://blizzardwatch.com/2022/08/25/soft-target-mode/

77. Battle Shout. "Soft Targeting, Does that Mean Console WoW?" Battle Shout. 2022. https://battle-shout.com/soft-targeting-wow/

78. YouTube. "Ways to Handle TARGETING When Playing with a CONTROLLER in WoW." YouTube. https://www.youtube.com/watch?v=sKvdDlQdLN8

79. FFXIV Console Games Wiki. "Controller Guide." FFXIV Wiki. https://ffxiv.consolegameswiki.com/wiki/Controller_Guide

80. AkhMorning. "Controller Targeting – FFXIV 7.0." AkhMorning. https://www.akhmorning.com/resources/controller-guide/controller-targeting/

81. AddOn Studio. "WoW:SecureUnitButtonTemplate." AddOn Studio Wiki. https://addonstudio.org/wiki/WoW:SecureUnitButtonTemplate

82. Wowpedia. "SecureUnitButtonTemplate." Wowpedia. https://wowpedia.fandom.com/wiki/SecureUnitButtonTemplate

83. GitHub. "Cell – A World of Warcraft raid frame addon." GitHub. https://github.com/enderneko/Cell

84. Wago.io. "KephUI – Cross Party Frames." Wago.io. https://wago.io/0Eml3NbHv

85. Blizzard US Forums. "Healing addons & their status." WoW US Forums. 2026. https://us.forums.blizzard.com/en/wow/t/healing-addons-their-status/2235343

86. Square Enix Forums. "Healer targeting on controller." FFXIV Forums. https://forum.square-enix.com/ffxiv/threads/384784-Healer-targeting-on-controller

87. WoW Lazy Macros. "Controllers, GSE, and You." WoW Lazy Macros Forums. https://wowlazymacros.com/t/controllers-gse-and-you/39240

88. YouTube / Throne & Liberty. "Customize controller for healing: BEST layout." YouTube. https://www.youtube.com/watch?v=np3hb2FetSA

