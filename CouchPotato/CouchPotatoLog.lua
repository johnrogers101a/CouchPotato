-- CouchPotatoLog.lua — Shared logging for all CouchPotato addons
-- Moved from ControllerCompanion_Loader/ into the CouchPotato shared addon.
local CouchPotatoLog = {}
_G.CouchPotatoLog = CouchPotatoLog

local ADDON_COLORS = {
    ["ControllerCompanion"] = "|cff69ccf0",
    ["Loader"]              = "|cffff6600",
    ["DCS"]                 = "|cff00ccff",
    ["SP"]                  = "|cffff99cc",
    ["CP"]                  = "|cffaaddff",
}

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

function CouchPotatoLog:Debug(prefix, enabled, ...)
    if not enabled then return end
    self:Print(prefix, "|cff888888[Debug]|r", ...)
end
