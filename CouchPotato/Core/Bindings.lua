-- CouchPotato/Core/Bindings.lua
-- SetOverrideBinding system: controller layout applied non-destructively
-- Keyboard bindings are NEVER modified; override bindings are cleared on disconnect
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local Bindings = CP:NewModule("Bindings")

-- State
Bindings.ownerFrame = nil
Bindings.pendingApply = false
Bindings.pendingClear = false
Bindings.ltHoldTimer = nil
Bindings.ltHeld = false

function Bindings:OnEnable()
    -- Create owner frame for bindings
    self.ownerFrame = CreateFrame("Frame", "CouchPotatoBindingOwner", UIParent)
    
    -- Register events
    self:RegisterEvent("GAME_PAD_ACTIVE_CHANGED", "OnGamePadActiveChanged")
    self:RegisterEvent("GAME_PAD_CONNECTED", "OnGamePadConnected")
    self:RegisterEvent("GAME_PAD_DISCONNECTED", "OnGamePadDisconnected")
    self:RegisterEvent("CVAR_UPDATE", "OnCVarUpdate")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatLeave")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    
    -- Apply bindings if controller is active
    if C_GamePad.IsEnabled() then
        self:ApplyControllerBindings()
    end
end

function Bindings:OnDisable()
    self:UnregisterAllEvents()
    if self.ownerFrame then
        ClearOverrideBindings(self.ownerFrame)
    end
end

-- Event: GAME_PAD_ACTIVE_CHANGED
function Bindings:OnGamePadActiveChanged(event, isActive)
    if isActive then
        self:ApplyControllerBindings()
    else
        self:ClearControllerBindings()
    end
end

-- Event: GAME_PAD_CONNECTED
function Bindings:OnGamePadConnected()
    if C_GamePad.IsEnabled() then
        self:ApplyControllerBindings()
    end
end

-- Event: GAME_PAD_DISCONNECTED
function Bindings:OnGamePadDisconnected()
    self:ClearControllerBindings()
end

-- Event: CVAR_UPDATE
function Bindings:OnCVarUpdate(event, cvarName, cvarValue)
    if cvarName ~= "GamePadEnable" then return end
    
    if cvarValue == "1" then
        self:ApplyControllerBindings()
    elseif cvarValue == "0" then
        self:ClearControllerBindings()
    end
end

-- Event: PLAYER_REGEN_ENABLED (leaving combat)
function Bindings:OnCombatLeave()
    if self.pendingApply then
        self.pendingApply = false
        self:ApplyControllerBindings()
    elseif self.pendingClear then
        self.pendingClear = false
        self:ClearControllerBindings()
    end
end

-- Event: PLAYER_SPECIALIZATION_CHANGED
function Bindings:OnSpecChanged()
    if C_GamePad.IsEnabled() then
        self:ApplyControllerBindings()
    end
end

-- Event: PLAYER_ENTERING_WORLD
function Bindings:OnEnteringWorld()
    if C_GamePad.IsEnabled() then
        self:ApplyControllerBindings()
    end
end

-- Apply controller bindings for current spec
function Bindings:ApplyControllerBindings()
    if InCombatLockdown() then
        self.pendingApply = true
        return
    end
    
    local Specs = CP:GetModule("Specs", true)
    if not Specs then return end
    
    local layout = Specs:GetCurrentLayout()
    if not layout then return end
    
    local owner = self.ownerFrame
    ClearOverrideBindings(owner)
    
    -- RT/LT are reserved for the Radial wheel (RT = open wheel, LT = modifier layer).
    -- Do NOT bind PADRTRIGGER or PADLTRIGGER here — the Radial module owns those.
    -- PADRSHOULDER / PADLSHOULDER cycle wheels while the radial is open.
    -- Face buttons activate the highlighted radial slot.
    -- D-pad: used for targeting / navigation (VirtualCursor module).
    -- System bindings
    SetOverrideBinding(owner, true, "PADLSTICK", "TOGGLEAUTORUN")
    SetOverrideBinding(owner, true, "PADRSTICK", "TARGETNEAREST")
    SetOverrideBinding(owner, true, "PADBACK", "TOGGLEWORLDMAP")
    
    CP:Print(string.format("Applied %s bindings.", layout.specName or "controller"))
end

-- Clear controller bindings (restore keyboard)
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

-- LT hold modifier layer
function Bindings:OnLTDown()
    self.ltHeld = false
    self.ltHoldTimer = C_Timer.After(0.2, function()
        self.ltHeld = true
        self:ApplyModifierLayer()
    end)
end

function Bindings:OnLTUp()
    if not self.ltHeld then
        -- Tap: movement spell fires via normal binding
    else
        self.ltHeld = false
        self:ClearModifierLayer()
    end
end

function Bindings:ApplyModifierLayer()
    if InCombatLockdown() then return end
    
    local Specs = CP:GetModule("Specs", true)
    if not Specs then return end
    
    local layout = Specs:GetCurrentLayout()
    if not layout or not layout.modLayer then return end
    
    local owner = self.ownerFrame
    if layout.modLayer.dpadUp then
        SetOverrideBindingSpell(owner, true, "PADDUP", layout.modLayer.dpadUp)
    end
    if layout.modLayer.dpadDown then
        SetOverrideBindingSpell(owner, true, "PADDDOWN", layout.modLayer.dpadDown)
    end
    if layout.modLayer.dpadLeft then
        SetOverrideBindingSpell(owner, true, "PADDLEFT", layout.modLayer.dpadLeft)
    end
    if layout.modLayer.dpadRight then
        SetOverrideBindingSpell(owner, true, "PADDRIGHT", layout.modLayer.dpadRight)
    end
end

function Bindings:ClearModifierLayer()
    if not InCombatLockdown() then
        self:ApplyControllerBindings()
    end
end
