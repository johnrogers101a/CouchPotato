-- CouchPotato.lua
-- Core namespace, error capture system, and slash commands for the CouchPotato suite.
-- Patch 12.0.1 (Interface 120001)

local ADDON_NAME = "CouchPotato"

-- Namespace exposed to other files in this addon
local CP = {}
_G.CouchPotatoShared = CP

CP.version = "1.0.0"

-------------------------------------------------------------------------------
-- Shared utilities: used by DCS, SP, and other suite addons
-------------------------------------------------------------------------------

-- Shared theme constants for consistent UI across all suite addons.
CP.THEME = {
    GOLD          = {1, 0.82, 0.0, 1},
    GOLD_LINE     = {0.9, 0.75, 0.1, 0.8},
    GOLD_ACCENT   = {1, 0.78, 0.1, 1},
    BG_DARK       = {0, 0, 0, 0.5},
    FONT_PATH     = "Fonts\\FRIZQT__.TTF",
    HEADER_HEIGHT = 24,
    COLLAPSE_BTN_SIZE = 36,
    PIN_BTN_SIZE  = 26,
    LOCK_TEXTURE   = "Interface\\Buttons\\LockButton-Locked-Up",
    UNLOCK_TEXTURE = "Interface\\Buttons\\LockButton-Unlocked-Up",
}

-- CreateLogger: returns a logging function bound to a prefix.
-- Usage: local mylog = CouchPotatoShared.CreateLogger("DCS")
--        mylog("Info", "something happened")
function CP.CreateLogger(prefix)
    return function(level, msg)
        if _G.CouchPotatoLog and _G.CouchPotatoLog[level] then
            _G.CouchPotatoLog[level](_G.CouchPotatoLog, prefix, msg)
        end
    end
end

-- GetBaseTrackerAnchor: find the lowest visible tracker module for docking.
-- Returns the frame whose BOTTOM edge is the lowest visible point of the
-- Blizzard objective tracker, or nil when no tracker frame exists at all.
--
-- Design: ObjectiveTrackerFrame itself is ALWAYS the final fallback whenever
-- the frame exists, even when IsShown() returns false (which WoW does when no
-- quests are tracked).  The "smart find lowest module" logic is an enhancement
-- layered on top — it only kicks in when modules are actually visible.  This
-- prevents the frames from drifting to the minimap or off-screen when the
-- tracker is empty.
function CP.GetBaseTrackerAnchor()
    -- If the frame doesn't exist at all there is nothing to anchor to.
    if not ObjectiveTrackerFrame then
        return nil
    end

    -- Smart enhancement: when the tracker (or its modules) is actually
    -- rendering content, find the lowest visible module so we dock flush
    -- to the bottom of that content rather than the outer container edge.
    -- This is skipped (falls through to the ObjectiveTrackerFrame fallback)
    -- when no modules are visible — e.g. no quests tracked outside a delve.
    local trackerShown = ObjectiveTrackerFrame.IsShown
                         and ObjectiveTrackerFrame:IsShown()

    if trackerShown then
        -- 1. Iterate modules table when available.
        if type(ObjectiveTrackerFrame.modules) == "table" then
            local bestFrame  = nil
            local bestBottom = math.huge
            for _, module in pairs(ObjectiveTrackerFrame.modules) do
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
                return bestFrame
            end
        end

        -- 2. Named module fallback list.
        local knownModules = {
            "ScenarioObjectiveTracker",
            "QuestObjectiveTracker",
            "BonusObjectiveTracker",
            "WorldQuestObjectiveTracker",
            "CampaignQuestObjectiveTracker",
            "ProfessionsObjectiveTracker",
            "AdventureObjectiveTracker",
            "AchievementObjectiveTracker",
        }
        local bestFrame  = nil
        local bestBottom = math.huge
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
            return bestFrame
        end
    end

    -- 3. Outer container — always use this when the frame exists, even when
    --    empty (no quests tracked).  The tracker frame stays positioned at
    --    the correct screen location even when it has no visible children.
    return ObjectiveTrackerFrame
end

-------------------------------------------------------------------------------
-- SavedVariables default structure
-------------------------------------------------------------------------------
local DB_DEFAULTS = {
    errorLog      = {},
    debugLog      = {},
    minimapAngle  = 225,   -- degrees clockwise from top
    windowState   = { shown = false },
    addonStates   = {
        ControllerCompanion  = true,
        DelveCompanionStats  = true,
        DelversJourney       = true,
        StatPriority         = true,
    },
}

local function InitDB()
    local isNew = (CouchPotatoDB == nil)
    if not CouchPotatoDB then
        CouchPotatoDB = {}
    end
    local db = CouchPotatoDB
    for k, v in pairs(DB_DEFAULTS) do
        if db[k] == nil then
            -- shallow copy tables, primitive values directly
            if type(v) == "table" then
                local copy = {}
                for k2, v2 in pairs(v) do copy[k2] = v2 end
                db[k] = copy
            else
                db[k] = v
            end
        end
    end
    -- Migration: ensure addonStates sub-keys exist for addons added after initial install
    if not db.addonStates then
        db.addonStates = {}
    end
    local stateDefaults = DB_DEFAULTS.addonStates
    for addonKey, defaultVal in pairs(stateDefaults) do
        if db.addonStates[addonKey] == nil then
            db.addonStates[addonKey] = defaultVal
        end
    end

    if _G.CouchPotatoLog then
        local state = isNew and "fresh" or "restored"
        _G.CouchPotatoLog:Info("CP", "DB initialized: " .. state)
    end
