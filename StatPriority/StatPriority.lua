-- StatPriority.lua
-- Displays stat priority for the player's current specialization.
-- UI matches DelveCompanionStats: gold-bordered olive header, tooltip content frame.
--
-- Phase 2: Multi-source display (Wowhead, Icy Veins, Method) with URL copy buttons.
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

ns.version = "2.0.0"

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
            if data then
                spprint("_differs:", tostring(data._differs))
            end
        end
    else
        spprint("Usage: /sp [show|hide|toggle|reset|debug]")
    end
end

-------------------------------------------------------------------------------
-- ShowURLPopup: Show the singleton URL popup with the given URL pre-selected.
-------------------------------------------------------------------------------
function ns:ShowURLPopup(url)
    if not ns.urlPopup then return end
    if ns.urlPopupEditBox then
        ns.urlPopupEditBox:SetText(url or "")
        pcall(function() ns.urlPopupEditBox:HighlightText() end)
        pcall(function() ns.urlPopupEditBox:SetFocus() end)
    end
    ns.urlPopup:Show()
end

-------------------------------------------------------------------------------
-- UpdateStatPriority: Reads player spec, looks up data, updates UI.
-------------------------------------------------------------------------------
function ns:UpdateStatPriority()
    if not ns.frame then return end

    -- Default state
    local specName   = "No Specialization"
    local statsText  = ""
    local data       = nil

    local specIndex = nil
    if GetSpecialization then
        specIndex = GetSpecialization()
    end

    if specIndex and specIndex > 0 then
        local specID, name = GetSpecializationInfo(specIndex)
        if specID then
            data = StatPriorityData and StatPriorityData[specID]
            if data then
                specName = data.specName or name or "Unknown Spec"
                -- Join stats with gold ">" separator
                local sep = " |cffFFD100>|r "
                statsText = table.concat(data.stats, sep)
            else
                specName = name or "Unknown Spec"
                statsText = ""
                spprint("Warning: no data for specID", specID)
            end
        end
    end

    -- Update header title
    if ns.headerTitle then
        ns.headerTitle:SetText(specName)
    end

    local sep = " |cffFFD100>|r "

    if data and data._differs then
        -- Multi-source display
        if ns.statsLabel then ns.statsLabel:Hide() end

        if ns.wowheadLabel then
            local text = "|cff00ccffWowhead:|r " .. table.concat(data.wowhead, sep)
            ns.wowheadLabel:SetText(text)
            ns.wowheadLabel:Show()
        end
        if ns.icyveinsLabel then
            local text = "|cff33cc33Icy Veins:|r " .. table.concat(data.icyveins, sep)
            ns.icyveinsLabel:SetText(text)
            ns.icyveinsLabel:Show()
        end
        if ns.methodLabel then
            local text = "|cffff6600Method:|r " .. table.concat(data.method, sep)
            ns.methodLabel:SetText(text)
            ns.methodLabel:Show()
        end

        -- Show URL buttons for each source (if URL exists)
        if ns.wowheadUrlBtn then
            if data.urls and data.urls.wowhead then
                ns.wowheadUrlBtn:Show()
            else
                ns.wowheadUrlBtn:Hide()
            end
        end
        if ns.icyveinsUrlBtn then
            if data.urls and data.urls.icyveins then
                ns.icyveinsUrlBtn:Show()
            else
                ns.icyveinsUrlBtn:Hide()
            end
        end
        if ns.methodUrlBtn then
            if data.urls and data.urls.method then
                ns.methodUrlBtn:Show()
            else
                ns.methodUrlBtn:Hide()
            end
        end
    else
        -- Unified display (Phase 1 behavior)
        if ns.statsLabel then
            ns.statsLabel:SetText(statsText)
            ns.statsLabel:Show()
        end

        if ns.wowheadLabel  then ns.wowheadLabel:Hide()  end
        if ns.icyveinsLabel then ns.icyveinsLabel:Hide() end
        if ns.methodLabel   then ns.methodLabel:Hide()   end

        if ns.wowheadUrlBtn  then ns.wowheadUrlBtn:Hide()  end
        if ns.icyveinsUrlBtn then ns.icyveinsUrlBtn:Hide() end
        if ns.methodUrlBtn   then ns.methodUrlBtn:Hide()   end
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
        -- Count visible source lines
        local visibleLines = 0
        if ns.statsLabel and ns.statsLabel:IsShown() then
            visibleLines = 1
        else
            if ns.wowheadLabel  and ns.wowheadLabel:IsShown()  then visibleLines = visibleLines + 1 end
            if ns.icyveinsLabel and ns.icyveinsLabel:IsShown() then visibleLines = visibleLines + 1 end
            if ns.methodLabel   and ns.methodLabel:IsShown()   then visibleLines = visibleLines + 1 end
        end
        if visibleLines == 0 then visibleLines = 1 end
        local contentH = visibleLines * 20 + 16
        ns.contentFrame:SetHeight(contentH)
        ns.frame:SetHeight(headerH + contentH + 8)
    else
        ns.frame:SetHeight(headerH)
    end
