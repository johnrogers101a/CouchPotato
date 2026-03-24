-- CouchPotatoDiag.lua
-- Diagnostic addon: dumps scenario criteria and widget data for debugging.
-- Usage: /cpdiag  → opens a scrollable, copyable diagnostic window.
--
-- Output is also persisted to CouchPotatoDB.lastDiag for cross-session access.

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

-------------------------------------------------------------------------------
-- Diagnostic data collection  (returns a plain-text string, no color codes)
-------------------------------------------------------------------------------

local function collectCriteria(criteria, label, lines)
    if not criteria then
        lines[#lines + 1] = label .. " = nil"
        return
    end
    lines[#lines + 1] = label .. ":"
    lines[#lines + 1] = "  description       = " .. tostring(criteria.description)
    lines[#lines + 1] = "  criteriaType      = " .. tostring(criteria.criteriaType)
    lines[#lines + 1] = "  completed         = " .. tostring(criteria.completed)
    lines[#lines + 1] = "  quantity          = " .. tostring(criteria.quantity)
    lines[#lines + 1] = "  totalQuantity     = " .. tostring(criteria.totalQuantity)
    lines[#lines + 1] = "  flags             = " .. tostring(criteria.flags)
    lines[#lines + 1] = "  assetID           = " .. tostring(criteria.assetID)
    lines[#lines + 1] = "  criteriaID        = " .. tostring(criteria.criteriaID)
    lines[#lines + 1] = "  duration          = " .. tostring(criteria.duration)
    lines[#lines + 1] = "  elapsed           = " .. tostring(criteria.elapsed)
    lines[#lines + 1] = "  failed            = " .. tostring(criteria.failed)
    lines[#lines + 1] = "  isWeightedProgress= " .. tostring(criteria.isWeightedProgress)
    lines[#lines + 1] = "  isFormatted       = " .. tostring(criteria.isFormatted)
    lines[#lines + 1] = "  quantityString    = " .. tostring(criteria.quantityString)
end

local function collectWidgetSet(setID, label, lines)
    if not setID or setID == 0 then
        lines[#lines + 1] = label .. ": no widgetSetID"
        return
    end
    lines[#lines + 1] = label .. " (setID=" .. tostring(setID) .. "):"
    local widgets = safe(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
    if not widgets then
        lines[#lines + 1] = "  GetAllWidgetsBySetID returned nil"
        return
    end
    if #widgets == 0 then
        lines[#lines + 1] = "  (no widgets in set)"
        return
    end
    local getters = {
        { name = "GetScenarioHeaderDelvesWidgetVisualizationInfo", fn = C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo },
        { name = "GetIconAndTextWidgetVisualizationInfo",           fn = C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo },
        { name = "GetTextWithStateWidgetVisualizationInfo",         fn = C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo },
        { name = "GetStatusBarWidgetVisualizationInfo",             fn = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo },
        { name = "GetTextWithSubtextWidgetVisualizationInfo",       fn = C_UIWidgetManager.GetTextWithSubtextWidgetVisualizationInfo },
    }
    for _, w in ipairs(widgets) do
        local wid = w.widgetID
        lines[#lines + 1] = "  Widget ID=" .. tostring(wid) .. " type=" .. tostring(w.widgetType)
        local anyHit = false
        for _, getter in ipairs(getters) do
            if getter.fn then
                local info = safe(getter.fn, wid)
                if info then
                    anyHit = true
                    lines[#lines + 1] = "    [" .. getter.name .. "]"
                    for k, v in pairs(info) do
                        local t = type(v)
                        if t == "string" or t == "number" or t == "boolean" then
                            lines[#lines + 1] = "      " .. tostring(k) .. " = " .. tostring(v)
                        end
                    end
                    if info.tooltip then
                        lines[#lines + 1] = "      ** tooltip = " .. tostring(info.tooltip)
                    end
                end
            end
        end
        if not anyHit then
            lines[#lines + 1] = "    (no visualization info returned for any getter)"
        end
    end
end

local function buildDiagText()
    local lines = {}

    lines[#lines + 1] = "=== CouchPotatoDiag ==="
    lines[#lines + 1] = "Generated: " .. date("%Y-%m-%d %H:%M:%S")
    lines[#lines + 1] = ""

    -- ----------------------------------------------------------------
    -- Section 7: Addon version / loaded status  (placed first so it's
    --            visible without scrolling)
    -- ----------------------------------------------------------------
    lines[#lines + 1] = "=== Section 7: Addon Info ==="
    local addonList = {
        "CouchPotato",
        "CouchPotatoDiag",
        "ControllerCompanion",
        "ControllerCompanion_Loader",
        "DelveCompanionStats",
        "StatPriority",
    }
    for _, name in ipairs(addonList) do
        local loaded  = safe(C_AddOns and C_AddOns.IsAddOnLoaded, name)
        local version = safe(C_AddOns and C_AddOns.GetAddOnMetadata, name, "Version")
        lines[#lines + 1] = string.format("  %-30s loaded=%-5s version=%s",
            name, tostring(loaded), tostring(version))
    end
    -- CouchPotatoShared version if available
    if _G.CouchPotatoShared and _G.CouchPotatoShared.version then
        lines[#lines + 1] = "  CouchPotatoShared.version = " .. tostring(_G.CouchPotatoShared.version)
    end
    lines[#lines + 1] = ""

    -- ----------------------------------------------------------------
    -- Section 1: Scenario step info
    -- ----------------------------------------------------------------
    lines[#lines + 1] = "=== Section 1: Scenario Step Info ==="
    local stepInfo = safe(C_ScenarioInfo.GetScenarioStepInfo)
    if stepInfo then
        lines[#lines + 1] = "title             = " .. tostring(stepInfo.title)
        lines[#lines + 1] = "description       = " .. tostring(stepInfo.description)
        lines[#lines + 1] = "numCriteria       = " .. tostring(stepInfo.numCriteria)
        lines[#lines + 1] = "widgetSetID       = " .. tostring(stepInfo.widgetSetID)
        lines[#lines + 1] = "isBonusStep       = " .. tostring(stepInfo.isBonusStep)
        lines[#lines + 1] = "weightedProgress  = " .. tostring(stepInfo.weightedProgress)
    else
        lines[#lines + 1] = "GetScenarioStepInfo returned nil (not in a scenario?)"
    end
    lines[#lines + 1] = ""

    -- ----------------------------------------------------------------
    -- Section 2: All criteria for current step
    -- ----------------------------------------------------------------
    lines[#lines + 1] = "=== Section 2: Current Step Criteria ==="
    local numCriteria = stepInfo and stepInfo.numCriteria or 0
    if numCriteria and numCriteria > 0 then
        for i = 1, numCriteria do
            local criteria = safe(C_ScenarioInfo.GetCriteriaInfo, i)
            collectCriteria(criteria, "Criteria[" .. i .. "]", lines)
        end
    else
        lines[#lines + 1] = "numCriteria = 0 or unavailable"
    end
    lines[#lines + 1] = ""

    -- ----------------------------------------------------------------
    -- Section 3: Multi-step criteria scan
    -- ----------------------------------------------------------------
    lines[#lines + 1] = "=== Section 3: Multi-Step Criteria Scan ==="
    local scenarioInfo = safe(C_ScenarioInfo.GetScenarioInfo)
    if scenarioInfo then
        lines[#lines + 1] = "Scenario: " .. tostring(scenarioInfo.name)
        lines[#lines + 1] = "numSteps: " .. tostring(scenarioInfo.numSteps)
        local numSteps = scenarioInfo.numSteps or 0
        if numSteps > 0 then
            for stepID = 1, numSteps do
                local foundAny = false
                for ci = 1, 20 do
                    local criteria = safe(C_ScenarioInfo.GetCriteriaInfoByStep, stepID, ci)
                    if criteria then
                        foundAny = true
                        collectCriteria(criteria, "Step[" .. stepID .. "] Criteria[" .. ci .. "]", lines)
                    else
                        break
                    end
                end
                if not foundAny then
                    lines[#lines + 1] = "Step[" .. stepID .. "]: no criteria returned"
                end
            end
        else
            lines[#lines + 1] = "numSteps = 0 or unavailable"
        end
    else
        lines[#lines + 1] = "GetScenarioInfo returned nil"
    end
    lines[#lines + 1] = ""

    -- ----------------------------------------------------------------
    -- Section 4: Objective tracker widget set
    -- ----------------------------------------------------------------
    lines[#lines + 1] = "=== Section 4: Objective Tracker Widget Set ==="
    local trackerSetID = safe(C_UIWidgetManager.GetObjectiveTrackerWidgetSetID)
    collectWidgetSet(trackerSetID, "ObjectiveTracker WidgetSet", lines)
    lines[#lines + 1] = ""

    -- ----------------------------------------------------------------
    -- Section 5: Step widget set (from stepInfo.widgetSetID)
    -- ----------------------------------------------------------------
    lines[#lines + 1] = "=== Section 5: Step widgetSetID ==="
    local stepWidgetSetID = stepInfo and stepInfo.widgetSetID
    collectWidgetSet(stepWidgetSetID, "Step WidgetSet", lines)
    lines[#lines + 1] = ""

    -- ----------------------------------------------------------------
    -- Section 6: Delve status
    -- ----------------------------------------------------------------
    lines[#lines + 1] = "=== Section 6: Delve Status ==="
    local delveInProgress = safe(C_PartyInfo.IsDelveInProgress)
    local delveComplete   = safe(C_PartyInfo.IsDelveComplete)
    local hasActiveDelve  = safe(C_DelvesUI and C_DelvesUI.HasActiveDelve)
    lines[#lines + 1] = "C_PartyInfo.IsDelveInProgress() = " .. tostring(delveInProgress)
    lines[#lines + 1] = "C_PartyInfo.IsDelveComplete()   = " .. tostring(delveComplete)
    lines[#lines + 1] = "C_DelvesUI.HasActiveDelve()     = " .. tostring(hasActiveDelve)
    lines[#lines + 1] = ""

    lines[#lines + 1] = "=== Dump complete ==="

    return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------
-- Diagnostic window
-------------------------------------------------------------------------------

local DIAG_W = 600
local DIAG_H = 500

local _diagFrame = nil

local function buildDiagFrame()
    if _diagFrame then return _diagFrame end

    local f = CreateFrame("Frame", "CouchPotatoDiagFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(DIAG_W, DIAG_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    tinsert(UISpecialFrames, "CouchPotatoDiagFrame")

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", f.TitleBg, "LEFT", 5, 0)
    title:SetText("CouchPotato Diagnostic")

    f.CloseButton:SetScript("OnClick", function() f:Hide() end)

    -- Instruction line
    local instr = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    instr:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -36)
    instr:SetText("Select all (Ctrl+A) then copy (Ctrl+C)")

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -34)
    refreshBtn:SetText("Refresh")

    -- Close button (secondary, in content area — Escape also closes via UISpecialFrames)
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -6, 0)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Separator
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -60)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -60)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)

    -- ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",   16, -64)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 8)

    -- EditBox inside scroll
    local eb = CreateFrame("EditBox", nil, scrollFrame)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetWidth(DIAG_W - 60)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:SetScrollChild(eb)
    f._editBox = eb

    -- Refresh populates the editbox
    local function refresh()
        local text = buildDiagText()
        eb:SetText(text)
        -- Persist to saved variables
        if _G.CouchPotatoDB then
            _G.CouchPotatoDB.lastDiag = text
        end
    end

    refreshBtn:SetScript("OnClick", refresh)

    f:SetScript("OnShow", function()
        refresh()
        eb:SetFocus()
        eb:HighlightText()
    end)

    _diagFrame = f
    return f
end

-------------------------------------------------------------------------------
-- Slash command
-------------------------------------------------------------------------------

SLASH_CPDIAG1 = "/cpdiag"
SlashCmdList["CPDIAG"] = function()
    local f = buildDiagFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        f:Raise()
    end
end
