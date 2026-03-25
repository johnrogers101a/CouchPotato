-- DelversJourney.lua
-- Tracks Delver's Journey season rank and XP progress.
-- UI matches DelveCompanionStats: gold-bordered header, collapsible content.
local addonName, ns = ...
if not ns then
    addonName = "DelversJourney"
    ns = {}
end
_G.DelversJourneyNS = ns

ns.version = "1.0.0"

local FONT_PATH = "Fonts\\FRIZQT__.TTF"
local CP = _G.CouchPotatoShared

local djlog = (CP and CP.CreateLogger) and CP.CreateLogger("DJ")
    or function(level, msg)
        if _G.CouchPotatoLog and _G.CouchPotatoLog[level] then
            _G.CouchPotatoLog[level](_G.CouchPotatoLog, "DJ", msg)
        end
    end

local function djprint(msg)
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Print("DJ", msg)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffDJ:|r " .. tostring(msg))
    else
        print("|cff33ccffDJ:|r " .. tostring(msg))
    end
end

local function FormatNumber(num)
    if not num then return "0" end
    local s = tostring(math.floor(num))
    local result = ""
    local len = #s
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. s:sub(i, i)
    end
    return result
end

-- Slash commands
SLASH_DELVESJOURNEY1 = "/dj"
SLASH_DELVESJOURNEY2 = "/delvesjourney"
SlashCmdList["DELVESJOURNEY"] = function(msg)
    local cmd = msg and msg:lower():match("^%s*(%S+)") or ""
    djlog("Info", "Slash /dj received, cmd='" .. cmd .. "'")
    if cmd == "show" then
        if ns.frame then ns.frame:Show() end
        djprint("Frame shown")
    elseif cmd == "hide" then
        if ns.frame then ns.frame:Hide() end
        djprint("Frame hidden")
    elseif cmd == "toggle" then
        if ns.frame then
            if ns.frame:IsShown() then ns.frame:Hide(); djprint("Frame hidden")
            else ns.frame:Show(); ns:UpdateDelversJourney(); djprint("Frame shown") end
        end
    elseif cmd == "reset" then
        if DelversJourneyDB then DelversJourneyDB.position = nil; DelversJourneyDB.pinned = nil end
        if ns.ApplyPinnedState then ns.ApplyPinnedState() end
        djprint("Position reset")
    else
        djprint("Usage: /dj [show|hide|toggle|reset]")
    end
end

-------------------------------------------------------------------------------
-- IsInDelve — returns true when the player is inside a delve
-------------------------------------------------------------------------------
local function IsInDelve()
    local _, instanceType = IsInInstance()
    if instanceType == "scenario" then return true end
    local ok, hasDelve = pcall(function()
        return C_DelvesUI.HasActiveDelve and C_DelvesUI.HasActiveDelve()
    end)
    if ok and hasDelve then return true end
    local ok2, inProgress = pcall(function()
        return C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
    end)
    if ok2 and inProgress then return true end
    return false
end

-------------------------------------------------------------------------------
-- GetTrackerAnchor — Chain: ObjectiveTracker → DJ (DJ is first, directly below OT)
-------------------------------------------------------------------------------
local function GetTrackerAnchor()
    if CP and CP.GetBaseTrackerAnchor then
        local anchor = CP.GetBaseTrackerAnchor()
        if anchor then return anchor end
    end
    return ObjectiveTrackerFrame or nil
end

