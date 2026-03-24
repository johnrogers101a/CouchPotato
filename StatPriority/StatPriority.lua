-- StatPriority.lua
-- Displays stat priority for the player's current specialization.
-- UI matches DelveCompanionStats: gold-bordered olive header, tooltip content frame.
--
-- DESIGN NOTE: All initialization (SavedVars, frame creation, UI setup,
-- position restore) happens atomically inside the ADDON_LOADED handler.
-- We intentionally do NOT register PLAYER_LOGIN — same pattern as DCS.

local addonName, ns = ...
-- Fallback for test environments (dofile() does not populate varargs)
if not ns then
    addonName = "StatPriority"
    ns = {}
end
_G.StatPriorityNS = ns

ns.version = "1.0.0"

-------------------------------------------------------------------------------
-- spprint: Write a coloured message to the chat frame (or print fallback).
-- Delegates to CouchPotatoLog when available; bare fallback otherwise.
-------------------------------------------------------------------------------
local function spprint(...)
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Print("SP", ...)
    elseif DEFAULT_CHAT_FRAME then
        local msg = "|cffff99ccSP:|r"
        for i = 1, select("#", ...) do
            msg = msg .. " " .. tostring(select(i, ...))
        end
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    else
        print("|cffff99ccSP:|r", ...)
    end
end

-------------------------------------------------------------------------------
-- Slash commands: /sp  or  /statpriority
-------------------------------------------------------------------------------
SLASH_SP1 = "/sp"
SLASH_SP2 = "/statpriority"
SlashCmdList["SP"] = function(msg)
    local cmd = msg and msg:lower():match("^%s*(%S+)") or ""
    if cmd == "show" then
        if ns.frame then ns.frame:Show() end
        spprint("Frame shown manually")
    elseif cmd == "hide" then
        if ns.frame then ns.frame:Hide() end
        spprint("Frame hidden manually")
    elseif cmd == "toggle" then
        if ns.frame then
            if ns.frame:IsShown() then
                ns.frame:Hide()
                spprint("Frame hidden (toggle)")
            else
                ns.frame:Show()
                spprint("Frame shown (toggle)")
                ns:UpdateStatPriority()
            end
        end
    elseif cmd == "reset" then
        if StatPriorityDB then StatPriorityDB.position = nil end
        if ns.frame then
            ns.frame:ClearAllPoints()
            if ChatFrame1 then
                ns.frame:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 40)
            else
                ns.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 5, 160)
            end
        end
        spprint("Frame position reset to default")
    elseif cmd == "debug" then
        spprint("StatPriority v" .. ns.version)
        local specIndex = GetSpecialization and GetSpecialization() or nil
        spprint("specIndex:", tostring(specIndex))
        if specIndex then
            local specID = select(1, GetSpecializationInfo(specIndex))
            spprint("specID:", tostring(specID))
            local data = StatPriorityData and StatPriorityData[specID]
            spprint("data:", data and data.specName or "nil")
        end
    else
        spprint("Usage: /sp [show|hide|toggle|reset|debug]")
    end
end

-------------------------------------------------------------------------------
-- UpdateStatPriority: Reads player spec, looks up data, updates UI.
-------------------------------------------------------------------------------
function ns:UpdateStatPriority()
    if not ns.frame then return end

    -- Default state
    local specName   = "No Specialization"
    local statsText  = ""

    local specIndex = nil
    if GetSpecialization then
        specIndex = GetSpecialization()
    end

    if specIndex and specIndex > 0 then
        local specID, name = GetSpecializationInfo(specIndex)
        if specID then
            local data = StatPriorityData and StatPriorityData[specID]
            if data then
                specName  = data.specName or name or "Unknown Spec"
                -- Join stats with gold ">" separator
                local sep = " |cffFFD100>|r "
                statsText = table.concat(data.stats, sep)
            else
                specName  = name or ("Spec " .. tostring(specID))
                statsText = ""
                spprint("Warning: no data for specID", specID)
            end
        end
    end

    -- Update header title
    if ns.headerTitle then
        ns.headerTitle:SetText(specName)
    end

    -- Update content label
    if ns.statsLabel then
        ns.statsLabel:SetText(statsText)
    end

    -- Resize content frame to fit label
    ns:UpdateFrameHeight()
end

