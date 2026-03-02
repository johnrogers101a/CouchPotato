-- CouchPotato/Core/Bindings.lua
-- Minimal override-binding system for CouchPotato wheel trigger.
--
-- ARCHITECTURE:
--   When wheel is CLOSED (normal play):
--     - CouchPotato binds ONLY PADRTRIGGER → CouchPotatoTriggerBtn (opens wheel)
--     - PAD1-4 (face buttons): WoW handles normally (action bars, etc.)
--     - All other buttons: WoW handles normally
--     - CouchPotato stays out of the way — no interception, no overrides
--
--   When wheel is OPEN:
--     - CouchPotato overrides PAD1-4 → wheel slot SecureActionButtons
--     - CouchPotato overrides PADLSHOULDER/PADRSHOULDER → cycle buttons
--     - PADRTRIGGER stays bound (now closes the wheel)
--
--   When wheel CLOSES:
--     - ClearOverrideBindings restores ALL of WoW's normal bindings
--     - Re-apply ONLY the PADRTRIGGER binding (so user can reopen wheel)
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
    -- Reuse existing ownerFrame if we've been through a Disable/Enable cycle.
    -- CreateFrame with the same global name throws a Lua error in WoW.
    if not self.ownerFrame then
        self.ownerFrame = CreateFrame("Frame", "CouchPotatoBindingOwner", UIParent,
            "SecureHandlerStateTemplate")
    end

    self:RegisterEvent("GAME_PAD_ACTIVE_CHANGED",      "OnGamePadActiveChanged")
    self:RegisterEvent("GAME_PAD_CONNECTED",           "OnGamePadConnected")
    self:RegisterEvent("GAME_PAD_DISCONNECTED",        "OnGamePadDisconnected")
    self:RegisterEvent("CVAR_UPDATE",                  "OnCVarUpdate")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",         "OnCombatLeave")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",        "OnEnteringWorld")
    self:RegisterEvent("UPDATE_BINDINGS",              "OnUpdateBindings")

    if C_GamePad.IsEnabled() and not self.wheelOpen then
        self:ApplyTriggerBinding()
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

-- ── Trigger binding ──────────────────────────────────────────────────────────
-- Sets ONLY the wheel-open trigger. Called on enable and after wheel closes.
-- We do NOT touch PAD1-4 or any other buttons — WoW handles those normally.
function Bindings:ApplyTriggerBinding()
    if InCombatLockdown() then
        self.pendingApply = true
        return
    end
    
    ClearOverrideBindings(self.ownerFrame)
    self.wheelOpen = false
    
    -- Only bind the trigger. Everything else is WoW's to manage.
    SetOverrideBindingClick(self.ownerFrame, true, "PADRTRIGGER", "CouchPotatoTriggerBtn", "LeftButton")
end

-- ── Wheel mode ───────────────────────────────────────────────────────────────
-- Called by Radial when the wheel opens. Only bumpers + trigger needed now.
function Bindings:ApplyWheelBindings(wheelIdx)
    if InCombatLockdown() then return end

    local owner = self.ownerFrame
    ClearOverrideBindings(owner)
    self.wheelOpen = true

    -- Bumpers cycle wheels while open
    SetOverrideBindingClick(owner, true, "PADLSHOULDER", "CouchPotatoLSBtn", "LeftButton")
    SetOverrideBindingClick(owner, true, "PADRSHOULDER", "CouchPotatoRSBtn", "LeftButton")

    -- Keep trigger bound (AnyDown opens, AnyUp confirms+closes)
    SetOverrideBindingClick(owner, true, "PADRTRIGGER", "CouchPotatoTriggerBtn", "LeftButton")
end

-- Called by Radial when the wheel closes.
function Bindings:RestoreDirectBindings()
    if InCombatLockdown() then return end
    ClearOverrideBindings(self.ownerFrame)
    self.wheelOpen = false
    self:ApplyTriggerBinding()
end

-- ── Event handlers ───────────────────────────────────────────────────────────
function Bindings:OnGamePadActiveChanged(event, isActive)
    if isActive and not self.wheelOpen then
        self:ApplyTriggerBinding()
    end
    -- Bug fix: Do NOT clear bindings on isActive=false. GAME_PAD_ACTIVE_CHANGED
    -- fires on every input-source switch (including mouse move/keypress).
    -- Real deactivation is covered by OnCVarUpdate(GamePadEnable=0) and OnGamePadDisconnected.
end

function Bindings:OnGamePadConnected()
    if C_GamePad.IsEnabled() and not self.wheelOpen then
        self:ApplyTriggerBinding()
    end
end

function Bindings:OnGamePadDisconnected()
    self:ClearControllerBindings()
end

function Bindings:OnCVarUpdate(event, cvarName, cvarValue)
    if cvarName ~= "GamePadEnable" then return end
    if cvarValue == "1" and not self.wheelOpen then
        self:ApplyTriggerBinding()
    elseif cvarValue == "0" then
        self:ClearControllerBindings()
    end
end

function Bindings:OnCombatLeave()
    if self.pendingApply then
        self.pendingApply = false
        self:ApplyTriggerBinding()
    elseif self.pendingClear then
        self.pendingClear = false
        self:ClearControllerBindings()
    end
end

function Bindings:OnEnteringWorld()
    if C_GamePad.IsEnabled() and not self.wheelOpen then
        self:ApplyTriggerBinding()
    end
end

-- UPDATE_BINDINGS: debounced reapply — batch all calls within a 0.5 s window
function Bindings:OnUpdateBindings()
    if self._applyTimer then
        self._applyTimer:Cancel()
    end
    self._applyTimer = self:ScheduleTimer(function()
        self._applyTimer = nil
        if C_GamePad.IsEnabled() and not self.wheelOpen then
            self:ApplyTriggerBinding()
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
function Bindings:ApplyControllerBindings() self:ApplyTriggerBinding() end
