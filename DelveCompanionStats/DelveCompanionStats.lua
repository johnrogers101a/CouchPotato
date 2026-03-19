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
SlashCmdList["DCS"] = function(arg)
    local cmd = strtrim(strlower(arg or ""))
    if cmd == "debug" then
        ns:PrintDebugInfo()
    else
        dcsprint("Usage: /dcs debug")
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
    local lines = {}
    local function add(s) lines[#lines + 1] = tostring(s) end

    add("=== DCS Debug Info ===")
    add("C_DelvesUI exists: " .. tostring(C_DelvesUI ~= nil))

    -- Check known function existence
    local knownFns = {
        "GetCompanionInfoForActivePlayer",
        "GetFactionForCompanion",
        "GetActiveCompanion",
        "GetActiveDelve",
    }
    for _, fnName in ipairs(knownFns) do
        local exists = C_DelvesUI and C_DelvesUI[fnName] ~= nil
        add("  C_DelvesUI." .. fnName .. " exists: " .. tostring(exists))
    end

    -- Enumerate all keys on C_DelvesUI
    if C_DelvesUI then
        add("C_DelvesUI keys:")
        for k, _ in pairs(C_DelvesUI) do
            add("  " .. tostring(k))
        end
    end

    -- Call each known function and print raw return
    for _, fnName in ipairs(knownFns) do
        if C_DelvesUI and C_DelvesUI[fnName] then
            local ok, result = pcall(C_DelvesUI[fnName])
            add("  C_DelvesUI." .. fnName .. "() => ok=" .. tostring(ok) .. " result=" .. tostring(result))
        end
    end

    -- GetFactionForCompanion: call with no args (returns active companion's faction ID)
    if C_DelvesUI and C_DelvesUI.GetFactionForCompanion then
        local ok, result = pcall(C_DelvesUI.GetFactionForCompanion)
        add("  GetFactionForCompanion() => ok=" .. tostring(ok) .. " result=" .. tostring(result))
    end

    -- Current addon state
    add("factionID (last known): "   .. tostring(ns._lastFactionID))
    add("name (last known): "        .. tostring(ns._lastName))
    add("level (last known): "       .. tostring(ns._lastLevel))
    add("nameLabel text: "  .. tostring(ns.nameLabel  and ns.nameLabel:GetText()  or "N/A"))
    add("levelLabel text: " .. tostring(ns.levelLabel and ns.levelLabel:GetText() or "N/A"))

    -- Live API return values
    add("HasActiveDelve() = " .. tostring(C_DelvesUI.HasActiveDelve and C_DelvesUI.HasActiveDelve()))
    local ok2, result2 = pcall(function() return C_DelvesUI.GetFactionForCompanion() end)
    add("GetFactionForCompanion() = " .. tostring(result2))
    local _, instanceType = IsInInstance()
    add("IsInInstance() type = " .. tostring(instanceType))
    add("IsInDelve() = " .. tostring(IsInDelve()))

    local text = table.concat(lines, "\n")

    -- Show in scrollable popup (create once, reuse on subsequent calls)
    if not ns.debugPopup then ns:CreateDebugPopup() end
    ns.debugPopup._editBox:SetText(text)
    ns.debugPopup:Show()
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
    ns.frame:SetSize(200, 100)
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
            local wasShown = ns.frame:IsShown()
            ns:UpdateFrameVisibility()
            if wasShown and ns.frame:IsShown() then
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
-- UpdateCompanionData: Fetch active companion from C_DelvesUI and update UI
-- Uses fully dynamic API calls — no hardcoded faction ID lookup tables.
-- Called by event handlers and during initialization.
-------------------------------------------------------------------------------
function ns:UpdateCompanionData(event)
    if not ns.frame then return end
    dcsprint("UpdateCompanionData triggered by: " .. tostring(event))

    -- Step 1: Get the active companion's faction ID directly (no args required)
    local factionID = nil
    if C_DelvesUI and C_DelvesUI.GetFactionForCompanion then
        local ok, result = pcall(C_DelvesUI.GetFactionForCompanion)
        if ok and result and result ~= 0 then
            factionID = result
        end
    end
    dcsprint("  GetFactionForCompanion() => " .. tostring(factionID))

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
    dcsprint("  GetFactionDataByID(" .. tostring(factionID) .. ") => " .. tostring(name))

    -- Step 3: Get companion level from friendship reputation
    local level = nil
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local ok, friendData = pcall(C_GossipInfo.GetFriendshipReputation, factionID)
        if ok and friendData then
            level = friendData.friendshipRank or friendData.reaction or friendData.standing
        end
    end
    dcsprint("  level => " .. tostring(level))

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

    -- Persist to SavedVariables
    if DelveCompanionStatsDB then
        DelveCompanionStatsDB.companionName  = name
        DelveCompanionStatsDB.companionLevel = level
    end
end
