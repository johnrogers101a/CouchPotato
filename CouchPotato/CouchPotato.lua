-------------------------------------------------------------------------------
-- CouchPotato - BG3-inspired Radial Controller UI for World of Warcraft
-- Main Ace3 Entry Point
-------------------------------------------------------------------------------

-- Localize globals
local LibStub = LibStub
local CreateFrame = CreateFrame
local C_GamePad = C_GamePad
local C_AddOns = C_AddOns
local pairs = pairs
local type = type
local string_lower = string.lower
local string_match = string.match
local string_format = string.format
local ReloadUI = ReloadUI

-------------------------------------------------------------------------------
-- Addon Initialization
-------------------------------------------------------------------------------

local CP = LibStub("AceAddon-3.0"):NewAddon("CouchPotato", "AceConsole-3.0", "AceEvent-3.0")

-- Expose globally for cross-module access
-- Usage in other files: local CP = CouchPotato
_G["CouchPotato"] = CP

-- Version info
CP.version = "1.0.0"
CP.addonName = "CouchPotato"

-------------------------------------------------------------------------------
-- AceDB Defaults
-------------------------------------------------------------------------------

local defaults = {
    profile = {
        -- Core settings
        enabled = true,
        debugMode = false,
        
        -- UI settings
        uiScale = 1.0,
        radialAlpha = 0.9,
        
        -- Controller features
        vibrationEnabled = true,
        ledEnabled = true,
        
        -- Blizzard UI integration
        hideBlizzardFrames = true,
        
        -- Trigger behavior thresholds (0.0 - 1.0 axis values)
        peekThreshold = 0.35,   -- Trigger axis value to "peek" at radial
        lockThreshold = 0.75,   -- Trigger axis value to "lock" radial open
    },
    char = {
        -- Per-character wheel state
        currentWheel = 1,           -- Active wheel index (1-8)
        wheelLayouts = {},          -- Per-wheel slot assignments
        healerMode = false,         -- Heal mode enabled for this character
    },
}

-------------------------------------------------------------------------------
-- Lifecycle: OnInitialize
-- Called when SavedVariables are available (ADDON_LOADED)
-------------------------------------------------------------------------------

function CP:OnInitialize()
    -- Initialize AceDB
    self.db = LibStub("AceDB-3.0"):New("CouchPotatoDB", defaults, true)
    
    -- Register slash commands
    self:RegisterChatCommand("cp", "ChatCommand")
    self:RegisterChatCommand("couchpotato", "ChatCommand")
    
    self:DebugPrint("Initialized")
end

-------------------------------------------------------------------------------
-- Lifecycle: OnEnable
-- Called after PLAYER_LOGIN when the addon is enabled
-------------------------------------------------------------------------------

function CP:OnEnable()
    -- Register core events
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Entering combat
    self:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Leaving combat
    
    -- Check if controller is already active
    if self:IsControllerActive() then
        self:Print("Controller detected. Radial UI ready.")
        self:NotifyModules("CONTROLLER_CONNECTED")
    end
    
    self:DebugPrint("Enabled")
end

-------------------------------------------------------------------------------
-- Lifecycle: OnDisable
-- Called when the addon is disabled
-------------------------------------------------------------------------------

function CP:OnDisable()
    -- Unregister all events
    self:UnregisterAllEvents()
    
    -- Notify modules of shutdown
    self:NotifyModules("ADDON_DISABLING")
    
    self:DebugPrint("Disabled")
end

-------------------------------------------------------------------------------
-- Event Handlers
-------------------------------------------------------------------------------

function CP:PLAYER_ENTERING_WORLD(event, isLogin, isReload)
    if isLogin then
        self:DebugPrint("Player logged in")
    elseif isReload then
        self:DebugPrint("UI reloaded")
    end
    
    -- Re-check controller state on world enter
    if self:IsControllerActive() then
        self:NotifyModules("CONTROLLER_STATE_UPDATE", true)
    end
end

function CP:PLAYER_REGEN_DISABLED()
    -- Entering combat - notify modules for combat lockdown
    self:NotifyModules("COMBAT_LOCKDOWN_ENTER")
end

