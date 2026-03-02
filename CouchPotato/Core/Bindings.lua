-- CouchPotato/Core/Bindings.lua
-- Override-binding system for gamepad face buttons.
-- Uses SetOverrideBindingSpell (not SetBinding) for direct mode.
--
-- WHY NOT SetBinding + SaveBindings?
--   WoW's built-in gamepad preset system fires UPDATE_BINDINGS on every login
--   and re-applies its preset, overwriting any SetBinding calls for PAD keys.
--   SetOverrideBindingSpell sits in the OVERRIDE layer which has higher priority
--   than the preset / permanent layer and is never clobbered by presets.
--   Bindings are session-only but reapplied on every PLAYER_ENTERING_WORLD,
--   GAME_PAD_ACTIVE_CHANGED, etc. — so they are always in effect when needed.
--
-- TWO MODES:
--   Direct mode (wheel closed): face buttons → SetOverrideBindingSpell
--   Wheel mode  (wheel open):   face buttons → SetOverrideBindingClick → SecureActionButton
--
-- Face button → slot mapping (matches physical position on controller):
--   PAD4 (Y/△) → slot 1  (top,    12 o'clock)
--   PAD2 (B/○) → slot 4  (right,   3 o'clock)
--   PAD1 (A/✕) → slot 7  (bottom,  6 o'clock)
--   PAD3 (X/□) → slot 10 (left,    9 o'clock)
--
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local Bindings = CP:NewModule("Bindings")

Bindings.ownerFrame     = nil
Bindings.pendingApply   = false
Bindings.pendingClear   = false
Bindings.wheelOpen      = false
Bindings._applyTimer    = nil  -- debounce handle for UPDATE_BINDINGS

-- Which slot each face button maps to (by cardinal position in the 12-slot wheel)
Bindings.FACE_TO_SLOT = {
    PAD4 = 1,   -- Y / △ = top
    PAD2 = 4,   -- B / ○ = right
    PAD1 = 7,   -- A / ✕ = bottom
    PAD3 = 10,  -- X / □ = left
}

function Bindings:OnEnable()
    -- Guard: reuse the existing ownerFrame if we've been through a Disable/Enable
    -- cycle. Creating a second frame with the same global name throws a Lua error in WoW.
    if not self.ownerFrame then
        self.ownerFrame = CreateFrame("Frame", "CouchPotatoBindingOwner", UIParent,
            "SecureHandlerStateTemplate")
    end
    self:RegisterEvent("GAME_PAD_ACTIVE_CHANGED",      "OnGamePadActiveChanged")
    self:RegisterEvent("GAME_PAD_CONNECTED",           "OnGamePadConnected")
    self:RegisterEvent("GAME_PAD_DISCONNECTED",        "OnGamePadDisconnected")
    self:RegisterEvent("CVAR_UPDATE",                  "OnCVarUpdate")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",         "OnCombatLeave")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED","OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",        "OnEnteringWorld")
    self:RegisterEvent("UPDATE_BINDINGS",              "OnUpdateBindings")

    if C_GamePad.IsEnabled() then
        self:ApplyDirectBindings()
    end
end

function Bindings:OnDisable()
    self:UnregisterAllEvents()
    if not InCombatLockdown() then
        if self.ownerFrame then
            ClearOverrideBindings(self.ownerFrame)
        end
    end
end

-- ── Direct mode ──────────────────────────────────────────────────────────────
-- Face buttons cast spells via SetOverrideBindingSpell.
-- Override bindings have higher priority than WoW's gamepad preset and are
-- never clobbered when UPDATE_BINDINGS fires on login or preset change.
function Bindings:ApplyDirectBindings()
    if InCombatLockdown() then
        self.pendingApply = true
        return
    end

    local Specs  = CP:GetModule("Specs", true)
    local layout = Specs and Specs:GetCurrentLayout()

    -- Clear any existing overrides (wheel-mode click bindings or a previous
    -- direct-mode call) so we start from a clean state.
    ClearOverrideBindings(self.ownerFrame)
    self.wheelOpen = false

    -- Face buttons → spec spells via override bindings.
    -- isPriority=false: wheel-mode uses isPriority=true and takes precedence
    -- when the wheel is open, then direct-mode re-applies here on wheel close.
    if layout then
        if layout.primary   then
            SetOverrideBindingSpell(self.ownerFrame, false, "PAD4", layout.primary)   -- Y / △
        end
        if layout.secondary then
            SetOverrideBindingSpell(self.ownerFrame, false, "PAD2", layout.secondary) -- B / ○
        end
        if layout.tertiary  then
            SetOverrideBindingSpell(self.ownerFrame, false, "PAD1", layout.tertiary)  -- A / ✕
        end
        if layout.interrupt then
            SetOverrideBindingSpell(self.ownerFrame, false, "PAD3", layout.interrupt) -- X / □
        end
    end

    -- System defaults as transient overrides (WoW already has sane defaults here)
    SetOverrideBinding(self.ownerFrame, true, "PADLSTICK", "TOGGLEAUTORUN")
    SetOverrideBinding(self.ownerFrame, true, "PADRSTICK", "TARGETNEAREST")
    SetOverrideBinding(self.ownerFrame, true, "PADBACK",   "TOGGLEWORLDMAP")
end

-- ── Wheel mode ───────────────────────────────────────────────────────────────
-- Called by Radial when the wheel opens. Face buttons click the SecureActionButtons.
-- Transient override layer sits on top of the permanent spell bindings.
function Bindings:ApplyWheelBindings(wheelIdx)
    if InCombatLockdown() then return end

    local owner = self.ownerFrame
    ClearOverrideBindings(owner)
    self.wheelOpen = true

    -- Map face buttons to the four cardinal slot buttons on the active wheel
    for pad, slotIdx in pairs(self.FACE_TO_SLOT) do
        local btnName = string.format("CouchPotatoWheel%dSlot%d", wheelIdx, slotIdx)
        SetOverrideBindingClick(owner, true, pad, btnName, "LeftButton")
    end
end

-- Called by Radial when the wheel closes.
function Bindings:RestoreDirectBindings()
    self:ApplyDirectBindings()
end

-- ── Event handlers ───────────────────────────────────────────────────────────
function Bindings:OnGamePadActiveChanged(event, isActive)
    if isActive then self:ApplyDirectBindings()
    else             self:ClearControllerBindings() end
end

function Bindings:OnGamePadConnected()
    if C_GamePad.IsEnabled() then self:ApplyDirectBindings() end
end

function Bindings:OnGamePadDisconnected()
    self:ClearControllerBindings()
end

function Bindings:OnCVarUpdate(event, cvarName, cvarValue)
    if cvarName ~= "GamePadEnable" then return end
    if cvarValue == "1" then self:ApplyDirectBindings()
    else                     self:ClearControllerBindings() end
end

function Bindings:OnCombatLeave()
    if self.pendingApply then
        self.pendingApply = false
        self:ApplyDirectBindings()
    elseif self.pendingClear then
        self.pendingClear = false
        self:ClearControllerBindings()
    end
end

function Bindings:OnSpecChanged()
    if C_GamePad.IsEnabled() and not self.wheelOpen then
        self:ApplyDirectBindings()
    end
end

function Bindings:OnEnteringWorld()
    if C_GamePad.IsEnabled() then self:ApplyDirectBindings() end
end

-- UPDATE_BINDINGS: debounced reapply — batch all calls within a 0.5 s window
function Bindings:OnUpdateBindings()
    if self._applyTimer then
        self._applyTimer:Cancel()
    end
    self._applyTimer = self:ScheduleTimer(function()
        self._applyTimer = nil
        if C_GamePad.IsEnabled() and not self.wheelOpen then
            self:ApplyDirectBindings()
        end
    end, 0.5)
end

function Bindings:ClearControllerBindings()
    if InCombatLockdown() then
        self.pendingClear = true
        return
    end
    -- Clear all override bindings set by this frame (both direct and wheel mode).
    -- The permanent-layer bindings (WoW's gamepad preset) are untouched.
    if self.ownerFrame then
        ClearOverrideBindings(self.ownerFrame)
    end
end

-- Legacy / compat
function Bindings:ApplyControllerBindings() self:ApplyDirectBindings() end
