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

-------------------------------------------------------------------------------
-- dcsprint: Write a coloured message to the chat frame (or print fallback)
-------------------------------------------------------------------------------
local function dcsprint(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffDCS:|r " .. tostring(msg))
    else
        print("|cff00ccffDCS:|r " .. tostring(msg))
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
-- across all phases of a delve run in TWW), with HasActiveDelve() as a
-- secondary fallback.
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
                table.insert(lines, ("  -> IsInDelve will return %s"):format(tostring(hadVal == true)))
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
                rank          = tostring(fr.friendshipRank  or "nil")
                standing      = tostring(fr.standing        or "nil")
                nextThreshold = tostring(fr.nextThreshold   or fr.reactionThreshold or "nil")
                table.insert(lines, ("C_GossipInfo.GetFriendshipReputation(%d) => {friendshipRank=%s, standing=%s, nextThreshold=%s, ...}"):format(
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
    -- Dump tooltip lines for spell 1280098 (source of boon stat values)
    table.insert(lines, "--- Tooltip for 1280098 ---")
    pcall(function()
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetSpellByID(1280098)
        for i = 1, GameTooltip:NumLines() do
            local left = _G["GameTooltipTextLeft" .. i]
            if left and left:GetText() then
                local rawText = left:GetText()
                table.insert(lines, ("  L%d: %s"):format(i, rawText))
                -- Debug: show raw captured stat name and its resolved abbreviation
                local rawStat, rawNum = rawText:match("^(.+): (%d+)%%.?%s*$")
                if rawStat then
                    table.insert(lines, ("    [boon] raw stat=%q  abbrev=%q"):format(
                        rawStat, GetBoonAbbrev(rawStat)))
                end
            end
        end
        GameTooltip:Hide()
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

        -- All initialization happens here, atomically, before any other events fire
        ns:OnLoad()
    end
end)

-------------------------------------------------------------------------------
-- UpdateFrameVisibility: Show or hide the frame based on active delve state.
-- Calls UpdateCompanionData when the frame transitions from hidden to shown.
-------------------------------------------------------------------------------
function ns:UpdateFrameVisibility()
    if not ns.frame then return end
    local wasShown = ns.frame:IsShown()
    if IsInDelve() then
        ns.frame:Show()
    else
        ns.frame:Hide()
    end
    if not wasShown and ns.frame:IsShown() then
        ns:UpdateCompanionData()
    end
end

-------------------------------------------------------------------------------
-- OnLoad: Frame creation + UI setup + SavedVars init + position restore
-- Called exactly once from ADDON_LOADED handler above.
-- Guard: if ns.frame already exists, skip (idempotent safety).
-------------------------------------------------------------------------------
function ns:OnLoad()
    -- Guard: idempotent — never initialize twice
    if ns.frame then return end

    -- 1. Initialize SavedVariables
    -- NOTE: Per WoW API docs, SavedVariables are guaranteed to be loaded
    -- by the time ADDON_LOADED fires for our addon.
    DelveCompanionStatsDB = DelveCompanionStatsDB or {}
    local db = DelveCompanionStatsDB

    -- Ensure schema fields exist (nil-safe defaults for future access)
    db.position       = db.position       -- keep existing or nil
    db.companionName  = db.companionName  -- keep existing or nil
    db.companionLevel = db.companionLevel -- keep existing or nil

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
        print("|cffff4444DelveCompanionStats:|r Could not create display frame. Addon disabled.")
        ns.frame = nil
        return
    end

    ns.frame = frameResult

    -- Apply Blizzard Dialog-box backdrop (pcall: guards against missing BackdropTemplate)
    pcall(function()
        ns.frame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        ns.frame:SetBackdropColor(0, 0, 0, 0.80)
        ns.frame:SetBackdropBorderColor(1, 1, 1, 0.5)
    end)

    -- Set frame strata and level to ensure visibility above other UI
    ns.frame:SetFrameStrata("DIALOG")
    ns.frame:SetFrameLevel(100)

    -- 3. Set size and default anchor (above ChatFrame1 when available)
    ns.frame:SetSize(240, 160)
    if ChatFrame1 then
        ns.frame:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 10)
    else
        ns.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 5, 130)
    end

    -- 4b. Create section header label ("Delve Companion")
    ns.headerLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ns.headerLabel:SetPoint("TOPLEFT", ns.frame, "TOPLEFT", 12, -8)
    ns.headerLabel:SetWidth(216)
    ns.headerLabel:SetJustifyH("LEFT")
    local headerFontOk = pcall(function() ns.headerLabel:SetFontObject("GameFontHighlight") end)
    if not headerFontOk or not ns.headerLabel:GetFont() then
        ns.headerLabel:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    end
    ns.headerLabel:SetTextColor(1.0, 0.85, 0.0, 1)
    ns.headerLabel:SetShadowOffset(2, -2)
    ns.headerLabel:SetShadowColor(0, 0, 0, 1)
    ns.headerLabel:SetText("Delve Companion")

    -- 5. Create name label (guarded: frame confirmed non-nil above)
    ns.nameLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.nameLabel:SetPoint("TOPLEFT", ns.headerLabel, "BOTTOMLEFT", 0, -4)
    ns.nameLabel:SetWidth(216)
    ns.nameLabel:SetJustifyH("LEFT")
    ns.nameLabel:SetTextColor(1, 1, 1, 1)
    local nameFontOk = pcall(function() ns.nameLabel:SetFontObject("GameFontNormal") end)
    if not nameFontOk or not ns.nameLabel:GetFont() then
        ns.nameLabel:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    end
    ns.nameLabel:SetText("No companion data")
    ns.nameLabel:SetShadowOffset(2, -2)
    ns.nameLabel:SetShadowColor(0, 0, 0, 1)

    -- 6. Create level label
    ns.levelLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.levelLabel:SetPoint("TOPLEFT", ns.nameLabel, "BOTTOMLEFT", 0, -4)
    ns.levelLabel:SetWidth(216)
    ns.levelLabel:SetJustifyH("LEFT")
    ns.levelLabel:SetTextColor(1, 1, 1, 1)
    local levelFontOk = pcall(function() ns.levelLabel:SetFontObject("GameFontNormal") end)
    if not levelFontOk or not ns.levelLabel:GetFont() then
        ns.levelLabel:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    end
    ns.levelLabel:SetText("")
    ns.levelLabel:SetShadowOffset(2, -2)
    ns.levelLabel:SetShadowColor(0, 0, 0, 1)

    -- 6b. Create XP label (below levelLabel)
    ns.xpLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.xpLabel:SetPoint("TOPLEFT", ns.levelLabel, "BOTTOMLEFT", 0, -4)
    ns.xpLabel:SetWidth(216)
    ns.xpLabel:SetJustifyH("LEFT")
    local xpFontOk = pcall(function() ns.xpLabel:SetFontObject("GameFontNormal") end)
    if not xpFontOk or not ns.xpLabel:GetFont() then
        ns.xpLabel:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    end
    ns.xpLabel:SetTextColor(1, 1, 1, 1)
    ns.xpLabel:SetShadowColor(0, 0, 0, 1)
    ns.xpLabel:SetShadowOffset(2, -2)
    ns.xpLabel:SetText("")

    -- 6c. Create boon label (below xpLabel)
    ns.boonLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.boonLabel:SetPoint("TOPLEFT", ns.xpLabel, "BOTTOMLEFT", 0, -4)
    local boonFontOk = pcall(function() ns.boonLabel:SetFontObject("GameFontNormal") end)
    if not boonFontOk or not ns.boonLabel:GetFont() then
        ns.boonLabel:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    end
    ns.boonLabel:SetWidth(216)
    ns.boonLabel:SetJustifyH("LEFT")
    ns.boonLabel:SetTextColor(1, 1, 1, 1)
    ns.boonLabel:SetShadowOffset(2, -2)
    ns.boonLabel:SetShadowColor(0, 0, 0, 1)
    ns.boonLabel:SetText("")

    -- 6d. Create nemesis label (below boonLabel)
    ns.nemesisLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.nemesisLabel:SetPoint("TOPLEFT", ns.boonLabel, "BOTTOMLEFT", 0, -4)
    local nemesisFontOk = pcall(function() ns.nemesisLabel:SetFontObject("GameFontNormal") end)
    if not nemesisFontOk or not ns.nemesisLabel:GetFont() then
        ns.nemesisLabel:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    end
    ns.nemesisLabel:SetWidth(216)
    ns.nemesisLabel:SetJustifyH("LEFT")
    ns.nemesisLabel:SetTextColor(1, 1, 1, 1)
    ns.nemesisLabel:SetShadowOffset(2, -2)
    ns.nemesisLabel:SetShadowColor(0, 0, 0, 1)
    ns.nemesisLabel:SetText("")

    -- 7. Make frame movable
    -- Safe: frame created above in this same function before drag handlers registered
    ns.frame:SetMovable(true)
    ns.frame:EnableMouse(true)
    ns.frame:RegisterForDrag("LeftButton")
    ns.frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    ns.frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        DelveCompanionStatsDB.position = {
            point         = point,
            relativePoint = relativePoint,
            x             = x,
            y             = y,
        }
    end)

    -- 8. Restore saved position (wrapped in pcall for corrupt SavedVariables safety)
    if db and db.position then
        local posOk = pcall(function()
            local p = db.position
            ns.frame:ClearAllPoints()
            ns.frame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
        end)
        -- posOk == false means corrupt position data; default anchor from step 3 remains
        if not posOk then dcsprint("Could not restore saved position; using default.") end
    end

    -- 9. Determine frame visibility based on active delve state
    ns:UpdateFrameVisibility()

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
        -- UNIT_AURA fires when buffs/debuffs change on a unit; used to detect
        -- when the boon aura (spell 1280098) becomes active after zone-in.
        ns.frame:RegisterEvent("UNIT_AURA")
        ns.frame:SetScript("OnEvent", function(self, event, ...)
            -- UNIT_AURA: only refresh boon data when player's own auras change in a delve.
            -- Avoids redundant updates for non-player units (party members, NPCs, etc.).
            if event == "UNIT_AURA" then
                local unitID = ...
                if unitID == "player" and IsInDelve() then
                    ns:UpdateCompanionData(event)
                end
                return
            end

            -- PLAYER_ENTERING_WORLD: run normal visibility + data update, then schedule
            -- two delayed refreshes so boons (which may not be applied immediately on
            -- zone-in) have time to activate before we query the tooltip.
            if event == "PLAYER_ENTERING_WORLD" then
                ns:UpdateFrameVisibility()
                if ns.frame:IsShown() then
                    ns:UpdateCompanionData(event)
                end
                if C_Timer and C_Timer.After then
                    C_Timer.After(2, function()
                        if IsInDelve() then ns:UpdateCompanionData("TIMER_2S_PEW") end
                    end)
                    C_Timer.After(5, function()
                        if IsInDelve() then ns:UpdateCompanionData("TIMER_5S_PEW") end
                    end)
                end
                return
            end

            -- All other events: refresh visibility then data.
            ns:UpdateFrameVisibility()
            if ns.frame:IsShown() then
                ns:UpdateCompanionData(event)
            end
        end)
    end

    -- Explicitly show fontstrings (belt-and-suspenders: ensures visibility even if parent Show() is pending)
    if ns.nameLabel then ns.nameLabel:Show() end
    if ns.levelLabel then ns.levelLabel:Show() end

    -- Polling fallbacks: data may not be ready immediately on ADDON_LOADED
    if C_Timer and C_Timer.After then
        C_Timer.After(3,  function() ns:UpdateCompanionData("TIMER_3S") end)
        C_Timer.After(5,  function() ns:UpdateCompanionData("TIMER_5S") end)
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
    ["Strength"]               = "Strength",
    ["Haste"]                  = "Haste",
    ["Critical Strike"]        = "Crit",
    ["Mastery"]                = "Mastery",
    ["Versatility"]            = "Vers",
    ["Reduce incoming damage"] = "Dmg Red",
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
-- GetBoonsDisplayText: Reads the tooltip for boon spell 1280098 and returns a
-- one-per-line summary of non-zero stats, e.g. "Max HP: 6%\nMove Spd: 10%".
-- Returns "" if no boon lines are found (hides the boon label).
-------------------------------------------------------------------------------
GetBoonsDisplayText = function()
    local parts = {}
    local ok = pcall(function()
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetSpellByID(1280098)
        local numLines = GameTooltip:NumLines()
        for i = 1, numLines do
            local lineText = _G["GameTooltipTextLeft"..i] and _G["GameTooltipTextLeft"..i]:GetText()
            -- Guard: if the tooltip still contains unresolved spell template variables
            -- (e.g. "$w1%"), the boon aura hasn't been applied yet; skip the line.
            if lineText and not lineText:find("%$w%d") then
                for subline in (lineText .. "\n"):gmatch("([^\n]*)\n") do
                    local stat, pct = subline:match("^(.+): (%d+)%%.?%s*$")
                    local n = tonumber(pct)
                    if stat and n and n > 0 then
                        local abbrev = GetBoonAbbrev(stat)
                        table.insert(parts, abbrev .. ": " .. n .. "%")
                    end
                end
            end
        end
        GameTooltip:Hide()
    end)
    if not ok or #parts == 0 then return "" end
    return table.concat(parts, "\n")
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

