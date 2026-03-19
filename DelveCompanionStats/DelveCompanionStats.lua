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
            tinsert(linesTable, labelName .. " => nil (label not created)")
            return
        end
        local okText, txt = pcall(function() return label:GetText() end)
        tinsert(linesTable, ("%s:GetText() => %q"):format(labelName, okText and tostring(txt) or "<API error>"))

        local okShown, shown = pcall(function() return label:IsShown() end)
        tinsert(linesTable, ("%s:IsShown() => %s"):format(labelName, okShown and tostring(shown) or "<API error>"))

        pcall(function()
            local font, size, flags = label:GetFont()
            tinsert(linesTable, ('%s:GetFont() => font=%q, size=%s, flags=%q'):format(
                labelName, tostring(font), tostring(size), tostring(flags)))
        end)

        pcall(function()
            local r, g, b, a = label:GetTextColor()
            tinsert(linesTable, ("%s:GetTextColor() => r=%s, g=%s, b=%s, a=%s"):format(
                labelName, tostring(r), tostring(g), tostring(b), tostring(a)))
        end)

        pcall(function()
            local pt, rel, relPt, x, y = label:GetPoint(1)
            local relName = rel and (rel.GetName and rel:GetName() or tostring(rel)) or "nil"
            tinsert(linesTable, ('%s:GetPoint(1) => point=%q, relativeTo=%s, relativePoint=%q, x=%s, y=%s'):format(
                labelName, tostring(pt), relName, tostring(relPt), tostring(x), tostring(y)))
        end)

        local okW, w = pcall(function() return label:GetWidth() end)
        tinsert(linesTable, ("%s:GetWidth() => %s"):format(labelName, okW and tostring(w) or "<API error>"))
    end

    -- =========================================================================
    tinsert(lines, "=== INSTANCE STATE ===")
    -- =========================================================================
    local inInstance, instanceType
    local inInstOk, inInstErr = pcall(function()
        inInstance, instanceType = IsInInstance()
    end)
    if not inInstOk then
        tinsert(lines, "IsInInstance() => <API error: " .. tostring(inInstErr) .. ">")
    else
        tinsert(lines, ("IsInInstance() => inInstance=%s, instanceType=%q"):format(
            tostring(inInstance), tostring(instanceType)))
        if instanceType == "scenario" then
            tinsert(lines, "  -> instanceType == \"scenario\"? YES => IsInDelve will return TRUE")
        else
            tinsert(lines, "  -> instanceType == \"scenario\"? NO => checking HasActiveDelve() as fallback...")
            local hadOk, hadVal = pcall(function() return C_DelvesUI.HasActiveDelve() end)
            if hadOk then
                tinsert(lines, ("  C_DelvesUI.HasActiveDelve() => %s"):format(tostring(hadVal)))
                tinsert(lines, ("  -> IsInDelve will return %s"):format(tostring(hadVal == true)))
            else
                tinsert(lines, "  C_DelvesUI.HasActiveDelve() => <API error: " .. tostring(hadVal) .. ">")
            end
        end
    end

    -- =========================================================================
    tinsert(lines, "")
    tinsert(lines, "=== FRAME VISIBILITY DECISION ===")
    -- =========================================================================
    local inDelveResult = IsInDelve()
    tinsert(lines, ("IsInDelve() logic result => %s"):format(tostring(inDelveResult)))
    tinsert(lines, ("Expected frame visibility => %q"):format(
        inDelveResult and "Should be shown" or "Should be hidden"))
    if ns.frame then
        local okS, isShown   = pcall(function() return ns.frame:IsShown() end)
        local okV, isVisible = pcall(function() return ns.frame:IsVisible() end)
        tinsert(lines, ("frame:IsShown() => %s"):format(okS and tostring(isShown) or "<API error>"))
        tinsert(lines, ("frame:IsVisible() => %s"):format(okV and tostring(isVisible) or "<API error>"))
    else
        tinsert(lines, "frame => nil (frame was not created)")
    end

    -- =========================================================================
    tinsert(lines, "")
    tinsert(lines, "=== FRAME PROPERTIES ===")
    -- =========================================================================
    if ns.frame then
        local w2, h2
        local okSize = pcall(function() w2, h2 = ns.frame:GetSize() end)
        if okSize then
            tinsert(lines, ("frame:GetSize() => width=%s, height=%s"):format(tostring(w2), tostring(h2)))
        else
            tinsert(lines, "frame:GetSize() => <API error>")
        end

        local okAlpha, alpha = pcall(function() return ns.frame:GetAlpha() end)
        tinsert(lines, ("frame:GetAlpha() => %s"):format(okAlpha and tostring(alpha) or "<API error>"))

        local okStrata, strata = pcall(function() return ns.frame:GetFrameStrata() end)
        tinsert(lines, ("frame:GetFrameStrata() => %q"):format(okStrata and tostring(strata) or "<API error>"))

        local okLevel, level = pcall(function() return ns.frame:GetFrameLevel() end)
        tinsert(lines, ("frame:GetFrameLevel() => %s"):format(okLevel and tostring(level) or "<API error>"))

        local parentName = "<error>"
        pcall(function()
            local p = ns.frame:GetParent()
            parentName = p and (p.GetName and p:GetName() or tostring(p)) or "nil"
        end)
        tinsert(lines, ("frame:GetParent() => %s"):format(parentName))

        pcall(function()
            local pt, rel, relPt, x, y = ns.frame:GetPoint(1)
            local relName = rel and (rel.GetName and rel:GetName() or tostring(rel)) or "nil"
            tinsert(lines, ('frame:GetPoint(1) => point=%q, relativeTo=%s, relativePoint=%q, x=%s, y=%s'):format(
                tostring(pt), relName, tostring(relPt), tostring(x), tostring(y)))
        end)
    else
        tinsert(lines, "frame => nil (skipping frame properties)")
    end

    -- =========================================================================
    tinsert(lines, "")
    tinsert(lines, "=== COMPANION STATE ===")
    -- =========================================================================
    local factionID
    local okFaction = pcall(function() factionID = C_DelvesUI.GetFactionForCompanion() end)
    if not okFaction then
        tinsert(lines, "C_DelvesUI.GetFactionForCompanion() => <API error>")
    elseif not factionID or factionID == 0 then
        tinsert(lines, "C_DelvesUI.GetFactionForCompanion() => nil")
        tinsert(lines, "  -> No active companion")
    else
        tinsert(lines, ("C_DelvesUI.GetFactionForCompanion() => factionID=%d"):format(factionID))

        local compName = "nil"
        pcall(function()
            local fd = C_Reputation.GetFactionDataByID(factionID)
            compName = fd and (fd.name or "nil") or "nil"
        end)
        tinsert(lines, ("C_Reputation.GetFactionDataByID(%d) => name=%q"):format(factionID, compName))

        local rank, standing, nextThreshold = "nil", "nil", "nil"
        pcall(function()
            local fr = C_GossipInfo.GetFriendshipReputation(factionID)
            if fr then
                rank          = tostring(fr.friendshipRank  or "nil")
                standing      = tostring(fr.standing        or "nil")
                nextThreshold = tostring(fr.nextThreshold   or fr.reactionThreshold or "nil")
                tinsert(lines, ("C_GossipInfo.GetFriendshipReputation(%d) => {friendshipRank=%s, standing=%s, nextThreshold=%s, ...}"):format(
                    factionID, rank, standing, nextThreshold))
            else
                tinsert(lines, ("C_GossipInfo.GetFriendshipReputation(%d) => nil"):format(factionID))
            end
        end)
        tinsert(lines, ("  -> Companion: %s (Level %s)"):format(compName, rank))
        tinsert(lines, ("  -> XP progress: %s / %s"):format(standing, nextThreshold))
    end

    -- =========================================================================
    tinsert(lines, "")
    tinsert(lines, "=== FRAME CONTENT ===")
    -- =========================================================================
    tinsert(lines, "--- nameLabel ---")
    dumpLabel(ns.nameLabel, "nameLabel", lines)
    tinsert(lines, "--- levelLabel ---")
    dumpLabel(ns.levelLabel, "levelLabel", lines)
    tinsert(lines, "--- xpLabel ---")
    dumpLabel(ns.xpLabel, "xpLabel", lines)

    -- =========================================================================
    tinsert(lines, "")
    tinsert(lines, "=== LAST KNOWN STATE ===")
    -- =========================================================================
    tinsert(lines, ("ns._lastFactionID => %s"):format(tostring(ns._lastFactionID)))
    tinsert(lines, ("ns._lastName => %s"):format(tostring(ns._lastName)))
    tinsert(lines, ("ns._lastLevel => %s"):format(tostring(ns._lastLevel)))
    local db = DelveCompanionStatsDB
    if db then
        tinsert(lines, ("DelveCompanionStatsDB.companionName => %s"):format(tostring(db.companionName)))
        tinsert(lines, ("DelveCompanionStatsDB.companionLevel => %s"):format(tostring(db.companionLevel)))
        if db.position then
            local pos = db.position
            tinsert(lines, ("DelveCompanionStatsDB.position => {point=%q, relativePoint=%q, x=%s, y=%s}"):format(
                tostring(pos.point), tostring(pos.relativePoint), tostring(pos.x), tostring(pos.y)))
        else
            tinsert(lines, "DelveCompanionStatsDB.position => nil")
        end
    else
        tinsert(lines, "DelveCompanionStatsDB => nil")
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
        return CreateFrame("Frame", "DelveCompanionStatsFrame", UIParent)
    end)

    if not frameOk or not frameResult then
        -- Frame creation failed — log and abort. Addon will be silently disabled.
        print("|cffff4444DelveCompanionStats:|r Could not create display frame. Addon disabled.")
        ns.frame = nil
        return
    end

    ns.frame = frameResult

    -- Set frame strata and level to ensure visibility above other UI
    ns.frame:SetFrameStrata("DIALOG")
    ns.frame:SetFrameLevel(100)

    -- 3. Set size and default anchor (above ChatFrame1 when available)
    ns.frame:SetSize(200, 120)
    if ChatFrame1 then
        ns.frame:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 10)
    else
        ns.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 5, 130)
    end

    -- 5. Create name label (guarded: frame confirmed non-nil above)
    ns.nameLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.nameLabel:SetPoint("TOPLEFT", ns.frame, "TOPLEFT", 8, -8)
    ns.nameLabel:SetWidth(184)
    ns.nameLabel:SetJustifyH("LEFT")
    ns.nameLabel:SetTextColor(1, 1, 1, 1)  -- Explicit white text color
    -- Validate font; fall back to STANDARD_TEXT_FONT if GameFontNormal didn't load
    if not ns.nameLabel:GetFont() then
        ns.nameLabel:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    end
    ns.nameLabel:SetText("No companion data")
    ns.nameLabel:SetShadowOffset(2, -2)
    ns.nameLabel:SetShadowColor(0, 0, 0, 1)

    -- 6. Create level label
    ns.levelLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.levelLabel:SetPoint("TOPLEFT", ns.nameLabel, "BOTTOMLEFT", 0, -4)
    ns.levelLabel:SetWidth(184)
    ns.levelLabel:SetJustifyH("LEFT")
    ns.levelLabel:SetTextColor(1, 1, 1, 1)  -- Explicit white text color
    -- Validate font; fall back to STANDARD_TEXT_FONT if GameFontNormal didn't load
    if not ns.levelLabel:GetFont() then
        ns.levelLabel:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    end
    ns.levelLabel:SetText("")
    ns.levelLabel:SetShadowOffset(2, -2)
    ns.levelLabel:SetShadowColor(0, 0, 0, 1)

    -- 6b. Create XP label (below levelLabel)
    ns.xpLabel = ns.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.xpLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    ns.xpLabel:SetTextColor(1, 1, 1, 1)
    ns.xpLabel:SetShadowColor(0, 0, 0, 1)
    ns.xpLabel:SetShadowOffset(1, -1)
    ns.xpLabel:SetJustifyH("LEFT")
    ns.xpLabel:SetPoint("TOPLEFT", ns.levelLabel, "BOTTOMLEFT", 0, -4)
    ns.xpLabel:SetText("")

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
        if not posOk then
            -- Corrupt position data — log and fall back to default anchor
            print("|cffffff00DelveCompanionStats:|r Could not restore position. Using default.")
        end
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
        ns.frame:SetScript("OnEvent", function(self, event, ...)
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
            xpText = FormatNumber(currentXP) .. " / " .. FormatNumber(maxXP) .. " XP"
        end
        ns.xpLabel:SetText(xpText)
    end

    -- Persist to SavedVariables
    if DelveCompanionStatsDB then
        DelveCompanionStatsDB.companionName  = name
        DelveCompanionStatsDB.companionLevel = level
    end
end
