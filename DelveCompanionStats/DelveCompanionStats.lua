-- DelveCompanionStats.lua
-- Tracks delve companion levels and displays them above the chat window.

local addonName, ns = ...

-- Initialize namespace
ns.version = "1.0.0"

-- ADDON_LOADED handler
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize SavedVariables
        DelveCompanionStatsDB = DelveCompanionStatsDB or {}
        ns:OnLoad()
    elseif event == "PLAYER_LOGIN" then
        ns:OnEnable()
    end
end)

--- Called once when the addon first loads.
function ns:OnLoad()
    -- Initialization logic goes here
end

--- Called when the player is fully logged in.
function ns:OnEnable()
    -- Enable logic goes here
end
