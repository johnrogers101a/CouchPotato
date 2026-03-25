-- CouchPotato.lua
-- Core namespace, error capture system, and slash commands for the CouchPotato suite.
-- Patch 12.0.1 (Interface 120001)

local ADDON_NAME = "CouchPotato"

-- Namespace exposed to other files in this addon
local CP = {}
_G.CouchPotatoShared = CP

CP.version = "1.0.0"

-------------------------------------------------------------------------------
-- SavedVariables default structure
-------------------------------------------------------------------------------
local DB_DEFAULTS = {
    errorLog      = {},
    debugLog      = {},
    minimapAngle  = 225,   -- degrees clockwise from top
    windowState   = { shown = false },
    addonStates   = {
        ControllerCompanion  = true,
        DelveCompanionStats  = true,
        StatPriority         = true,
    },
}

local function InitDB()
    local isNew = (CouchPotatoDB == nil)
    if not CouchPotatoDB then
        CouchPotatoDB = {}
    end
    local db = CouchPotatoDB
    for k, v in pairs(DB_DEFAULTS) do
        if db[k] == nil then
            -- shallow copy tables, primitive values directly
            if type(v) == "table" then
                local copy = {}
                for k2, v2 in pairs(v) do copy[k2] = v2 end
                db[k] = copy
            else
                db[k] = v
            end
        end
    end
    -- Migration: ensure addonStates sub-keys exist for addons added after initial install
    if not db.addonStates then
        db.addonStates = {}
    end
    local stateDefaults = DB_DEFAULTS.addonStates
    for addonKey, defaultVal in pairs(stateDefaults) do
        if db.addonStates[addonKey] == nil then
            db.addonStates[addonKey] = defaultVal
        end
    end

    if _G.CouchPotatoLog then
        local state = isNew and "fresh" or "restored"
        _G.CouchPotatoLog:Info("CP", "DB initialized: " .. state)
    end
end

-------------------------------------------------------------------------------
-- Error capture: hook WoW error handler
-------------------------------------------------------------------------------
local SUITE_PATTERNS = {
    "CouchPotato",
    "ControllerCompanion",
    "DelveCompanionStats",
    "StatPriority",
}

local MAX_ERROR_LOG = 500

local function IsSuiteError(msg, stack)
    local haystack = (msg or "") .. (stack or "")
    for _, pattern in ipairs(SUITE_PATTERNS) do
        if haystack:find(pattern, 1, true) then
            return true, pattern
        end
    end
    return false, nil
end

local function GuessAddonName(msg, stack)
    local haystack = (msg or "") .. (stack or "")
    for _, pattern in ipairs(SUITE_PATTERNS) do
        if haystack:find(pattern, 1, true) then
            return pattern
        end
    end
    return "CouchPotato"
end

local _originalErrorHandler = nil

local function CouchPotatoErrorHandler(msg, stack)
    local isSuite, _ = IsSuiteError(msg, stack)
    if isSuite and CouchPotatoDB then
        local addonGuess = GuessAddonName(msg, stack)
        local log = CouchPotatoDB.errorLog
        local entry = {
            timestamp = GetTime and GetTime() or 0,
            message   = tostring(msg or ""),
            stack     = tostring(stack or ""),
            addonName = addonGuess,
        }
        table.insert(log, 1, entry)  -- newest first
        -- Cap at MAX_ERROR_LOG entries
        while #log > MAX_ERROR_LOG do
            table.remove(log)
        end
        -- Also write to debug log
        local summary = tostring(msg or ""):sub(1, 120)
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Error(addonGuess, "Captured error: " .. summary)
        end
    end
    -- Always forward to original handler
    if _originalErrorHandler then
        _originalErrorHandler(msg, stack)
    end
end

local function HookErrorHandler()
    local ok, err = pcall(function()
        _originalErrorHandler = geterrorhandler and geterrorhandler() or nil
        seterrorhandler(CouchPotatoErrorHandler)
    end)
    if ok then
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Info("CP", "Error handler hooked successfully")
        end
    else
        -- If hooking fails (e.g., protected environment), proceed without it
        _originalErrorHandler = nil
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Warn("CP", "Error handler hook failed: " .. tostring(err))
        end
    end
end

