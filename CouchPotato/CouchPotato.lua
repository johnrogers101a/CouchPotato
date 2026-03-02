-------------------------------------------------------------------------------
-- CouchPotato - BG3-inspired Radial Controller UI for World of Warcraft
-- Pure WoW Lua — no LibStub, no Ace3, no external dependencies
-------------------------------------------------------------------------------

-- Localize globals
local CreateFrame = CreateFrame
local C_GamePad = C_GamePad
local C_AddOns = C_AddOns
local pairs = pairs
local ipairs = ipairs
local type = type
local string_lower = string.lower
local string_match = string.match
local string_format = string.format
local ReloadUI = ReloadUI

-------------------------------------------------------------------------------
-- Core namespace
-------------------------------------------------------------------------------
local CP = {}
_G["CouchPotato"] = CP

CP.version    = "1.0.0"
CP.addonName  = "CouchPotato"
CP._modules   = {}           -- [name] = module table
CP._eventCallbacks = {}      -- [event] = list of {obj, fn}

-------------------------------------------------------------------------------
-- Central event dispatch frame (single frame for ALL events)
-------------------------------------------------------------------------------
local _mainFrame = CreateFrame("Frame")
CP._mainFrame = _mainFrame   -- expose for testing/debugging

_mainFrame:SetScript("OnEvent", function(_, event, ...)
    local cbs = CP._eventCallbacks[event]
    if not cbs then return end
    -- snapshot to allow safe modification during iteration
    local snapshot = {}
    for i = 1, #cbs do snapshot[i] = cbs[i] end
    for i = 1, #snapshot do
        snapshot[i].fn(snapshot[i].obj, event, ...)
    end
end)

