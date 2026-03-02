-- CouchPotato/Core/Bindings.lua
-- SetOverrideBinding system: controller layout applied non-destructively.
-- Override bindings layer on TOP of existing bindings — ClearOverrideBindings
-- restores originals automatically (WoW's built-in save/restore).
--
-- TWO MODES:
--   Direct mode (wheel closed): face buttons → spells from spec layout
--   Wheel mode  (wheel open):   face buttons → click radial slot SecureActionButtons
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

Bindings.ownerFrame   = nil
Bindings.pendingApply = false
Bindings.pendingClear = false
Bindings.wheelOpen    = false

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
        self.ownerFrame = CreateFrame("Frame", "CouchPotatoBindingOwner", UIParent)
    end
    self:RegisterEvent("GAME_PAD_ACTIVE_CHANGED",     "OnGamePadActiveChanged")
    self:RegisterEvent("GAME_PAD_CONNECTED",          "OnGamePadConnected")
    self:RegisterEvent("GAME_PAD_DISCONNECTED",       "OnGamePadDisconnected")
    self:RegisterEvent("CVAR_UPDATE",                 "OnCVarUpdate")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",        "OnCombatLeave")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED","OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",       "OnEnteringWorld")

    if C_GamePad.IsEnabled() then
        self:ApplyDirectBindings()
    end
end

function Bindings:OnDisable()
    self:UnregisterAllEvents()
    if self.ownerFrame then
        ClearOverrideBindings(self.ownerFrame)
    end
end

-- ── Direct mode ─────────────────────────────────────────────────────────────
-- Face buttons cast spells directly; shoulders still cycle wheel.
function Bindings:ApplyDirectBindings()
    if InCombatLockdown() then
        self.pendingApply = true
        return
    end

    local Specs = CP:GetModule("Specs", true)
    local layout = Specs and Specs:GetCurrentLayout()
    local owner  = self.ownerFrame

    ClearOverrideBindings(owner)
    self.wheelOpen = false

    -- Face buttons → primary abilities from spec layout
    if layout then
        if layout.primary   then SetOverrideBindingSpell(owner, true, "PAD4", layout.primary)   end  -- Y
        if layout.secondary then SetOverrideBindingSpell(owner, true, "PAD2", layout.secondary)  end  -- B
        if layout.tertiary  then SetOverrideBindingSpell(owner, true, "PAD1", layout.tertiary)   end  -- A
        if layout.interrupt then SetOverrideBindingSpell(owner, true, "PAD3", layout.interrupt)  end  -- X
    end

    -- System defaults
    SetOverrideBinding(owner, true, "PADLSTICK", "TOGGLEAUTORUN")
    SetOverrideBinding(owner, true, "PADRSTICK", "TARGETNEAREST")
    SetOverrideBinding(owner, true, "PADBACK",   "TOGGLEWORLDMAP")

    if layout then
        CP:Print(string.format("Applied %s bindings.", layout.specName or "controller"))
    end
end

-- ── Wheel mode ───────────────────────────────────────────────────────────────
-- Called by Radial when the wheel opens. Face buttons click the SecureActionButtons.
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

    -- Keep system bindings
    SetOverrideBinding(owner, true, "PADLSTICK", "TOGGLEAUTORUN")
    SetOverrideBinding(owner, true, "PADRSTICK", "TARGETNEAREST")
    SetOverrideBinding(owner, true, "PADBACK",   "TOGGLEWORLDMAP")
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

function Bindings:ClearControllerBindings()
    if InCombatLockdown() then
        self.pendingClear = true
        return
    end
    if self.ownerFrame then
        ClearOverrideBindings(self.ownerFrame)
        CP:Print("Keyboard bindings restored.")
    end
end

-- Legacy / compat
function Bindings:ApplyControllerBindings() self:ApplyDirectBindings() end