-------------------------------------------------------------------------------
-- ADDON_LOADED event handler
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Info("CP", "ADDON_LOADED fired for: " .. tostring(addonName))
        end
        InitDB()
        HookErrorHandler()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-------------------------------------------------------------------------------
-- Enable/Disable addon management
-------------------------------------------------------------------------------

-- Canonical addon key → human-readable display name.
local ADDON_DISPLAY_NAMES = {
    ControllerCompanion  = "Controller Companion",
    DelveCompanionStats  = "Delve Companion Stats",
    StatPriority         = "Stat Priority",
}

-- Canonical addon name → display name mapping.
-- Keys are lowercase aliases; value is the canonical SavedVars key.
local ADDON_ALIASES = {
    controllercompanion  = "ControllerCompanion",
    cc                   = "ControllerCompanion",
    delvecompanionstats  = "DelveCompanionStats",
    dcs                  = "DelveCompanionStats",
    statpriority         = "StatPriority",
    sp                   = "StatPriority",
}

-- cpprint: write a coloured [CP] message to the chat frame.
local function cpprint(msg)
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Print("CP", msg)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff6600CP:|r " .. tostring(msg))
    else
        print("|cffff6600CP:|r " .. tostring(msg))
    end
end

-- EnsureAddonStates: guarantee CouchPotatoDB.addonStates is populated.
-- Safe to call before ADDON_LOADED (e.g. if the slash cmd fires early).
local function EnsureAddonStates()
    if not CouchPotatoDB then
        CouchPotatoDB = {}
    end
    if not CouchPotatoDB.addonStates then
        CouchPotatoDB.addonStates = {}
    end
    local stateDefaults = DB_DEFAULTS.addonStates
    for addonKey, defaultVal in pairs(stateDefaults) do
        if CouchPotatoDB.addonStates[addonKey] == nil then
            CouchPotatoDB.addonStates[addonKey] = defaultVal
        end
    end
end

-- PrintAddonStatus: list all suite addons and their current enabled/disabled state.
local function PrintAddonStatus()
    EnsureAddonStates()
    cpprint("Suite addon states:")
    local order = { "ControllerCompanion", "DelveCompanionStats", "StatPriority" }
    for _, name in ipairs(order) do
        local state = CouchPotatoDB.addonStates[name]
        local label = (state == false) and "|cffff4444disabled|r" or "|cff44ff44enabled|r"
        local displayName = ADDON_DISPLAY_NAMES[name] or name
        cpprint("  " .. displayName .. ": " .. label)
    end
end

-- Combat deferral for ControllerCompanion disable (protected frames)
local pendingCombatActions = {}

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        for _, action in ipairs(pendingCombatActions) do
            action()
        end
        pendingCombatActions = {}
    end
end)

-- DoDisableAddon: perform the functional disable for a canonical addon name.
local function DoDisableAddon(name)
    if name == "ControllerCompanion" then
        if _G.ControllerCompanion and _G.ControllerCompanion.OnControllerDeactivated then
            _G.ControllerCompanion:OnControllerDeactivated()
        end
        -- Hide all CC frames if accessible
        if _G.ControllerCompanion and _G.ControllerCompanion._mainFrame then
            _G.ControllerCompanion._mainFrame:Hide()
        end
    elseif name == "DelveCompanionStats" then
        local ns = _G.DelveCompanionStatsNS
        if ns then
            ns._cpDisabled = true
            if ns.frame then ns.frame:Hide() end
        end
    elseif name == "StatPriority" then
        local ns = _G.StatPriorityNS
        if ns then
            ns._cpDisabled = true
            if ns.frame then ns.frame:Hide() end
        end
    end
end

-- DoEnableAddon: perform the functional enable for a canonical addon name.
local function DoEnableAddon(name)
    if name == "ControllerCompanion" then
        if _G.ControllerCompanion and _G.ControllerCompanion.OnControllerActivated then
            _G.ControllerCompanion:OnControllerActivated()
        end
    elseif name == "DelveCompanionStats" then
        local ns = _G.DelveCompanionStatsNS
        if ns then
            ns._cpDisabled = false
            if ns.frame then ns.frame:Show() end
        end
    elseif name == "StatPriority" then
        local ns = _G.StatPriorityNS
        if ns then
            ns._cpDisabled = false
            if ns.frame then ns.frame:Show() end
            if ns.UpdateStatPriority then ns:UpdateStatPriority() end
        end
    end
end

