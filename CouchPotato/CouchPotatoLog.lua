-- CouchPotatoLog.lua — Shared logging for all CouchPotato addons
-- Moved from ControllerCompanion_Loader/ into the CouchPotato shared addon.
local CouchPotatoLog = {}
_G.CouchPotatoLog = CouchPotatoLog

local ADDON_COLORS = {
    ["ControllerCompanion"] = "|cff69ccf0",
    ["Loader"]              = "|cffff6600",
    ["IP"]                  = "|cff00ccff",
    ["CP"]                  = "|cffaaddff",
    ["CPQ"]                 = "|cffffff00",
}

-- Log level constants
CouchPotatoLog.LEVELS = {
    DEBUG = 1,
    INFO  = 2,
    WARN  = 3,
    ERROR = 4,
}

local LEVEL_NAMES = { [1] = "DEBUG", [2] = "INFO", [3] = "WARN", [4] = "ERROR" }

local MAX_DEBUG_LOG = 1000

-------------------------------------------------------------------------------
-- Internal: append an entry to CouchPotatoDB.debugLog
-------------------------------------------------------------------------------
local function AppendDebugLog(level, addon, message)
    -- CouchPotatoDB may not be initialized yet at early load time; guard it
    if not _G.CouchPotatoDB then return end
    local log = _G.CouchPotatoDB.debugLog
    if not log then
        _G.CouchPotatoDB.debugLog = {}
        log = _G.CouchPotatoDB.debugLog
    end
    local ts = (GetTime and GetTime()) or 0
    local entry = {
        timestamp = ts,
        level     = LEVEL_NAMES[level] or "INFO",
        addon     = tostring(addon or "?"),
        message   = tostring(message or ""),
    }
    table.insert(log, entry)
    -- Cap oldest entries
    while #log > MAX_DEBUG_LOG do
        table.remove(log, 1)
    end
end

-------------------------------------------------------------------------------
-- :Print — chat output (unchanged public API)
-------------------------------------------------------------------------------
function CouchPotatoLog:Print(prefix, ...)
    local color = ADDON_COLORS[prefix] or "|cffcccccc"
    local parts = { ... }
    local msg = color .. prefix .. "|r:"
    for i = 1, #parts do
        msg = msg .. " " .. tostring(parts[i])
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    else
        print(msg)
    end
end

-------------------------------------------------------------------------------
-- :Debug — level DEBUG (old two-arg signature kept for back-compat)
-- New canonical form: CouchPotatoLog:Debug(addon, message)
-- Legacy form:        CouchPotatoLog:Debug(prefix, enabled, ...)
-------------------------------------------------------------------------------
function CouchPotatoLog:Debug(prefix, ...)
    local args = { ... }
    -- Legacy back-compat: second arg was a boolean "enabled" flag
    if type(args[1]) == "boolean" then
        local enabled = args[1]
        if not enabled then return end
        -- Remaining args are the message parts
        local parts = {}
        for i = 2, #args do parts[#parts + 1] = tostring(args[i]) end
        local msg = table.concat(parts, " ")
        self:Print(prefix, "|cff888888[Debug]|r", msg)
        AppendDebugLog(CouchPotatoLog.LEVELS.DEBUG, prefix, msg)
        return
    end
    -- New form: Debug(addon, message)
    local msg = table.concat(args, " ")
    AppendDebugLog(CouchPotatoLog.LEVELS.DEBUG, prefix, msg)
end

-------------------------------------------------------------------------------
-- :Info — level INFO
-------------------------------------------------------------------------------
function CouchPotatoLog:Info(addon, ...)
    local parts = { ... }
    local msg = table.concat(parts, " ")
    AppendDebugLog(CouchPotatoLog.LEVELS.INFO, addon, msg)
end

-------------------------------------------------------------------------------
-- :Warn — level WARN
-------------------------------------------------------------------------------
function CouchPotatoLog:Warn(addon, ...)
    local parts = { ... }
    local msg = table.concat(parts, " ")
    AppendDebugLog(CouchPotatoLog.LEVELS.WARN, addon, msg)
end

-------------------------------------------------------------------------------
-- :Error — level ERROR (also prints to chat so it's visible immediately)
-------------------------------------------------------------------------------
function CouchPotatoLog:Error(addon, ...)
    local parts = { ... }
    local msg = table.concat(parts, " ")
    AppendDebugLog(CouchPotatoLog.LEVELS.ERROR, addon, msg)
    self:Print(addon, "|cffff4444[ERROR]|r", msg)
end

-------------------------------------------------------------------------------
-- Expose internal for tests / ConfigWindow
-------------------------------------------------------------------------------
CouchPotatoLog._appendDebugLog = AppendDebugLog
CouchPotatoLog._levelNames     = LEVEL_NAMES
CouchPotatoLog._maxDebugLog    = MAX_DEBUG_LOG
