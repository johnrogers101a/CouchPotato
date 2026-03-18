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

-- Companion ID → Display Name mapping
-- Hardcoded because WoW API provides no function to retrieve display names by companion ID
-- Known companions in WoW Delves (as of patch 12.0.x)
ns.companionNames = {
    [1] = "Brann Bronzebeard",
    [2] = "Valeera Sanguinar",
    [3] = "Waxmonger Squick",
    [4] = "Turalyon",
    [5] = "Thisalee Crow",
}

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
    -- Wrapped in pcall: BackdropTemplate may be unavailable in some WoW versions.
    -- If CreateFrame fails, ns.frame = nil and addon disables gracefully.
    local frameOk, frameResult = pcall(function()
        return CreateFrame("Frame", "DelveCompanionStatsFrame", UIParent, "BackdropTemplate")
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

    -- 4. Apply dark semi-transparent backdrop
    ns.frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    ns.frame:SetBackdropColor(0, 0, 0, 0.7)

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

    -- 9. Populate companion data: Try live API first, fall back to SavedVariables
    -- NOTE: UpdateCompanionData uses C_DelvesUI.GetFactionForCompanion() + C_Reputation
    -- and C_GossipInfo APIs to fetch live data, and updates SavedVariables + UI atomically.
    ns:UpdateCompanionData()

    -- 10. Show the frame
    if ns.frame then ns.frame:Show() end

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
        ns.frame:SetScript("OnEvent", function(self, event, ...)
            ns:UpdateCompanionData()
        end)
    end

    -- Explicitly show fontstrings (belt-and-suspenders: ensures visibility even if parent Show() is pending)
    if ns.nameLabel then ns.nameLabel:Show() end
    if ns.levelLabel then ns.levelLabel:Show() end
end

-------------------------------------------------------------------------------
-- UpdateCompanionData: Fetch active companion from C_DelvesUI and update UI
-- Called by event handlers and during initialization
-------------------------------------------------------------------------------
function ns:UpdateCompanionData()
    if not ns.frame then return end
    local name, level = nil, nil

    -- Step 1: Get companion ID via GetCompanionInfoForActivePlayer
    local companionID = nil
    if C_DelvesUI and C_DelvesUI.GetCompanionInfoForActivePlayer then
        local ok, result = pcall(C_DelvesUI.GetCompanionInfoForActivePlayer)
        if ok and result and result ~= 0 then
            companionID = result
        end
    end

    -- Step 2: Look up companion name in hardcoded table; fall back to "Unknown Companion"
    if companionID then
        name = ns.companionNames[companionID] or "Unknown Companion"
    end

    -- Step 3: Get companion level from friendship reputation (needs faction ID)
    local factionID = nil
    if C_DelvesUI and C_DelvesUI.GetFactionForCompanion then
        local ok, result = pcall(C_DelvesUI.GetFactionForCompanion, companionID)
        if ok and result and result ~= 0 then
            factionID = result
        end
    end

    if factionID and C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local ok, friendData = pcall(C_GossipInfo.GetFriendshipReputation, factionID)
        if ok and friendData then
            if C_GossipInfo.GetFriendshipReputationRanks then
                local rok, ranks = pcall(C_GossipInfo.GetFriendshipReputationRanks, factionID)
                if rok and ranks and ranks.currentLevel then
                    level = ranks.currentLevel
                end
            end
        end
    end

    -- Fall back to SavedVariables if live API returned nothing
    if not name and DelveCompanionStatsDB then
        name  = DelveCompanionStatsDB.companionName
        level = DelveCompanionStatsDB.companionLevel
    end

    -- Update UI
    if ns.nameLabel then
        ns.nameLabel:SetText(name or "No companion data")
    end
    if ns.levelLabel then
        ns.levelLabel:SetText(level and ("Level: " .. tostring(level)) or "")
    end

    -- Persist to SavedVariables
    if name and DelveCompanionStatsDB then
        DelveCompanionStatsDB.companionName  = name
        DelveCompanionStatsDB.companionLevel = level
    end
end