end

-------------------------------------------------------------------------------
-- Error capture: hook WoW error handler
-------------------------------------------------------------------------------
local SUITE_PATTERNS = {
    "CouchPotato",
    "ControllerCompanion",
    "DelveCompanionStats",
    "DelversJourney",
    "StatPriority",
}

local MAX_ERROR_LOG = 500

local function IsSuiteError(msg, stack)
    local haystack = (msg or "") .. (stack or "")
    for _, pattern in ipairs(SUITE_PATTERNS) do
        if haystack:find(pattern, 1, true) then
            return true, pattern
        end
    end
    return false, nil
end

local function GuessAddonName(msg, stack)
    local haystack = (msg or "") .. (stack or "")
    for _, pattern in ipairs(SUITE_PATTERNS) do
        if haystack:find(pattern, 1, true) then
            return pattern
        end
    end
    return "CouchPotato"
end

local _originalErrorHandler = nil

local function CouchPotatoErrorHandler(msg, stack)
    local isSuite, _ = IsSuiteError(msg, stack)
    if isSuite and CouchPotatoDB then
        local addonGuess = GuessAddonName(msg, stack)
        local log = CouchPotatoDB.errorLog
        local entry = {
            timestamp = GetTime and GetTime() or 0,
            message   = tostring(msg or ""),
            stack     = tostring(stack or ""),
            addonName = addonGuess,
        }
        table.insert(log, 1, entry)  -- newest first
        -- Cap at MAX_ERROR_LOG entries
        while #log > MAX_ERROR_LOG do
            table.remove(log)
        end
        -- Also write to debug log
        local summary = tostring(msg or ""):sub(1, 120)
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Error(addonGuess, "Captured error: " .. summary)
        end
    end
    -- Always forward to original handler
    if _originalErrorHandler then
        _originalErrorHandler(msg, stack)
    end
end

local function HookErrorHandler()
    local ok, err = pcall(function()
        _originalErrorHandler = geterrorhandler and geterrorhandler() or nil
        seterrorhandler(CouchPotatoErrorHandler)
    end)
    if ok then
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Info("CP", "Error handler hooked successfully")
        end
    else
        -- If hooking fails (e.g., protected environment), proceed without it
        _originalErrorHandler = nil
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Warn("CP", "Error handler hook failed: " .. tostring(err))
        end
    end
end

-------------------------------------------------------------------------------
-- ADDON_LOADED event handler
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Info("CP", "ADDON_LOADED fired for: " .. tostring(addonName))
        end
        InitDB()
        HookErrorHandler()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-------------------------------------------------------------------------------
-- Enable/Disable addon management
-------------------------------------------------------------------------------

-- Canonical addon key → human-readable display name.
local ADDON_DISPLAY_NAMES = {
    ControllerCompanion  = "Controller Companion",
    DelveCompanionStats  = "Delve Companion Stats",
    DelversJourney       = "Delver's Journey",
    StatPriority         = "Stat Priority",
}

-- Canonical addon name → display name mapping.
-- Keys are lowercase aliases; value is the canonical SavedVars key.
local ADDON_ALIASES = {
    controllercompanion  = "ControllerCompanion",
    cc                   = "ControllerCompanion",
    delvecompanionstats  = "DelveCompanionStats",
    dcs                  = "DelveCompanionStats",
    delversjourney       = "DelversJourney",
    dj                   = "DelversJourney",
    statpriority         = "StatPriority",
    sp                   = "StatPriority",
}

-- cpprint: write a coloured [CP] message to the chat frame.
local function cpprint(msg)
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Print("CP", msg)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff6600CP:|r " .. tostring(msg))
    else
        print("|cffff6600CP:|r " .. tostring(msg))
    end
end

-- EnsureAddonStates: guarantee CouchPotatoDB.addonStates is populated.
-- Safe to call before ADDON_LOADED (e.g. if the slash cmd fires early).
local function EnsureAddonStates()
    if not CouchPotatoDB then
        CouchPotatoDB = {}
    end
    if not CouchPotatoDB.addonStates then
        CouchPotatoDB.addonStates = {}
    end
    local stateDefaults = DB_DEFAULTS.addonStates
    for addonKey, defaultVal in pairs(stateDefaults) do
        if CouchPotatoDB.addonStates[addonKey] == nil then
            CouchPotatoDB.addonStates[addonKey] = defaultVal
        end
    end
end

