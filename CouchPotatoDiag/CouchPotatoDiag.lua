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

    -- ----------------------------------------------------------------
    -- Section 8: Nemesis Data Hunt
    -- Tries every plausible API approach to locate "Enemy groups remaining: n/n"
    -- which is visible in the Blizzard Nemesis Strongbox tooltip but is NOT
    -- present in scenario criteria (criteriaType=92 = quest objectives only).
    -- ----------------------------------------------------------------
    lines[#lines + 1] = "=== Section 8: Nemesis Data Hunt ==="

    -- 8a: Spell description for Nemesis Strongbox (spell 472952)
    lines[#lines + 1] = "--- 8a: C_Spell.GetSpellDescription(472952) ---"
    local spellDesc = safe(C_Spell and C_Spell.GetSpellDescription, 472952)
    lines[#lines + 1] = "  result = " .. tostring(spellDesc)

    -- 8b: Tooltip scan via C_TooltipInfo.GetHyperlink
    lines[#lines + 1] = "--- 8b: C_TooltipInfo.GetHyperlink('spell:472952') ---"
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local tipData = safe(C_TooltipInfo.GetHyperlink, "spell:472952")
        if tipData then
            lines[#lines + 1] = "  type(result) = " .. type(tipData)
            if type(tipData) == "table" then
                for k, v in pairs(tipData) do
                    local t = type(v)
                    if t == "string" or t == "number" or t == "boolean" then
                        lines[#lines + 1] = "  " .. tostring(k) .. " = " .. tostring(v)
                    end
                end
                -- Scan lines sub-table if present
                if tipData.lines then
                    lines[#lines + 1] = "  lines count = " .. tostring(#tipData.lines)
                    for i, ln in ipairs(tipData.lines) do
                        if type(ln) == "table" then
                            local leftText  = tostring(ln.leftText  or "")
                            local rightText = tostring(ln.rightText or "")
                            lines[#lines + 1] = ("  line[%d]: left=%q right=%q"):format(i, leftText, rightText)
                        end
                    end
                end
            end
        else
            lines[#lines + 1] = "  result = nil"
        end
    else
        lines[#lines + 1] = "  C_TooltipInfo.GetHyperlink not available"
    end

    -- 8c: Player buff scan for spell 472952 (Nemesis Strongbox aura)
    lines[#lines + 1] = "--- 8c: Player buff scan for spellID 472952 ---"
    local foundBuff = false
    if C_UnitAuras then
        for i = 1, 40 do
            local aura = safe(C_UnitAuras.GetBuffDataByIndex, "player", i)
            if not aura then break end
            if aura.spellId == 472952 then
                lines[#lines + 1] = ("  FOUND buff index=%d name=%q spellId=%d"):format(
                    i, tostring(aura.name), tostring(aura.spellId))
                foundBuff = true
            end
        end
        if not foundBuff then
            lines[#lines + 1] = "  Not found in player buffs (checked up to 40)"
        end
    else
        lines[#lines + 1] = "  C_UnitAuras not available"
    end

    -- 8d: C_TaskQuest scan for quest objectives
    lines[#lines + 1] = "--- 8d: C_TaskQuest.GetQuestsForPlayerByMapID (current zone) ---"
    if C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
        local mapID = safe(C_Map and C_Map.GetBestMapForUnit, "player")
        lines[#lines + 1] = "  player mapID = " .. tostring(mapID)
        if mapID then
            local taskQuests = safe(C_TaskQuest.GetQuestsForPlayerByMapID, mapID)
            if taskQuests then
                lines[#lines + 1] = "  task quests count = " .. tostring(#taskQuests)
                for _, qid in ipairs(taskQuests) do
                    local title = safe(C_QuestLog and C_QuestLog.GetTitleForQuestID, qid)
                    lines[#lines + 1] = ("  questID=%d title=%s"):format(qid, tostring(title))
                end
            else
                lines[#lines + 1] = "  result = nil"
            end
        end
    else
        lines[#lines + 1] = "  C_TaskQuest.GetQuestsForPlayerByMapID not available"
    end

    -- 8e: GetQuestObjectiveInfo for common Nemesis Strongbox quest IDs (guesses)
    lines[#lines + 1] = "--- 8e: GetQuestObjectiveInfo probe (common delve quest IDs) ---"
    local probeQuestIDs = { 78631, 78632, 78633, 78634, 78635, 78636, 78637 }
    if GetQuestObjectiveInfo then
        for _, qid in ipairs(probeQuestIDs) do
            for oi = 1, 5 do
                local text, objType, finished, numFulfilled, numRequired =
                    safe(GetQuestObjectiveInfo, qid, oi, false)
                if text then
                    lines[#lines + 1] = ("  quest=%d obj=%d text=%q type=%s %s/%s finished=%s"):format(
                        qid, oi,
                        tostring(text), tostring(objType),
                        tostring(numFulfilled), tostring(numRequired),
                        tostring(finished))
                end
            end
        end
    else
        lines[#lines + 1] = "  GetQuestObjectiveInfo not available"
    end

    -- 8b-extended: Try more tooltip approaches for spell 472952
    lines[#lines + 1] = "--- 8b-extended: C_TooltipInfo.GetSpellByID(472952) ---"
    if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        local tipData = safe(C_TooltipInfo.GetSpellByID, 472952)
        if tipData then
            lines[#lines + 1] = "  type(result) = " .. type(tipData)
            if tipData.lines then
                lines[#lines + 1] = "  lines count = " .. tostring(#tipData.lines)
                for i, ln in ipairs(tipData.lines) do
                    if type(ln) == "table" then
                        local leftText  = tostring(ln.leftText  or "")
                        local rightText = tostring(ln.rightText or "")
                        lines[#lines + 1] = ("  line[%d]: left=%q right=%q"):format(i, leftText, rightText)
                    end
                end
            end
        else
            lines[#lines + 1] = "  result = nil"
        end
    else
        lines[#lines + 1] = "  C_TooltipInfo.GetSpellByID not available"
    end

    lines[#lines + 1] = "--- 8b-extended: C_TooltipInfo.GetUnitByToken('mouseover') ---"
    if C_TooltipInfo and C_TooltipInfo.GetUnitByToken then
        local tipData = safe(C_TooltipInfo.GetUnitByToken, "mouseover")
        if tipData then
            lines[#lines + 1] = "  type(result) = " .. type(tipData)
            if tipData.lines then
                lines[#lines + 1] = "  lines count = " .. tostring(#tipData.lines)
                for i, ln in ipairs(tipData.lines) do
                    if type(ln) == "table" then
                        local leftText  = tostring(ln.leftText  or "")
                        local rightText = tostring(ln.rightText or "")
                        lines[#lines + 1] = ("  line[%d]: left=%q right=%q"):format(i, leftText, rightText)
                    end
                end
            end
        else
            lines[#lines + 1] = "  result = nil (no mouseover target)"
        end
    else
        lines[#lines + 1] = "  C_TooltipInfo.GetUnitByToken not available"
    end

    lines[#lines + 1] = "--- 8b-extended: C_TooltipInfo.GetItemByID for strongbox IDs 503870, 503871 ---"
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        for _, itemID in ipairs({ 503870, 503871 }) do
            local tipData = safe(C_TooltipInfo.GetItemByID, itemID)
            if tipData then
                lines[#lines + 1] = ("  itemID=%d: lines count=%s"):format(itemID, tostring(tipData.lines and #tipData.lines or 0))
                if tipData.lines then
                    for i, ln in ipairs(tipData.lines) do
                        if type(ln) == "table" then
                            local leftText  = tostring(ln.leftText  or "")
                            local rightText = tostring(ln.rightText or "")
                            lines[#lines + 1] = ("    line[%d]: left=%q right=%q"):format(i, leftText, rightText)
                        end
                    end
                end
            else
                lines[#lines + 1] = ("  itemID=%d: result = nil"):format(itemID)
            end
        end
    else
        lines[#lines + 1] = "  C_TooltipInfo.GetItemByID not available"
    end

    -- 8f: Scan widget sets 1-1000 for any that return data (nemesis may be a hidden set)
    -- NOTE: delve widget is known to be at set 842 — scan higher to catch it.
    lines[#lines + 1] = "--- 8f: Widget set scan (IDs 1-1000, report non-empty sets) ---"
    local widgetSetsFound = 0
    for setID = 1, 1000 do
        local widgets = safe(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
        if widgets and #widgets > 0 then
            widgetSetsFound = widgetSetsFound + 1
            lines[#lines + 1] = ("  setID=%d has %d widgets"):format(setID, #widgets)
            for _, w in ipairs(widgets) do
                -- Try the delves widget getter — it's the one that showed "Enemy groups" in Blizzard UI
                local info = safe(C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo, w.widgetID)
                if info then
                    lines[#lines + 1] = ("    widget %d [DelvesViz]: tooltip=%q"):format(
                        w.widgetID, tostring(info.tooltip or ""))
                    for k, v in pairs(info) do
                        local t = type(v)
                        if t == "string" and v ~= "" then
                            lines[#lines + 1] = ("      %s = %q"):format(k, v)
                        elseif t == "number" or t == "boolean" then
                            lines[#lines + 1] = ("      %s = %s"):format(k, tostring(v))
                        end
                    end
                end
            end
        end
    end
    if widgetSetsFound == 0 then
        lines[#lines + 1] = "  No non-empty widget sets found in range 1-1000"
    end

    -- 8g: Dump FULL delve widget data including arrays (currencies, spells, rewardInfo)
    lines[#lines + 1] = "--- 8g: Full delve widget dump (currencies/spells/rewardInfo) ---"
    local stepWidgetSetIDFor8g = stepInfo and stepInfo.widgetSetID
    if stepWidgetSetIDFor8g and stepWidgetSetIDFor8g ~= 0 then
        local widgets8g = safe(C_UIWidgetManager.GetAllWidgetsBySetID, stepWidgetSetIDFor8g)
        if widgets8g then
            for _, w in ipairs(widgets8g) do
                local delvesInfo = safe(C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo, w.widgetID)
                if delvesInfo then
                    lines[#lines + 1] = ("  widgetID=%d [ScenarioHeaderDelves] full dump:"):format(w.widgetID)
                    -- Scalar fields
                    for k, v in pairs(delvesInfo) do
                        local t = type(v)
                        if t == "string" or t == "number" or t == "boolean" then
                            lines[#lines + 1] = ("    %s = %s"):format(tostring(k), tostring(v))
                        end
                    end
                    -- currencies array
                    if delvesInfo.currencies then
                        lines[#lines + 1] = ("    currencies count=%d"):format(#delvesInfo.currencies)
                        for i, c in ipairs(delvesInfo.currencies) do
                            lines[#lines + 1] = ("    currencies[%d]:"):format(i)
                            for k, v in pairs(c) do
                                lines[#lines + 1] = ("      %s = %s"):format(tostring(k), tostring(v))
                            end
                        end
                    else
                        lines[#lines + 1] = "    currencies = nil"
                    end
                    -- spells array
                    if delvesInfo.spells then
                        lines[#lines + 1] = ("    spells count=%d"):format(#delvesInfo.spells)
                        for i, s in ipairs(delvesInfo.spells) do
                            lines[#lines + 1] = ("    spells[%d]:"):format(i)
                            for k, v in pairs(s) do
                                lines[#lines + 1] = ("      %s = %s"):format(tostring(k), tostring(v))
                            end
                            -- Also try spell description and tooltip
                            if s.spellID then
                                local desc = safe(C_Spell and C_Spell.GetSpellDescription, s.spellID)
                                lines[#lines + 1] = ("      C_Spell.GetSpellDescription(%d) = %s"):format(
                                    s.spellID, tostring(desc))
                                if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
                                    local st = safe(C_TooltipInfo.GetSpellByID, s.spellID)
                                    if st and st.lines then
                                        lines[#lines + 1] = ("      GetSpellByID tooltip lines=%d"):format(#st.lines)
                                        for li, ln in ipairs(st.lines) do
                                            if type(ln) == "table" then
                                                lines[#lines + 1] = ("        line[%d]: left=%q right=%q"):format(
                                                    li,
                                                    tostring(ln.leftText  or ""),
                                                    tostring(ln.rightText or ""))
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    else
                        lines[#lines + 1] = "    spells = nil"
                    end
                    -- rewardInfo
                    if delvesInfo.rewardInfo then
                        lines[#lines + 1] = "    rewardInfo:"
                        for k, v in pairs(delvesInfo.rewardInfo) do
                            lines[#lines + 1] = ("      %s = %s"):format(tostring(k), tostring(v))
                        end
                    else
                        lines[#lines + 1] = "    rewardInfo = nil"
                    end
                end
            end
        else
            lines[#lines + 1] = "  GetAllWidgetsBySetID returned nil for stepWidgetSetID"
        end
    else
        lines[#lines + 1] = "  No stepWidgetSetID available for 8g"
    end

    -- 8h: Scan ALL widget types for set 842 (known delve step widget set)
    lines[#lines + 1] = "--- 8h: All visualization getters for widget set 842 ---"
    local allGetters = {
        { name = "GetScenarioHeaderDelvesWidgetVisualizationInfo", fn = C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo },
        { name = "GetIconAndTextWidgetVisualizationInfo",           fn = C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo },
        { name = "GetTextWithStateWidgetVisualizationInfo",         fn = C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo },
        { name = "GetStatusBarWidgetVisualizationInfo",             fn = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo },
        { name = "GetTextWithSubtextWidgetVisualizationInfo",       fn = C_UIWidgetManager.GetTextWithSubtextWidgetVisualizationInfo },
        { name = "GetBulletTextListWidgetVisualizationInfo",        fn = C_UIWidgetManager.GetBulletTextListWidgetVisualizationInfo },
        { name = "GetTextureAndTextRowVisualizationInfo",           fn = C_UIWidgetManager.GetTextureAndTextRowVisualizationInfo },
        { name = "GetCaptureBarWidgetVisualizationInfo",            fn = C_UIWidgetManager.GetCaptureBarWidgetVisualizationInfo },
        { name = "GetDoubleStatusBarWidgetVisualizationInfo",       fn = C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo },
        { name = "GetFillUpFramesWidgetVisualizationInfo",          fn = C_UIWidgetManager.GetFillUpFramesWidgetVisualizationInfo },
        { name = "GetItemDisplayVisualizationInfo",                 fn = C_UIWidgetManager.GetItemDisplayVisualizationInfo },
    }
    local widgets842 = safe(C_UIWidgetManager.GetAllWidgetsBySetID, 842)
    if widgets842 and #widgets842 > 0 then
        lines[#lines + 1] = ("  set 842 has %d widgets"):format(#widgets842)
        for _, w in ipairs(widgets842) do
            lines[#lines + 1] = ("  Widget ID=%d type=%s"):format(w.widgetID, tostring(w.widgetType))
            local anyHit = false
            for _, getter in ipairs(allGetters) do
                if getter.fn then
                    local info = safe(getter.fn, w.widgetID)
                    if info then
                        anyHit = true
                        lines[#lines + 1] = ("    [%s]"):format(getter.name)
                        for k, v in pairs(info) do
                            local t = type(v)
                            if t == "string" or t == "number" or t == "boolean" then
                                lines[#lines + 1] = ("      %s = %s"):format(tostring(k), tostring(v))
                            elseif t == "table" then
                                lines[#lines + 1] = ("      %s = <table len=%d>"):format(tostring(k), #v)
                            end
                        end
                    end
                end
            end
            if not anyHit then
                lines[#lines + 1] = "    (no getter returned data)"
            end
        end
    else
        lines[#lines + 1] = "  set 842 is empty or unavailable"
    end

    -- 8i: Try C_Scenario (different from C_ScenarioInfo)
    lines[#lines + 1] = "--- 8i: C_Scenario API ---"
    if C_Scenario then
        local csInfo = safe(C_Scenario.GetInfo)
        if csInfo then
            lines[#lines + 1] = "  C_Scenario.GetInfo():"
            for k, v in pairs(csInfo) do
                local t = type(v)
                if t == "string" or t == "number" or t == "boolean" then
                    lines[#lines + 1] = ("    %s = %s"):format(tostring(k), tostring(v))
                end
            end
        else
            lines[#lines + 1] = "  C_Scenario.GetInfo() = nil"
        end

        local csStepInfo = safe(C_Scenario.GetStepInfo)
        if csStepInfo then
            lines[#lines + 1] = "  C_Scenario.GetStepInfo():"
            for k, v in pairs(csStepInfo) do
                local t = type(v)
                if t == "string" or t == "number" or t == "boolean" then
                    lines[#lines + 1] = ("    %s = %s"):format(tostring(k), tostring(v))
                end
            end
        else
            lines[#lines + 1] = "  C_Scenario.GetStepInfo() = nil"
        end

        local bonusSteps = safe(C_Scenario.GetBonusSteps)
        lines[#lines + 1] = "  C_Scenario.GetBonusSteps() = " .. tostring(bonusSteps)
        if type(bonusSteps) == "table" then
            for i, v in ipairs(bonusSteps) do
                lines[#lines + 1] = ("    [%d] = %s"):format(i, tostring(v))
            end
        end

        local superseded = safe(C_Scenario.GetSupersededObjectives)
        lines[#lines + 1] = "  C_Scenario.GetSupersededObjectives() = " .. tostring(superseded)
        if type(superseded) == "table" then
            for i, v in ipairs(superseded) do
                lines[#lines + 1] = ("    [%d] = %s"):format(i, tostring(v))
            end
        end

        local shouldShow = safe(C_Scenario.ShouldShowCriteria)
        lines[#lines + 1] = "  C_Scenario.ShouldShowCriteria() = " .. tostring(shouldShow)
    else
        lines[#lines + 1] = "  C_Scenario not available"
    end

    -- 8j: Scan world quest / bonus objective APIs
    lines[#lines + 1] = "--- 8j: World quest / bonus objective APIs ---"
    local numWatches = safe(GetNumQuestWatches)
    lines[#lines + 1] = "  GetNumQuestWatches() = " .. tostring(numWatches)
    if numWatches and numWatches > 0 then
        for i = 1, numWatches do
            local watchInfo = safe(GetQuestWatchInfo, i)
            if watchInfo then
                lines[#lines + 1] = ("  GetQuestWatchInfo(%d):"):format(i)
                for k, v in pairs(watchInfo) do
                    local t = type(v)
                    if t == "string" or t == "number" or t == "boolean" then
                        lines[#lines + 1] = ("    %s = %s"):format(tostring(k), tostring(v))
                    end
                end
            else
                lines[#lines + 1] = ("  GetQuestWatchInfo(%d) = nil"):format(i)
            end
        end
    end

    local numWQWatches = safe(GetNumWorldQuestWatches)
    lines[#lines + 1] = "  GetNumWorldQuestWatches() = " .. tostring(numWQWatches)

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local numEntries = safe(C_QuestLog.GetNumQuestLogEntries)
        lines[#lines + 1] = "  C_QuestLog.GetNumQuestLogEntries() = " .. tostring(numEntries)
        if numEntries and numEntries > 0 then
            for i = 1, numEntries do
                local info = safe(C_QuestLog.GetInfo, i)
                if info and info.questID then
                    local title = tostring(info.title or "")
                    local lower = title:lower()
                    if lower:find("nemesis") or lower:find("strongbox") or lower:find("enemy") or lower:find("delve") then
                        lines[#lines + 1] = ("  ** Quest[%d] questID=%d title=%q"):format(i, info.questID, title)
                    end
                end
            end
        end
    else
        lines[#lines + 1] = "  C_QuestLog.GetNumQuestLogEntries not available"
    end

    -- 8k: Vignette API (nemesis packs might be vignettes)
    lines[#lines + 1] = "--- 8k: C_VignetteInfo API ---"
    if C_VignetteInfo and C_VignetteInfo.GetVignettes then
        local vignettes = safe(C_VignetteInfo.GetVignettes)
        if vignettes then
            lines[#lines + 1] = "  vignette count = " .. tostring(#vignettes)
            for _, vignetteGUID in ipairs(vignettes) do
                local vInfo = safe(C_VignetteInfo.GetVignetteInfo, vignetteGUID)
                if vInfo then
                    lines[#lines + 1] = ("  vignette GUID=%s"):format(tostring(vignetteGUID))
                    lines[#lines + 1] = ("    name=%s"):format(tostring(vInfo.name))
                    lines[#lines + 1] = ("    objectGUID=%s"):format(tostring(vInfo.objectGUID))
                    lines[#lines + 1] = ("    vignetteID=%s"):format(tostring(vInfo.vignetteID))
                    lines[#lines + 1] = ("    type=%s"):format(tostring(vInfo.type))
                    -- Dump remaining fields
                    for k, v in pairs(vInfo) do
                        if k ~= "name" and k ~= "objectGUID" and k ~= "vignetteID" and k ~= "type" then
                            local t = type(v)
                            if t == "string" or t == "number" or t == "boolean" then
                                lines[#lines + 1] = ("    %s = %s"):format(tostring(k), tostring(v))
                            end
                        end
                    end
                end
            end
        else
            lines[#lines + 1] = "  GetVignettes() = nil"
        end
    else
        lines[#lines + 1] = "  C_VignetteInfo not available"
    end

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
