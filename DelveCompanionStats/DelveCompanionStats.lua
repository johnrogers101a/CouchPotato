-- DelveCompanionStats.lua
-- Tracks delve companion levels and displays them above the chat window.
--
-- DESIGN NOTE: All initialization (SavedVars, frame creation, UI setup,
-- position restore) happens atomically inside the ADDON_LOADED handler.
-- We intentionally do NOT register PLAYER_LOGIN — doing so created a race
-- condition where OnEnable() could run before OnLoad() completed (or before
-- the frame existed), causing "attempt to index field 'nameLabel' (a nil value)".
-- By collapsing everything into ADDON_LOADED, initialization is guaranteed
-- to be complete before any other events fire.

local addonName, ns = ...
-- Fallback for test environments (dofile() does not populate varargs)
if not ns then
    addonName = "DelveCompanionStats"
    ns = {}
end
_G.DelveCompanionStatsNS = ns

ns.version = "1.0.0"

-- Throttle timestamps for high-frequency events (seconds)
local lastAuraUpdate    = 0
local lastFactionUpdate = 0
local THROTTLE_INTERVAL = 2  -- minimum seconds between processing
-- Pending deferred-retry timer handle for UNIT_AURA throttle.
-- When a UNIT_AURA fires during the cooldown window we schedule one retry so
-- boons collected mid-window are never silently dropped.
local pendingAuraTimer  = false

-------------------------------------------------------------------------------
-- dcsprint: Write a coloured message to the chat frame (or print fallback).
-- Delegates to CouchPotatoLog when available; bare fallback otherwise.
-------------------------------------------------------------------------------
local function dcsprint(msg)
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Print("DCS", msg)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffDCS:|r " .. tostring(msg))
    else
        print("|cff00ccffDCS:|r " .. tostring(msg))
    end
end

-- dcslog: structured log via CouchPotatoLog (level = "Debug"/"Info"/"Warn"/"Error")
local function dcslog(level, msg)
    if _G.CouchPotatoLog and _G.CouchPotatoLog[level] then
        _G.CouchPotatoLog[level](_G.CouchPotatoLog, "DCS", msg)
    end
end



-------------------------------------------------------------------------------
-- Slash commands: /dcs  or  /delvecompanion
-------------------------------------------------------------------------------
SLASH_DCS1 = "/dcs"
SLASH_DCS2 = "/delvecompanion"
SlashCmdList["DCS"] = function(msg)
    local cmd = msg and msg:lower():match("^%s*(%S+)") or ""
    if cmd == "debug" then
        ns:PrintDebugInfo()
    elseif cmd == "show" then
        ns.frame:Show()
        dcsprint("Frame shown manually")
    elseif cmd == "hide" then
        ns.frame:Hide()
        dcsprint("Frame hidden manually")
    elseif cmd == "toggle" then
        if ns.frame:IsShown() then
            ns.frame:Hide()
            dcsprint("Frame hidden (toggle)")
        else
            ns.frame:Show()
            dcsprint("Frame shown (toggle)")
            ns:UpdateCompanionData("MANUAL")
        end
    elseif cmd == "reset" then
        DelveCompanionStatsDB.position = nil
        if ns.frame then
            ns.frame:ClearAllPoints()
            if ChatFrame1 then
                ns.frame:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 10)
            else
                ns.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 5, 130)
            end
        end
        dcsprint("Frame position reset to default")
    else
        dcsprint("Usage: /dcs [debug|show|hide|toggle|reset]")
    end
end

-------------------------------------------------------------------------------
-- CreateDebugPopup: Build the scrollable debug info popup (singleton).
-------------------------------------------------------------------------------
function ns:CreateDebugPopup()
    if ns.debugPopup then return ns.debugPopup end

    local ok, popup = pcall(function()
        return CreateFrame("Frame", "DelveCompanionStatsDebugPopup", UIParent, "BackdropTemplate")
    end)
    if not ok or not popup then
        -- Fallback: plain Frame without BackdropTemplate
        popup = CreateFrame("Frame", "DelveCompanionStatsDebugPopup", UIParent)
    end

    popup:SetSize(600, 400)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(100)

    -- Dark semi-transparent backdrop (same style as the main display frame)
    popup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    popup:SetBackdropColor(0, 0, 0, 0.85)

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -8)
    title:SetText("DCS Debug Info")

    -- ScrollFrame (inner area: inset 8,-28 from topleft, -28,30 from bottomright)
    local scrollFrame = CreateFrame("ScrollFrame", nil, popup)
    scrollFrame:SetPoint("TOPLEFT",     popup, "TOPLEFT",     8,  -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -28,  30)

    -- EditBox as scroll child
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    local fontOk = pcall(function() editBox:SetFontObject("GameFontHighlight") end)
    if not fontOk then
        editBox:SetFont(STANDARD_TEXT_FONT, 12, "")
    end
    editBox:SetSize(scrollFrame:GetWidth(), 2000)
    scrollFrame:SetScrollChild(editBox)

    -- Store editBox reference for external access and testing
    popup._editBox = editBox

    -- Close button
    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -8, 8)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Dismiss on ESC
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then self:Hide() end
    end)

    popup:Hide()
    ns.debugPopup = popup
    return popup
end

-------------------------------------------------------------------------------
-- IsInDelve: Returns true when the player is inside a delve instance.
-- Uses IsInInstance() returning "scenario" as the primary signal (reliable
-- across all phases of a delve run in TWW), with HasActiveDelve() and
-- C_PartyInfo.IsDelveInProgress() as secondary/tertiary fallbacks.
-------------------------------------------------------------------------------
local function IsInDelve()
    local _, instanceType = IsInInstance()
    -- Delves are "scenario" instances in TWW
    if instanceType == "scenario" then return true end
    -- Also check HasActiveDelve as secondary signal (pcall guards against API errors)
    local ok, hasDelve = pcall(function()
        return C_DelvesUI.HasActiveDelve and C_DelvesUI.HasActiveDelve()
    end)
    if ok and hasDelve then return true end
    -- Tertiary fallback: C_PartyInfo.IsDelveInProgress() (confirmed reliable in cpdiag data)
    local ok2, inProgress = pcall(function()
        return C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
    end)
    if ok2 and inProgress then return true end
    return false
end

-- Forward declarations so PrintDebugInfo (below) can call these local functions
-- which are defined later in the file.
local GetBoonsDisplayText
local GetNemesisProgress
local GetBoonAbbrev