-- GetNemesisProgress: Returns all scenario criteria (totalQuantity > 0) as
-- separate "Label: X/Y" lines joined by "\n", or "" when no criteria exist.
-- Queries C_ScenarioInfo — shows every objective so the player has full context.
-------------------------------------------------------------------------------
GetNemesisProgress = function()
    if not C_ScenarioInfo or not C_ScenarioInfo.GetScenarioStepInfo then return "" end
    local stepInfo = C_ScenarioInfo.GetScenarioStepInfo()
    if not stepInfo or not stepInfo.numCriteria then return "" end

    local lines = {}
    for i = 1, stepInfo.numCriteria do
        local ok, c = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if ok and c and c.totalQuantity and c.totalQuantity > 0 then
            local label = (c.description and AbbreviateLabel(c.description)) or ("Obj" .. i)
            table.insert(lines, label .. ": " .. tostring(c.quantity) .. "/" .. tostring(c.totalQuantity))
        end
    end
    return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------
-- UpdateCompanionData: Fetch active companion from C_DelvesUI and update UI
-- Uses fully dynamic API calls — no hardcoded faction ID lookup tables.
-- Called by event handlers and during initialization.
-------------------------------------------------------------------------------
function ns:UpdateCompanionData(event)
    if not ns.frame then return end

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
        if ns.nameLabel then ns.nameLabel:SetText("No Companion") end
        if ns.levelLabel then ns.levelLabel:SetText("") end
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
            level = fd.friendshipRank or fd.reaction or fd.standing
        end
    end

    -- Store last-known values for debug inspection
    ns._lastFactionID = factionID
    ns._lastName      = name
    ns._lastLevel     = level

    -- Update UI
    if ns.nameLabel then
        ns.nameLabel:SetText(name)
    end
    if ns.levelLabel then
        if level then
            -- Strip any existing "Level " prefix the API may have returned before prepending
            local levelStr = tostring(level):gsub("^[Ll]evel%s+", "")
            ns.levelLabel:SetText("Level " .. levelStr)
        else
            ns.levelLabel:SetText("")
        end
    end

    -- XP display (currentXP = standing - reactionThreshold, maxXP = nextThreshold - reactionThreshold)
    if ns.xpLabel then
        local xpText = ""
        if friendData and friendData.standing and friendData.reactionThreshold
            and friendData.nextThreshold
            and friendData.nextThreshold > friendData.reactionThreshold then
            local currentXP = friendData.standing - friendData.reactionThreshold
            local maxXP     = friendData.nextThreshold - friendData.reactionThreshold
            local percent = math.floor((currentXP / maxXP) * 100)
            xpText = FormatNumber(currentXP) .. " / " .. FormatNumber(maxXP) .. " XP (" .. percent .. "%)"
        end
        ns.xpLabel:SetText(xpText)
    end

    -- Boon display
    if ns.boonLabel then
        local boonText = GetBoonsDisplayText()
        ns.boonLabel:SetText(boonText)
        if boonText == "" then
            ns.boonLabel:Hide()
        else
            ns.boonLabel:Show()
        end
    end

    -- Nemesis progress display
    if ns.nemesisLabel then
        local nemesisText = GetNemesisProgress()
        ns.nemesisLabel:SetText(nemesisText)
        if nemesisText == "" then
            ns.nemesisLabel:Hide()
        else
            ns.nemesisLabel:Show()
        end
    end

    -- Dynamic frame height based on visible content
    if ns.frame then
        -- Base: top-pad(8) + header(20) + gap(4) + name(18) + gap(4) + level(18) + gap(4) + xp(18) + gap(4) + bottom-pad(8) ≈ 100
        local height = 100
        -- Count boon lines (each separated by \n)
        if ns.boonLabel and ns.boonLabel:IsShown() then
            local boonText = ns.boonLabel:GetText() or ""
            local _, newlines = boonText:gsub("\n", "\n")
            height = height + (newlines + 1) * 16
        end
        -- Nemesis label (may be multi-line)
        if ns.nemesisLabel and ns.nemesisLabel:IsShown() then
            local nemText = ns.nemesisLabel:GetText() or ""
            local _, newlines = nemText:gsub("\n", "\n")
            height = height + (newlines + 1) * 16
        end
        ns.frame:SetHeight(height)
    end

    -- Persist to SavedVariables
    if DelveCompanionStatsDB then
        DelveCompanionStatsDB.companionName  = name
        DelveCompanionStatsDB.companionLevel = level
    end
end