-------------------------------------------------------------------------------
-- Event API factory — injects RegisterEvent/Unregister/UnregisterAll onto obj
-------------------------------------------------------------------------------
local function _injectEventAPI(obj)
    obj._ownedEvents = {}

    function obj:RegisterEvent(event, handler)
        local cbs = CP._eventCallbacks[event]
        if not cbs then
            cbs = {}
            CP._eventCallbacks[event] = cbs
            _mainFrame:RegisterEvent(event)
        end

        -- Resolve handler
        local fn
        if type(handler) == "function" then
            fn = handler
        elseif type(handler) == "string" then
            local methodName = handler
            fn = function(self_, evt, ...)
                if self_[methodName] then self_[methodName](self_, evt, ...) end
            end
        else
            -- No handler — use event name as method name
            fn = function(self_, evt, ...)
                if self_[evt] then self_[evt](self_, evt, ...) end
            end
        end

        -- Replace existing entry for this obj, or append
        for i = 1, #cbs do
            if cbs[i].obj == obj then
                cbs[i].fn = fn
                self._ownedEvents[event] = true
                return
            end
        end
        cbs[#cbs + 1] = { obj = obj, fn = fn }
        self._ownedEvents[event] = true
    end

    function obj:UnregisterEvent(event)
        local cbs = CP._eventCallbacks[event]
        if not cbs then return end
        for i = 1, #cbs do
            if cbs[i].obj == obj then
                table.remove(cbs, i)
                break
            end
        end
        if #cbs == 0 then
            CP._eventCallbacks[event] = nil
            _mainFrame:UnregisterEvent(event)
        end
        if self._ownedEvents then self._ownedEvents[event] = nil end
    end

    function obj:UnregisterAllEvents()
        for event in pairs(self._ownedEvents) do
            self:UnregisterEvent(event)
        end
        self._ownedEvents = {}
    end
end

-------------------------------------------------------------------------------
-- Timer API factory — injects ScheduleTimer/ScheduleRepeatingTimer/CancelTimer
-------------------------------------------------------------------------------
local function _injectTimerAPI(obj)
    function obj:ScheduleTimer(handler, delay, ...)
        local args = { ... }
        local cancelled = false
        local fn
        if type(handler) == "function" then
            fn = handler
        else
            local methodName = handler
            fn = function() if self[methodName] then self[methodName](self) end end
        end
        C_Timer.After(delay, function()
            if not cancelled then fn(unpack(args)) end
        end)
        return {
            Cancel      = function() cancelled = true end,
            IsCancelled = function() return cancelled end,
        }
    end

    function obj:ScheduleRepeatingTimer(handler, interval)
        local fn
        if type(handler) == "function" then
            fn = handler
        else
            local methodName = handler
            fn = function() if self[methodName] then self[methodName](self) end end
        end
        return C_Timer.NewTicker(interval, fn)
    end

    function obj:CancelTimer(handle)
        if type(handle) == "table" and handle.Cancel then
            handle:Cancel()
        end
    end
end

-------------------------------------------------------------------------------
-- Print API factory
-------------------------------------------------------------------------------
local function _injectPrintAPI(obj)
    function obj:Print(...)
        local parts = { ... }
        local msg = "|cff69ccf0CouchPotato|r:"
        for i = 1, #parts do
            msg = msg .. " " .. tostring(parts[i])
        end
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

-------------------------------------------------------------------------------
-- Apply all APIs to CP itself
-------------------------------------------------------------------------------
_injectEventAPI(CP)
_injectTimerAPI(CP)
_injectPrintAPI(CP)

-------------------------------------------------------------------------------
-- Module system
-------------------------------------------------------------------------------
function CP:NewModule(name)
    local mod = {
        name     = name,
        _enabled = false,
    }
    _injectEventAPI(mod)
    _injectTimerAPI(mod)
    _injectPrintAPI(mod)

    function mod:Enable()
        self._enabled = true
        if self.OnEnable then self:OnEnable() end
    end

    function mod:Disable()
        self._enabled = false
        if self.OnDisable then self:OnDisable() end
    end

    function mod:IsEnabled()
        return self._enabled
    end

    self._modules[name] = mod
    return mod
end

function CP:GetModule(name, silent)
    if not self._modules[name] and not silent then
        error("Module '" .. name .. "' not found", 2)
    end
    return self._modules[name]
end

function CP:IterateModules()
    return pairs(self._modules)
end

-------------------------------------------------------------------------------
-- Slash command registration (replaces AceConsole:RegisterChatCommand)
-------------------------------------------------------------------------------
function CP:RegisterChatCommand(cmd, handler)
    local key = cmd:upper()
    _G["SLASH_" .. key .. "1"] = "/" .. cmd
    _G.SlashCmdList = _G.SlashCmdList or {}
    if type(handler) == "function" then
        _G.SlashCmdList[key] = handler
    else
        _G.SlashCmdList[key] = function(input)
            if self[handler] then self[handler](self, input) end
        end
    end
end

-------------------------------------------------------------------------------
-- Test helper: fire event directly to all registered callbacks
-- (Used by spec/helpers.lua — not called in production)
-------------------------------------------------------------------------------
CP._FireEvent = function(event, ...)
    local cbs = CP._eventCallbacks[event]
    if not cbs then return end
    local snapshot = {}
    for i = 1, #cbs do snapshot[i] = cbs[i] end
    for i = 1, #snapshot do
        snapshot[i].fn(snapshot[i].obj, event, ...)
    end
end

-------------------------------------------------------------------------------
-- SavedVariables defaults (replaces AceDB)
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        enabled            = true,
        debugMode          = false,
        uiScale            = 1.0,
        radialAlpha        = 0.9,
        vibrationEnabled   = true,
        ledEnabled         = true,
        hideBlizzardFrames = true,
        peekThreshold      = 0.35,
        lockThreshold      = 0.75,
    },
    char = {
        currentWheel  = 1,
        wheelLayouts  = {},
        healerMode    = false,
    },
}