-------------------------------------------------------------------------------
-- PrintDebugInfo: Dump C_DelvesUI API state and last-known addon values.
-- Output goes into a scrollable popup instead of spamming the chat frame.
-------------------------------------------------------------------------------
function ns:PrintDebugInfo()
    local popup = ns:CreateDebugPopup()
    local lines = {}

    -- Helper: dump a FontString label's debug properties into the lines table
    local function dumpLabel(label, labelName, linesTable)
        if not label then
            table.insert(linesTable, labelName .. " => nil (label not created)")
            return
        end
        local okText, txt = pcall(function() return label:GetText() end)
        table.insert(linesTable, ("%s:GetText() => %q"):format(labelName, okText and tostring(txt) or "<API error>"))

        local okShown, shown = pcall(function() return label:IsShown() end)
        table.insert(linesTable, ("%s:IsShown() => %s"):format(labelName, okShown and tostring(shown) or "<API error>"))

        pcall(function()
            local font, size, flags = label:GetFont()
            table.insert(linesTable, ('%s:GetFont() => font=%q, size=%s, flags=%q'):format(
                labelName, tostring(font), tostring(size), tostring(flags)))
        end)

        pcall(function()
            local r, g, b, a = label:GetTextColor()
            table.insert(linesTable, ("%s:GetTextColor() => r=%s, g=%s, b=%s, a=%s"):format(
                labelName, tostring(r), tostring(g), tostring(b), tostring(a)))
        end)

        pcall(function()
            local pt, rel, relPt, x, y = label:GetPoint(1)
            local relName = rel and (rel.GetName and rel:GetName() or tostring(rel)) or "nil"
            table.insert(linesTable, ('%s:GetPoint(1) => point=%q, relativeTo=%s, relativePoint=%q, x=%s, y=%s'):format(
                labelName, tostring(pt), relName, tostring(relPt), tostring(x), tostring(y)))
        end)

        local okW, w = pcall(function() return label:GetWidth() end)
        table.insert(linesTable, ("%s:GetWidth() => %s"):format(labelName, okW and tostring(w) or "<API error>"))
    end

    -- =========================================================================
    table.insert(lines, "=== INSTANCE STATE ===")
    -- =========================================================================
    local inInstance, instanceType
    local inInstOk, inInstErr = pcall(function()
        inInstance, instanceType = IsInInstance()
    end)
    if not inInstOk then
        table.insert(lines, "IsInInstance() => <API error: " .. tostring(inInstErr) .. ">")
    else
        table.insert(lines, ("IsInInstance() => inInstance=%s, instanceType=%q"):format(
            tostring(inInstance), tostring(instanceType)))
        if instanceType == "scenario" then
            table.insert(lines, "  -> instanceType == \"scenario\"? YES => IsInDelve will return TRUE")
        else
            table.insert(lines, "  -> instanceType == \"scenario\"? NO => checking HasActiveDelve() as fallback...")
            local hadOk, hadVal = pcall(function() return C_DelvesUI.HasActiveDelve() end)
            if hadOk then
                table.insert(lines, ("  C_DelvesUI.HasActiveDelve() => %s"):format(tostring(hadVal)))
                if hadVal then
                    table.insert(lines, "  -> IsInDelve will return TRUE (HasActiveDelve)")
                else
                    table.insert(lines, "  -> HasActiveDelve() false; checking C_PartyInfo.IsDelveInProgress()...")
                    local pipOk, pipVal = pcall(function()
                        return C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
                    end)
                    if pipOk then
                        table.insert(lines, ("  C_PartyInfo.IsDelveInProgress() => %s"):format(tostring(pipVal)))
                        table.insert(lines, ("  -> IsInDelve will return %s"):format(tostring(pipVal == true)))
                    else
                        table.insert(lines, "  C_PartyInfo.IsDelveInProgress() => <API error or unavailable>")
                    end
                end
            else
                table.insert(lines, "  C_DelvesUI.HasActiveDelve() => <API error: " .. tostring(hadVal) .. ">")
            end
        end
    end

    -- =========================================================================
    table.insert(lines, "")
    table.insert(lines, "=== FRAME VISIBILITY DECISION ===")
    -- =========================================================================
    local inDelveResult = IsInDelve()
    table.insert(lines, ("IsInDelve() logic result => %s"):format(tostring(inDelveResult)))
    table.insert(lines, ("Expected frame visibility => %q"):format(
        inDelveResult and "Should be shown" or "Should be hidden"))
    if ns.frame then
        local okS, isShown   = pcall(function() return ns.frame:IsShown() end)
        local okV, isVisible = pcall(function() return ns.frame:IsVisible() end)
        table.insert(lines, ("frame:IsShown() => %s"):format(okS and tostring(isShown) or "<API error>"))
        table.insert(lines, ("frame:IsVisible() => %s"):format(okV and tostring(isVisible) or "<API error>"))
    else
        table.insert(lines, "frame => nil (frame was not created)")
    end

    -- =========================================================================
    table.insert(lines, "")
    table.insert(lines, "=== FRAME PROPERTIES ===")
    -- =========================================================================
    if ns.frame then
        local w2, h2
        local okSize = pcall(function() w2, h2 = ns.frame:GetSize() end)
        if okSize then
            table.insert(lines, ("frame:GetSize() => width=%s, height=%s"):format(tostring(w2), tostring(h2)))
        else
            table.insert(lines, "frame:GetSize() => <API error>")
        end

        local okAlpha, alpha = pcall(function() return ns.frame:GetAlpha() end)
        table.insert(lines, ("frame:GetAlpha() => %s"):format(okAlpha and tostring(alpha) or "<API error>"))

        local okStrata, strata = pcall(function() return ns.frame:GetFrameStrata() end)
        table.insert(lines, ("frame:GetFrameStrata() => %q"):format(okStrata and tostring(strata) or "<API error>"))

        local okLevel, level = pcall(function() return ns.frame:GetFrameLevel() end)
        table.insert(lines, ("frame:GetFrameLevel() => %s"):format(okLevel and tostring(level) or "<API error>"))

        local parentName = "<error>"
        pcall(function()
            local p = ns.frame:GetParent()
            parentName = p and (p.GetName and p:GetName() or tostring(p)) or "nil"
        end)
        table.insert(lines, ("frame:GetParent() => %s"):format(parentName))

        pcall(function()
            local pt, rel, relPt, x, y = ns.frame:GetPoint(1)
            local relName = rel and (rel.GetName and rel:GetName() or tostring(rel)) or "nil"
            table.insert(lines, ('frame:GetPoint(1) => point=%q, relativeTo=%s, relativePoint=%q, x=%s, y=%s'):format(
                tostring(pt), relName, tostring(relPt), tostring(x), tostring(y)))
        end)
    else
        table.insert(lines, "frame => nil (skipping frame properties)")
    end

    -- =========================================================================
    table.insert(lines, "")
    table.insert(lines, "=== COMPANION STATE ===")
    -- =========================================================================
    local factionID
    local okFaction = pcall(function() factionID = C_DelvesUI.GetFactionForCompanion() end)
    if not okFaction then
        table.insert(lines, "C_DelvesUI.GetFactionForCompanion() => <API error>")
    elseif not factionID or factionID == 0 then
        table.insert(lines, "C_DelvesUI.GetFactionForCompanion() => nil")
        table.insert(lines, "  -> No active companion")
    else
        table.insert(lines, ("C_DelvesUI.GetFactionForCompanion() => factionID=%d"):format(factionID))

        local compName = "nil"
        pcall(function()
            local fd = C_Reputation.GetFactionDataByID(factionID)
            compName = fd and (fd.name or "nil") or "nil"
        end)
        table.insert(lines, ("C_Reputation.GetFactionDataByID(%d) => name=%q"):format(factionID, compName))

        local rank, standing, nextThreshold = "nil", "nil", "nil"
        pcall(function()
            local fr = C_GossipInfo.GetFriendshipReputation(factionID)
            if fr then
                rank          = tostring(fr.reaction  or "nil")
                standing      = tostring(fr.standing        or "nil")
                nextThreshold = tostring(fr.nextThreshold   or fr.reactionThreshold or "nil")
                table.insert(lines, ("C_GossipInfo.GetFriendshipReputation(%d) => {reaction=%s, standing=%s, nextThreshold=%s, ...}"):format(
                    factionID, rank, standing, nextThreshold))
            else
                table.insert(lines, ("C_GossipInfo.GetFriendshipReputation(%d) => nil"):format(factionID))
            end
        end)
        table.insert(lines, ("  -> Companion: %s (Level %s)"):format(compName, rank))
        table.insert(lines, ("  -> XP progress: %s / %s"):format(standing, nextThreshold))
    end

    -- =========================================================================
    table.insert(lines, "")
    table.insert(lines, "=== FRAME CONTENT ===")
    -- =========================================================================
    table.insert(lines, "--- nameLabel ---")
    dumpLabel(ns.nameLabel, "nameLabel", lines)
    table.insert(lines, "--- levelLabel ---")
    dumpLabel(ns.levelLabel, "levelLabel", lines)
    table.insert(lines, "--- xpLabel ---")
    dumpLabel(ns.xpLabel, "xpLabel", lines)

    -- =========================================================================
    table.insert(lines, "")
    table.insert(lines, "=== LAST KNOWN STATE ===")
    -- =========================================================================
    table.insert(lines, ("factionID (last known) => %s"):format(tostring(ns._lastFactionID)))
    table.insert(lines, ("name (last known) => %s"):format(tostring(ns._lastName)))
    table.insert(lines, ("level (last known) => %s"):format(tostring(ns._lastLevel)))
    local db = DelveCompanionStatsDB
    if db then
        table.insert(lines, ("DelveCompanionStatsDB.companionName => %s"):format(tostring(db.companionName)))
        table.insert(lines, ("DelveCompanionStatsDB.companionLevel => %s"):format(tostring(db.companionLevel)))
        if db.position then
            local pos = db.position
            table.insert(lines, ("DelveCompanionStatsDB.position => {point=%q, relativePoint=%q, x=%s, y=%s}"):format(
                tostring(pos.point), tostring(pos.relativePoint), tostring(pos.x), tostring(pos.y)))
        else
            table.insert(lines, "DelveCompanionStatsDB.position => nil")
        end
    else
        table.insert(lines, "DelveCompanionStatsDB => nil")
    end

    -- =========================================================================
    table.insert(lines, "")
    table.insert(lines, "=== BOON STATE ===")
    -- =========================================================================
    -- Dump C_Spell.GetSpellDescription(1280098) (source of boon stat values)
    table.insert(lines, "--- C_Spell.GetSpellDescription(1280098) ---")
    pcall(function()
        if C_Spell and C_Spell.GetSpellDescription then
            local descOk, spellDesc = pcall(C_Spell.GetSpellDescription, 1280098)
            if descOk and spellDesc and spellDesc ~= "" then
                -- Strip color codes for display
                local cleanDesc = spellDesc
                    :gsub("|cn[^:]+:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                -- Also dump the raw (pre-strip) description for format diagnosis.
                table.insert(lines, "  [raw, pre-strip]: " .. spellDesc)
                local lineNum = 0
                for ln in (cleanDesc .. "\n"):gmatch("([^\n]*)\n") do
                    lineNum = lineNum + 1
                    table.insert(lines, ("  L%d: %s"):format(lineNum, ln))
                    -- Use the same resilient patterns as GetBoonsDisplayText.
                    local rawStat, rawNum = ln:match("^(.+):%s*(%d+)%%%D*$")
                    if not rawStat then rawStat, rawNum = ln:match("^(.+):%s*(%d+)%D*$") end
                    if rawStat then
                        rawStat = rawStat:match("^%s*(.-)%s*$")
                        table.insert(lines, ("    [boon] raw stat=%q  abbrev=%q"):format(
                            rawStat, GetBoonAbbrev(rawStat)))
                    end
                end
            else
                table.insert(lines, "  (no description returned)")
            end
        else
            table.insert(lines, "  C_Spell.GetSpellDescription not available")
        end
    end)

    local boonText = ""
    pcall(function() boonText = GetBoonsDisplayText() end)
    table.insert(lines, ("GetBoonsDisplayText() returns: %q"):format(boonText))
    table.insert(lines, "--- boonLabel ---")
    dumpLabel(ns.boonLabel, "boonLabel", lines)

    -- =========================================================================
    table.insert(lines, "")
    table.insert(lines, "=== NEMESIS STATE ===")
    -- =========================================================================
    local scenarioAvail = (C_ScenarioInfo ~= nil and "yes" or "no")
    table.insert(lines, ("C_ScenarioInfo available? %s"):format(scenarioAvail))
    if scenarioAvail == "yes" then
        local stepInfo = C_ScenarioInfo.GetScenarioStepInfo()
        local numC = (stepInfo and stepInfo.numCriteria) or 0
        table.insert(lines, ("GetScenarioStepInfo().numCriteria: %d"):format(numC))
        for i = 1, numC do
            local ok, ci = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
            if ok and ci then
                table.insert(lines, ("  Criteria[%d]: description=%q, quantity=%s, totalQuantity=%s"):format(
                    i, tostring(ci.description), tostring(ci.quantity), tostring(ci.totalQuantity)))
            else
                table.insert(lines, ("  Criteria[%d]: <nil>"):format(i))
            end
        end
    end
    local nemText = ""
    pcall(function() nemText = GetNemesisProgress() end)
    table.insert(lines, ("GetNemesisProgress() returns: %q"):format(nemText))
    table.insert(lines, "--- nemesisLabel ---")
    dumpLabel(ns.nemesisLabel, "nemesisLabel", lines)
    table.insert(lines, "--- nemesisDetailLabel ---")
    dumpLabel(ns.nemesisDetailLabel, "nemesisDetailLabel", lines)

    -- Deep diagnostic: dump all C_ScenarioInfo methods and safe-call GetScenarioStepInfo
    if C_ScenarioInfo then
        table.insert(lines, "C_ScenarioInfo available? yes")
        -- Dump all available methods
        table.insert(lines, "--- C_ScenarioInfo methods ---")
        for k, v in pairs(C_ScenarioInfo) do
            table.insert(lines, "  ." .. k .. " = " .. type(v))
        end
        -- Safe call
        if C_ScenarioInfo.GetScenarioStepInfo then
            local ok, si = pcall(C_ScenarioInfo.GetScenarioStepInfo)
            if ok and si then
                local n = si.numCriteria or 0
                table.insert(lines, "GetScenarioStepInfo().numCriteria = " .. tostring(n))
                for i = 1, n do
                    local ok2, c = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
                    if ok2 and c then
                        table.insert(lines, "  criteria[" .. i .. "] desc=" .. (c.description or "nil") .. " qty=" .. tostring(c.quantity) .. " total=" .. tostring(c.totalQuantity))
                    end
                end
            else
                table.insert(lines, "GetScenarioStepInfo() = ERROR or nil")
            end
        else
            table.insert(lines, "GetScenarioStepInfo = nil (method not available)")
        end
    else
        table.insert(lines, "C_ScenarioInfo available? no")
    end

    -- Deep diagnostic: scan C_DelvesUI for nemesis-related keys
    table.insert(lines, "--- C_DelvesUI nemesis keys ---")
    if C_DelvesUI then
        for k, _ in pairs(C_DelvesUI) do
            local lk = k:lower()
            if lk:find("nem") or lk:find("strong") or lk:find("enemy") or lk:find("group") or lk:find("kill") then
                table.insert(lines, "  C_DelvesUI." .. k)
            end
        end
    end

    -- Deep diagnostic: check quest log for nemesis-related entries
    table.insert(lines, "--- Quest log nemesis search ---")
    if C_QuestLog then
        local okEntries, numEntries = pcall(function() return C_QuestLog.GetNumQuestLogEntries() end)
        if not okEntries then
            table.insert(lines, "C_QuestLog.GetNumQuestLogEntries() => <API error: " .. tostring(numEntries) .. ">")
        else
            table.insert(lines, "Quest entries: " .. tostring(numEntries))
            for i = 1, numEntries do
                local okInfo, info = pcall(function() return C_QuestLog.GetInfo(i) end)
                if okInfo and info and info.title then
                    local t = info.title:lower()
                    if t:find("nem") or t:find("strong") or t:find("enemy") then
                        table.insert(lines, "  [" .. i .. "] " .. info.title .. " id=" .. tostring(info.questID))
                    end
                end
            end
        end
    else
        table.insert(lines, "C_QuestLog not available")
    end

    -- Deep diagnostic: dump header frame children (helps identify collapse button key in TWW)
    if ns.headerFrame then
        lines[#lines+1] = "--- Header frame children ---"
        for k, v in pairs(ns.headerFrame) do
            lines[#lines+1] = "  ." .. tostring(k) .. " = " .. type(v)
        end
    end

    local text = table.concat(lines, "\n")
    popup._editBox:SetText(text)
    popup:Show()
end

-------------------------------------------------------------------------------
-- Central event frame — ADDON_LOADED only (no PLAYER_LOGIN race condition)
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Unregister immediately — we only need to initialize once
        self:UnregisterEvent("ADDON_LOADED")
        dcslog("Info", "ADDON_LOADED fired for: " .. tostring(arg1))

        -- Check if this addon is functionally disabled via CouchPotato suite
        if _G.CouchPotatoDB and _G.CouchPotatoDB.addonStates and
           _G.CouchPotatoDB.addonStates.DelveCompanionStats == false then
            dcslog("Info", "DelveCompanionStats is disabled via /cp disable — skipping init")
            ns._cpDisabled = true
            return
        end

        -- All initialization happens here, atomically, before any other events fire
        ns:OnLoad()

        -- Delayed resize: use fixed 235 px (avoids picking up "All Objectives" ~460 px width)
        C_Timer.After(0.5, function()
            local w = 248
            if ns.frame then ns.frame:SetWidth(w) end
            if ns.headerFrame then ns.headerFrame:SetWidth(w) end
            if ns.header then ns.header:SetWidth(w) end
            local cw = w - 12
            if ns.nameLabel then ns.nameLabel:SetWidth(cw) end
            if ns.boonLabel then ns.boonLabel:SetWidth(cw) end
            if ns.boonHeaderLabel then ns.boonHeaderLabel:SetWidth(cw) end
            if ns.nemesisLabel then ns.nemesisLabel:SetWidth(cw) end
            if ns.nemesisDetailLabel then ns.nemesisDetailLabel:SetWidth(cw) end
        end)
    end
end)

-------------------------------------------------------------------------------
-- GetTrackerAnchor: Returns the first visible Blizzard objective tracker frame
-- (ScenarioObjectiveTracker preferred, ObjectiveTrackerFrame as fallback).
-- Returns nil when neither is available/visible.
-------------------------------------------------------------------------------
local function GetTrackerAnchor()
    -- Always anchor to the full ObjectiveTrackerFrame so we stay below ALL
    -- tracker content (quests, scenarios, achievements, etc.), not just
    -- the Delves/Scenario section.
    if ObjectiveTrackerFrame
        and ObjectiveTrackerFrame.IsShown
        and ObjectiveTrackerFrame:IsShown() then
        return ObjectiveTrackerFrame
    end
    return nil
end

-------------------------------------------------------------------------------
-- AnchorFrame: Attaches ns.frame directly below the Blizzard objective tracker
-- when one is visible.  Falls back to the last saved position (draggable) when
-- no tracker is found.  Parent is always UIParent — we only use the tracker as
-- a SetPoint reference, never as a parent, to avoid inheriting its child
-- textures (scroll arrows, ornaments, etc.).
-------------------------------------------------------------------------------
local function AnchorFrame()
    if not ns.frame then return end
    local anchor = GetTrackerAnchor()
    if anchor then
        ns.frame:ClearAllPoints()
        ns.frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        ns.isDraggable = false
    else
        -- Fall back to saved position; allow dragging when unanchored
        local pos = DelveCompanionStatsDB and DelveCompanionStatsDB.position
        if pos then
            ns.frame:ClearAllPoints()
            ns.frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
        end
        ns.isDraggable = true
    end
end

-------------------------------------------------------------------------------
-- UpdateFrameVisibility: Show or hide the frame based on active delve state.
-- Calls AnchorFrame and UpdateCompanionData when the frame becomes visible.
-------------------------------------------------------------------------------
function ns:UpdateFrameVisibility()
    if not ns.frame then return end
    local wasShown = ns.frame:IsShown()
    if IsInDelve() then
        ns.frame:Show()
        AnchorFrame()
    else
        ns.frame:Hide()
    end
    if not wasShown and ns.frame:IsShown() then
        ns:UpdateCompanionData()
    end
end

-------------------------------------------------------------------------------
-- UpdateFrameHeight: Resize the outer frame to header + visible content.
-- Called after expanding collapsed state.
-------------------------------------------------------------------------------
function ns:UpdateFrameHeight()
    local headerH = ns.headerFrame and ns.headerFrame:GetHeight() or 28
    if ns.contentFrame and ns.contentFrame:IsShown() then
        ns.frame:SetHeight(headerH + (ns.contentFrame:GetHeight() or 0))
    else
        ns.frame:SetHeight(headerH)
    end
end

-------------------------------------------------------------------------------
-- OnLoad: Frame creation + UI setup + SavedVars init + position restore
-- Called exactly once from ADDON_LOADED handler above.
-- Guard: if ns.frame already exists, skip (idempotent safety).
-------------------------------------------------------------------------------
function ns:OnLoad()
    -- Guard: idempotent — never initialize twice
    if ns.frame then
        dcslog("Warn", "OnLoad called but ns.frame already exists — skipping (idempotent guard)")
        return
    end

    dcslog("Info", "OnLoad: starting initialization, version=" .. ns.version)

    -- 1. Initialize SavedVariables
    -- NOTE: Per WoW API docs, SavedVariables are guaranteed to be loaded
    -- by the time ADDON_LOADED fires for our addon.
    DelveCompanionStatsDB = DelveCompanionStatsDB or {}
    local db = DelveCompanionStatsDB

    -- Ensure schema fields exist (nil-safe defaults for future access)
    db.position       = db.position       -- keep existing or nil
    db.companionName  = db.companionName  -- keep existing or nil
    db.companionLevel = db.companionLevel -- keep existing or nil
    db.collapsed      = db.collapsed      -- keep existing or nil (nil = expanded)
    db.pinned         = db.pinned         -- keep existing or nil (nil = treat as pinned)

    -- 2. Create the main display frame
    -- Wrapped in pcall: guards against any unexpected frame creation failures.
    -- If CreateFrame fails, ns.frame = nil and addon disables gracefully.
    local frameOk, frameResult = pcall(function()
        return CreateFrame("Frame", "DelveCompanionStatsFrame", UIParent, "BackdropTemplate")
    end)
    if not frameOk or not frameResult then
        -- Fallback: plain Frame without BackdropTemplate
        local ok2, f2 = pcall(function()
            return CreateFrame("Frame", "DelveCompanionStatsFrame", UIParent)
        end)
        if ok2 and f2 then
            frameResult = f2
            frameOk = true
        end
    end
    if not frameOk or not frameResult then
        dcslog("Error", "Could not create display frame — addon disabled")
        print("|cffff4444DelveCompanionStats:|r Could not create display frame. Addon disabled.")
        ns.frame = nil
        return
    end

    ns.frame = frameResult
    dcslog("Info", "Frame created successfully: DelveCompanionStatsFrame")

    -- Use MEDIUM strata at a low frame level so the frame sits at the same rendering
    -- layer as the objective tracker content (also MEDIUM) but below Blizzard's own
    -- tracker text which uses higher frame levels within MEDIUM.  LOW strata caused
    -- the frames to render behind quest text while still overlapping it positionally.
    ns.frame:SetFrameStrata("MEDIUM")
    ns.frame:SetFrameLevel(1)

    -- 3. Determine frame width — match ObjectiveTrackerFrame (outer tracker container)
    -- for exact alignment with Blizzard's tracker. Fall back to ScenarioObjectiveTracker,
    -- then hardcoded 248 px.
    local frameWidth = 0
    if ObjectiveTrackerFrame and ObjectiveTrackerFrame.GetWidth then
        frameWidth = ObjectiveTrackerFrame:GetWidth()
    end
    if frameWidth < 100 or frameWidth > 400 then
        if ScenarioObjectiveTracker and ScenarioObjectiveTracker.GetWidth then
            frameWidth = ScenarioObjectiveTracker:GetWidth()
        end
    end
    if frameWidth < 100 or frameWidth > 400 then
        frameWidth = 248  -- match Delves section content box width
    end
    -- Inner content width: 6 px label inset each side (matches ObjectiveTracker label inset),
    -- minus 16 px to account for the 8px left/right padding on the content frame anchors.
    local contentWidth = frameWidth - 12 - 16

    -- Set size and default anchor (above ChatFrame1 when available)
    ns.frame:SetSize(frameWidth, 160)
    if ChatFrame1 then
        ns.frame:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 10)
    else
        ns.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 5, 130)
    end

    -- 4a. Header frame — matches Blizzard ObjectiveTracker section header precisely.
    -- Transparent/minimal background, gold text, single thin gold underline below the title,
    -- collapse button far right. No full box border — text floats like native tracker headers.
    local header = CreateFrame("Button", nil, ns.frame)
    ns.header = header
    ns.headerFrame = header
    header:SetHeight(28)
    header:SetPoint("TOPLEFT",  ns.frame, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", ns.frame, "TOPRIGHT", 0, 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if DelveCompanionStatsDB and DelveCompanionStatsDB.pinned == false then
            ns.frame:StartMoving()
        end
    end)
    header:SetScript("OnDragStop", function()
        ns.frame:StopMovingOrSizing()
        if DelveCompanionStatsDB then
            local point, _, relPoint, x, y = ns.frame:GetPoint()
            DelveCompanionStatsDB.position = {point=point, relPoint=relPoint, x=x, y=y}
        end
    end)

    -- Header is fully transparent — matches Blizzard ObjectiveTracker section headers
    -- (no background tint, no border box).

    -- Title: GameFontNormal base, try ObjectiveTitleFont (exact Blizzard tracker header font),
    -- gold colour matching "Delves"/"Quests" section headers.
    local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Try the exact Blizzard tracker header font first; fall back silently.
    pcall(function() headerTitle:SetFontObject(ObjectiveTitleFont) end)
    headerTitle:SetPoint("LEFT", header, "LEFT", 8, 0)
    headerTitle:SetJustifyV("MIDDLE")
    headerTitle:SetText("Companion")
    -- Gold matching Blizzard section headers: R=1 G=0.82 B=0 (same as tracker "Delves" text)
    headerTitle:SetTextColor(1, 0.82, 0.0, 1)

    -- Underline: thin 1px gold line from RIGHT of title text to RIGHT of header frame.
    -- Blizzard's tracker headers have NO line under the text itself — line starts after text.
    local headerBottomLine = header:CreateTexture(nil, "ARTWORK")
    headerBottomLine:SetHeight(1)
    headerBottomLine:SetPoint("LEFT",  headerTitle, "RIGHT", 4, 0)
    headerBottomLine:SetPoint("RIGHT", header,      "RIGHT", 0, 0)
    headerBottomLine:SetColorTexture(0.9, 0.75, 0.1, 0.8)

    -- Collapse button: gold en-dash, far right, vertically centred
    -- Sized at 26x26 (at least 10px larger than old 16px variants) for easy clicking.
    local collapseBtn = CreateFrame("Button", nil, header)
    collapseBtn:SetSize(26, 26)
    collapseBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    -- Font set explicitly (not as 3rd arg) so text renders even before font objects load
    local collapseBtnText = collapseBtn:CreateFontString(nil, "OVERLAY")
    collapseBtnText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    collapseBtnText:SetAllPoints(collapseBtn)
    collapseBtnText:SetJustifyH("CENTER")
    collapseBtnText:SetJustifyV("MIDDLE")
    collapseBtnText:SetTextColor(1, 0.78, 0.1, 1)
    collapseBtnText:SetText("–")
    collapseBtn:SetFontString(collapseBtnText)

    collapseBtn:SetScript("OnClick", function()
        if ns.contentFrame:IsShown() then
            ns.contentFrame:Hide()
            collapseBtnText:SetText("+")
            if DelveCompanionStatsDB then
                DelveCompanionStatsDB.collapsed = true
            end
            ns.frame:SetHeight(header:GetHeight())
        else
            ns.contentFrame:Show()
            collapseBtnText:SetText("–")
            if DelveCompanionStatsDB then
                DelveCompanionStatsDB.collapsed = false
            end
            ns:UpdateFrameHeight()
        end
    end)

    -- Store references on ns for test access and height calculations
    ns.headerFrame      = header
    ns.headerTitle      = headerTitle
    ns.headerLabel      = headerTitle   -- alias for backward-compat
    ns.collapseBtn      = collapseBtn
    ns.collapseBtnText  = collapseBtnText

    -- Pin button: to the LEFT of the collapse button. Lock icon indicates whether
    -- the frame is anchored to the Blizzard tracker (locked/pinned) or freely draggable
    -- (unlocked/unpinned). Default: pinned (locked icon).
    -- Pin button: sized at 26x26 (at least 10px larger than old 16x16) for easy clicking.
    local pinBtn = CreateFrame("Button", nil, header)
    pinBtn:SetSize(26, 26)
    pinBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -4, 0)
    pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
    pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
    pinBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    pinBtn:EnableMouse(true)
    ns.pinBtn = pinBtn

    -- ApplyPinnedState: anchor frame below the objective tracker, disable dragging, lock icon.
    -- Uses ObjectiveTrackerFrame (the outer auto-sizing container) as the anchor so DCS
    -- sits directly below all tracker content.  Falls back to a right-side default when
    -- the tracker is not yet visible (e.g. at load time before PLAYER_ENTERING_WORLD).
    local function ApplyPinnedState()
        ns.isDraggable = false
        ns.frame:SetMovable(false)
        ns.frame:ClearAllPoints()
        local trackerAnchor = GetTrackerAnchor()
        if trackerAnchor then
            ns.frame:SetPoint("TOPRIGHT", trackerAnchor, "BOTTOMRIGHT", 0, -4)
            dcslog("Info", "ApplyPinnedState: anchored below ObjectiveTrackerFrame")
        else
            -- Tracker not visible yet — park on right side of screen until
            -- PLAYER_ENTERING_WORLD fires and re-anchors us properly.
            ns.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
            dcslog("Info", "ApplyPinnedState: tracker not visible — parked TOPRIGHT fallback")
        end
        ns.pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
        ns.pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
        DelveCompanionStatsDB.pinned = true
    end

    -- ApplyUnpinnedState: detach from tracker, enable free drag, grey icon.
    local function ApplyUnpinnedState()
        ns.isDraggable = true
        ns.frame:SetMovable(true)
        ns.pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        ns.pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
        DelveCompanionStatsDB.pinned = false
    end

    pinBtn:SetScript("OnClick", function()
        local db = DelveCompanionStatsDB
        if not db then return end
        if db.pinned == false then
            -- currently unpinned → pin it
            ApplyPinnedState()
        else
            -- currently pinned (or nil) → unpin it
            db.pinned = false
            ns.frame:SetMovable(true)
            if ns.pinBtn then
                ns.pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
                ns.pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
            end
        end
    end)

    -- Expose for tests and external helpers
    ns.ApplyPinnedState   = ApplyPinnedState
    ns.ApplyUnpinnedState = ApplyUnpinnedState

    -- 4b. Content frame — plain semi-transparent dark background (no backdrop/border),
    -- matching the Blizzard ObjectiveTracker content area style.
    local contentFrame
    local contentOk, contentResult = pcall(function()
        return CreateFrame("Frame", nil, ns.frame, "BackdropTemplate")
    end)
    if contentOk and contentResult then
        contentFrame = contentResult
    else
        contentFrame = CreateFrame("Frame", nil, ns.frame)
    end
    contentFrame:SetPoint("TOPLEFT",  ns.headerFrame, "BOTTOMLEFT",   0, -2)
    contentFrame:SetPoint("TOPRIGHT", ns.headerFrame, "BOTTOMRIGHT",  0, -2)
    -- No visible backdrop — content text floats on transparent background matching
    -- Blizzard's ObjectiveTracker content area (no box, no border, no background panel).
    -- Store on ns so UpdateCompanionData can resize it
    ns.contentFrame = contentFrame

    -- 5. Name label — objective body text style (white, ~11pt), matching tracker objective
    -- lines ("- 1/3 Elementary Voidcore Shard" etc).  8px left padding, 8px top padding.
    ns.nameLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.nameLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 8, -8)
    ns.nameLabel:SetWidth(contentWidth)
    ns.nameLabel:SetJustifyH("LEFT")
    -- Apply font object then override color so ObjectiveFont default color is not kept.
    pcall(function() ns.nameLabel:SetFontObject(ObjectiveFont) end)
    ns.nameLabel:SetTextColor(1, 1, 1, 1)  -- pure white, set AFTER font object
    ns.nameLabel:SetText("No companion data")
    ns.nameLabel:SetShadowOffset(1, -1)
    ns.nameLabel:SetShadowColor(0, 0, 0, 1)
    ns.nameLabel:SetWordWrap(false)

    -- 6c. Boon header label — "Boons" section header, styled like Blizzard quest/objective
    -- titles (e.g. "An Elementary Voidcore"): muted gold, GameFontNormalSmall.
    -- Shown whenever a companion is active; positioned 6px below the level line.
    ns.boonHeaderLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.boonHeaderLabel:SetPoint("TOPLEFT", ns.nameLabel, "BOTTOMLEFT", 0, -6)
    ns.boonHeaderLabel:SetWidth(contentWidth)
    ns.boonHeaderLabel:SetJustifyH("LEFT")
    -- Use ObjectiveFont when available; set color AFTER so muted gold is preserved.
    pcall(function() ns.boonHeaderLabel:SetFontObject(ObjectiveFont) end)
    ns.boonHeaderLabel:SetTextColor(0.9, 0.75, 0.3, 1)
    ns.boonHeaderLabel:SetShadowOffset(1, -1)
    ns.boonHeaderLabel:SetShadowColor(0, 0, 0, 1)
    ns.boonHeaderLabel:SetText("Boons")
    ns.boonHeaderLabel:Hide()

    -- 6d. Boon value label — stat values "Max HP: 6%, Move Spd: 10%" or "None".
    -- Matches Blizzard objective text style: white for active values, grey for "None".
    -- Anchored 4px below the Boons header.
    ns.boonLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.boonLabel:SetPoint("TOPLEFT", ns.boonHeaderLabel, "BOTTOMLEFT", 0, -4)
    ns.boonLabel:SetWidth(contentWidth)
    ns.boonLabel:SetJustifyH("LEFT")
    -- Apply font then set color to ensure white is not overridden by font defaults.
    pcall(function() ns.boonLabel:SetFontObject(ObjectiveFont) end)
    ns.boonLabel:SetTextColor(1, 1, 1, 1)
    ns.boonLabel:SetShadowOffset(1, -1)
    ns.boonLabel:SetShadowColor(0, 0, 0, 1)
    ns.boonLabel:SetText("")

    -- Backward-compat stubs: levelLabel and xpLabel are no longer displayed
    -- individually but tests check their text stays "" after UpdateCompanionData.
    ns.levelLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.levelLabel:SetText("")
    ns.levelLabel:Hide()

    ns.xpLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.xpLabel:SetText("")
    ns.xpLabel:Hide()

    -- 6e. Nemesis header label — "Enemy Groups Remaining" section sub-header, styled like
    -- Blizzard objective/quest title text: muted gold, GameFontNormalSmall.
    -- Anchored 6px below the boon value label; shown only when nemesis data is present.
    ns.nemesisLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.nemesisLabel:SetPoint("TOPLEFT", ns.boonLabel, "BOTTOMLEFT", 0, -6)
    ns.nemesisLabel:SetWidth(contentWidth)
    ns.nemesisLabel:SetJustifyH("LEFT")
    -- Use ObjectiveFont when available; set color AFTER so muted gold is preserved.
    pcall(function() ns.nemesisLabel:SetFontObject(ObjectiveFont) end)
    ns.nemesisLabel:SetTextColor(0.9, 0.75, 0.3, 1)
    ns.nemesisLabel:SetShadowOffset(1, -1)
    ns.nemesisLabel:SetShadowColor(0, 0, 0, 1)
    ns.nemesisLabel:SetText("")
    ns.nemesisLabel:Hide()

    -- 6f. Nemesis value label — "X / Y" count below the header; white objective text.
    ns.nemesisDetailLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.nemesisDetailLabel:SetPoint("TOPLEFT", ns.nemesisLabel, "BOTTOMLEFT", 0, -4)
    ns.nemesisDetailLabel:SetWidth(contentWidth)
    ns.nemesisDetailLabel:SetJustifyH("LEFT")
    -- Apply font then set white so font default color is not kept.
    pcall(function() ns.nemesisDetailLabel:SetFontObject(ObjectiveFont) end)
    ns.nemesisDetailLabel:SetTextColor(1, 1, 1, 1)
    ns.nemesisDetailLabel:SetShadowOffset(1, -1)
    ns.nemesisDetailLabel:SetShadowColor(0, 0, 0, 1)
    ns.nemesisDetailLabel:SetText("")
    ns.nemesisDetailLabel:Hide()

    -- 7. Make frame movable (only active when not anchored to the tracker)
    -- Safe: frame created above in this same function before drag handlers registered
    ns.frame:SetMovable(true)
    ns.frame:EnableMouse(true)

    -- 8. Restore saved position (wrapped in pcall for corrupt SavedVariables safety)
    if db and db.position then
        local posOk = pcall(function()
            local p = db.position
            ns.frame:ClearAllPoints()
            -- Support both 'relativePoint' (legacy) and 'relPoint' (new pin-save format)
            ns.frame:SetPoint(p.point, UIParent, p.relativePoint or p.relPoint, p.x, p.y)
        end)
        -- posOk == false means corrupt position data; default anchor from step 3 remains
        if not posOk then dcsprint("Could not restore saved position; using default.") end
    end

    -- 8b. Restore collapsed state from SavedVariables
    if db.collapsed then
        if ns.contentFrame then ns.contentFrame:Hide() end
        ns.frame:SetHeight(ns.headerFrame and ns.headerFrame:GetHeight() or 28)
        if ns.collapseBtnText then ns.collapseBtnText:SetText("+") end
    end

    -- 8c. Restore pin/unpin state. Default (nil) is treated as pinned.
    if DelveCompanionStatsDB.pinned == false then
        ns.frame:SetMovable(true)
        local pos = DelveCompanionStatsDB.position
        if pos and pos.point then
            ns.frame:ClearAllPoints()
            ns.frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        end
        if ns.pinBtn then ns.pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up") end
    else
        -- pinned (true or nil) → anchor to tracker, immovable, locked icon
        ApplyPinnedState()
    end

    -- 9. Determine frame visibility based on active delve state
    ns:UpdateFrameVisibility()

    -- ResizeToTracker: re-measure ScenarioObjectiveTracker width and apply to all labels.
    -- Called on PLAYER_ENTERING_WORLD so the tracker is fully sized before we read it.
    local function ResizeToTracker()
        local w = 248  -- Fixed width for Delves section content box
        if ns.frame then ns.frame:SetWidth(w) end
        if ns.header then ns.header:SetWidth(w) end
        if ns.headerFrame then ns.headerFrame:SetWidth(w) end
        local cw = w - 12
        if ns.nameLabel         then ns.nameLabel:SetWidth(cw) end
        if ns.boonLabel         then ns.boonLabel:SetWidth(cw) end
        if ns.boonHeaderLabel   then ns.boonHeaderLabel:SetWidth(cw) end
        if ns.nemesisLabel      then ns.nemesisLabel:SetWidth(cw) end
        if ns.nemesisDetailLabel then ns.nemesisDetailLabel:SetWidth(cw) end
    end

    -- 11. Register events for companion data updates
    if ns.frame then
        ns.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        ns.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        -- DELVE_COMPANION_UPDATE may not exist in all WoW versions; pcall guards against error
        pcall(function() ns.frame:RegisterEvent("DELVE_COMPANION_UPDATE") end)
        -- UPDATE_FACTION fires when friendship reputation changes
        ns.frame:RegisterEvent("UPDATE_FACTION")
        -- MAJOR_FACTION_RENOWN_LEVEL_CHANGED fires when renown level changes
        ns.frame:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
        -- Additional events to widen the data-refresh net
        ns.frame:RegisterEvent("UPDATE_INSTANCE_INFO")
        ns.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
        ns.frame:RegisterEvent("UNIT_NAME_UPDATE")
        -- SCENARIO_CRITERIA_UPDATE fires when nemesis kill count changes
        pcall(function() ns.frame:RegisterEvent("SCENARIO_CRITERIA_UPDATE") end)
        -- QUEST_WATCH_LIST_CHANGED fires when quests are tracked/untracked;
        -- re-anchor so we stay below the full tracker content.
        ns.frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
        -- UNIT_AURA fires when buffs/debuffs change on a unit; used to detect
        -- when the boon aura (spell 1280098) becomes active after zone-in.
        ns.frame:RegisterEvent("UNIT_AURA")
        -- SPELL_DATA_LOAD_RESULT fires when an asynchronous spell description
        -- finishes loading.  Boon spell 1280098 may not be cached on first query;
        -- re-running UpdateCompanionData when it arrives guarantees fresh values.
        pcall(function() ns.frame:RegisterEvent("SPELL_DATA_LOAD_RESULT") end)
        ns.frame:SetScript("OnEvent", function(self, event, ...)
            -- Suppress all event handling if functionally disabled via /cp disable
            if ns._cpDisabled then return end
            -- UNIT_AURA: only refresh boon data when player's own auras change in a delve.
            -- Avoids redundant updates for non-player units (party members, NPCs, etc.).
            -- Throttled to once every THROTTLE_INTERVAL seconds to prevent continuous spam.
            if event == "UNIT_AURA" then
                local unitID = ...
                if unitID == "player" and IsInDelve() then
                    local now = GetTime()
                    if now - lastAuraUpdate >= THROTTLE_INTERVAL then
                        lastAuraUpdate = now
                        pendingAuraTimer = false
                        ns:UpdateCompanionData(event)
                    elseif not pendingAuraTimer and C_Timer and C_Timer.After then
                        -- A boon was collected during the throttle window.
                        -- Schedule exactly one deferred retry so it is never dropped.
                        pendingAuraTimer = true
                        local retryDelay = THROTTLE_INTERVAL - (now - lastAuraUpdate) + 0.1
                        C_Timer.After(retryDelay, function()
                            pendingAuraTimer = false
                            if IsInDelve() then
                                lastAuraUpdate = GetTime()
                                ns:UpdateCompanionData("UNIT_AURA_RETRY")
                            end
                        end)
                    end
                end
                return
            end

            -- SPELL_DATA_LOAD_RESULT: fires when an async spell description finishes
            -- loading.  Re-run boon data if we are in a delve and the loaded spell is
            -- the boon spell (1280098), or if no spellID arg is available (fire anyway).
            if event == "SPELL_DATA_LOAD_RESULT" then
                local spellID = ...
                if IsInDelve() and (spellID == nil or spellID == 1280098) then
                    ns:UpdateCompanionData(event)
                end
                return
            end

            -- PLAYER_ENTERING_WORLD: run normal visibility + data update, then schedule
            -- two delayed refreshes so boons (which may not be applied immediately on
            -- zone-in) have time to activate before we query the tooltip.
            if event == "PLAYER_ENTERING_WORLD" then
                ResizeToTracker()
                ns:UpdateFrameVisibility()
                AnchorFrame()
                if ns.frame:IsShown() then
                    ns:UpdateCompanionData(event)
                end
                if C_Timer and C_Timer.After then
                    C_Timer.After(2, function()
                        if IsInDelve() then
                            AnchorFrame()
                            ns:UpdateCompanionData("TIMER_2S_PEW")
                        end
                    end)
                end
                return
            end

            -- QUEST_WATCH_LIST_CHANGED: re-anchor after a short delay so the
            -- tracker has time to finish its layout before we read its bounds.
            if event == "QUEST_WATCH_LIST_CHANGED" then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.1, function() AnchorFrame() end)
                end
                return
            end

            -- UPDATE_FACTION: fires in pairs every time reputation changes; throttle it.
            if event == "UPDATE_FACTION" then
                local now = GetTime()
                if now - lastFactionUpdate < THROTTLE_INTERVAL then return end
                lastFactionUpdate = now
            end

            -- All other events: refresh visibility then data.
            ns:UpdateFrameVisibility()
            if ns.frame:IsShown() then
                ns:UpdateCompanionData(event)
            end
        end)
    end

    -- Explicitly show nameLabel (belt-and-suspenders: ensures visibility even if parent Show() is pending)
    if ns.nameLabel then ns.nameLabel:Show() end

    -- Polling fallbacks: data may not be ready immediately on ADDON_LOADED.
    -- Two staggered timers (3s and 10s) are sufficient; the 5s duplicate is removed.
    if C_Timer and C_Timer.After then
        C_Timer.After(3,  function() ns:UpdateCompanionData("TIMER_3S") end)
        C_Timer.After(10, function() ns:UpdateCompanionData("TIMER_10S") end)
    end