-- PrintAddonStatus: list all suite addons and their current enabled/disabled state.
local function PrintAddonStatus()
    EnsureAddonStates()
    cpprint("Suite addon states:")
    local order = { "ControllerCompanion", "DelveCompanionStats", "DelversJourney", "StatPriority" }
    for _, name in ipairs(order) do
        local state = CouchPotatoDB.addonStates[name]
        local label = (state == false) and "|cffff4444disabled|r" or "|cff44ff44enabled|r"
        local displayName = ADDON_DISPLAY_NAMES[name] or name
        cpprint("  " .. displayName .. ": " .. label)
    end
end

-- Combat deferral for ControllerCompanion disable (protected frames)
local pendingCombatActions = {}

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        for _, action in ipairs(pendingCombatActions) do
            action()
        end
        pendingCombatActions = {}
    end
end)

-- DoDisableAddon: perform the functional disable for a canonical addon name.
local function DoDisableAddon(name)
    if name == "ControllerCompanion" then
        if _G.ControllerCompanion and _G.ControllerCompanion.OnControllerDeactivated then
            _G.ControllerCompanion:OnControllerDeactivated()
        end
        -- Hide all CC frames if accessible
        if _G.ControllerCompanion and _G.ControllerCompanion._mainFrame then
            _G.ControllerCompanion._mainFrame:Hide()
        end
    elseif name == "DelveCompanionStats" then
        local ns = _G.DelveCompanionStatsNS
        if ns then
            ns._cpDisabled = true
            if ns.frame then ns.frame:Hide() end
        end
    elseif name == "StatPriority" then
        local ns = _G.StatPriorityNS
        if ns then
            ns._cpDisabled = true
            if ns.frame then ns.frame:Hide() end
        end
    end
end

-- DoEnableAddon: perform the functional enable for a canonical addon name.
local function DoEnableAddon(name)
    if name == "ControllerCompanion" then
        if _G.ControllerCompanion and _G.ControllerCompanion.OnControllerActivated then
            _G.ControllerCompanion:OnControllerActivated()
        end
    elseif name == "DelveCompanionStats" then
        local ns = _G.DelveCompanionStatsNS
        if ns then
            ns._cpDisabled = false
            if ns.frame then ns.frame:Show() end
        end
    elseif name == "StatPriority" then
        local ns = _G.StatPriorityNS
        if ns then
            ns._cpDisabled = false
            if ns.frame then ns.frame:Show() end
            if ns.UpdateStatPriority then ns:UpdateStatPriority() end
        end
    end
end

-- HandleEnableDisable: main entry point for /cp enable|disable <addon>
local function HandleEnableDisable(action, rawName)
    EnsureAddonStates()

    if not rawName or rawName == "" then
        PrintAddonStatus()
        return
    end

    local alias = strlower(rawName)
    local canonical = ADDON_ALIASES[alias]
    if not canonical then
        cpprint("Unknown addon '" .. rawName .. "'. Valid names: controllercompanion (cc), delvecompanionstats (dcs), statpriority (sp)")
        return
    end

    local states = CouchPotatoDB.addonStates
    local isEnabled = (states[canonical] ~= false)
    local displayName = ADDON_DISPLAY_NAMES[canonical] or canonical

    if action == "disable" then
        if not isEnabled then
            cpprint(displayName .. " is already disabled.")
            return
        end
        states[canonical] = false
        -- ControllerCompanion: warn+defer if in combat
        if canonical == "ControllerCompanion" then
            local inCombat = InCombatLockdown and InCombatLockdown() or false
            if inCombat then
                cpprint(displayName .. " will be disabled after combat ends.")
                table.insert(pendingCombatActions, function()
                    DoDisableAddon(canonical)
                    cpprint(displayName .. " disabled (post-combat).")
                end)
                return
            end
        end
        DoDisableAddon(canonical)
        cpprint(displayName .. " disabled.")
    elseif action == "enable" then
        if isEnabled then
            cpprint(displayName .. " is already enabled.")
            return
        end
        states[canonical] = true
        DoEnableAddon(canonical)
        cpprint(displayName .. " enabled.")
    end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

-- /cp  — open CouchPotato shared config window, or enable/disable addons
SLASH_CP1 = "/cp"
SLASH_CP2 = "/couchpotato"
SlashCmdList["CP"] = function(msg)
    msg = strtrim(strlower(msg or ""))
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "Slash /cp received, args: '" .. msg .. "'")
    end

    -- Parse subcommand
    local subcmd, rest = msg:match("^(%S+)%s*(.*)")
    subcmd = subcmd or ""
    rest   = rest   or ""

    if subcmd == "enable" or subcmd == "disable" then
        HandleEnableDisable(subcmd, rest ~= "" and rest or nil)
        return
    end

    if CouchPotatoShared.ConfigWindow then
        CouchPotatoShared.ConfigWindow.Toggle()
    end
end