local function deepMerge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            deepMerge(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local function _initDB()
    CouchPotatoDB          = CouchPotatoDB          or {}
    CouchPotatoDB.profile  = CouchPotatoDB.profile  or {}
    CouchPotatoDB.char     = CouchPotatoDB.char     or {}
    deepMerge(CouchPotatoDB.profile, defaults.profile)
    deepMerge(CouchPotatoDB.char,    defaults.char)
    CP.db = CouchPotatoDB
    -- ResetProfile helper (used by /cp reset)
    CP.db.ResetProfile = function()
        for k in pairs(CP.db.profile) do CP.db.profile[k] = nil end
        deepMerge(CP.db.profile, defaults.profile)
    end
end

-------------------------------------------------------------------------------
-- Lifecycle: ADDON_LOADED → initialize
-------------------------------------------------------------------------------
function CP:_OnAddonLoaded()
    _initDB()

    -- Slash commands
    self:RegisterChatCommand("cp",          "ChatCommand")
    self:RegisterChatCommand("couchpotato", "ChatCommand")

    self:DebugPrint("Initialized")
end

-------------------------------------------------------------------------------
-- Lifecycle: PLAYER_LOGIN → enable
-------------------------------------------------------------------------------
function CP:_OnPlayerLogin()
    -- Register core events
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")

    -- Enable all registered modules
    for _, mod in self:IterateModules() do
        mod:Enable()
    end

    -- Check controller
    if self:IsControllerActive() then
        self:Print("Controller detected. Radial UI ready.")
        self:NotifyModules("CONTROLLER_CONNECTED")
    end

    self:DebugPrint("Enabled")
end

-- Register lifecycle events on the main frame
_mainFrame:RegisterEvent("ADDON_LOADED")
_mainFrame:RegisterEvent("PLAYER_LOGIN")

-- Add lifecycle handlers directly into the callback table
-- (before any module loads, so these fire first)
CP._eventCallbacks["ADDON_LOADED"] = {
    {
        obj = CP,
        fn  = function(self, event, addonName)
            if addonName == CP.addonName then
                self:_OnAddonLoaded()
            end
        end,
    }
}
CP._eventCallbacks["PLAYER_LOGIN"] = {
    {
        obj = CP,
        fn  = function(self, event)
            self:_OnPlayerLogin()
        end,
    }
}

-------------------------------------------------------------------------------
-- Event handlers (CP-level)
-------------------------------------------------------------------------------
function CP:PLAYER_ENTERING_WORLD(event, isLogin, isReload)
    if isLogin then
        self:DebugPrint("Player logged in")
    elseif isReload then
        self:DebugPrint("UI reloaded")
    end
    if self:IsControllerActive() then
        self:NotifyModules("CONTROLLER_STATE_UPDATE", true)
    end
end

function CP:PLAYER_REGEN_DISABLED()
    self:NotifyModules("COMBAT_LOCKDOWN_ENTER")
end

function CP:PLAYER_REGEN_ENABLED()
    self:NotifyModules("COMBAT_LOCKDOWN_EXIT")
end

-- Wire CP-level events through RegisterEvent so they go through the normal dispatch
-- These are registered when _OnPlayerLogin fires; the methods above handle them.
-- (RegisterEvent with no handler uses the event name as method name)

-------------------------------------------------------------------------------
-- Chat command handler
-- Usage: /cp show | hide | reload | config | reset | debug | status
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

    elseif cmd == "reset" then
        self.db:ResetProfile()
        self:Print("Profile reset to defaults")

    elseif cmd == "debug" then
        self.db.profile.debugMode = not self.db.profile.debugMode
        self:Print(string_format("Debug mode: %s",
            self.db.profile.debugMode and "ON" or "OFF"))

    elseif cmd == "status" then
        self:PrintStatus()

    else
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
-- Helpers
-------------------------------------------------------------------------------
function CP:PrintStatus()
    self:Print("=== CouchPotato Status ===")
    self:Print(string_format("Version: %s", self.version))
    self:Print(string_format("Controller Active: %s",
        self:IsControllerActive() and "Yes" or "No"))
    self:Print(string_format("Enabled: %s",
        self.db and self.db.profile.enabled and "Yes" or "No"))
    self:Print(string_format("Current Wheel: %d",
        self.db and self.db.char.currentWheel or 1))
    self:Print(string_format("Healer Mode: %s",
        self.db and self.db.char.healerMode and "Yes" or "No"))
    self:Print(string_format("Debug Mode: %s",
        self.db and self.db.profile.debugMode and "Yes" or "No"))

    local moduleCount = 0
    for _ in self:IterateModules() do moduleCount = moduleCount + 1 end
    self:Print(string_format("Modules Loaded: %d", moduleCount))
end

function CP:OnControllerActivated()
    -- Ensure db is always ready before any module touches it,
    -- regardless of which event path triggered the load.
    if not self.db then _initDB() end
    self:NotifyModules("CONTROLLER_ACTIVATED")
    for name, mod in self:IterateModules() do
        if mod.Enable and not mod._enabled then mod:Enable() end
    end
end

function CP:OnControllerDeactivated()
    self:NotifyModules("CONTROLLER_DEACTIVATED")
    for name, mod in self:IterateModules() do
        if mod.Disable then mod:Disable() end
    end
end

function CP:IsControllerActive()
    if C_GamePad and C_GamePad.IsEnabled then
        return C_GamePad.IsEnabled()
    end
    return false
end

function CP:NotifyModules(event, ...)
    for name, mod in self:IterateModules() do
        if mod.OnCPEvent then
            mod:OnCPEvent(event, ...)
        end
    end
end

function CP:DebugPrint(...)
    if self.db and self.db.profile and self.db.profile.debugMode then
        self:Print("|cff888888[Debug]|r", ...)
    end
end