end

-------------------------------------------------------------------------------
-- FormatNumber: Format a number with comma separators (e.g. 12345 -> "12,345")
-------------------------------------------------------------------------------
local function FormatNumber(num)
    if not num or num == 0 then return tostring(num or 0) end
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

-------------------------------------------------------------------------------
-- BOON_ABBREV: Maps tooltip stat names (from spell 1280098) to short labels.
-- Used by GetBoonsDisplayText() to build a one-per-line summary.
-------------------------------------------------------------------------------
local BOON_ABBREV = {
    ["Maximum Health"]         = "Max HP",
    ["Movement Speed"]         = "Move Spd",
    ["Strength"]               = "Str",
    ["Haste"]                  = "Haste",
    ["Critical Strike"]        = "Crit",
    ["Mastery"]                = "Mast",
    ["Versatility"]            = "Vers",
    ["Damage Reduction"]       = "Dmg Red",
}

-------------------------------------------------------------------------------
-- GetBoonAbbrev: Resolves a raw tooltip stat name (which may contain WoW color
-- escape codes or extra whitespace) to its short display label.
-- Resolution order:
--   1. Strip color codes / whitespace, then exact key match in BOON_ABBREV.
--   2. Case-insensitive substring match against every key in BOON_ABBREV.
--   3. Fallback: first word of the cleaned name (or first 6 chars).
-------------------------------------------------------------------------------
GetBoonAbbrev = function(statName)
    -- Strip WoW color escape codes and trim surrounding whitespace.
    local clean = statName
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :match("^%s*(.-)%s*$")
    local lower = clean:lower()
    -- 1. Exact match.
    if BOON_ABBREV[clean] then return BOON_ABBREV[clean] end
    -- 2. Case-insensitive substring match.
    for k, v in pairs(BOON_ABBREV) do
        if lower:find(k:lower(), 1, true) then return v end
    end
    -- 3. Fallback: first word or first 6 chars.
    return clean:match("^(%S+)") or clean:sub(1, 6)
