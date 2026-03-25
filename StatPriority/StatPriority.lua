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

local FONT_PATH = "Fonts\\FRIZQT__.TTF"

-------------------------------------------------------------------------------
-- splog: Structured logging via CouchPotatoLog. Falls back gracefully.
-------------------------------------------------------------------------------
-- Delegates to shared CreateLogger when available; inline fallback otherwise.
local splog = (_G.CouchPotatoShared and _G.CouchPotatoShared.CreateLogger)
    and _G.CouchPotatoShared.CreateLogger("SP")
    or function(level, msg)
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
    if not GetSpecializationInfo then return 0 end
    local specID = select(1, GetSpecializationInfo(specIndex))
    splog("Debug", "GetDisplaySpecID: resolved specID=" .. tostring(specID) .. " from specIndex=" .. tostring(specIndex))
    return specID
end

-------------------------------------------------------------------------------
-- formatStatPriority: Formats a stat priority array into a display string.
-- Top-level entries are joined with " > " (gold colour).
-- Sub-array entries (tables) represent equal-priority stats joined with " = ".
-------------------------------------------------------------------------------
local function formatStatPriority(statsArray)
    local gtSep = " |cffFFD100>|r "
    local eqSep = " |cffFFD100=|r "
    local parts = {}
    for _, entry in ipairs(statsArray) do
        if type(entry) == "table" then
            parts[#parts + 1] = table.concat(entry, eqSep)
        else
            parts[#parts + 1] = entry
        end
    end
    return table.concat(parts, gtSep)
end

-------------------------------------------------------------------------------
-- GetStatValue: Returns a formatted string for the given stat abbreviation.
-- Primary stats (Str, Agil, Int) return comma-formatted integers.
-- Secondary stats (Haste, Crit, Mast, Vers) return "%.1f%%" percentages.
-- Returns "?" if the API is unavailable.
-------------------------------------------------------------------------------
local function commaFormat(n)
    local val = math.floor(n + 0.5)
    local sign = val < 0 and "-" or ""
    local s = tostring(math.abs(val))
    local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. result
end

local function GetStatValue(statAbbrev)
    local ok, val
    if statAbbrev == "Str" then
        ok, val = pcall(function() return UnitStat("player", 1) end)
        if ok and val then return commaFormat(val) end
    elseif statAbbrev == "Agil" then
        ok, val = pcall(function() return UnitStat("player", 2) end)
        if ok and val then return commaFormat(val) end
    elseif statAbbrev == "Int" then
        ok, val = pcall(function() return UnitStat("player", 4) end)
        if ok and val then return commaFormat(val) end
    elseif statAbbrev == "Haste" then
        ok, val = pcall(function() return GetHaste() end)
        if ok and val then return string.format("%.1f%%", val) end
    elseif statAbbrev == "Crit" then
        ok, val = pcall(function() return GetCritChance() end)
        if ok and val then return string.format("%.1f%%", val) end
    elseif statAbbrev == "Mast" then
        ok, val = pcall(function() return GetMasteryEffect() end)
        if ok and val then return string.format("%.1f%%", val) end
    elseif statAbbrev == "Vers" then
        ok, val = pcall(function()
            return GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
        end)
        if ok and val then return string.format("%.1f%%", val) end
    else
        splog("Warn", "GetStatValue: unrecognized stat abbreviation: " .. tostring(statAbbrev))
        return "?"
    end
    return "?"
end

-- Expose for tests
_G.StatPriorityGetStatValue = GetStatValue

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
            -- Join stats with gold ">" separator (equal-priority groups use "=")
            statsText = formatStatPriority(data.stats)
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

    if data and data._differs then
        splog("Info", "Display mode: multi-source (sources differ), specID=" .. tostring(data and data.specName))
        -- Multi-source display
        if ns.statsLabel then ns.statsLabel:Hide() end

        if ns.wowheadLabel then
            local text = "|cff00ccffWowhead:|r " .. formatStatPriority(data.wowhead)
            ns.wowheadLabel:SetText(text)
            ns.wowheadLabel:Show()
        end
        if ns.icyveinsLabel then
            local text = "|cff33cc33Icy Veins:|r " .. formatStatPriority(data.icyveins)
            ns.icyveinsLabel:SetText(text)
            ns.icyveinsLabel:Show()
        end
        if ns.methodLabel then
            local text = "|cffff6600Method:|r " .. formatStatPriority(data.method)
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
        splog("Info", "Display mode: unified (single source or no data) — circle display")

        -- Hide legacy text label; circles are used instead
        if ns.statsLabel then ns.statsLabel:Hide() end

        if ns.wowheadLabel  then ns.wowheadLabel:Hide()  end
        if ns.icyveinsLabel then ns.icyveinsLabel:Hide() end
        if ns.methodLabel   then ns.methodLabel:Hide()   end

        if ns.wowheadUrlBtn  then ns.wowheadUrlBtn:Hide()  end
        if ns.icyveinsUrlBtn then ns.icyveinsUrlBtn:Hide() end
        if ns.methodUrlBtn   then ns.methodUrlBtn:Hide()   end

        -- Build flattened list of { statName, connector } pairs for circle layout.
        -- connector is ">" (different priority) or "=" (equal priority, sub-array).
        local circleStats = {}   -- list of stat name strings
        local connectors  = {}   -- connectors[i] = symbol between circle i and i+1
        if data and data.stats then
            do
                local ci = 0
                circleStats  = {}
                connectors   = {}
                local numEntries = #data.stats
                for ei, entry in ipairs(data.stats) do
                    if type(entry) == "table" then
                        for j, subStat in ipairs(entry) do
                            ci = ci + 1
                            circleStats[ci] = subStat
                            if j < #entry then
                                connectors[ci] = "="   -- "=" within the group
                            elseif ei < numEntries then
                                connectors[ci] = ">"   -- ">" after last in group
                            end
                        end
                    else
                        ci = ci + 1
                        circleStats[ci] = entry
                        if ei < numEntries then
                            connectors[ci] = ">"
                        end
                    end
                end
            end
        end

        local numCircles = #circleStats
        splog("Debug", "Circle display: " .. tostring(numCircles) .. " circles")

        -- Show/hide circles and connectors
        if ns.statCircles then
            for i = 1, #ns.statCircles do
                local circ = ns.statCircles[i]
                if i <= numCircles then
                    local sName = circleStats[i]
                    circ.nameFS:SetText(sName)
                    circ.valueFS:SetText(GetStatValue(sName))
                    circ.frame:Show()
                else
                    circ.frame:Hide()
                end
            end
        end
        if ns.statConnectors then
            for i = 1, #ns.statConnectors do
                local conn = ns.statConnectors[i]
                if connectors[i] then
                    conn:SetText(connectors[i])
                    conn:Show()
                else
                    conn:Hide()
                end
            end
        end
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
        local contentH
        -- Multi-source mode: count visible source lines
        if (ns.wowheadLabel and ns.wowheadLabel:IsShown()) or
           (ns.icyveinsLabel and ns.icyveinsLabel:IsShown()) or
           (ns.methodLabel and ns.methodLabel:IsShown()) then
            local visibleLines = 0
            if ns.wowheadLabel  and ns.wowheadLabel:IsShown()  then visibleLines = visibleLines + 1 end
            if ns.icyveinsLabel and ns.icyveinsLabel:IsShown() then visibleLines = visibleLines + 1 end
            if ns.methodLabel   and ns.methodLabel:IsShown()   then visibleLines = visibleLines + 1 end
            if visibleLines == 0 then visibleLines = 1 end
            contentH = visibleLines * 20 + 16
        -- Unified circle display: fixed height for circles (52px visual diameter + padding)
        elseif ns.statCircles then
            contentH = 62
        -- Legacy text label (fallback)
        elseif ns.statsLabel and ns.statsLabel:IsShown() then
            contentH = 36
        else
            contentH = 62  -- default circle height
        end
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
    fs:SetFont(FONT_PATH, 11, "OUTLINE")
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
-- GetTrackerAnchor: Returns the best anchor frame for StatPriority to dock
-- below.  The anchor chain is:
--
--   SmartTrackerBottom (lowest visible tracker module, or ObjectiveTrackerFrame)
--     → DelveCompanionStatsFrame (if shown, dock below it instead)
--       → StatPriority (docks below DCS)
--
-- This prevents StatPriority and DelveCompanionStats from overlapping when
-- both are visible at the bottom of the quest tracker.
--
-- Strategy (WoW 12.x):
--   1. If DelveCompanionStatsFrame exists and is shown, anchor below it.
--   2. Otherwise use smart tracker anchor logic:
--      a. Iterate ObjectiveTrackerFrame.modules to find the lowest visible module.
--      b. Fall back to known named module globals.
--      c. Final fallback: ObjectiveTrackerFrame itself.
--   3. Returns nil when no tracker is visible at all.
-------------------------------------------------------------------------------
local function GetTrackerAnchor()
    -- 1. Chain anchor: if DelveCompanionStatsFrame is visible, dock below it.
    local dcsFrame = _G.DelveCompanionStatsFrame
    if dcsFrame and dcsFrame.IsShown and dcsFrame:IsShown() then
        splog("Info", "GetTrackerAnchor: DelveCompanionStatsFrame is visible — anchoring SP below DCS (chain: OT→DCS→SP)")
        return dcsFrame
    end
    splog("Debug", "GetTrackerAnchor: DelveCompanionStatsFrame not visible — using smart tracker anchor")

    -- 2. Delegate to shared utility when available.
    if _G.CouchPotatoShared and _G.CouchPotatoShared.GetBaseTrackerAnchor then
        local anchor = _G.CouchPotatoShared.GetBaseTrackerAnchor()
        if anchor then
            splog("Info", "GetTrackerAnchor: resolved via CouchPotatoShared.GetBaseTrackerAnchor")
        else
            splog("Debug", "GetTrackerAnchor: shared utility returned nil")
        end
        return anchor
    end

    -- Inline fallback (kept for resilience if CouchPotato core not loaded)
    -- ObjectiveTrackerFrame is ALWAYS the final fallback when the frame exists —
    -- even when IsShown() returns false (e.g. no quests tracked outside a delve).
    if not ObjectiveTrackerFrame then
        splog("Debug", "GetTrackerAnchor: ObjectiveTrackerFrame not available — returning nil")
        return nil
    end
    local trackerShown = ObjectiveTrackerFrame.IsShown
                         and ObjectiveTrackerFrame:IsShown()
    if trackerShown then
        if ObjectiveTrackerFrame.modules then
            local bestFrame, bestBottom = nil, math.huge
            for _, module in ipairs(ObjectiveTrackerFrame.modules) do
                if module and module.IsShown and module:IsShown() then
                    local f = (module.ContentsFrame and module.ContentsFrame.IsShown
                               and module.ContentsFrame:IsShown() and module.ContentsFrame)
                              or (module.Header and module.Header.IsShown
                                  and module.Header:IsShown() and module.Header)
                              or module
                    if f and f.GetBottom then
                        local bottom = f:GetBottom()
                        if bottom and bottom < bestBottom then
                            bestBottom = bottom
                            bestFrame  = f
                        end
                    end
                end
            end
            if bestFrame then
                splog("Info", "GetTrackerAnchor: found lowest module via .modules table")
                return bestFrame
            end
        end
        local knownModules = {
            "ScenarioObjectiveTracker", "QuestObjectiveTracker",
            "BonusObjectiveTracker", "WorldQuestObjectiveTracker",
            "CampaignQuestObjectiveTracker", "ProfessionsObjectiveTracker",
            "AdventureObjectiveTracker", "AchievementObjectiveTracker",
        }
        local bestFrame, bestBottom = nil, math.huge
        for _, name in ipairs(knownModules) do
            local f = _G[name]
            if f and f.IsShown and f:IsShown() and f.GetBottom then
                local bottom = f:GetBottom()
                if bottom and bottom < bestBottom then
                    bestBottom = bottom
                    bestFrame  = f
                end
            end
        end
        if bestFrame then
            splog("Info", "GetTrackerAnchor: found lowest module via named globals")
            return bestFrame
        end
    end
    splog("Info", "GetTrackerAnchor: using ObjectiveTrackerFrame as anchor")
    return ObjectiveTrackerFrame
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
    -- Use MEDIUM strata at a low frame level so the frame sits at the same rendering
    -- layer as the objective tracker content (also MEDIUM) but below Blizzard's own
    -- tracker text which uses higher frame levels within MEDIUM.  LOW strata caused
    -- the frames to render behind quest text while still overlapping it positionally.
    ns.frame:SetFrameStrata("MEDIUM")
    ns.frame:SetFrameLevel(1)
    ns.frame:SetMovable(true)
    splog("Info", "Frame created successfully: StatPriorityFrame")

    -- Match the ObjectiveTrackerFrame width (the outer auto-sizing tracker container),
    -- then fall back to ScenarioObjectiveTracker, then hardcoded 248 px.
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
        frameWidth = 248
    end
    local contentWidth = frameWidth - 12
    splog("Info", "OnLoad: frameWidth=" .. tostring(frameWidth))

    ns.frame:SetSize(frameWidth, 60)

    -- -----------------------------------------------------------------------
    -- 3. Header frame — matches Blizzard ObjectiveTracker section header precisely.
    -- Dark semi-transparent background bar, larger gold text, full-width gold underline.
    -- -----------------------------------------------------------------------
    local header = CreateFrame("Button", nil, ns.frame)
    ns.headerFrame = header
    header:SetHeight(26)
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
            local point, _, relativePoint, x, y = ns.frame:GetPoint()
            StatPriorityDB.position = { point = point, relativePoint = relativePoint, x = x, y = y }
            splog("Info", "Frame position saved: point=" .. tostring(point) ..
                  " relativePoint=" .. tostring(relativePoint) ..
                  " x=" .. tostring(x) .. " y=" .. tostring(y))
        end
    end)

    -- Dark semi-transparent background bar — matches Blizzard ObjectiveTracker section headers.
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(header)
    headerBg:SetColorTexture(0, 0, 0, 0.5)

    -- Title: GameFontNormalLarge (14pt) matching Blizzard tracker header size.
    -- Try ObjectiveTitleFont first (exact Blizzard font); fall back to GameFontNormalLarge.
    local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pcall(function() headerTitle:SetFontObject(ObjectiveTitleFont) end)
    headerTitle:SetPoint("LEFT", header, "LEFT", 8, 0)
    headerTitle:SetJustifyV("MIDDLE")
    headerTitle:SetText("Stat Priority")
    headerTitle:SetTextColor(1, 0.82, 0.0, 1)
    ns.headerTitle = headerTitle
    ns.headerLabel = headerTitle  -- alias

    -- Collapse button: gold en-dash, far right.
    -- Created BEFORE the gold lines so the lines can anchor to the header edges.
    -- Sized at 36x36 for easy clicking.
    local collapseBtn = CreateFrame("Button", nil, header)
    collapseBtn:SetSize(36, 36)
    collapseBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)

    -- Gold line: full width across the TOP of the header bar.
    local headerTopLine = header:CreateTexture(nil, "ARTWORK")
    headerTopLine:SetHeight(1)
    headerTopLine:SetPoint("TOPLEFT",  header, "TOPLEFT",  0, 0)
    headerTopLine:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    headerTopLine:SetColorTexture(0.9, 0.75, 0.1, 0.8)

    -- Gold line: full width across the BOTTOM of the header bar — from left edge to right edge.
    -- Matches Blizzard's ObjectiveTracker section headers exactly.
    local headerBottomLine = header:CreateTexture(nil, "ARTWORK")
    headerBottomLine:SetHeight(1)
    headerBottomLine:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT",  0, 0)
    headerBottomLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerBottomLine:SetColorTexture(0.9, 0.75, 0.1, 0.8)
    local collapseBtnText = collapseBtn:CreateFontString(nil, "OVERLAY")
    collapseBtnText:SetFont(FONT_PATH, 16, "OUTLINE")
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
    -- the frame is docked below visible tracker content (locked/pinned) or freely
    -- draggable (unlocked/unpinned). Default: pinned (locked icon).
    -- Sized at 26x26 (at least 10px larger than the old 16x16) for easy clicking.
    local pinBtn = CreateFrame("Button", nil, header)
    pinBtn:SetSize(26, 26)
    pinBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -4, 0)
    pinBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
    pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
    pinBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    pinBtn:EnableMouse(true)
    ns.pinBtn = pinBtn
    splog("Debug", "Pin button created: 26x26, LEFT of collapseBtn")

    -- ApplyPinnedState: anchor frame below visible tracker content, disable dragging, lock icon.
    -- GetTrackerAnchor() returns the last visible tracker sub-module (not the full container)
    -- so we dock to the bottom of actual visible quest/scenario content, not the frame boundary.
    local function ApplyPinnedState()
        ns.frame:SetMovable(false)
        local anchor = GetTrackerAnchor()
        ns.frame:ClearAllPoints()
        if anchor then
            -- Use a tight -2px gap when docking directly below DCS (both frames
            -- have gold headers that visually touch).  Use -14px for all other
            -- anchors (tracker modules, ObjectiveTrackerFrame) to match the same
            -- spacing that DCS itself uses when docking below the tracker.
            local gap = (anchor == _G.DelveCompanionStatsFrame) and -2 or -14
            ns.frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, gap)
            -- Match width to the anchor: DCS width, or ObjectiveTrackerFrame width
            local widthSource = (anchor == _G.DelveCompanionStatsFrame) and _G.DelveCompanionStatsFrame or ObjectiveTrackerFrame
            if widthSource and widthSource.GetWidth then
                local tw = widthSource:GetWidth()
                if tw and tw >= 100 and tw <= 400 then
                    ns.frame:SetWidth(tw)
                end
            end
            local anchorName = (anchor.GetName and anchor:GetName()) or tostring(anchor)
            splog("Info", "ApplyPinnedState: anchored to tracker visible-content bottom (anchor=" .. tostring(anchorName) .. ") gap=" .. tostring(gap))
        else
            ns.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
            splog("Info", "ApplyPinnedState: no tracker visible — parked TOPRIGHT fallback")
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

    pinBtn:SetScript("OnClick", function(self)
        local db = StatPriorityDB or {}
        if db.pinned == false then
            -- Currently unpinned -> pin
            db.pinned = true
            StatPriorityDB = db
            ns.ApplyPinnedState()
        else
            -- Currently pinned -> unpin
            db.pinned = false
            StatPriorityDB = db
            ns.ApplyUnpinnedState()
        end
        splog("Info", "Pin toggled: pinned=" .. tostring(db.pinned))
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
    contentFrame:SetPoint("TOPLEFT",  header, "BOTTOMLEFT",  0, -2)
    contentFrame:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    contentFrame:SetHeight(36)
    -- No visible backdrop — content text floats on transparent background matching
    -- Blizzard's ObjectiveTracker content area (no box, no border, no background panel).
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
    -- 5a-ii. Circle pool for unified stat display (7 circles + 6 connectors)
    -- Circles are 46px container frames.  Two layered Indicator textures produce
    -- a filled circle with a gold ring border:
    --   • ring  (BORDER layer): Indicator-Gray tinted gold at 54px — bleeds 4px
    --     outside the container on each side, giving the gold border effect.
    --   • fill  (ARTWORK layer): Indicator-Gray at 42px — ARTWORK draws on top of
    --     BORDER, leaving the 6px gold rim visible around the dark fill.
    -- Both textures are true filled circles so they composite cleanly.
    -- MiniMap-TrackingBorder is intentionally avoided: it has an arrow pointer
    -- and non-standard UV mapping that renders incorrectly at badge sizes.
    -- Layout: 5×46 + 4×8 = 262px fits in ~260px usable content width.
    -- -----------------------------------------------------------------------
    local circleSize    = 46
    local connectorW    = 8
    local circleSpacing = circleSize + connectorW  -- 54px per slot
    local circleOffsetY = -7  -- top padding inside content frame

    local statCircles    = {}
    local statConnectors = {}

    for i = 1, 7 do
        local x = 4 + (i - 1) * circleSpacing

        -- Container frame for this circle badge
        local circ = CreateFrame("Frame", nil, contentFrame)
        circ:SetSize(circleSize, circleSize)
        circ:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", x, circleOffsetY)

        -- Gold ring: BORDER layer so it renders strictly below ARTWORK.
        -- Indicator-Gray tinted bright gold gives a clean circle shape.
        -- 54px into a 46px frame bleeds 4px on each side — the exposed
        -- rim is the visible gold ring border.
        local ring = circ:CreateTexture(nil, "BORDER")
        ring:SetSize(54, 54)
        ring:SetPoint("CENTER", circ, "CENTER", 0, 0)
        ring:SetTexture("Interface\\COMMON\\Indicator-Gray")
        ring:SetVertexColor(1, 0.82, 0, 1)  -- bright gold, full alpha

        -- Dark fill: ARTWORK layer renders on top of BORDER, guaranteeing
        -- the 6px gold rim (3px each side) stays visible.
        local bg = circ:CreateTexture(nil, "ARTWORK")
        bg:SetSize(42, 42)
        bg:SetPoint("CENTER", circ, "CENTER", 0, 0)
        bg:SetTexture("Interface\\COMMON\\Indicator-Gray")
        bg:SetVertexColor(0.08, 0.06, 0.02, 0.95)

        -- Stat abbreviation: upper half of circle, anchored to CENTER +8px
        local nameFS = circ:CreateFontString(nil, "OVERLAY")
        nameFS:SetFont(FONT_PATH, 9, "OUTLINE")
        nameFS:SetPoint("CENTER", circ, "CENTER", 0, 8)
        nameFS:SetJustifyH("CENTER")
        nameFS:SetJustifyV("MIDDLE")
        nameFS:SetTextColor(1, 0.82, 0, 1)
        nameFS:SetText("")

        -- Stat value: lower half of circle, anchored to CENTER -7px
        local valueFS = circ:CreateFontString(nil, "OVERLAY")
        valueFS:SetFont(FONT_PATH, 8, "OUTLINE")
        valueFS:SetPoint("CENTER", circ, "CENTER", 0, -7)
        valueFS:SetJustifyH("CENTER")
        valueFS:SetJustifyV("MIDDLE")
        valueFS:SetTextColor(1, 1, 1, 1)
        valueFS:SetText("")

        circ:Hide()  -- hidden until UpdateStatPriority populates it

        statCircles[i] = { frame = circ, nameFS = nameFS, valueFS = valueFS }
    end
    ns.statCircles = statCircles

    -- Connector FontStrings: one between each pair of circles
    for i = 1, 6 do
        local x = 4 + (i - 1) * circleSpacing + circleSize + 1
        local conn = contentFrame:CreateFontString(nil, "OVERLAY")
        conn:SetFont(FONT_PATH, 10, "OUTLINE")
        conn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", x, circleOffsetY - (circleSize / 2 - 7))
        conn:SetWidth(connectorW)
        conn:SetJustifyH("CENTER")
        conn:SetJustifyV("MIDDLE")
        conn:SetTextColor(1, 0.82, 0, 1)
        conn:SetText(">")
        conn:Hide()
        statConnectors[i] = conn
    end
    ns.statConnectors = statConnectors
    splog("Debug", "Circle pool created: 7 circles + 6 connectors")

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
    urlTitle:SetFont(FONT_PATH, 11, "OUTLINE")
    urlTitle:SetPoint("TOPLEFT", urlPopup, "TOPLEFT", 10, -10)
    urlTitle:SetTextColor(1, 0.82, 0.0, 1)
    urlTitle:SetText("Copy URL (Ctrl+C):")

    -- EditBox for URL
    local editBox = CreateFrame("EditBox", nil, urlPopup)
    editBox:SetPoint("TOPLEFT",  urlPopup, "TOPLEFT",  10, -26)
    editBox:SetPoint("TOPRIGHT", urlPopup, "TOPRIGHT", -10, -26)
    editBox:SetHeight(20)
    editBox:SetFontObject("GameFontHighlightSmall")
    pcall(function() editBox:SetFont(FONT_PATH, 11, "") end)
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
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
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
            -- Support both canonical key (relativePoint) and legacy key (relPoint)
            ns.frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.relPoint or pos.point,
                              pos.x or 0, pos.y or 0)
            splog("Info", "Pin restore: unpinned — restored saved position point=" .. tostring(pos.point) ..
                  " x=" .. tostring(pos.x) .. " y=" .. tostring(pos.y))
        else
            ns.frame:ClearAllPoints()
            ns.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
            splog("Debug", "No saved position for unpinned state, using default TOPRIGHT")
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
            -- Same gap logic as ApplyPinnedState: -2px below DCS, -14px otherwise.
            local gap = (anchor == _G.DelveCompanionStatsFrame) and -2 or -14
            ns.frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, gap)
            local anchorName = (anchor.GetName and anchor:GetName()) or tostring(anchor)
            splog("Info", "Pin restore: pinned — anchored to tracker visible-content bottom (anchor=" .. tostring(anchorName) .. ") gap=" .. tostring(gap))
        else
            -- Tracker not visible yet — park on right side of screen until
            -- PLAYER_ENTERING_WORLD fires and re-anchors properly.
            ns.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
            splog("Info", "Pin restore: pinned but no tracker — parked TOPRIGHT fallback")
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
        -- Suppress all event handling if functionally disabled via /cp disable
        if ns._cpDisabled then return end
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

    -- -----------------------------------------------------------------------
    -- 9c. Register for stat value change events to refresh circle values.
    --     UNIT_STATS fires when primary stats change (gear swap, buffs).
    --     COMBAT_RATING_UPDATE fires when secondary stats change.
    -- -----------------------------------------------------------------------
    local statEventFrame = CreateFrame("Frame")
    statEventFrame:RegisterEvent("UNIT_STATS")
    statEventFrame:RegisterEvent("COMBAT_RATING_UPDATE")
    statEventFrame:SetScript("OnEvent", function(self, event, unit)
        if ns._cpDisabled then return end
        -- UNIT_STATS passes the unit; only refresh for the player
        if event == "UNIT_STATS" and unit ~= "player" then return end
        splog("Debug", "Stat event: " .. event .. " — refreshing circle values")
        -- Only refresh values in the circles; no need to rebuild the full layout
        if ns.statCircles then
            for _, circ in ipairs(ns.statCircles) do
                if circ.frame:IsShown() then
                    local sName = circ.nameFS:GetText()
                    if sName and sName ~= "" then
                        circ.valueFS:SetText(GetStatValue(sName))
                    end
                end
            end
        end
    end)
    ns.statEventFrame = statEventFrame
    splog("Debug", "Registered for UNIT_STATS, COMBAT_RATING_UPDATE (circle value refresh)")

    -- -----------------------------------------------------------------------
    -- 9b. Re-anchor when tracker content changes.
    --     QUEST_WATCH_LIST_CHANGED fires when quests are added/removed from the
    --     tracker, which can change which module is last-visible.  We do a short
    --     delayed re-anchor so the tracker has time to finish its own layout.
    --     PLAYER_ENTERING_WORLD covers zone transitions (tracker resets).
    -- -----------------------------------------------------------------------
    local function ReAnchorIfPinned()
        if ns._cpDisabled then return end
        if StatPriorityDB and StatPriorityDB.pinned ~= false then
            splog("Debug", "ReAnchorIfPinned: pinned=true — re-applying anchor")
            ns.ApplyPinnedState()
        end
    end

    local anchorEventFrame = CreateFrame("Frame")
    anchorEventFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    anchorEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Additional re-anchor triggers: world quests / bonus objectives appearing
    -- when entering a zone can shift tracker height without a QUEST_WATCH_LIST_CHANGED.
    anchorEventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    anchorEventFrame:RegisterEvent("QUEST_POI_UPDATE")
    pcall(function() anchorEventFrame:RegisterEvent("QUEST_ACCEPTED") end)
    pcall(function() anchorEventFrame:RegisterEvent("QUEST_REMOVED") end)
    pcall(function() anchorEventFrame:RegisterEvent("SCENARIO_UPDATE") end)
    pcall(function() anchorEventFrame:RegisterEvent("TRACKED_ACHIEVEMENT_UPDATE") end)
    anchorEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    local _spReanchorPending = false
    anchorEventFrame:SetScript("OnEvent", function(self, event)
        if ns._cpDisabled then return end
        if _spReanchorPending then return end
        _spReanchorPending = true
        splog("Debug", "ReAnchor event: " .. event .. " — scheduling delayed re-anchor")
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, function()
                _spReanchorPending = false
                ReAnchorIfPinned()
            end)
        else
            _spReanchorPending = false
            ReAnchorIfPinned()
        end
    end)
    ns.anchorEventFrame = anchorEventFrame
    splog("Debug", "Registered for QUEST_WATCH_LIST_CHANGED, PLAYER_ENTERING_WORLD, QUEST_LOG_UPDATE, QUEST_POI_UPDATE, QUEST_ACCEPTED, QUEST_REMOVED, SCENARIO_UPDATE, TRACKED_ACHIEVEMENT_UPDATE, ZONE_CHANGED_NEW_AREA (re-anchor)")

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

        -- Check if this addon is functionally disabled via CouchPotato suite
        if _G.CouchPotatoDB and _G.CouchPotatoDB.addonStates and
           _G.CouchPotatoDB.addonStates.StatPriority == false then
            splog("Info", "StatPriority is disabled via /cp disable — skipping init")
            ns._cpDisabled = true
            return
        end

        ns:OnLoad()
    end
end)