-------------------------------------------------------------------------------
-- UpdateDelversJourney
-------------------------------------------------------------------------------
function ns:UpdateDelversJourney()
    if not ns.frame then return end
    djlog("Debug", "UpdateDelversJourney called")

    local factionID
    local ok, result = pcall(C_DelvesUI.GetDelvesFactionForSeason)
    if ok and result and result ~= 0 then factionID = result end

    if not factionID then
        if ns.headerTitle then ns.headerTitle:SetText("Delver's Journey") end
        if ns.rankLabel then ns.rankLabel:SetText("No season data") end
        if ns.xpLabel then ns.xpLabel:SetText("") end
        djlog("Warn", "No factionID from GetDelvesFactionForSeason")
        return
    end

    local seasonName = "Delver's Journey"
    local okD, fData = pcall(C_MajorFactions.GetMajorFactionData, factionID)
    if okD and fData and fData.name then seasonName = fData.name end
    seasonName = seasonName:gsub("^Delves:%s*", "")
    if ns.headerTitle then ns.headerTitle:SetText(seasonName) end

    local okR, rInfo = pcall(C_MajorFactions.GetMajorFactionRenownInfo, factionID)
    if okR and rInfo then
        local rank = rInfo.renownLevel or 0
        local xpEarned = rInfo.renownReputationEarned or 0
        local xpMax = rInfo.renownLevelThreshold or 0
        if ns.rankLabel then ns.rankLabel:SetText("Rank " .. tostring(rank)) end
        if ns.xpLabel then ns.xpLabel:SetText(FormatNumber(xpEarned) .. " / " .. FormatNumber(xpMax)) end
        djlog("Info", "UpdateDelversJourney: rank=" .. rank .. " xp=" .. xpEarned .. "/" .. xpMax)
    else
        if ns.rankLabel then ns.rankLabel:SetText("Rank ?") end
        if ns.xpLabel then ns.xpLabel:SetText("") end
    end

    ns:UpdateFrameHeight()
end

function ns:UpdateFrameHeight()
    local headerH = ns.headerFrame and ns.headerFrame:GetHeight() or 26
    if ns.contentFrame and ns.contentFrame:IsShown() then
        local contentH = 52  -- 8 top + rank(16) + 4 gap + xp(16) + 8 bottom
        ns.contentFrame:SetHeight(contentH)
        ns.frame:SetHeight(headerH + contentH)
    else
        ns.frame:SetHeight(headerH)
    end
end

function ns:UpdateFrameVisibility()
    if not ns.frame then return end
    if IsInDelve() then
        ns.frame:Show()
        djlog("Debug", "UpdateFrameVisibility: in delve, showing frame")
    else
        ns.frame:Hide()
        djlog("Debug", "UpdateFrameVisibility: not in delve, hiding frame")
    end
end

