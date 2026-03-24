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
-- splog: Structured logging via CouchPotatoLog. Falls back gracefully.
-------------------------------------------------------------------------------
local function splog(level, msg)
    if _G.CouchPotatoLog and _G.CouchPotatoLog[level] then
        _G.CouchPotatoLog[level](_G.CouchPotatoLog, "SP", msg)
    end
end

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
    splog("Info", "Slash /sp received, cmd='" .. cmd .. "'")
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
                splog("Info", "Frame hidden via /sp toggle")
            else
                ns.frame:Show()
                spprint("Frame shown (toggle)")
                splog("Info", "Frame shown via /sp toggle")
                ns:UpdateStatPriority()
            end
        end
    elseif cmd == "reset" then
        if StatPriorityDB then
            StatPriorityDB.position = nil
            StatPriorityDB.pinned   = nil
            splog("Info", "/sp reset: cleared position and pinned from SavedVars")
        end
        if ns.frame and ns.ApplyPinnedState then
            ns.ApplyPinnedState()
            splog("Info", "/sp reset: re-applied pinned state (docked)")
        end
        spprint("Frame position reset to default (docked)")
        splog("Info", "Frame position reset to default via /sp reset")
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
    splog("Info", "URL popup opened, url=" .. tostring(url))
    if not ns.urlPopup then return end
    if ns.urlPopupEditBox then
        ns.urlPopupEditBox:SetText(url or "")
        pcall(function() ns.urlPopupEditBox:HighlightText() end)
        pcall(function() ns.urlPopupEditBox:SetFocus() end)
    end
    ns.urlPopup:Show()
end

-------------------------------------------------------------------------------
-- GetDisplaySpecID: Returns the specID to display based on StatPriorityDB.specOverride.
--   "current" or nil  → GetSpecialization() + GetSpecializationInfo()
--   "loot"            → GetLootSpecialization() (0 means fall back to current)
--   integer specID    → use that specID directly
-------------------------------------------------------------------------------
function ns:GetDisplaySpecID()
    local override = StatPriorityDB and StatPriorityDB.specOverride
    splog("Debug", "GetDisplaySpecID: override=" .. tostring(override))

    if type(override) == "number" then
        -- Fixed spec override
        splog("Info", "GetDisplaySpecID: fixed specID override=" .. tostring(override))
        return override
    elseif override == "loot" then
        -- Loot spec mode
        local lootSpecID = 0
        if GetLootSpecialization then
            lootSpecID = GetLootSpecialization() or 0
            splog("Info", "GetDisplaySpecID: loot mode, GetLootSpecialization()=" .. tostring(lootSpecID))
        else
            splog("Warn", "GetDisplaySpecID: GetLootSpecialization API not available")
        end
        if lootSpecID and lootSpecID > 0 then
            splog("Info", "GetDisplaySpecID: using loot specID=" .. tostring(lootSpecID))
            return lootSpecID
        else
            -- Fall back to current spec when loot spec is "Current Specialization" (0)
            splog("Info", "GetDisplaySpecID: loot spec is 0 (current) — falling back to active spec")
            -- fall through to current spec logic below
        end
    end

    -- Default: current spec
    if not GetSpecialization then
        splog("Warn", "GetDisplaySpecID: GetSpecialization API not available")
        return nil
    end
    local specIndex = GetSpecialization()
    splog("Debug", "GetDisplaySpecID: current mode, specIndex=" .. tostring(specIndex))
    if not specIndex or specIndex <= 0 then
        splog("Debug", "GetDisplaySpecID: no active spec (specIndex=" .. tostring(specIndex) .. ")")
        return nil
    end
    local specID = select(1, GetSpecializationInfo(specIndex))
    splog("Debug", "GetDisplaySpecID: resolved specID=" .. tostring(specID) .. " from specIndex=" .. tostring(specIndex))
    return specID
end

