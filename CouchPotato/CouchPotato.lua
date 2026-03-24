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
-- Slash commands
-------------------------------------------------------------------------------

-- /cp  — open CouchPotato shared config window
SLASH_CP1 = "/cp"
SLASH_CP2 = "/couchpotato"
SlashCmdList["CP"] = function(msg)
    msg = strtrim(strlower(msg or ""))
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "Slash /cp received, args: '" .. msg .. "'")
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
