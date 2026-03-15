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
    -- 1. Create the main display frame
    ns.frame = CreateFrame("Frame", "DelveCompanionStatsFrame", UIParent, "BackdropTemplateMixin and BackdropTemplate")

    -- 2. Set size
    ns.frame:SetSize(200, 100)

    -- 3. Anchor to BOTTOM of UIParent
    ns.frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 20, 100)

    -- 4. Apply dark semi-transparent backdrop
    ns.frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    ns.frame:SetBackdropColor(0, 0, 0, 0.7)

    -- 5. Create name label
    ns.nameLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.nameLabel:SetPoint("TOPLEFT", ns.frame, "TOPLEFT", 8, -8)
    ns.nameLabel:SetWidth(184)
    ns.nameLabel:SetJustifyH("LEFT")
    ns.nameLabel:SetText("No companion data")

    -- 6. Create level label
    ns.levelLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.levelLabel:SetPoint("TOPLEFT", ns.nameLabel, "BOTTOMLEFT", 0, -4)
    ns.levelLabel:SetWidth(184)
    ns.levelLabel:SetJustifyH("LEFT")
    ns.levelLabel:SetText("")

    -- 7. Make frame movable
    ns.frame:SetMovable(true)
    ns.frame:EnableMouse(true)
    ns.frame:RegisterForDrag("LeftButton")
    ns.frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    ns.frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        DelveCompanionStatsDB.position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)

    -- 8. Hide frame initially
    ns.frame:Hide()
end

--- Called when the player is fully logged in.
function ns:OnEnable()
    local db = DelveCompanionStatsDB

    -- 1. Restore position from SavedVariables if it exists
    if db.position then
        local p = db.position
        ns.frame:ClearAllPoints()
        ns.frame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    end

    -- 2. Populate companion data from SavedVariables OR show placeholder
    if db.companionName then
        ns.nameLabel:SetText(db.companionName)
        ns.levelLabel:SetText("Level: " .. (db.companionLevel or "?"))
    else
        ns.nameLabel:SetText("No companion data")
        ns.levelLabel:SetText("")
    end

    -- 3. Show the frame
    ns.frame:Show()
end