function CP:PLAYER_REGEN_ENABLED()
    -- Leaving combat - notify modules combat lockdown ended
    self:NotifyModules("COMBAT_LOCKDOWN_EXIT")
end

-------------------------------------------------------------------------------
-- Chat Command Handler
-- Usage: /cp show | hide | reload | config | reset | debug
-------------------------------------------------------------------------------

function CP:ChatCommand(input)
    input = input or ""
    local cmd = string_lower(input)
    cmd = string_match(cmd, "^%s*(%S+)") or ""
    
    if cmd == "show" then
        self:NotifyModules("SHOW_UI")
        self:Print("Radial UI shown")
        
    elseif cmd == "hide" then
        self:NotifyModules("HIDE_UI")
        self:Print("Radial UI hidden")
        
    elseif cmd == "reload" then
        ReloadUI()
        
    elseif cmd == "config" or cmd == "options" then
        self:Print("Configuration panel not yet implemented")
        -- TODO: Open config panel when implemented
        
    elseif cmd == "reset" then
        self.db:ResetProfile()
        self:Print("Profile reset to defaults")
        
    elseif cmd == "debug" then
        self.db.profile.debugMode = not self.db.profile.debugMode
        self:Print(string_format("Debug mode: %s", self.db.profile.debugMode and "ON" or "OFF"))
        
    elseif cmd == "status" then
        self:PrintStatus()
        
    else
        -- Show help
        self:Print("CouchPotato v" .. self.version)
        self:Print("Commands:")
        self:Print("  /cp show    - Show radial UI")
        self:Print("  /cp hide    - Hide radial UI")
        self:Print("  /cp reload  - Reload UI")
        self:Print("  /cp config  - Open configuration")
        self:Print("  /cp reset   - Reset profile to defaults")
        self:Print("  /cp status  - Show addon status")
        self:Print("  /cp debug   - Toggle debug mode")
    end
end

-------------------------------------------------------------------------------
-- Helper: Print addon status
-------------------------------------------------------------------------------

function CP:PrintStatus()
    self:Print("=== CouchPotato Status ===")
    self:Print(string_format("Version: %s", self.version))
    self:Print(string_format("Controller Active: %s", self:IsControllerActive() and "Yes" or "No"))
    self:Print(string_format("Enabled: %s", self.db.profile.enabled and "Yes" or "No"))
    self:Print(string_format("Current Wheel: %d", self.db.char.currentWheel))
    self:Print(string_format("Healer Mode: %s", self.db.char.healerMode and "Yes" or "No"))
    self:Print(string_format("Debug Mode: %s", self.db.profile.debugMode and "Yes" or "No"))
    
    -- Count loaded modules
    local moduleCount = 0
    for _ in self:IterateModules() do
        moduleCount = moduleCount + 1
    end
    self:Print(string_format("Modules Loaded: %d", moduleCount))
end

-------------------------------------------------------------------------------
-- Helper: Check if controller is active
-------------------------------------------------------------------------------

function CP:IsControllerActive()
    if C_GamePad and C_GamePad.IsEnabled then
        return C_GamePad.IsEnabled()
    end
    return false
end

-------------------------------------------------------------------------------
-- Helper: Notify all modules of a CouchPotato event
-- Modules can implement OnCPEvent(event, ...) to receive these
-------------------------------------------------------------------------------

function CP:NotifyModules(event, ...)
    for name, mod in self:IterateModules() do
        if mod.OnCPEvent then
            mod:OnCPEvent(event, ...)
        end
    end
end

-------------------------------------------------------------------------------
-- Helper: Debug print (only when debug mode enabled)
-------------------------------------------------------------------------------

function CP:DebugPrint(...)
    if self.db and self.db.profile and self.db.profile.debugMode then
        self:Print("|cff888888[Debug]|r", ...)
    end
end

-------------------------------------------------------------------------------
-- Module access pattern for other files:
--
-- local CP = CouchPotato
-- local MyModule = CP:NewModule("ModuleName", "AceEvent-3.0")
--
-- function MyModule:OnEnable()
--     -- Module enabled
-- end
--
-- function MyModule:OnCPEvent(event, ...)
--     -- Handle CouchPotato-specific events
-- end
-------------------------------------------------------------------------------
