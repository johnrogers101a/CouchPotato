-- InfoPanels/Core/Utils.lua
-- Shared utility functions. Eliminates duplication across BuiltIn panels.
-- Single Responsibility: Common helpers used by multiple modules.

local _, ns = ...
if not ns then ns = {} end

local Utils = {}
ns.Utils = Utils

-------------------------------------------------------------------------------
-- IsInDelve: Check if the player is currently inside a delve.
-- Consolidated from DelveCompanionStats.lua and DelversJourney.lua (QI-3 fix).
-------------------------------------------------------------------------------
function Utils.IsInDelve()
    if not _G.IsInInstance then return false end
    local _, instanceType = _G.IsInInstance()
    if instanceType == "scenario" then return true end
    local ok, hasDelve = pcall(function()
        return _G.C_DelvesUI and _G.C_DelvesUI.HasActiveDelve and _G.C_DelvesUI.HasActiveDelve()
    end)
    if ok and hasDelve then return true end
    local ok2, inProgress = pcall(function()
        return _G.C_PartyInfo and _G.C_PartyInfo.IsDelveInProgress and _G.C_PartyInfo.IsDelveInProgress()
    end)
    if ok2 and inProgress then return true end
    return false
end

-------------------------------------------------------------------------------
-- DeepCopy: Deep-copy a table (no metatables, no functions).
-- Safe for serializable data tables only.
-------------------------------------------------------------------------------
function Utils.DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = Utils.DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-------------------------------------------------------------------------------
-- GenerateUID: Generate an 11-character base64 unique ID (like WeakAuras).
-------------------------------------------------------------------------------
function Utils.GenerateUID()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    local uid = {}
    local seed = (_G.GetTime and _G.GetTime() or os.time()) * 1000
    math.randomseed(seed)
    for i = 1, 11 do
        local idx = math.random(1, #chars)
        uid[i] = chars:sub(idx, idx)
    end
    return table.concat(uid)
end

-------------------------------------------------------------------------------
-- CommaFormat: Format a number with comma separators.
-------------------------------------------------------------------------------
function Utils.CommaFormat(n)
    if not n then return "0" end
    local val = math.floor(n + 0.5)
    local sign = val < 0 and "-" or ""
    local s = tostring(math.abs(val))
    local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. result
end

-------------------------------------------------------------------------------
-- FormatNumber: Alias for CommaFormat (backward compat with UIFramework).
-------------------------------------------------------------------------------
Utils.FormatNumber = Utils.CommaFormat

-------------------------------------------------------------------------------
-- FormatBindingValue: Format a fetched value using an optional binding.format.
-- Returns a display string. For numeric values with a format string, applies
-- string.format(binding.format, val). Falls back to tostring(val or "").
-------------------------------------------------------------------------------
function Utils.FormatBindingValue(val, binding)
    local displayVal = tostring(val or "")
    if binding and binding.format and type(val) == "number" then
        local ok, result = pcall(string.format, binding.format, val)
        if ok then displayVal = result end
    end
    return displayVal
end

-------------------------------------------------------------------------------
-- FetchAndFormatBinding: Fetch from DataSources and format for display.
-- Returns displayText, isError.
--   displayText - the formatted value string, or nil on error
--   isError     - true if the fetch returned an error
-------------------------------------------------------------------------------
function Utils.FetchAndFormatBinding(DataSources, binding)
    if not DataSources or not binding then return nil, true end
    local val, err = DataSources.Fetch(binding.sourceId)
    if err then return nil, true end
    return Utils.FormatBindingValue(val, binding), false
end

return Utils