-------------------------------------------------------------------------------
-- OnLoad
-------------------------------------------------------------------------------
function ns:OnLoad()
    if ns.frame then return end
    djlog("Info", "OnLoad: starting initialization, version=" .. ns.version)

    DelversJourneyDB = DelversJourneyDB or {}
    local db = DelversJourneyDB

    -- Frame width from tracker
    local frameWidth = 0
    if ObjectiveTrackerFrame and ObjectiveTrackerFrame.GetWidth then
        frameWidth = ObjectiveTrackerFrame:GetWidth()
    end
    if frameWidth < 100 or frameWidth > 400 then frameWidth = 248 end
    local contentWidth = frameWidth - 12

    -- Main frame
    local frame
    local fOk, fR = pcall(CreateFrame, "Frame", "DelversJourneyFrame", UIParent, "BackdropTemplate")
    if fOk and fR then frame = fR
    else
        local fOk2, fR2 = pcall(CreateFrame, "Frame", "DelversJourneyFrame", UIParent)
        if fOk2 and fR2 then frame = fR2 end
    end
    if not frame then
        djlog("Error", "Could not create frame — addon disabled")
        return
    end
    ns.frame = frame
    frame:Hide()
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(1)
    frame:SetSize(frameWidth, 80)
    frame:SetMovable(true)
    frame:EnableMouse(true)

    djlog("Info", "Frame created successfully: DelversJourneyFrame")

    -- Header
    local header = CreateFrame("Button", nil, frame)
    ns.headerFrame = header
    header:SetHeight(26)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")

    header:SetScript("OnDragStart", function()
        if db.pinned == false then frame:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        db.position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)

    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(header)
    headerBg:SetColorTexture(0, 0, 0, 0.5)

    local headerTopLine = header:CreateTexture(nil, "ARTWORK")
    headerTopLine:SetHeight(1)
    headerTopLine:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    headerTopLine:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    headerTopLine:SetColorTexture(0.9, 0.75, 0.1, 0.8)

    local headerBottomLine = header:CreateTexture(nil, "ARTWORK")
    headerBottomLine:SetHeight(1)
    headerBottomLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerBottomLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerBottomLine:SetColorTexture(0.9, 0.75, 0.1, 0.8)

    local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pcall(function() headerTitle:SetFontObject(ObjectiveTitleFont) end)
    headerTitle:SetPoint("LEFT", header, "LEFT", 8, 0)
    headerTitle:SetJustifyV("MIDDLE")
    headerTitle:SetText("Delver's Journey")
    headerTitle:SetTextColor(1, 0.82, 0.0, 1)
    ns.headerTitle = headerTitle

    -- Collapse button
    local collapseBtn = CreateFrame("Button", nil, header)
    collapseBtn:SetSize(36, 36)
    collapseBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    local collapseBtnText = collapseBtn:CreateFontString(nil, "OVERLAY")
    collapseBtnText:SetFont(FONT_PATH, 16, "OUTLINE")
    collapseBtnText:SetAllPoints(collapseBtn)
    collapseBtnText:SetJustifyH("CENTER")
    collapseBtnText:SetJustifyV("MIDDLE")
    collapseBtnText:SetTextColor(1, 0.78, 0.1, 1)
    collapseBtnText:SetText("\226\128\147")
    collapseBtn:SetFontString(collapseBtnText)
    ns.collapseBtn = collapseBtn
    ns.collapseBtnText = collapseBtnText

    -- Pin button
    local pinBtn = CreateFrame("Button", nil, header)
    pinBtn:SetSize(26, 26)
    pinBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -4, 0)
    pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
    pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
    pinBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    pinBtn:EnableMouse(true)
    ns.pinBtn = pinBtn

    -- Pin state functions
    local function ApplyPinnedState()
        frame:SetMovable(false)
        local anchor = GetTrackerAnchor()
        frame:ClearAllPoints()
        if anchor then
            local gap = -14
            frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, gap)
            if ObjectiveTrackerFrame and ObjectiveTrackerFrame.GetWidth then
                local tw = ObjectiveTrackerFrame:GetWidth()
                if tw and tw >= 100 and tw <= 400 then frame:SetWidth(tw) end
            end
        else
            frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
        end
        pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
        pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
        db.pinned = true
        djlog("Info", "ApplyPinnedState: anchored below " .. (anchor and anchor:GetName() or "UIParent"))
    end
    ns.ApplyPinnedState = ApplyPinnedState

    local function ApplyUnpinnedState()
        frame:SetMovable(true)
        pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
        db.pinned = false
    end
    ns.ApplyUnpinnedState = ApplyUnpinnedState

    pinBtn:SetScript("OnClick", function()
        if db.pinned == false then
            db.pinned = true
            ApplyPinnedState()
        else
            db.pinned = false
            ApplyUnpinnedState()
        end
    end)

    -- Content frame
    local contentFrame
    local cok, cr = pcall(CreateFrame, "Frame", nil, frame, "BackdropTemplate")
    if cok and cr then contentFrame = cr
    else contentFrame = CreateFrame("Frame", nil, frame) end
    contentFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    contentFrame:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    contentFrame:SetHeight(52)
    ns.contentFrame = contentFrame

    -- Rank label
    ns.rankLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.rankLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 8, -8)
    ns.rankLabel:SetWidth(contentWidth)
    ns.rankLabel:SetJustifyH("LEFT")
    pcall(function() ns.rankLabel:SetFontObject(ObjectiveFont) end)
    ns.rankLabel:SetTextColor(1, 1, 1, 1)
    ns.rankLabel:SetShadowOffset(1, -1)
    ns.rankLabel:SetShadowColor(0, 0, 0, 1)
    ns.rankLabel:SetText("Rank ?")

    -- XP label
    ns.xpLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.xpLabel:SetPoint("TOPLEFT", ns.rankLabel, "BOTTOMLEFT", 0, -4)
    ns.xpLabel:SetWidth(contentWidth)
    ns.xpLabel:SetJustifyH("LEFT")
    pcall(function() ns.xpLabel:SetFontObject(ObjectiveFont) end)
    ns.xpLabel:SetTextColor(1, 1, 1, 1)
    ns.xpLabel:SetShadowOffset(1, -1)
    ns.xpLabel:SetShadowColor(0, 0, 0, 1)
    ns.xpLabel:SetText("")

    -- Collapse logic
    collapseBtn:SetScript("OnClick", function()
        if contentFrame:IsShown() then
            contentFrame:Hide()
            collapseBtnText:SetText("+")
            db.collapsed = true
            frame:SetHeight(header:GetHeight())
        else
            contentFrame:Show()
            collapseBtnText:SetText("\226\128\147")
            db.collapsed = false
            ns:UpdateFrameHeight()
        end
    end)

    -- Restore state
    if db.collapsed then
        contentFrame:Hide()
        collapseBtnText:SetText("+")
        frame:SetHeight(header:GetHeight())
    end

    if db.pinned == false then
        frame:SetMovable(true)
        local pos = db.position
        if pos and pos.point then
            frame:ClearAllPoints()
            frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
        end
        pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
    else
        db.pinned = true
        ApplyPinnedState()
    end

    -- Events
    local eventFrame = CreateFrame("Frame")
    local _reanchorPending = false
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
    eventFrame:RegisterEvent("UPDATE_FACTION")
    eventFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    pcall(function() eventFrame:RegisterEvent("QUEST_ACCEPTED") end)
    pcall(function() eventFrame:RegisterEvent("QUEST_REMOVED") end)
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    eventFrame:SetScript("OnEvent", function(self, event)
        if ns._cpDisabled then return end
        if event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" or event == "UPDATE_FACTION" then
            if IsInDelve() then
                ns:UpdateDelversJourney()
            end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            ns:UpdateFrameVisibility()
            if IsInDelve() then
                ns:UpdateDelversJourney()
            end
            if db.pinned ~= false then ApplyPinnedState() end
            return
        end
        if event == "ZONE_CHANGED_NEW_AREA" then
            ns:UpdateFrameVisibility()
            if IsInDelve() then
                ns:UpdateDelversJourney()
            end
            return
        end
        if not _reanchorPending then
            _reanchorPending = true
            C_Timer.After(0.2, function()
                _reanchorPending = false
                if db.pinned ~= false then ApplyPinnedState() end
            end)
        end
    end)
    ns.eventFrame = eventFrame

    -- Delayed width fix
    C_Timer.After(0.5, function()
        if ns.frame then ns.frame:SetWidth(frameWidth) end
        if ns.rankLabel then ns.rankLabel:SetWidth(contentWidth) end
        if ns.xpLabel then ns.xpLabel:SetWidth(contentWidth) end
    end)

    -- Initial data
    ns:UpdateDelversJourney()
    ns:UpdateFrameVisibility()

    djlog("Info", "OnLoad complete — DelversJourney v" .. ns.version .. " ready")
end

-- ADDON_LOADED
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        djlog("Info", "ADDON_LOADED fired for: " .. tostring(arg1))
        self:UnregisterEvent("ADDON_LOADED")
        if _G.CouchPotatoDB and _G.CouchPotatoDB.addonStates and
           _G.CouchPotatoDB.addonStates.DelversJourney == false then
            djlog("Info", "DelversJourney disabled via /cp disable — skipping init")
            ns._cpDisabled = true
            return
        end
        ns:OnLoad()
    end
end)
