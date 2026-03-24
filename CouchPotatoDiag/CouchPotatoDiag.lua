-- CouchPotatoDiag.lua
-- Diagnostic addon: dumps scenario criteria and widget data for debugging nemesis enemy groups.
-- Usage: /cpdiag

local PREFIX = "|cff00ff00[CPDiag]|r "

local function p(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function dumpCriteria(criteria, label)
    if not criteria then
        p(label .. " = nil")
        return
    end
    p(label .. ":")
    p("  description       = " .. tostring(criteria.description))
    p("  criteriaType      = " .. tostring(criteria.criteriaType))
    p("  completed         = " .. tostring(criteria.completed))
    p("  quantity          = " .. tostring(criteria.quantity))
    p("  totalQuantity     = " .. tostring(criteria.totalQuantity))
    p("  flags             = " .. tostring(criteria.flags))
    p("  assetID           = " .. tostring(criteria.assetID))
    p("  criteriaID        = " .. tostring(criteria.criteriaID))
    p("  duration          = " .. tostring(criteria.duration))
    p("  elapsed           = " .. tostring(criteria.elapsed))
    p("  failed            = " .. tostring(criteria.failed))
    p("  isWeightedProgress= " .. tostring(criteria.isWeightedProgress))
    p("  isFormatted       = " .. tostring(criteria.isFormatted))
    p("  quantityString    = " .. tostring(criteria.quantityString))
end

local function dumpWidgetSet(setID, label)
    if not setID or setID == 0 then
        p(label .. ": no widgetSetID")
        return
    end
    p(label .. " (setID=" .. tostring(setID) .. "):")
    local widgets = safe(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
    if not widgets then
        p("  GetAllWidgetsBySetID returned nil")
        return
    end
    if #widgets == 0 then
        p("  (no widgets in set)")
        return
    end
    for _, w in ipairs(widgets) do
        local wid = w.widgetID
        p("  Widget ID=" .. tostring(wid) .. " type=" .. tostring(w.widgetType))

        -- Try every known visualization getter
        local getters = {
            { name = "GetScenarioHeaderDelvesWidgetVisualizationInfo", fn = C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo },
            { name = "GetIconAndTextWidgetVisualizationInfo",           fn = C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo },
            { name = "GetTextWithStateWidgetVisualizationInfo",         fn = C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo },
            { name = "GetStatusBarWidgetVisualizationInfo",             fn = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo },
            { name = "GetTextWithSubtextWidgetVisualizationInfo",       fn = C_UIWidgetManager.GetTextWithSubtextWidgetVisualizationInfo },
        }
        local anyHit = false
        for _, getter in ipairs(getters) do
            if getter.fn then
                local info = safe(getter.fn, wid)
                if info then
                    anyHit = true
                    p("    [" .. getter.name .. "]")
                    -- Dump all string/number/boolean fields generically
                    for k, v in pairs(info) do
                        local t = type(v)
                        if t == "string" or t == "number" or t == "boolean" then
                            p("      " .. tostring(k) .. " = " .. tostring(v))
                        end
                    end
                    -- Highlight tooltip specifically since it may carry enemy group info
                    if info.tooltip then
                        p("      ** tooltip = " .. tostring(info.tooltip))
                    end
                end
            end
        end
        if not anyHit then
            p("    (no visualization info returned for any getter)")
        end
    end
end

local function runDiag()
    p("========================================")
    p("CouchPotatoDiag — scenario/widget dump")
    p("========================================")

    -- ----------------------------------------------------------------
    -- Section 1: Scenario step info
    -- ----------------------------------------------------------------
    p("--- Section 1: Scenario Step Info ---")
    local stepInfo = safe(C_ScenarioInfo.GetScenarioStepInfo)
    if stepInfo then
        p("title             = " .. tostring(stepInfo.title))
        p("description       = " .. tostring(stepInfo.description))
        p("numCriteria       = " .. tostring(stepInfo.numCriteria))
        p("widgetSetID       = " .. tostring(stepInfo.widgetSetID))
        p("isBonusStep       = " .. tostring(stepInfo.isBonusStep))
        p("weightedProgress  = " .. tostring(stepInfo.weightedProgress))
    else
        p("GetScenarioStepInfo returned nil (not in a scenario?)")
    end

    -- ----------------------------------------------------------------
    -- Section 2: All criteria for current step
    -- ----------------------------------------------------------------
    p("--- Section 2: Current Step Criteria ---")
    local numCriteria = stepInfo and stepInfo.numCriteria or 0
    if numCriteria and numCriteria > 0 then
        for i = 1, numCriteria do
            local criteria = safe(C_ScenarioInfo.GetCriteriaInfo, i)
            dumpCriteria(criteria, "Criteria[" .. i .. "]")
        end
    else
        p("numCriteria = 0 or unavailable")
    end

    -- ----------------------------------------------------------------
    -- Section 3: Multi-step criteria scan
    -- ----------------------------------------------------------------
    p("--- Section 3: Multi-Step Criteria Scan ---")
    local scenarioInfo = safe(C_ScenarioInfo.GetScenarioInfo)
    if scenarioInfo then
        p("Scenario: " .. tostring(scenarioInfo.name))
        p("numSteps: " .. tostring(scenarioInfo.numSteps))
        local numSteps = scenarioInfo.numSteps or 0
        if numSteps > 0 then
            for stepID = 1, numSteps do
                -- GetCriteriaInfoByStep takes (stepID, criteriaIndex)
                -- We probe up to 20 criteria per step
                local foundAny = false
                for ci = 1, 20 do
                    local criteria = safe(C_ScenarioInfo.GetCriteriaInfoByStep, stepID, ci)
                    if criteria then
                        foundAny = true
                        dumpCriteria(criteria, "Step[" .. stepID .. "] Criteria[" .. ci .. "]")
                    else
                        break
                    end
                end
                if not foundAny then
                    p("Step[" .. stepID .. "]: no criteria returned")
                end
            end
        else
            p("numSteps = 0 or unavailable")
        end
    else
        p("GetScenarioInfo returned nil")
    end

    -- ----------------------------------------------------------------
    -- Section 4: Objective tracker widget set
    -- ----------------------------------------------------------------
    p("--- Section 4: Objective Tracker Widget Set ---")
    local trackerSetID = safe(C_UIWidgetManager.GetObjectiveTrackerWidgetSetID)
    dumpWidgetSet(trackerSetID, "ObjectiveTracker WidgetSet")

    -- ----------------------------------------------------------------
    -- Section 5: Step widget set (from stepInfo.widgetSetID)
    -- ----------------------------------------------------------------
    p("--- Section 5: Step widgetSetID ---")
    local stepWidgetSetID = stepInfo and stepInfo.widgetSetID
    dumpWidgetSet(stepWidgetSetID, "Step WidgetSet")

    -- ----------------------------------------------------------------
    -- Section 6: Delve status
    -- ----------------------------------------------------------------
    p("--- Section 6: Delve Status ---")
    local delveInProgress = safe(C_PartyInfo.IsDelveInProgress)
    local delveComplete   = safe(C_PartyInfo.IsDelveComplete)
    local hasActiveDelve  = safe(C_DelvesUI and C_DelvesUI.HasActiveDelve)
    p("C_PartyInfo.IsDelveInProgress() = " .. tostring(delveInProgress))
    p("C_PartyInfo.IsDelveComplete()   = " .. tostring(delveComplete))
    p("C_DelvesUI.HasActiveDelve()     = " .. tostring(hasActiveDelve))

    p("========================================")
    p("Dump complete.")
    p("========================================")
end

-- Register slash command
SLASH_CPDIAG1 = "/cpdiag"
SlashCmdList["CPDIAG"] = function()
    runDiag()
end