-------------------------------------------------------------------------------
-- UpdateStatPriority: Reads player spec, looks up data, updates UI.
-------------------------------------------------------------------------------
function ns:UpdateStatPriority()
    if not ns.frame then
        splog("Warn", "UpdateStatPriority called but ns.frame is nil")
        return
    end

    splog("Debug", "UpdateStatPriority: starting")

    -- Default state
    local specName   = "No Specialization"
    local statsText  = ""
    local data       = nil

    local specID = ns:GetDisplaySpecID()
    splog("Debug", "UpdateStatPriority: GetDisplaySpecID() returned specID=" .. tostring(specID))

    -- Resolve a fallback display name for when StatPriorityData has no entry.
    -- For the "current" spec path we use GetSpecializationInfo (has the freshest name);
    -- for loot/fixed paths we use GetSpecializationInfoByID when available.
    local function getAPISpecName(sid)
        -- Try the active-spec API first (works for all modes in the common case)
        if GetSpecialization and GetSpecializationInfo then
            local idx = GetSpecialization()
            if idx and idx > 0 then
                local infoID, infoName = GetSpecializationInfo(idx)
                if infoID == sid then
                    return infoName
                end
            end
        end
        -- Fall back to by-ID lookup when available
        if GetSpecializationInfoByID then
            local _, n = GetSpecializationInfoByID(sid)
            return n
        end
        return nil
    end

    -- specID == 0 means the API returned a "not ready" value (early-load race):
    -- treat as "has index but invalid specID" → show "Unknown Spec".
    if specID == 0 then
        specName = "Unknown Spec"
        splog("Warn", "UpdateStatPriority: specID=0 (API not ready) — showing 'Unknown Spec'")
    elseif specID and specID > 0 then
        local name = getAPISpecName(specID)
        splog("Debug", "UpdateStatPriority: specID=" .. tostring(specID) .. " apiName=" .. tostring(name))

        data = StatPriorityData and StatPriorityData[specID]
        if data then
            splog("Info", "StatPriorityData lookup: found data for specID=" .. tostring(specID) .. " specName=" .. tostring(data.specName))
            specName = data.specName or name or "Unknown Spec"
            -- Join stats with gold ">" separator
            local sep = " |cffFFD100>|r "
            statsText = table.concat(data.stats, sep)
        else
            splog("Warn", "StatPriorityData lookup: NO data for specID=" .. tostring(specID))
            specName = name or "Unknown Spec"
            statsText = ""
            spprint("Warning: no data for specID", specID)
        end
    else
        splog("Debug", "No active specialization (specID=" .. tostring(specID) .. ")")
    end

    -- Update header title
    if ns.headerTitle then
        ns.headerTitle:SetText(specName)
        splog("Debug", "Header text set to: " .. tostring(specName))
    end

    local sep = " |cffFFD100>|r "

    if data and data._differs then
        splog("Info", "Display mode: multi-source (sources differ), specID=" .. tostring(data and data.specName))
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
                splog("Debug", "Wowhead URL button shown")
            else
                ns.wowheadUrlBtn:Hide()
            end
        end
        if ns.icyveinsUrlBtn then
            if data.urls and data.urls.icyveins then
                ns.icyveinsUrlBtn:Show()
                splog("Debug", "IcyVeins URL button shown")
            else
                ns.icyveinsUrlBtn:Hide()
            end
        end
        if ns.methodUrlBtn then
            if data.urls and data.urls.method then
                ns.methodUrlBtn:Show()
                splog("Debug", "Method URL button shown")
            else
                ns.methodUrlBtn:Hide()
            end
        end
    else
        splog("Info", "Display mode: unified (single source or no data)")
        -- Unified display (Phase 1 behavior)
        if ns.statsLabel then
            ns.statsLabel:SetText(statsText)
            ns.statsLabel:Show()
            splog("Debug", "Stats text set to: " .. tostring(statsText):sub(1, 80))
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
    splog("Debug", "UpdateStatPriority: complete")
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
        splog("Info", "URL button clicked, url=" .. tostring(url))
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
-- GetTrackerAnchor: Returns ObjectiveTrackerFrame if it exists and is shown.
-- Returns nil otherwise. Used by pinned-state anchor logic.
-------------------------------------------------------------------------------
local function GetTrackerAnchor()
    if ObjectiveTrackerFrame
        and ObjectiveTrackerFrame.IsShown
        and ObjectiveTrackerFrame:IsShown() then
        splog("Debug", "GetTrackerAnchor: ObjectiveTrackerFrame is visible — returning it")
        return ObjectiveTrackerFrame
    end
    splog("Debug", "GetTrackerAnchor: ObjectiveTrackerFrame not available/visible — returning nil")
    return nil