-- /cc  — open ControllerCompanion controller-specific config
SLASH_CC1 = "/cc"
SLASH_CC2 = "/controllercompanion"
SlashCmdList["CC"] = function(msg)
    msg = strtrim(strlower(msg or ""))
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "Slash /cc received, args: '" .. msg .. "'")
    end
    if ControllerCompanion and ControllerCompanion.ConfigWindow then
        ControllerCompanion.ConfigWindow.Show()
    else
        -- Try force-loading ControllerCompanion if not loaded
        if C_AddOns and not C_AddOns.IsAddOnLoaded("ControllerCompanion") then
            if _G.CouchPotatoLog then
                _G.CouchPotatoLog:Info("CP", "Requesting load of ControllerCompanion")
            end
            C_AddOns.EnableAddOn("ControllerCompanion")
            C_AddOns.LoadAddOn("ControllerCompanion")
        end
        if ControllerCompanion and ControllerCompanion.ConfigWindow then
            ControllerCompanion.ConfigWindow.Show()
        else
            if _G.CouchPotatoLog then
                _G.CouchPotatoLog:Warn("CP", "ControllerCompanion not available after load attempt")
            end
            if CouchPotatoLog then
                CouchPotatoLog:Print("CP", "ControllerCompanion not available.")
            end
        end
    end
end