-------------------------------------------------------------------------------
-- UpdateFrameHeight: Resize the outer frame to header + visible content.
-------------------------------------------------------------------------------
function ns:UpdateFrameHeight()
    local headerH = ns.headerFrame and ns.headerFrame:GetHeight() or 28
    if ns.contentFrame and ns.contentFrame:IsShown() then
        -- Estimate content height: ~20px per line plus padding
        local labelH = 20
        ns.contentFrame:SetHeight(labelH + 16)
        ns.frame:SetHeight(headerH + ns.contentFrame:GetHeight() + 8)
    else
        ns.frame:SetHeight(headerH)
    end
end

-------------------------------------------------------------------------------
-- OnLoad: Frame creation + UI setup + SavedVars init + position restore.
-- Called exactly once from ADDON_LOADED handler below.
-- Guard: if ns.frame already exists, skip (idempotent safety).
-------------------------------------------------------------------------------
function ns:OnLoad()
    -- Guard: idempotent — never initialize twice
    if ns.frame then return end

    -- 1. Initialize SavedVariables
    StatPriorityDB = StatPriorityDB or {}
    local db = StatPriorityDB

    -- 2. Create the main display frame
    local frameOk, frameResult = pcall(function()
        return CreateFrame("Frame", "StatPriorityFrame", UIParent, "BackdropTemplate")
    end)
    if not frameOk or not frameResult then
        local ok2, f2 = pcall(function()
            return CreateFrame("Frame", "StatPriorityFrame", UIParent)
        end)
        if ok2 and f2 then
            frameResult = f2
            frameOk = true
        end
    end
    if not frameOk or not frameResult then
        spprint("Error: Could not create display frame. Addon disabled.")
        ns.frame = nil
        return
    end

    ns.frame = frameResult
    ns.frame:SetFrameStrata("DIALOG")
    ns.frame:SetFrameLevel(100)
    ns.frame:SetMovable(true)

    local frameWidth  = 248
    local contentWidth = frameWidth - 12

    -- Default anchor: above ChatFrame1, 40px above (30px above DCS default of 10)
    ns.frame:SetSize(frameWidth, 60)
    if db.position then
        ns.frame:ClearAllPoints()
        ns.frame:SetPoint(db.position.point, UIParent, db.position.relativePoint,
                          db.position.x, db.position.y)
    elseif ChatFrame1 then
        ns.frame:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 40)
    else
        ns.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 5, 160)
    end

    -- -----------------------------------------------------------------------
    -- 3. Header frame — matches DCS exactly
    -- -----------------------------------------------------------------------
    local header = CreateFrame("Button", nil, ns.frame)
    ns.headerFrame = header
    header:SetHeight(28)
    header:SetPoint("TOPLEFT",  ns.frame, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", ns.frame, "TOPRIGHT", 0, 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")

    header:SetScript("OnDragStart", function()
        ns.frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        ns.frame:StopMovingOrSizing()
        if StatPriorityDB then
            local point, _, relPoint, x, y = ns.frame:GetPoint()
            StatPriorityDB.position = { point = point, relativePoint = relPoint, x = x, y = y }
        end
    end)

    -- Background: dark olive
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(header)
    headerBg:SetColorTexture(0.15, 0.12, 0.03, 0.95)

    -- Top gold border
    local headerTopLine = header:CreateTexture(nil, "BORDER")
    headerTopLine:SetHeight(1)
    headerTopLine:SetPoint("TOPLEFT",  header, "TOPLEFT",  0, 0)
    headerTopLine:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    headerTopLine:SetColorTexture(1, 0.78, 0.1, 1)

    -- Bottom gold border
    local headerBottomLine = header:CreateTexture(nil, "BORDER")
    headerBottomLine:SetHeight(1)
    headerBottomLine:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT",  0, 0)
    headerBottomLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerBottomLine:SetColorTexture(1, 0.78, 0.1, 1)

    -- Title: FRIZQT 14pt OUTLINE, gold, left-aligned
    local headerTitle = header:CreateFontString(nil, "OVERLAY")
    headerTitle:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    headerTitle:SetPoint("LEFT", header, "LEFT", 8, 0)
    headerTitle:SetJustifyV("MIDDLE")
    headerTitle:SetText("Stat Priority")
    headerTitle:SetTextColor(1, 0.82, 0.0, 1)
    ns.headerTitle = headerTitle
    ns.headerLabel = headerTitle  -- alias

    -- Collapse button: gold en-dash, far right
    local collapseBtn = CreateFrame("Button", nil, header)
    collapseBtn:SetSize(20, 28)
    collapseBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    local collapseBtnText = collapseBtn:CreateFontString(nil, "OVERLAY")
    collapseBtnText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    collapseBtnText:SetAllPoints(collapseBtn)
    collapseBtnText:SetJustifyH("CENTER")
    collapseBtnText:SetJustifyV("MIDDLE")
    collapseBtnText:SetTextColor(1, 0.78, 0.1, 1)
    collapseBtnText:SetText("\226\128\147")  -- en-dash (–)
    collapseBtn:SetFontString(collapseBtnText)
    ns.collapseBtn     = collapseBtn
    ns.collapseBtnText = collapseBtnText

    collapseBtn:SetScript("OnClick", function()
        if ns.contentFrame:IsShown() then
            ns.contentFrame:Hide()
            collapseBtnText:SetText("+")
            if StatPriorityDB then StatPriorityDB.collapsed = true end
            ns.frame:SetHeight(header:GetHeight())
        else
            ns.contentFrame:Show()
            collapseBtnText:SetText("\226\128\147")
            if StatPriorityDB then StatPriorityDB.collapsed = false end
            ns:UpdateFrameHeight()
        end
    end)

    -- -----------------------------------------------------------------------
    -- 4. Content frame — BackdropTemplate with tooltip bg/border
    -- -----------------------------------------------------------------------
    local contentFrame
    local cok, cr = pcall(function()
        return CreateFrame("Frame", nil, ns.frame, "BackdropTemplate")
    end)
    if cok and cr then
        contentFrame = cr
    else
        contentFrame = CreateFrame("Frame", nil, ns.frame)
    end
    contentFrame:SetPoint("TOPLEFT",  header, "BOTTOMLEFT",  0, -4)
    contentFrame:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    contentFrame:SetHeight(36)

    -- Apply backdrop (pcall guards missing API in test env)
    pcall(function()
        contentFrame:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        contentFrame:SetBackdropColor(0.05, 0.04, 0.01, 0.95)
        contentFrame:SetBackdropBorderColor(1, 0.78, 0.1, 0.8)
    end)
    ns.contentFrame = contentFrame

    -- -----------------------------------------------------------------------
    -- 5. Stats label — GameFontHighlightSmall / ObjectiveFont, white
    -- -----------------------------------------------------------------------
    local statsLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 6, -6)
    statsLabel:SetWidth(contentWidth)
    statsLabel:SetJustifyH("LEFT")
    statsLabel:SetFontObject("GameFontHighlightSmall")
    pcall(function() statsLabel:SetFontObject(ObjectiveFont) end)
    statsLabel:SetTextColor(1, 1, 1, 1)
    statsLabel:SetText("")
    statsLabel:SetShadowOffset(1, -1)
    statsLabel:SetShadowColor(0, 0, 0, 1)
    statsLabel:SetWordWrap(true)
    ns.statsLabel = statsLabel

    -- -----------------------------------------------------------------------
    -- 6. Restore collapsed state
    -- -----------------------------------------------------------------------
    if db.collapsed then
        contentFrame:Hide()
        collapseBtnText:SetText("+")
        ns.frame:SetHeight(header:GetHeight())
    end

    -- -----------------------------------------------------------------------
    -- 7. Initial data load
    -- -----------------------------------------------------------------------
    ns:UpdateStatPriority()

    -- -----------------------------------------------------------------------
    -- 8. Register for spec change events
    -- -----------------------------------------------------------------------
    local specEventFrame = CreateFrame("Frame")
    specEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specEventFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            ns:UpdateStatPriority()
        end
    end)
    ns.specEventFrame = specEventFrame

    -- Delayed width fix (matches DCS pattern)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            if ns.frame then ns.frame:SetWidth(frameWidth) end
            if ns.headerFrame then ns.headerFrame:SetWidth(frameWidth) end
            if ns.statsLabel then ns.statsLabel:SetWidth(contentWidth) end
        end)
    end

    spprint("Loaded v" .. ns.version)
end

-------------------------------------------------------------------------------
-- Central event frame — ADDON_LOADED only (no PLAYER_LOGIN race condition)
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        self:UnregisterEvent("ADDON_LOADED")
        ns:OnLoad()
    end
end)