end

-------------------------------------------------------------------------------
-- OnLoad: Frame creation + UI setup + SavedVars init + position restore.
-- Called exactly once from ADDON_LOADED handler below.
-- Guard: if ns.frame already exists, skip (idempotent safety).
-------------------------------------------------------------------------------
function ns:OnLoad()
    -- Guard: idempotent — never initialize twice
    if ns.frame then
        splog("Warn", "OnLoad called but ns.frame already exists — skipping (idempotent guard)")
        return
    end

    splog("Info", "OnLoad: starting initialization, version=" .. ns.version)

    -- 1. Initialize SavedVariables
    StatPriorityDB = StatPriorityDB or {}
    local db = StatPriorityDB
    -- Initialize specOverride default
    if db.specOverride == nil then
        db.specOverride = "current"
        splog("Info", "SavedVariables: specOverride initialized to 'current'")
    end
    -- Validate: if specOverride is a number, verify it's a valid spec for the current class.
    -- If not (e.g., stale from race change), reset to "current".
    if type(db.specOverride) == "number" then
        local isValid = false
        if GetNumSpecializations then
            local numSpecs = GetNumSpecializations()
            for i = 1, numSpecs do
                local sid = select(1, GetSpecializationInfo(i))
                if sid == db.specOverride then
                    isValid = true
                    break
                end
            end
        end
        if not isValid then
            splog("Warn", "SavedVariables: specOverride=" .. tostring(db.specOverride) ..
                  " not valid for current class — resetting to 'current'")
            db.specOverride = "current"
        else
            splog("Info", "SavedVariables: specOverride=" .. tostring(db.specOverride) .. " validated OK")
        end
    end
    splog("Debug", "SavedVariables: StatPriorityDB initialized, specOverride=" .. tostring(db.specOverride))

    -- 2. Create the main display frame
    local frameOk, frameResult = pcall(function()
        return CreateFrame("Frame", "StatPriorityFrame", UIParent, "BackdropTemplate")
    end)
    if not frameOk or not frameResult then
        splog("Warn", "CreateFrame with BackdropTemplate failed, retrying without template")
        local ok2, f2 = pcall(function()
            return CreateFrame("Frame", "StatPriorityFrame", UIParent)
        end)
        if ok2 and f2 then
            frameResult = f2
            frameOk = true
        end
    end
    if not frameOk or not frameResult then
        splog("Error", "Could not create display frame — addon disabled")
        spprint("Error: Could not create display frame. Addon disabled.")
        ns.frame = nil
        return
    end

    ns.frame = frameResult
    ns.frame:SetFrameStrata("DIALOG")
    ns.frame:SetFrameLevel(100)
    ns.frame:SetMovable(true)
    splog("Info", "Frame created successfully: StatPriorityFrame")

    local frameWidth  = 248
    local contentWidth = frameWidth - 12

    ns.frame:SetSize(frameWidth, 60)

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
        -- Guard: only start moving when unpinned (matching DCS pattern)
        if StatPriorityDB and StatPriorityDB.pinned == false then
            splog("Info", "OnDragStart: unpinned — StartMoving")
            ns.frame:StartMoving()
        else
            splog("Debug", "OnDragStart: pinned — drag blocked")
        end
    end)
    header:SetScript("OnDragStop", function()
        ns.frame:StopMovingOrSizing()
        if StatPriorityDB then
            local point, _, relPoint, x, y = ns.frame:GetPoint()
            StatPriorityDB.position = { point = point, relPoint = relPoint, x = x, y = y }
            splog("Info", "Frame position saved: point=" .. tostring(point) ..
                  " relPoint=" .. tostring(relPoint) ..
                  " x=" .. tostring(x) .. " y=" .. tostring(y))
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
            splog("Info", "Frame collapsed")
        else
            ns.contentFrame:Show()
            collapseBtnText:SetText("\226\128\147")
            if StatPriorityDB then StatPriorityDB.collapsed = false end
            ns:UpdateFrameHeight()
            splog("Info", "Frame expanded")
        end
    end)

    -- Pin button: to the LEFT of the collapse button. Lock icon indicates whether
    -- the frame is anchored to ObjectiveTrackerFrame (locked/pinned) or freely
    -- draggable (unlocked/unpinned). Default: pinned (locked icon).
    local pinBtn = CreateFrame("Button", nil, header)
    pinBtn:SetSize(16, 16)
    pinBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -6, 0)
    pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
    pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
    pinBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    pinBtn:EnableMouse(true)
    ns.pinBtn = pinBtn
    splog("Debug", "Pin button created: 16x16, LEFT of collapseBtn")

    -- ApplyPinnedState: anchor frame to ObjectiveTrackerFrame, disable dragging, lock icon.
    local function ApplyPinnedState()
        ns.frame:SetMovable(false)
        local anchor = GetTrackerAnchor()
        ns.frame:ClearAllPoints()
        if anchor then
            ns.frame:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
            splog("Info", "ApplyPinnedState: anchored to ObjectiveTrackerFrame BOTTOM with -4px gap")
        else
            ns.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            splog("Info", "ApplyPinnedState: no tracker visible — anchored to UIParent CENTER fallback")
        end
        ns.pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
        ns.pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
        StatPriorityDB.pinned = true
        splog("Info", "ApplyPinnedState: complete — frame immovable, pinned=true")
    end

    -- ApplyUnpinnedState: detach from tracker, enable free drag, unlock icon.
    local function ApplyUnpinnedState()
        ns.frame:SetMovable(true)
        ns.pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        ns.pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
        StatPriorityDB.pinned = false
        splog("Info", "ApplyUnpinnedState: complete — frame movable, pinned=false")
    end

    -- Expose for tests and external helpers
    ns.ApplyPinnedState   = ApplyPinnedState
    ns.ApplyUnpinnedState = ApplyUnpinnedState

    pinBtn:SetScript("OnClick", function()
        local db = StatPriorityDB
        if not db then return end
        if db.pinned == false then
            -- currently unpinned → pin it
            splog("Info", "PinButton OnClick: was unpinned → pinning now")
            db.pinned = true
            ns.frame:SetMovable(false)
            ns.frame:ClearAllPoints()
            local anchor = GetTrackerAnchor()
            if anchor then
                ns.frame:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
                splog("Info", "PinButton OnClick: anchored to ObjectiveTrackerFrame")
            else
                ns.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                splog("Info", "PinButton OnClick: no tracker — anchored to UIParent CENTER")
            end
            if ns.pinBtn then
                ns.pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
                ns.pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
            end
        else
            -- currently pinned (or nil) → unpin it
            splog("Info", "PinButton OnClick: was pinned → unpinning now")
            db.pinned = false
            ns.frame:SetMovable(true)
            if ns.pinBtn then
                ns.pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
                ns.pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
            end
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
        local specID = ns:GetDisplaySpecID()
        splog("Debug", "getCurrentData: GetDisplaySpecID()=" .. tostring(specID))
        if specID and specID > 0 and StatPriorityData then
            return StatPriorityData[specID]
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
    splog("Debug", "URL popup created")

    -- -----------------------------------------------------------------------
    -- 7. Restore collapsed state
    -- -----------------------------------------------------------------------
    if db.collapsed then
        contentFrame:Hide()
        collapseBtnText:SetText("+")
        ns.frame:SetHeight(header:GetHeight())
        splog("Info", "Restored collapsed state: frame is collapsed")
    else
        splog("Debug", "Collapsed state: expanded (default)")
    end

    -- -----------------------------------------------------------------------
    -- 7b. Restore pin/unpin state. Default (nil) is treated as pinned.
    -- -----------------------------------------------------------------------
    if db.pinned == false then
        -- unpinned: restore saved position, allow dragging, unlock icon
        ns.frame:SetMovable(true)
        local pos = db.position
        if pos and pos.point then
            ns.frame:ClearAllPoints()
            -- Support both legacy key (relativePoint) and new key (relPoint)
            ns.frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.relPoint or pos.point,
                              pos.x or 0, pos.y or 0)
            splog("Info", "Pin restore: unpinned — restored saved position point=" .. tostring(pos.point) ..
                  " x=" .. tostring(pos.x) .. " y=" .. tostring(pos.y))
        else
            splog("Info", "Pin restore: unpinned but no saved position available")
        end
        if ns.pinBtn then
            ns.pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
            ns.pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
        end
        splog("Info", "Pin state restored: unpinned (pinned=false)")
    else
        -- pinned (true or nil) → immovable, locked icon, normalise to true
        db.pinned = true
        ns.frame:SetMovable(false)
        local anchor = GetTrackerAnchor()
        ns.frame:ClearAllPoints()
        if anchor then
            ns.frame:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
            splog("Info", "Pin restore: pinned — anchored to ObjectiveTrackerFrame")
        else
            -- Default fallback: above ChatFrame1 or UIParent (same as old default)
            if ChatFrame1 then
                ns.frame:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 40)
                splog("Info", "Pin restore: pinned but no tracker — anchored above ChatFrame1")
            else
                ns.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 5, 160)
                splog("Info", "Pin restore: pinned but no tracker — anchored UIParent fallback")
            end
        end
        if ns.pinBtn then
            ns.pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
            ns.pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
        end
        splog("Info", "Pin state restored: pinned (pinned=true)")
    end

    -- -----------------------------------------------------------------------
    -- 8. Initial data load
    -- -----------------------------------------------------------------------
    splog("Info", "Running initial UpdateStatPriority on load")
    ns:UpdateStatPriority()

    -- -----------------------------------------------------------------------
    -- 9. Register for spec change events
    -- -----------------------------------------------------------------------
    local specEventFrame = CreateFrame("Frame")
    specEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specEventFrame:RegisterEvent("PLAYER_LOGIN")
    specEventFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    specEventFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            splog("Info", "PLAYER_SPECIALIZATION_CHANGED fired — calling UpdateStatPriority")
            ns:UpdateStatPriority()
        elseif event == "PLAYER_LOGIN" then
            splog("Info", "PLAYER_LOGIN fired — calling UpdateStatPriority")
            ns:UpdateStatPriority()
        elseif event == "PLAYER_LOOT_SPEC_UPDATED" then
            local override = StatPriorityDB and StatPriorityDB.specOverride
            splog("Info", "PLAYER_LOOT_SPEC_UPDATED fired — override=" .. tostring(override))
            if override == "loot" then
                local lootID = GetLootSpecialization and GetLootSpecialization() or 0
                splog("Info", "PLAYER_LOOT_SPEC_UPDATED: GetLootSpecialization()=" .. tostring(lootID) .. " — calling UpdateStatPriority")
                ns:UpdateStatPriority()
            else
                splog("Debug", "PLAYER_LOOT_SPEC_UPDATED: override is not 'loot', skipping update")
            end
        end
    end)
    ns.specEventFrame = specEventFrame
    splog("Debug", "Registered for PLAYER_SPECIALIZATION_CHANGED, PLAYER_LOGIN, PLAYER_LOOT_SPEC_UPDATED")

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

    splog("Info", "OnLoad complete — StatPriority v" .. ns.version .. " ready")
    spprint("Loaded v" .. ns.version)
end

-------------------------------------------------------------------------------
-- Central event frame — ADDON_LOADED only (no PLAYER_LOGIN race condition)
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        splog("Info", "ADDON_LOADED fired for: " .. tostring(arg1))
        self:UnregisterEvent("ADDON_LOADED")
        ns:OnLoad()
    end
end)