-------------------------------------------------------------------------------
-- /cpquery — Temporary diagnostic: probe APIs for companion role, curios,
--            and Delver's Journey data. Output goes to Debug Log (exportable).
-------------------------------------------------------------------------------
SLASH_CPQUERY1 = "/cpquery"
SlashCmdList["CPQUERY"] = function(msg)
    local log = CP.CreateLogger("CPQ")

    -- Helper: try an API call, log result or error, return result
    local function tryAPI(label, fn, ...)
        if not fn then
            log("Info", label .. " => function does not exist")
            return nil
        end
        local args = {...}
        local ok, result = pcall(function() return fn(unpack(args)) end)
        if not ok then
            log("Info", label .. " => ERROR: " .. tostring(result))
            return nil
        end
        if type(result) == "table" then
            log("Info", label .. " => (table)")
            for k, v in pairs(result) do
                if type(v) == "table" then
                    log("Info", "  [" .. tostring(k) .. "] = (subtable)")
                    for k2, v2 in pairs(v) do
                        log("Info", "    " .. tostring(k2) .. " = " .. tostring(v2))
                    end
                else
                    log("Info", "  " .. tostring(k) .. " = " .. tostring(v))
                end
            end
        else
            log("Info", label .. " => " .. tostring(result))
        end
        return result
    end

    -- Helper: try calling a method by name on C_DelvesUI with optional args
    local function tryDelvesAPI(name, ...)
        local fn = C_DelvesUI and C_DelvesUI[name]
        return tryAPI("C_DelvesUI." .. name .. "(" .. (select('#', ...) > 0 and tostring(select(1, ...)) or "") .. ")", fn, ...)
    end

    log("Info", "=== /cpQuery Diagnostic Start ===")
    log("Info", "Timestamp: " .. (date and date("%Y-%m-%d %H:%M:%S") or "unknown"))

    -- =======================================================================
    -- SECTION 1: Full C_DelvesUI key dump
    -- =======================================================================
    log("Info", "")
    log("Info", "--- FULL C_DelvesUI API Surface ---")
    if C_DelvesUI then
        local keys = {}
        for k, _ in pairs(C_DelvesUI) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            log("Info", "  C_DelvesUI." .. k .. " (" .. type(C_DelvesUI[k]) .. ")")
        end
        log("Info", "  Total keys: " .. #keys)
    else
        log("Info", "  C_DelvesUI is nil!")
    end

    -- =======================================================================
    -- SECTION 2: Filtered key scan (role, curio, journey, season, rank)
    -- =======================================================================
    log("Info", "")
    log("Info", "--- C_DelvesUI Filtered Keys (role/curio/journey/season/rank/companion/tank/healer/dps/delver/tier/progress) ---")
    if C_DelvesUI then
        local filters = {"role", "combat", "curio", "companion", "tank", "healer", "dps",
                         "journey", "season", "rank", "delver", "tier", "progress", "equip"}
        for k, _ in pairs(C_DelvesUI) do
            local lk = k:lower()
            for _, f in ipairs(filters) do
                if lk:find(f) then
                    log("Info", "  MATCH: C_DelvesUI." .. k)
                    -- Try calling it with no args and with arg 1
                    if type(C_DelvesUI[k]) == "function" then
                        tryAPI("    call()", C_DelvesUI[k])
                        tryAPI("    call(1)", C_DelvesUI[k], 1)
                    end
                    break
                end
            end
        end
    end

    -- =======================================================================
    -- SECTION 3: Companion Role probing
    -- =======================================================================
    log("Info", "")
    log("Info", "--- Companion Role Probing ---")
    tryDelvesAPI("GetRoleForCompanion")
    tryDelvesAPI("GetRoleForCompanion", 1)
    tryDelvesAPI("GetCompanionRole")
    tryDelvesAPI("GetCompanionRole", 1)
    tryDelvesAPI("GetCompanionCombatRole")
    tryDelvesAPI("GetCompanionCombatRole", 1)
    tryDelvesAPI("GetCompanionConfigInfo")
    tryDelvesAPI("GetCompanionConfigInfo", 1)
    tryDelvesAPI("GetActiveCompanionInfo")
    tryDelvesAPI("GetCurrentCompanion")

    -- =======================================================================
    -- SECTION 4: Curio probing
    -- =======================================================================
    log("Info", "")
    log("Info", "--- Curio Probing ---")
    tryDelvesAPI("GetCurioInfoForCompanion")
    tryDelvesAPI("GetCurioInfoForCompanion", 1)
    tryDelvesAPI("GetEquippedCurios")
    tryDelvesAPI("GetEquippedCurios", 1)
    tryDelvesAPI("GetCombatCurio")
    tryDelvesAPI("GetCombatCurio", 1)
    tryDelvesAPI("GetUtilityCurio")
    tryDelvesAPI("GetUtilityCurio", 1)
    tryDelvesAPI("GetCurioCount")
    tryDelvesAPI("GetCurioCount", 1)
    tryDelvesAPI("GetCurioInfo", 1)
    tryDelvesAPI("GetCurioInfo", 2)
    tryDelvesAPI("GetOwnedCurios")
    tryDelvesAPI("GetEquippedCuriosForCompanion")
    tryDelvesAPI("GetEquippedCuriosForCompanion", 1)
    tryDelvesAPI("GetCuriosForCompanion")
    tryDelvesAPI("GetCuriosForCompanion", 1)
    tryDelvesAPI("GetSlottedCurios")
    tryDelvesAPI("GetSlottedCurios", 1)
    tryDelvesAPI("GetCurioNodeForCompanion")
    tryDelvesAPI("GetCurioNodeForCompanion", 1)
    tryDelvesAPI("GetCurioNodeForCompanion", 1, 1)
    tryDelvesAPI("GetCurioNodeForCompanion", 1, 2)

    -- Try trait-tree approach for curios (they may be trait nodes)
    log("Info", "")
    log("Info", "--- Trait Tree Curio Approach ---")
    tryDelvesAPI("GetCompanionTraitTreeID")
    tryDelvesAPI("GetCompanionTraitTreeID", 1)
    local treeID = nil
    if C_DelvesUI and C_DelvesUI.GetCompanionTraitTreeID then
        local ok, r = pcall(C_DelvesUI.GetCompanionTraitTreeID)
        if ok and r then treeID = r end
        if not treeID then
            local ok2, r2 = pcall(C_DelvesUI.GetCompanionTraitTreeID, 1)
            if ok2 and r2 then treeID = r2 end
        end
    end
    if treeID and C_Traits then
        log("Info", "Found treeID=" .. tostring(treeID) .. ", probing C_Traits...")
        tryAPI("C_Traits.GetTreeNodes(" .. treeID .. ")", C_Traits.GetTreeNodes, treeID)
        tryAPI("C_Traits.GetConfigIDByTreeID(" .. treeID .. ")", C_Traits.GetConfigIDByTreeID, treeID)
    end

    -- =======================================================================
    -- SECTION 5: Delver's Journey / Season probing
    -- =======================================================================
    log("Info", "")
    log("Info", "--- Delver's Journey / Season Probing ---")
    tryDelvesAPI("GetDelversJourneyInfo")
    tryDelvesAPI("GetSeasonProgress")
    tryDelvesAPI("GetDelverRank")
    tryDelvesAPI("GetCurrentDelvesSeasonNumber")
    tryDelvesAPI("GetDelvesSeasonInfo")
    tryDelvesAPI("GetSeasonalData")
    tryDelvesAPI("GetCurrentSeasonRewardInfo")
    tryDelvesAPI("GetGreatVaultProgress")

    -- Probe C_MajorFactions
    log("Info", "")
    log("Info", "--- C_MajorFactions Scan ---")
    if C_MajorFactions then
        local mfKeys = {}
        for k, _ in pairs(C_MajorFactions) do
            mfKeys[#mfKeys + 1] = k
        end
        table.sort(mfKeys)
        for _, k in ipairs(mfKeys) do
            log("Info", "  C_MajorFactions." .. k .. " (" .. type(C_MajorFactions[k]) .. ")")
        end
        -- Try GetMajorFactionData with speculative IDs
        if C_MajorFactions.GetMajorFactionData then
            for id = 2600, 2610 do
                local ok, data = pcall(C_MajorFactions.GetMajorFactionData, id)
                if ok and data and data.name then
                    log("Info", "  GetMajorFactionData(" .. id .. ") => name=" .. tostring(data.name) .. " renownLevel=" .. tostring(data.renownLevel))
                end
            end
            for id = 2640, 2660 do
                local ok, data = pcall(C_MajorFactions.GetMajorFactionData, id)
                if ok and data and data.name then
                    log("Info", "  GetMajorFactionData(" .. id .. ") => name=" .. tostring(data.name) .. " renownLevel=" .. tostring(data.renownLevel))
                end
            end
        end
    else
        log("Info", "  C_MajorFactions is nil")
    end

    -- Probe reputation IDs for season-related factions
    log("Info", "")
    log("Info", "--- Speculative Reputation Scan (2600-2660) ---")
    if C_Reputation and C_Reputation.GetFactionDataByID then
        for id = 2600, 2660 do
            local ok, data = pcall(C_Reputation.GetFactionDataByID, id)
            if ok and data and data.name and data.name ~= "" then
                log("Info", "  Faction " .. id .. ": " .. tostring(data.name) .. " (reaction=" .. tostring(data.reaction) .. ")")
                -- Also get friendship rep for XP data
                if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
                    local ok2, fr = pcall(C_GossipInfo.GetFriendshipReputation, id)
                    if ok2 and fr then
                        log("Info", "    FriendshipRep: standing=" .. tostring(fr.standing) .. " nextThreshold=" .. tostring(fr.nextThreshold) .. " reaction=" .. tostring(fr.reaction))
                    end
                end
            end
        end
    end

    -- Probe currency IDs for delve/journey related currencies
    log("Info", "")
    log("Info", "--- Speculative Currency Scan (2800-2850, 3050-3100) ---")
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ranges = {{2800, 2850}, {3050, 3100}}
        for _, range in ipairs(ranges) do
            for id = range[1], range[2] do
                local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
                if ok and info and info.name and info.name ~= "" then
                    local lname = info.name:lower()
                    if lname:find("delve") or lname:find("journey") or lname:find("season") or lname:find("vault") or lname:find("rank") then
                        log("Info", "  Currency " .. id .. ": " .. tostring(info.name) .. " qty=" .. tostring(info.quantity) .. " max=" .. tostring(info.maxQuantity))
                    end
                end
            end
        end
    end

    -- Quest log scan for journey/season quests
    log("Info", "")
    log("Info", "--- Quest Log Scan (journey/delver/season/rank) ---")
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local ok, numEntries = pcall(C_QuestLog.GetNumQuestLogEntries)
        if ok and numEntries then
            log("Info", "  Total quest entries: " .. tostring(numEntries))
            for i = 1, numEntries do
                local ok2, info = pcall(C_QuestLog.GetInfo, i)
                if ok2 and info and info.title then
                    local t = info.title:lower()
                    if t:find("journey") or t:find("delver") or t:find("season") or t:find("rank") or t:find("delve") then
                        log("Info", "  [" .. i .. "] " .. info.title .. " questID=" .. tostring(info.questID) .. " isComplete=" .. tostring(info.isComplete))
                    end
                end
            end
        end
    end

    -- =======================================================================
    -- SECTION 6: Existing companion data (for reference)
    -- =======================================================================
    log("Info", "")
    log("Info", "--- Existing Companion Data (reference) ---")
    if C_DelvesUI and C_DelvesUI.GetFactionForCompanion then
        local factionID = tryAPI("C_DelvesUI.GetFactionForCompanion()", C_DelvesUI.GetFactionForCompanion)
        if factionID and factionID ~= 0 then
            tryAPI("C_Reputation.GetFactionDataByID(" .. factionID .. ")", C_Reputation.GetFactionDataByID, factionID)
            if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
                tryAPI("C_GossipInfo.GetFriendshipReputation(" .. factionID .. ")", C_GossipInfo.GetFriendshipReputation, factionID)
            end
        end
    end

    -- =======================================================================
    -- SECTION 7: Targeted follow-up (trait node resolution, journey XP)
    -- =======================================================================
    log("Info", "")
    log("Info", "--- SECTION 7: Targeted Trait Node & Journey Resolution ---")

    -- 7a: Resolve Role node via C_Traits
    log("Info", "")
    log("Info", "-- 7a: Role Node Resolution --")
    local roleNodeID = nil
    if C_DelvesUI and C_DelvesUI.GetRoleNodeForCompanion then
        local ok, r = pcall(C_DelvesUI.GetRoleNodeForCompanion)
        if ok and r then roleNodeID = r end
    end
    log("Info", "RoleNodeID (active companion): " .. tostring(roleNodeID))

    local traitTreeID = nil
    if C_DelvesUI and C_DelvesUI.GetTraitTreeForCompanion then
        local ok, r = pcall(C_DelvesUI.GetTraitTreeForCompanion)
        if ok and r then traitTreeID = r end
    end
    log("Info", "TraitTreeID (active companion): " .. tostring(traitTreeID))

    -- Get configID for the trait tree
    local configID = nil
    if C_Traits and traitTreeID then
        tryAPI("C_Traits.GetConfigIDByTreeID(" .. traitTreeID .. ")", C_Traits and C_Traits.GetConfigIDByTreeID, traitTreeID)
        local ok, r = pcall(C_Traits.GetConfigIDByTreeID, traitTreeID)
        if ok and r then configID = r end
    end
    log("Info", "ConfigID: " .. tostring(configID))

    -- Resolve role node info
    if C_Traits and roleNodeID then
        tryAPI("C_Traits.GetNodeInfo(configID=" .. tostring(configID) .. ", roleNode=" .. roleNodeID .. ")", C_Traits.GetNodeInfo, configID, roleNodeID)
        -- Try getting the active entry for the role node
        local ok, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, roleNodeID)
        if ok and nodeInfo then
            log("Info", "Role node activeEntry: " .. tostring(nodeInfo.activeEntry))
            log("Info", "Role node type: " .. tostring(nodeInfo.type))
            log("Info", "Role node subTreeID: " .. tostring(nodeInfo.subTreeID))
            if nodeInfo.activeEntry then
                local entryID = type(nodeInfo.activeEntry) == "table" and nodeInfo.activeEntry.entryID or nodeInfo.activeEntry
                log("Info", "Role activeEntry resolved: " .. tostring(entryID))
                if entryID and C_Traits.GetEntryInfo then
                    tryAPI("C_Traits.GetEntryInfo(configID, " .. tostring(entryID) .. ")", C_Traits.GetEntryInfo, configID, entryID)
                    local ok2, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entryID)
                    if ok2 and entryInfo then
                        log("Info", "Entry definitionID: " .. tostring(entryInfo.definitionID))
                        log("Info", "Entry subTreeID: " .. tostring(entryInfo.subTreeID))
                        if entryInfo.definitionID and C_Traits.GetDefinitionInfo then
                            tryAPI("C_Traits.GetDefinitionInfo(" .. tostring(entryInfo.definitionID) .. ")", C_Traits.GetDefinitionInfo, entryInfo.definitionID)
                        end
                        if entryInfo.subTreeID and C_Traits.GetSubTreeInfo then
                            tryAPI("C_Traits.GetSubTreeInfo(configID, " .. tostring(entryInfo.subTreeID) .. ")", C_Traits.GetSubTreeInfo, configID, entryInfo.subTreeID)
                        end
                    end
                end
            end
            -- Also try entryIDs list
            if nodeInfo.entryIDs then
                log("Info", "Role node entryIDs: " .. table.concat(nodeInfo.entryIDs or {}, ", "))
                for _, eid in ipairs(nodeInfo.entryIDs) do
                    tryAPI("C_Traits.GetEntryInfo(configID, entryID=" .. eid .. ")", C_Traits.GetEntryInfo, configID, eid)
                    local ok3, ei = pcall(C_Traits.GetEntryInfo, configID, eid)
                    if ok3 and ei and ei.subTreeID and C_Traits.GetSubTreeInfo then
                        tryAPI("C_Traits.GetSubTreeInfo(configID, subTree=" .. ei.subTreeID .. ")", C_Traits.GetSubTreeInfo, configID, ei.subTreeID)
                    end
                    if ok3 and ei and ei.definitionID and C_Traits.GetDefinitionInfo then
                        tryAPI("C_Traits.GetDefinitionInfo(def=" .. ei.definitionID .. ")", C_Traits.GetDefinitionInfo, ei.definitionID)
                    end
                end
            end
        end
    end

    -- Also probe GetRoleSubtreeForCompanion with different role types
    log("Info", "")
    log("Info", "-- Role subtree by type --")
    if C_DelvesUI and C_DelvesUI.GetRoleSubtreeForCompanion then
        for roleType = 0, 4 do
            tryAPI("GetRoleSubtreeForCompanion(" .. roleType .. ")", C_DelvesUI.GetRoleSubtreeForCompanion, roleType)
        end
    end

    -- 7b: Resolve Curio nodes
    log("Info", "")
    log("Info", "-- 7b: Curio Node Resolution --")
    if C_DelvesUI and C_DelvesUI.GetCurioNodeForCompanion then
        for curioType = 0, 3 do
            local ok, nodeID = pcall(C_DelvesUI.GetCurioNodeForCompanion, curioType)
            log("Info", "GetCurioNodeForCompanion(" .. curioType .. ") => " .. tostring(ok and nodeID or "ERROR: " .. tostring(nodeID)))
            if ok and nodeID and C_Traits and configID then
                local ok2, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                if ok2 and nodeInfo then
                    log("Info", "  Curio node " .. nodeID .. " activeEntry: " .. tostring(nodeInfo.activeEntry))
                    log("Info", "  Curio node " .. nodeID .. " type: " .. tostring(nodeInfo.type))
                    if nodeInfo.activeEntry then
                        local entryID = type(nodeInfo.activeEntry) == "table" and nodeInfo.activeEntry.entryID or nodeInfo.activeEntry
                        if entryID and C_Traits.GetEntryInfo then
                            local ok3, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entryID)
                            if ok3 and entryInfo then
                                log("Info", "  Entry definitionID: " .. tostring(entryInfo.definitionID))
                                if entryInfo.definitionID and C_Traits.GetDefinitionInfo then
                                    tryAPI("  C_Traits.GetDefinitionInfo(" .. entryInfo.definitionID .. ")", C_Traits.GetDefinitionInfo, entryInfo.definitionID)
                                end
                            end
                        end
                    end
                    -- Also list all entryIDs and resolve them
                    if nodeInfo.entryIDs then
                        log("Info", "  Curio node entryIDs: " .. table.concat(nodeInfo.entryIDs, ", "))
                        for _, eid in ipairs(nodeInfo.entryIDs) do
                            local ok4, ei = pcall(C_Traits.GetEntryInfo, configID, eid)
                            if ok4 and ei and ei.definitionID and C_Traits.GetDefinitionInfo then
                                local ok5, def = pcall(C_Traits.GetDefinitionInfo, ei.definitionID)
                                if ok5 and def then
                                    log("Info", "    entryID=" .. eid .. " defID=" .. ei.definitionID .. " spellID=" .. tostring(def.spellID) .. " overrideName=" .. tostring(def.overrideName))
                                    -- If we have a spellID, get the spell name
                                    if def.spellID and C_Spell and C_Spell.GetSpellName then
                                        local ok6, spellName = pcall(C_Spell.GetSpellName, def.spellID)
                                        if ok6 then
                                            log("Info", "    => spellName: " .. tostring(spellName))
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 7c: Delver's Journey XP details
    log("Info", "")
    log("Info", "-- 7c: Delver's Journey XP --")

    -- Try faction 2644 (Delves: Season 1 from MajorFactions)
    if C_MajorFactions then
        tryAPI("C_MajorFactions.GetMajorFactionData(2644)", C_MajorFactions.GetMajorFactionData, 2644)
        if C_MajorFactions.GetMajorFactionRenownInfo then
            tryAPI("C_MajorFactions.GetMajorFactionRenownInfo(2644)", C_MajorFactions.GetMajorFactionRenownInfo, 2644)
        end
        if C_MajorFactions.GetCurrentRenownLevel then
            tryAPI("C_MajorFactions.GetCurrentRenownLevel(2644)", C_MajorFactions.GetCurrentRenownLevel, 2644)
        end
        if C_MajorFactions.GetRenownLevels then
            tryAPI("C_MajorFactions.GetRenownLevels(2644)", C_MajorFactions.GetRenownLevels, 2644)
        end
        if C_MajorFactions.HasMaximumRenown then
            tryAPI("C_MajorFactions.HasMaximumRenown(2644)", C_MajorFactions.HasMaximumRenown, 2644)
        end
        if C_MajorFactions.ShouldDisplayMajorFactionAsJourney then
            tryAPI("C_MajorFactions.ShouldDisplayMajorFactionAsJourney(2644)", C_MajorFactions.ShouldDisplayMajorFactionAsJourney, 2644)
        end
        if C_MajorFactions.ShouldUseJourneyRewardTrack then
            tryAPI("C_MajorFactions.ShouldUseJourneyRewardTrack(2644)", C_MajorFactions.ShouldUseJourneyRewardTrack, 2644)
        end
    end

    -- Try faction 2742 (GetDelvesFactionForSeason result)
    log("Info", "")
    log("Info", "-- Faction 2742 (GetDelvesFactionForSeason) --")
    if C_MajorFactions then
        tryAPI("C_MajorFactions.GetMajorFactionData(2742)", C_MajorFactions.GetMajorFactionData, 2742)
        if C_MajorFactions.GetMajorFactionRenownInfo then
            tryAPI("C_MajorFactions.GetMajorFactionRenownInfo(2742)", C_MajorFactions.GetMajorFactionRenownInfo, 2742)
        end
        if C_MajorFactions.GetCurrentRenownLevel then
            tryAPI("C_MajorFactions.GetCurrentRenownLevel(2742)", C_MajorFactions.GetCurrentRenownLevel, 2742)
        end
    end
    if C_Reputation and C_Reputation.GetFactionDataByID then
        tryAPI("C_Reputation.GetFactionDataByID(2742)", C_Reputation.GetFactionDataByID, 2742)
    end
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        tryAPI("C_GossipInfo.GetFriendshipReputation(2742)", C_GossipInfo.GetFriendshipReputation, 2742)
    end

    -- Also try the Delver's Journey currency (3068) in more detail
    log("Info", "")
    log("Info", "-- Delver's Journey Currency (3068) --")
    if C_CurrencyInfo then
        if C_CurrencyInfo.GetCurrencyInfo then
            tryAPI("C_CurrencyInfo.GetCurrencyInfo(3068)", C_CurrencyInfo.GetCurrencyInfo, 3068)
        end
    end

    log("Info", "")
    log("Info", "=== /cpQuery Diagnostic Complete ===")

    -- Direct user to the debug log
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Print("CPQ", "Diagnostic complete — check Settings > Debug Log tab, then Export.")
    end
end

-- Store reference to our error handler for tests/introspection
CP._errorHandler    = CouchPotatoErrorHandler
CP._isSuiteError    = IsSuiteError
CP._guessAddonName  = GuessAddonName
CP._hookErrorHandler = HookErrorHandler

-- Enable/disable API exposed for tests and other addons
CP._addonAliases          = ADDON_ALIASES
CP._handleEnableDisable   = HandleEnableDisable
CP._doDisableAddon        = DoDisableAddon
CP._doEnableAddon         = DoEnableAddon
CP._printAddonStatus      = PrintAddonStatus
CP._ensureAddonStates     = EnsureAddonStates
CP._cpprint               = cpprint
