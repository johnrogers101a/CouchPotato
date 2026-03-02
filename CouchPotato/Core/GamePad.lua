-- CouchPotato/Core/GamePad.lua
-- C_GamePad integration: vibration, state management, LED dispatch
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local GamePad = CP:NewModule("GamePad", "AceEvent-3.0", "AceTimer-3.0")

-- State tracking
GamePad.isActive = false
GamePad.deviceID = nil
GamePad.triggerState = { left = 0.0, right = 0.0 }
GamePad.peekTimer = nil

-- Vibration pattern definitions
-- C_GamePad.SetVibration(type, intensity): type = "Low"|"High"|"LTrigger"|"RTrigger"
local VIBRATION_PATTERNS = {
    MENU_OPEN        = { vibeType = "Low",      intensity = 0.3,  duration = 0.1  },
    MENU_CLOSE       = { vibeType = "Low",      intensity = 0.2,  duration = 0.08 },
    MENU_SELECT      = { vibeType = "High",     intensity = 0.5,  duration = 0.12 },
    WHEEL_CYCLE      = { vibeType = "LTrigger", intensity = 0.25, duration = 0.08 },
    WHEEL_PEEK       = { vibeType = "RTrigger", intensity = 0.2,  duration = 0.05 },
    WHEEL_LOCK       = { vibeType = "RTrigger", intensity = 0.5,  duration = 0.15 },
    COMBAT_ENTER     = { vibeType = "High",     intensity = 0.65, duration = 0.2  },
    HEAL_MODE_TOGGLE = { vibeType = "Low",      intensity = 0.4,  duration = 0.12 },
    TARGET_CHANGE    = { vibeType = "Low",      intensity = 0.2,  duration = 0.06 },
    ABILITY_USE      = { vibeType = "High",     intensity = 0.3,  duration = 0.08 },
    ERROR_BLOCKED    = { vibeType = "High",     intensity = 0.8,  duration = 0.3  },
}

function GamePad:OnEnable()
    -- Register events
    self:RegisterEvent("GAME_PAD_ACTIVE_CHANGED", "OnGamePadActiveChanged")
    self:RegisterEvent("GAME_PAD_CONNECTED", "OnGamePadConnected")
    self:RegisterEvent("GAME_PAD_DISCONNECTED", "OnGamePadDisconnected")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEnter")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatLeave")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCast")
    
    -- Initialize state
    self.isActive = C_GamePad.IsEnabled()
    if self.isActive then
        self.deviceID = C_GamePad.GetActiveDeviceID()
        
        -- Update LED for current spec
        local LED = CP:GetModule("LED", true)
        if LED then
            LED:UpdateForCurrentSpec()
        end
    end
end

function GamePad:OnDisable()
    self:UnregisterAllEvents()
    if self.peekTimer then
        self:CancelTimer(self.peekTimer)
        self.peekTimer = nil
    end
end

-- Event: GAME_PAD_ACTIVE_CHANGED
function GamePad:OnGamePadActiveChanged(event, isActive)
    self.isActive = isActive
    
    if isActive then
        self.deviceID = C_GamePad.GetActiveDeviceID()
        
        -- Update LED
        local LED = CP:GetModule("LED", true)
        if LED then
            LED:UpdateForCurrentSpec()
        end
        
        -- Reapply bindings
        local Bindings = CP:GetModule("Bindings", true)
        if Bindings then
            Bindings:ApplyControllerBindings()
        end
    else
        self.deviceID = nil
        
        -- Clear LED
        local LED = CP:GetModule("LED", true)
        if LED then
            LED:ClearColor()
        end
    end
end

-- Event: GAME_PAD_CONNECTED
function GamePad:OnGamePadConnected(event, deviceID)
    self.deviceID = deviceID
    self.isActive = C_GamePad.IsEnabled()
end

-- Event: GAME_PAD_DISCONNECTED
function GamePad:OnGamePadDisconnected(event, deviceID)
    if self.deviceID == deviceID then
        self.deviceID = nil
        self.isActive = false
    end
end

-- Event: PLAYER_REGEN_DISABLED (entering combat)
function GamePad:OnCombatEnter()
    self:Vibrate("COMBAT_ENTER")
    
    -- Notify Radial module
    local Radial = CP:GetModule("Radial", true)
    if Radial and Radial.OnCombatStart then
        Radial:OnCombatStart()
    end
end

-- Event: PLAYER_REGEN_ENABLED (leaving combat)
function GamePad:OnCombatLeave()
    -- Placeholder for future combat exit logic
end

-- Event: UNIT_SPELLCAST_SUCCEEDED
function GamePad:OnSpellCast(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if not CP.db.profile.ledEnabled then return end
    
    -- Update LED for spell school
    local LED = CP:GetModule("LED", true)
    if LED then
        LED:SetColorForSpell(spellID)
    end
    
    -- Brief ability use haptic
    self:Vibrate("ABILITY_USE")
end

-- Vibration system
function GamePad:Vibrate(patternName)
    if not CP.db.profile.vibrationEnabled then return end
    if not C_GamePad.IsEnabled() then return end
    
    local p = VIBRATION_PATTERNS[patternName]
    if not p then return end
    
    C_GamePad.SetVibration(p.vibeType, p.intensity)
    self:ScheduleTimer(function()
        C_GamePad.StopVibration()
    end, p.duration)
end

-- Trigger axis reading
function GamePad:GetTriggerValues()
    local deviceID = C_GamePad.GetActiveDeviceID()
    if not deviceID then return 0, 0 end
    
    -- GetDeviceMappedState returns standardized button names
    local mapped = C_GamePad.GetDeviceMappedState(deviceID)
    if not mapped then return 0, 0 end
    
    -- Trigger axes are exposed as analog values (0.0-1.0)
    local lt = mapped.leftTrigger or 0
    local rt = mapped.rightTrigger or 0
    
    return lt, rt
end

-- Public API
function GamePad:IsActive()
    return self.isActive
end

function GamePad:GetDeviceID()
    return self.deviceID
end

function GamePad:SetLEDColor(r, g, b)
    if not C_GamePad.IsEnabled() then return end
    local color = CreateColor(r, g, b)
    C_GamePad.SetLedColor(color)
end

function GamePad:ClearLEDColor()
    if not C_GamePad.IsEnabled() then return end
    C_GamePad.ClearLedColor()
end