end

-------------------------------------------------------------------------------
-- GetBoonsDisplayText: Reads boon spell 1280098 via C_Spell.GetSpellDescription
-- and returns a one-per-line summary of non-zero stats,
-- e.g. "Max HP: 6%\nMove Spd: 10%".
-- Returns "" if not in a delve or no boon data is found.
-- NOTE: Does NOT use GameTooltip — no floating tooltip side-effect.
-------------------------------------------------------------------------------
GetBoonsDisplayText = function()
    -- Only show boon info when inside a delve
    if not IsInDelve() then return "" end

    if not C_Spell or not C_Spell.GetSpellDescription then return "None" end
    local ok, desc = pcall(C_Spell.GetSpellDescription, 1280098)
    if not ok or not desc or desc == "" then return "None" end

    -- Debug: log the raw spell description so we can diagnose format mismatches.
    dcslog("Debug", "GetBoonsDisplayText: raw desc=" .. tostring(desc))

    -- Strip WoW color codes:
    --   |cnNAME:text|r  (named color codes, TWW+)
    --   |cXXXXXXXXtext|r  (hex ARGB color codes)
    local clean = desc
        :gsub("|cn[^:]+:", "")
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")

    -- Parse lines of the form "Stat Name: N%" or "Stat Name: N%." (trailing punctuation ok).
    -- Pattern priority:
    --   1. "Stat: 5%"  — percent sign present, optional trailing non-digit chars then EOL
    --   2. "Stat: 5"   — bare number, optional trailing non-digit chars then EOL
    -- This handles: "Strength: 2%." (period after %) and plain "Strength: 2%".
    local stats = {}
    for line in (clean .. "\n"):gmatch("([^\n]*)\n") do
        local statName, numStr
        -- Pattern 1: percent sign explicitly present; allow trailing punctuation/spaces.
        statName, numStr = line:match("^(.+):%s*(%d+)%%%D*$")
        if not statName then
            -- Pattern 2: no percent sign; allow trailing non-digit chars.
            statName, numStr = line:match("^(.+):%s*(%d+)%D*$")
            -- Exclude lines where the "number" is embedded in a longer word (e.g. version strings).
            if statName and line:match("^.+:%s*%d+%a") then
                statName = nil
                numStr = nil
            end
        end
        if statName and numStr then
            -- Trim any remaining whitespace from the stat name.
            statName = statName:match("^%s*(.-)%s*$")
            local val = tonumber(numStr)
            if val and val > 0 then
                local abbrev = GetBoonAbbrev(statName)
                stats[#stats + 1] = abbrev .. ": " .. val .. "%"
                dcslog("Debug", "GetBoonsDisplayText: matched stat=" .. statName .. " val=" .. val)
            end
        end
    end

    if #stats == 0 then return "None" end
    return table.concat(stats, ", ")
end

-------------------------------------------------------------------------------
-- AbbreviateLabel: Shorten a scenario criterion description to a compact label.
-- Strips common trailing action words (slain, destroyed, killed, kills, remaining)
-- then returns the last meaningful word, capitalised, truncated to 12 characters.
local function AbbreviateLabel(desc)
    -- Strip trailing action words (case-insensitive)
    local stripped = desc
        :gsub("%s+[Ss]lain$",     "")
        :gsub("%s+[Dd]estroyed$", "")
        :gsub("%s+[Kk]illed$",    "")
        :gsub("%s+[Kk]ills$",     "")
        :gsub("%s+[Rr]emaining$", "")
    -- Trim whitespace
    stripped = stripped:match("^%s*(.-)%s*$") or stripped
    -- Take the last word
    local lastWord = stripped:match("(%S+)%s*$") or stripped
    -- Capitalise first letter
    lastWord = lastWord:sub(1, 1):upper() .. lastWord:sub(2)
    -- Truncate to 12 characters
    if #lastWord > 12 then lastWord = lastWord:sub(1, 12) end
    return lastWord
end

-- IsCombatCriteria: Returns true only for combat/kill-type scenario criteria.
-- Filters out quest/interaction objectives (Speak with, Find, Collect, etc.)
-- so only enemy-kill trackers appear in the nemesis display.
local function IsCombatCriteria(description)
    if not description then return false end
    local desc = description:lower()
    -- Positive matches (combat/kill objectives)
    if desc:find("slain") or desc:find("killed") or desc:find("destroyed") or
       desc:find("defeated") or desc:find("enemy group") or desc:find("nemesis") then
        return true
    end
    -- Negative matches (interaction/quest objectives)
    if desc:find("^speak") or desc:find("^talk") or desc:find("^find ") or
       desc:find("^collect") or desc:find("^interact") or desc:find("^use ") or
       desc:find("^activate") or desc:find("^escort") or desc:find("^protect") or
       desc:find("^survive") or desc:find("^reach ") or desc:find("^enter ") then
        return false
    end
    -- Default: don't show ambiguous criteria
    return false
end
-- Expose for unit testing
ns.IsCombatCriteria = IsCombatCriteria

-- GetNemesisProgress: Returns nemesis enemy-group count from
-- C_Spell.GetSpellDescription(472952), which inside a delve contains a line:
--   "Enemy groups remaining: |cnWHITE_FONT_COLOR:X / Y|r"
-- Returns just the count "X / Y" (the header label provides the section title).
-- Returns "" if unavailable.
-------------------------------------------------------------------------------
GetNemesisProgress = function()
    if not C_Spell or not C_Spell.GetSpellDescription then return "" end
    local ok, desc = pcall(C_Spell.GetSpellDescription, 472952)
    if not ok or not desc or desc == "" then return "" end

    -- Strip WoW color codes: |cnNAME: ... |r
    local clean = desc:gsub("|cn[^:]+:", ""):gsub("|r", "")

    -- Extract "Enemy groups remaining: X / Y"
    local current, total = clean:match("Enemy groups remaining:%s*(%d+)%s*/%s*(%d+)")
    if not current or not total then return "" end

    return string.format("%s / %s", current, total)
end

-------------------------------------------------------------------------------
-- GetNemesisDetailText: Disabled — see GetNemesisProgress comment above.
-------------------------------------------------------------------------------
local function GetNemesisDetailText()
    return ""
end
ns.GetNemesisDetailText = GetNemesisDetailText

-------------------------------------------------------------------------------
-- UpdateCompanionData: Fetch active companion from C_DelvesUI and update UI
-- Uses fully dynamic API calls — no hardcoded faction ID lookup tables.
-- Called by event handlers and during initialization.
-------------------------------------------------------------------------------
function ns:UpdateCompanionData(event)
    if not ns.frame then return end

    dcslog("Debug", "UpdateCompanionData called, event=" .. tostring(event))

    -- Step 1: Get the active companion's faction ID directly (no args required)
    local factionID = nil
    if C_DelvesUI and C_DelvesUI.GetFactionForCompanion then
        local ok, result = pcall(C_DelvesUI.GetFactionForCompanion)
        if ok and result and result ~= 0 then
            factionID = result
        end
    end

    if not factionID then
        -- No active companion
        ns._lastFactionID = nil
        ns._lastName      = nil
        ns._lastLevel     = nil
        if ns.nameLabel       then ns.nameLabel:SetText("No Companion") end
        if ns.boonHeaderLabel then ns.boonHeaderLabel:Hide() end
        if ns.boonLabel       then ns.boonLabel:SetText(""); ns.boonLabel:Hide() end
        if ns.nemesisLabel    then ns.nemesisLabel:SetText(""); ns.nemesisLabel:Hide() end
        if ns.nemesisDetailLabel then ns.nemesisDetailLabel:SetText(""); ns.nemesisDetailLabel:Hide() end
        return
    end

    -- Step 2: Resolve companion name from faction data (dynamic — no lookup table)
    local name = "Unknown"
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, factionData = pcall(C_Reputation.GetFactionDataByID, factionID)
        if ok and factionData and factionData.name then
            name = factionData.name
        end
    end

    -- Step 3: Get companion level from friendship reputation
    local level = nil
    local friendData = nil
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local ok, fd = pcall(C_GossipInfo.GetFriendshipReputation, factionID)
        if ok and fd then
            friendData = fd
            level = fd.reaction or fd.standing
        end
    end

    -- Store last-known values for debug inspection
    ns._lastFactionID = factionID
    ns._lastName      = name
    ns._lastLevel     = level
    dcslog("Info", "UpdateCompanionData: factionID=" .. tostring(factionID) ..
           " name=" .. tostring(name) .. " level=" .. tostring(level))

    -- Update header title to show companion name dynamically
    if ns.headerTitle then
        ns.headerTitle:SetText(name)
    end

    -- Update UI — Line 1: "Level N  x/y (z%)" on nameLabel
    -- levelLabel and xpLabel are kept as hidden labels for backward-compat/testability

    -- Build level string
    local levelStr = ""
    if level then
        local lvlNum = tostring(level):gsub("^[Ll]evel%s+", "")
        levelStr = "Level " .. lvlNum
    end

    -- Build XP string with percentage
    local xpText = ""
    if friendData and friendData.standing and friendData.nextThreshold then
        local threshold = friendData.reactionThreshold or 0
        local currentXP = friendData.standing - threshold
        local maxXP = friendData.nextThreshold - threshold
        if maxXP > 0 then
            local pct = math.floor((currentXP / maxXP) * 100)
            xpText = FormatNumber(currentXP) .. "/" .. FormatNumber(maxXP) .. " (" .. pct .. "%)"
        end
    end

    local parts = {}
    if levelStr ~= "" then parts[#parts + 1] = levelStr end
    if xpText   ~= "" then parts[#parts + 1] = xpText end
    if ns.nameLabel then
        ns.nameLabel:SetText(table.concat(parts, "  "))
    end

    -- Boon display — header "Boons" (gold) + value "stat1, stat2" or "None" (white/grey).
    -- boonHeaderLabel is shown whenever a companion is active in a delve.
    -- boonLabel shows the value line returned by GetBoonsDisplayText().
    local boonsShown = false
    local boonText = GetBoonsDisplayText()
    -- Log whether boon text actually changed since the last update.  This makes
    -- it easy to diagnose stale-display bugs: if "boon CHANGED" never appears
    -- after collecting a boon the event/throttle path is the culprit; if it does
    -- appear but the UI looks wrong the rendering path needs attention.
    local prevBoonText = ns._lastBoonText
    if boonText ~= prevBoonText then
        dcslog("Debug", "UpdateCompanionData: boon CHANGED [" .. tostring(prevBoonText) .. "] -> [" .. tostring(boonText) .. "]")
        ns._lastBoonText = boonText
    else
        dcslog("Debug", "UpdateCompanionData: boon unchanged [" .. tostring(boonText) .. "]")
    end
    if ns.boonHeaderLabel then
        if boonText ~= "" then
            ns.boonHeaderLabel:Show()
        else
            ns.boonHeaderLabel:Hide()
        end
    end
    if ns.boonLabel then
        ns.boonLabel:SetText(boonText)
        if boonText == "" then
            ns.boonLabel:Hide()
        else
            boonsShown = true
            -- "None" is shown in grey/muted; actual stats in white
            if boonText == "None" then
                ns.boonLabel:SetTextColor(0.6, 0.6, 0.6, 1)
            else
                ns.boonLabel:SetTextColor(1, 1, 1, 1)
            end
            ns.boonLabel:Show()
        end
    end

    -- Nemesis display — header "Enemy Groups Remaining" (gold, nemesisLabel) +
    -- value "X / Y" (white, nemesisDetailLabel).
    local nemesisText = ""
    pcall(function() nemesisText = GetNemesisProgress() end)
    if ns.nemesisLabel then
        if nemesisText ~= "" then
            ns.nemesisLabel:SetText("Enemy Groups Remaining")
            ns.nemesisLabel:Show()
        else
            ns.nemesisLabel:SetText("")
            ns.nemesisLabel:Hide()
        end
    end
    if ns.nemesisDetailLabel then
        if nemesisText ~= "" then
            ns.nemesisDetailLabel:SetText(nemesisText)
            ns.nemesisDetailLabel:Show()
        else
            ns.nemesisDetailLabel:SetText("")
            ns.nemesisDetailLabel:Hide()
        end
    end

    -- Dynamic frame height based on visible content
    if ns.frame then
        -- Content frame: 8px top + nameLabel(16) + 4px bottom = 28px base
        local contentHeight = 28
        -- Boon section: 6px gap + header(16) + 4px gap + value(16)
        if ns.boonHeaderLabel and ns.boonHeaderLabel:IsShown() then
            contentHeight = contentHeight + 6 + 16
        end
        if ns.boonLabel and ns.boonLabel:IsShown() then
            contentHeight = contentHeight + 4 + 16
        end
        -- Nemesis section: 6px gap + header(16) + 4px gap + value(16)
        if ns.nemesisLabel and ns.nemesisLabel:IsShown() then
            contentHeight = contentHeight + 6 + 16
        end
        if ns.nemesisDetailLabel and ns.nemesisDetailLabel:IsShown() then
            contentHeight = contentHeight + 4 + 16
        end
        -- Resize contentFrame then total frame (header height + content, or header only when collapsed)
        if ns.contentFrame then ns.contentFrame:SetHeight(contentHeight) end
        local headerH = ns.headerFrame and ns.headerFrame:GetHeight() or 28
        if ns.contentFrame and ns.contentFrame:IsShown() then
            ns.frame:SetHeight(headerH + contentHeight)
        else
            ns.frame:SetHeight(headerH)
        end
    end

    -- Persist to SavedVariables
    if DelveCompanionStatsDB then
        DelveCompanionStatsDB.companionName  = name
        DelveCompanionStatsDB.companionLevel = level
    end
end