end

-------------------------------------------------------------------------------
-- CreateURLButton: Helper to create a small gold ">" URL button.
-------------------------------------------------------------------------------
local function createURLButton(parent, anchorLabel, getURL)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(16, 16)
    btn:SetPoint("LEFT", anchorLabel, "RIGHT", 4, 0)

    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    fs:SetAllPoints(btn)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetTextColor(1, 0.78, 0.1, 1)
    fs:SetText(">")
    btn:SetFontString(fs)

    btn:SetScript("OnClick", function()
        local url = getURL()
        if url and ns.ShowURLPopup then
            ns:ShowURLPopup(url)
        end
    end)

    btn:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(function()
                GameTooltip:SetText("Click to copy URL")
                GameTooltip:Show()
            end)
        end
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return btn
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
    -- 5a. Unified stats label (shown when _differs is false)
    -- -----------------------------------------------------------------------
    local statsLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 6, -6)
    statsLabel:SetWidth(contentWidth - 20)  -- leave room for URL button
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
    -- 5b. Per-source labels (shown when _differs is true)
    -- -----------------------------------------------------------------------
    local labelWidth = contentWidth - 24  -- leave room for URL button

    -- Wowhead label (cyan)
    local wowheadLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    wowheadLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 6, -6)
    wowheadLabel:SetWidth(labelWidth)
    wowheadLabel:SetJustifyH("LEFT")
    pcall(function() wowheadLabel:SetFontObject(ObjectiveFont) end)
    wowheadLabel:SetTextColor(1, 1, 1, 1)
    wowheadLabel:SetText("")
    wowheadLabel:SetShadowOffset(1, -1)
    wowheadLabel:SetShadowColor(0, 0, 0, 1)
    wowheadLabel:SetWordWrap(true)
    wowheadLabel:Hide()
    ns.wowheadLabel = wowheadLabel

    -- Icy Veins label (green)
    local icyveinsLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icyveinsLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 6, -26)
    icyveinsLabel:SetWidth(labelWidth)
    icyveinsLabel:SetJustifyH("LEFT")
    pcall(function() icyveinsLabel:SetFontObject(ObjectiveFont) end)
    icyveinsLabel:SetTextColor(1, 1, 1, 1)
    icyveinsLabel:SetText("")
    icyveinsLabel:SetShadowOffset(1, -1)
    icyveinsLabel:SetShadowColor(0, 0, 0, 1)
    icyveinsLabel:SetWordWrap(true)
    icyveinsLabel:Hide()
    ns.icyveinsLabel = icyveinsLabel

    -- Method label (orange)
    local methodLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    methodLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 6, -46)
    methodLabel:SetWidth(labelWidth)
    methodLabel:SetJustifyH("LEFT")
    pcall(function() methodLabel:SetFontObject(ObjectiveFont) end)
    methodLabel:SetTextColor(1, 1, 1, 1)
    methodLabel:SetText("")
    methodLabel:SetShadowOffset(1, -1)
    methodLabel:SetShadowColor(0, 0, 0, 1)
    methodLabel:SetWordWrap(true)
    methodLabel:Hide()
    ns.methodLabel = methodLabel

    -- -----------------------------------------------------------------------
    -- 5c. URL buttons — one per source, anchored to the right of each label
    -- -----------------------------------------------------------------------
    -- We need a deferred data lookup for buttons, so use a closure
    local function getCurrentData()
        local specIndex = GetSpecialization and GetSpecialization() or nil
        if specIndex and specIndex > 0 then
            local specID = select(1, GetSpecializationInfo(specIndex))
            if specID and StatPriorityData then
                return StatPriorityData[specID]
            end
        end
        return nil
    end

    ns.wowheadUrlBtn = createURLButton(contentFrame, wowheadLabel, function()
        local d = getCurrentData()
        return d and d.urls and d.urls.wowhead
    end)
    ns.wowheadUrlBtn:Hide()

    ns.icyveinsUrlBtn = createURLButton(contentFrame, icyveinsLabel, function()
        local d = getCurrentData()
        return d and d.urls and d.urls.icyveins
    end)
    ns.icyveinsUrlBtn:Hide()

    ns.methodUrlBtn = createURLButton(contentFrame, methodLabel, function()
        local d = getCurrentData()
        return d and d.urls and d.urls.method
    end)
    ns.methodUrlBtn:Hide()

    -- -----------------------------------------------------------------------
    -- 6. URL popup — singleton EditBox popup for copying URLs
    -- -----------------------------------------------------------------------
    local urlPopup
    local popupOk, popupResult = pcall(function()
        return CreateFrame("Frame", "StatPriorityURLPopup", UIParent, "BackdropTemplate")
    end)
    if popupOk and popupResult then
        urlPopup = popupResult
    else
        urlPopup = CreateFrame("Frame", "StatPriorityURLPopup", UIParent)
    end
    urlPopup:SetSize(360, 80)
    urlPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    urlPopup:SetFrameStrata("TOOLTIP")
    urlPopup:SetFrameLevel(200)
    urlPopup:SetMovable(true)
    pcall(function()
        urlPopup:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        urlPopup:SetBackdropColor(0.05, 0.04, 0.01, 0.95)
        urlPopup:SetBackdropBorderColor(1, 0.78, 0.1, 0.9)
    end)
    urlPopup:Hide()
    urlPopup:EnableMouse(true)
    urlPopup:RegisterForDrag("LeftButton")
    urlPopup:SetScript("OnDragStart", function() urlPopup:StartMoving() end)
    urlPopup:SetScript("OnDragStop",  function() urlPopup:StopMovingOrSizing() end)

    -- Label
    local urlTitle = urlPopup:CreateFontString(nil, "OVERLAY")
    urlTitle:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    urlTitle:SetPoint("TOPLEFT", urlPopup, "TOPLEFT", 10, -10)
    urlTitle:SetTextColor(1, 0.82, 0.0, 1)
    urlTitle:SetText("Copy URL (Ctrl+C):")

    -- EditBox for URL
    local editBox = CreateFrame("EditBox", nil, urlPopup)
    editBox:SetPoint("TOPLEFT",  urlPopup, "TOPLEFT",  10, -26)
    editBox:SetPoint("TOPRIGHT", urlPopup, "TOPRIGHT", -10, -26)
    editBox:SetHeight(20)
    editBox:SetFontObject("GameFontHighlightSmall")
    pcall(function() editBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "") end)
    editBox:SetAutoFocus(false)
    editBox:SetMultiLine(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function()
        urlPopup:Hide()
    end)
    ns.urlPopupEditBox = editBox

    -- Close button
    local closeBtn = CreateFrame("Button", nil, urlPopup, "UIPanelButtonTemplate")
    closeBtn:SetSize(60, 22)
    closeBtn:SetPoint("BOTTOM", urlPopup, "BOTTOM", 0, 6)
    pcall(function() closeBtn:SetText("Close") end)
    closeBtn:SetScript("OnClick", function()
        urlPopup:Hide()
    end)

    urlPopup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            urlPopup:Hide()
        end
    end)
    pcall(function() urlPopup:EnableKeyboard(true) end)

    ns.urlPopup = urlPopup

    -- -----------------------------------------------------------------------
    -- 7. Restore collapsed state
    -- -----------------------------------------------------------------------
    if db.collapsed then
        contentFrame:Hide()
        collapseBtnText:SetText("+")
        ns.frame:SetHeight(header:GetHeight())
    end

    -- -----------------------------------------------------------------------
    -- 8. Initial data load
    -- -----------------------------------------------------------------------
    ns:UpdateStatPriority()

    -- -----------------------------------------------------------------------
    -- 9. Register for spec change events
    -- -----------------------------------------------------------------------
    local specEventFrame = CreateFrame("Frame")
    specEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specEventFrame:RegisterEvent("PLAYER_LOGIN")
    specEventFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LOGIN" then
            ns:UpdateStatPriority()
        end
    end)
    ns.specEventFrame = specEventFrame

    -- Delayed width fix (matches DCS pattern)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            if ns.frame then ns.frame:SetWidth(frameWidth) end
            if ns.headerFrame then ns.headerFrame:SetWidth(frameWidth) end
            if ns.statsLabel then ns.statsLabel:SetWidth(contentWidth - 20) end
            if ns.wowheadLabel  then ns.wowheadLabel:SetWidth(contentWidth - 24)  end
            if ns.icyveinsLabel then ns.icyveinsLabel:SetWidth(contentWidth - 24) end
            if ns.methodLabel   then ns.methodLabel:SetWidth(contentWidth - 24)   end
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
