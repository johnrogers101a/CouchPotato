-- CouchPotato/Core/Bindings.lua
-- Persistent binding system using SetBinding+SaveBindings (ConsolePort pattern).
-- Override bindings are ONLY used for the transient wheel-open state.
--
-- TWO MODES:
--   Direct mode (wheel closed): face buttons → permanent SetBinding spells
--   Wheel mode  (wheel open):   face buttons → transient SetOverrideBindingClick
--
-- Why SetBinding instead of SetOverrideBindingSpell for direct mode:
--   SetOverrideBindingSpell is session-only; bindings vanish on /reload.
--   SetBinding + SaveBindings writes to disk and survives reloads and restarts.
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
Bindings._savedBindings = {}   -- PAD1-4 permanent bindings captured before first apply
Bindings._applyTimer    = nil  -- debounce handle for UPDATE_BINDINGS

-- Face buttons managed via permanent SetBinding (direct mode only)
local DIRECT_PADS = { "PAD4", "PAD2", "PAD1", "PAD3" }

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
        -- Restore original permanent bindings before we leave
        if next(self._savedBindings) then
            for _, pad in ipairs(DIRECT_PADS) do
                local action = self._savedBindings[pad]
                SetBinding(pad, (action and action ~= "") and action or nil)
            end
            SaveBindings(GetCurrentBindingSet())
            self._savedBindings = {}
        end
        if self.ownerFrame then
            ClearOverrideBindings(self.ownerFrame)
        end
    end
end

-- ── Direct mode ──────────────────────────────────────────────────────────────
-- Face buttons cast spells via permanent SetBinding; system keys via overrides.
function Bindings:ApplyDirectBindings()
    if InCombatLockdown() then
        self.pendingApply = true
        return
    end

    local Specs  = CP:GetModule("Specs", true)
    local layout = Specs and Specs:GetCurrentLayout()

    -- Snapshot originals once, before we overwrite anything
    if not next(self._savedBindings) then
        for _, pad in ipairs(DIRECT_PADS) do
            self._savedBindings[pad] = GetBindingAction(pad, false)  -- permanent layer only
        end
    end

    -- Clear any transient wheel-mode overrides
    ClearOverrideBindings(self.ownerFrame)
    self.wheelOpen = false

    -- Face buttons → spec spells via permanent bindings (survive /reload)
    if layout then
        if layout.primary   then SetBinding("PAD4", "SPELL " .. layout.primary)   end  -- Y
        if layout.secondary then SetBinding("PAD2", "SPELL " .. layout.secondary) end  -- B
        if layout.tertiary  then SetBinding("PAD1", "SPELL " .. layout.tertiary)  end  -- A
        if layout.interrupt then SetBinding("PAD3", "SPELL " .. layout.interrupt) end  -- X
        SaveBindings(GetCurrentBindingSet())
        CP:Print(string.format("Applied %s bindings.", layout.specName or "controller"))
    end

    -- System defaults stay as transient overrides (WoW already has sane defaults here)
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
    -- Restore whatever WoW had in the permanent layer before we touched it
    for _, pad in ipairs(DIRECT_PADS) do
        local action = self._savedBindings[pad]
        SetBinding(pad, (action and action ~= "") and action or nil)
    end
    SaveBindings(GetCurrentBindingSet())
    self._savedBindings = {}
    if self.ownerFrame then
        ClearOverrideBindings(self.ownerFrame)
    end
    CP:Print("Keyboard bindings restored.")
end

-- Legacy / compat
function Bindings:ApplyControllerBindings() self:ApplyDirectBindings() end