-- HandleEnableDisable: main entry point for /cp enable|disable <addon>
local function HandleEnableDisable(action, rawName)
    EnsureAddonStates()

    if not rawName or rawName == "" then
        PrintAddonStatus()
        return
    end

    local alias = strlower(rawName)
    local canonical = ADDON_ALIASES[alias]
    if not canonical then
        cpprint("Unknown addon '" .. rawName .. "'. Valid names: controllercompanion (cc), delvecompanionstats (dcs), statpriority (sp)")
        return
    end

    local states = CouchPotatoDB.addonStates
    local isEnabled = (states[canonical] ~= false)
    local displayName = ADDON_DISPLAY_NAMES[canonical] or canonical

    if action == "disable" then
        if not isEnabled then
            cpprint(displayName .. " is already disabled.")
            return
        end
        states[canonical] = false
        -- ControllerCompanion: warn+defer if in combat
        if canonical == "ControllerCompanion" then
            local inCombat = InCombatLockdown and InCombatLockdown() or false
            if inCombat then
                cpprint(displayName .. " will be disabled after combat ends.")
                table.insert(pendingCombatActions, function()
                    DoDisableAddon(canonical)
                    cpprint(displayName .. " disabled (post-combat).")
                end)
                return
            end
        end
        DoDisableAddon(canonical)
        cpprint(displayName .. " disabled.")
    elseif action == "enable" then
        if isEnabled then
            cpprint(displayName .. " is already enabled.")
            return
        end
        states[canonical] = true
        DoEnableAddon(canonical)
        cpprint(displayName .. " enabled.")
    end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

-- /cp  — open CouchPotato shared config window, or enable/disable addons
SLASH_CP1 = "/cp"
SLASH_CP2 = "/couchpotato"
SlashCmdList["CP"] = function(msg)
    msg = strtrim(strlower(msg or ""))
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "Slash /cp received, args: '" .. msg .. "'")
    end

    -- Parse subcommand
    local subcmd, rest = msg:match("^(%S+)%s*(.*)")
    subcmd = subcmd or ""
    rest   = rest   or ""

    if subcmd == "enable" or subcmd == "disable" then
        HandleEnableDisable(subcmd, rest ~= "" and rest or nil)
        return
    end

    if CouchPotatoShared.ConfigWindow then
        CouchPotatoShared.ConfigWindow.Toggle()
    end
end

-- /cc  — open ControllerCompanion controller-specific config
SLASH_CC1 = "/cc"
SLASH_CC2 = "/controllercompanion"
SlashCmdList["CC"] = function(msg)
    msg = strtrim(strlower(msg or ""))
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "Slash /cc received, args: '" .. msg .. "'")
    end
    if ControllerCompanion and ControllerCompanion.ConfigWindow then
        ControllerCompanion.ConfigWindow.Show()
    else
        -- Try force-loading ControllerCompanion if not loaded
        if C_AddOns and not C_AddOns.IsAddOnLoaded("ControllerCompanion") then
            if _G.CouchPotatoLog then
                _G.CouchPotatoLog:Info("CP", "Requesting load of ControllerCompanion")
            end
            C_AddOns.EnableAddOn("ControllerCompanion")
            C_AddOns.LoadAddOn("ControllerCompanion")
        end
        if ControllerCompanion and ControllerCompanion.ConfigWindow then
            ControllerCompanion.ConfigWindow.Show()
        else
            if _G.CouchPotatoLog then
                _G.CouchPotatoLog:Warn("CP", "ControllerCompanion not available after load attempt")
            end
            if CouchPotatoLog then
                CouchPotatoLog:Print("CP", "ControllerCompanion not available.")
            end
        end
    end
end

-- Store reference to our error handler for tests/introspection
CP._errorHandler    = CouchPotatoErrorHandler
CP._isSuiteError    = IsSuiteError
CP._guessAddonName  = GuessAddonName
CP._hookErrorHandler = HookErrorHandler

-- Enable/disable API exposed for tests and other addons
CP._addonAliases          = ADDON_ALIASES
CP._handleEnableDisable   = HandleEnableDisable
CP._doDisableAddon        = DoDisableAddon
CP._doEnableAddon         = DoEnableAddon
CP._printAddonStatus      = PrintAddonStatus
CP._ensureAddonStates     = EnsureAddonStates
CP._cpprint               = cpprint
