-- InfoPanels/BuiltIn/DelveCompanionStats.lua
-- Built-in panel: Delve Companion Stats.
-- PURE DATA TABLE — no customRender, no customUpdate, no function references.
-- Uses registered panel type "multi_section" via string key.
-- Uses shared Utils.IsInDelve() (DRY — no duplicated function).
--
-- Single Responsibility: DelveCompanionStats panel data definition.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

-- Companion name lookup
local COMPANION_NAMES = {
    [1] = "Brann Bronzebeard",
    [2] = "Faerin Lothar",
    [3] = "Waxmonger Squick",
    [4] = "Turalyon",
    [5] = "Thisalee Crow",
}

-- Boon abbreviation mapping
local BOON_ABBREVS = {
    ["critical strike"] = "Crit", ["crit"] = "Crit",
    ["haste"] = "Haste",
    ["mastery"] = "Mastery", ["mast"] = "Mast",
    ["versatility"] = "Vers", ["vers"] = "Vers",
    ["primary stat"] = "Primary",
    ["leech"] = "Leech",
    ["avoidance"] = "Avoidance",
    ["speed"] = "Speed",
    ["stamina"] = "Stam",
    ["armor"] = "Armor",
}

local function GetBoonAbbrev(rawStat)
    if not rawStat then return "" end
    local lower = rawStat:lower():match("^%s*(.-)%s*$")
    return BOON_ABBREVS[lower] or rawStat
end

-------------------------------------------------------------------------------
-- Register data sources for delve companion info.
-- These are registered at load time so the engine can bind to them.
-------------------------------------------------------------------------------
local function RegisterCompanionDataSources()
    local DataSources = ns.DataSources
    if not DataSources then return end
    local Utils = ns.Utils

    DataSources.Register("delve.companion.name", {
        name = "Companion Name",
        category = "Delve Info",
        description = "Active delve companion's name",
        events = { "PLAYER_ENTERING_WORLD", "UPDATE_FACTION" },
        fetch = function()
            if not _G.C_DelvesUI or not _G.C_DelvesUI.GetFactionForCompanion then
                return nil, "Delve API not available"
            end
            local ok, factionID = pcall(_G.C_DelvesUI.GetFactionForCompanion)
            if not ok or not factionID or factionID == 0 then return nil, "No companion data" end
            local name = "Companion"
            local ok2, compID = pcall(function()
                return _G.C_DelvesUI.GetActiveCompanion and _G.C_DelvesUI.GetActiveCompanion()
            end)
            if ok2 and compID and COMPANION_NAMES[compID] then
                name = COMPANION_NAMES[compID]
            end
            return name
        end,
    })

    DataSources.Register("delve.companion.leveltext", {
        name = "Companion Level",
        category = "Delve Info",
        description = "Companion level display text",
        events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not _G.C_DelvesUI or not _G.C_DelvesUI.GetFactionForCompanion then
                return nil, "Delve API not available"
            end
            local ok, factionID = pcall(_G.C_DelvesUI.GetFactionForCompanion)
            if not ok or not factionID or factionID == 0 then return nil, "No companion data" end
            if not _G.C_GossipInfo or not _G.C_GossipInfo.GetFriendshipReputation then
                return nil, "Friendship API not available"
            end
            local ok2, fr = pcall(_G.C_GossipInfo.GetFriendshipReputation, factionID)
            if ok2 and fr then
                return "Level " .. tostring(fr.reaction or "?")
            end
            return nil, "Could not read companion level"
        end,
    })

    DataSources.Register("delve.companion.xptext", {
        name = "Companion XP",
        category = "Delve Info",
        description = "Companion XP progress text",
        events = { "UPDATE_FACTION" },
        fetch = function()
            if not _G.C_DelvesUI or not _G.C_DelvesUI.GetFactionForCompanion then
                return nil, "Delve API not available"
            end
            local ok, factionID = pcall(_G.C_DelvesUI.GetFactionForCompanion)
            if not ok or not factionID or factionID == 0 then return nil, "No companion data" end
            if not _G.C_GossipInfo or not _G.C_GossipInfo.GetFriendshipReputation then
                return nil, "Friendship API not available"
            end
            local ok2, fr = pcall(_G.C_GossipInfo.GetFriendshipReputation, factionID)
            if ok2 and fr then
                local standing = fr.standing or 0
                local nextThreshold = fr.nextThreshold or fr.reactionThreshold or 0
                if nextThreshold and nextThreshold > 0 then
                    return Utils.FormatNumber(standing) .. " / " .. Utils.FormatNumber(nextThreshold)
                end
                return ""
            end
            return nil, "No XP data"
        end,
    })

    DataSources.Register("delve.companion.boons", {
        name = "Companion Boons",
        category = "Delve Info",
        description = "Active boon stat bonuses",
        events = { "UNIT_AURA" },
        fetch = function()
            if not _G.C_Spell or not _G.C_Spell.GetSpellDescription then return nil, "Spell API not available" end
            local ok, desc = pcall(_G.C_Spell.GetSpellDescription, 1280098)
            if not ok or not desc or desc == "" then return nil, "No boon data" end
            local clean = desc:gsub("|cn[^:]+:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local boons = {}
            for line in (clean .. "\n"):gmatch("([^\n]*)\n") do
                local rawStat, rawNum = line:match("^(.+):%s*(%d+)%%%D*$")
                if not rawStat then rawStat, rawNum = line:match("^(.+):%s*(%d+)%D*$") end
                if rawStat and rawNum then
                    rawStat = rawStat:match("^%s*(.-)%s*$")
                    boons[#boons + 1] = GetBoonAbbrev(rawStat) .. " +" .. rawNum .. "%"
                end
            end
            if #boons == 0 then return nil, "No boons active" end
            return table.concat(boons, ", ")
        end,
    })

    DataSources.Register("delve.companion.groups", {
        name = "Enemy Groups",
        category = "Delve Info",
        description = "Nemesis/enemy group progress",
        events = { "SCENARIO_CRITERIA_UPDATE", "CRITERIA_COMPLETE" },
        fetch = function()
            if not _G.C_ScenarioInfo or not _G.C_ScenarioInfo.GetScenarioStepInfo then
                return nil, "Scenario API not available"
            end
            local ok, stepInfo = pcall(_G.C_ScenarioInfo.GetScenarioStepInfo)
            if not ok or not stepInfo then return nil, "No scenario data" end
            local numCriteria = stepInfo.numCriteria or 0
            local total, completed = 0, 0
            for i = 1, numCriteria do
                local ok2, ci = pcall(_G.C_ScenarioInfo.GetCriteriaInfo, i)
                if ok2 and ci and ci.description then
                    local desc = ci.description:lower()
                    if desc:find("enem") or desc:find("group") or desc:find("kill") or desc:find("defeat") then
                        total = total + (ci.totalQuantity or 0)
                        completed = completed + (ci.quantity or 0)
                    end
                end
            end
            if total > 0 then
                return string.format("%d / %d groups", completed, total)
            end
            return nil, "No enemy group data"
        end,
    })
end

-------------------------------------------------------------------------------
-- Panel module
-------------------------------------------------------------------------------
local DelveCompanionStatsPanel = {}
ns.DelveCompanionStatsPanel = DelveCompanionStatsPanel

function DelveCompanionStatsPanel.RegisterDataSources()
    RegisterCompanionDataSources()
end

function DelveCompanionStatsPanel.GetDefinition()
    return {
        id = "delve_companion_stats",
        title = "Delve Companion",
        builtin = true,
        panelType = "multi_section",
        gap = -2,
        sections = {
            { sourceId = "delve.companion.name", defaultText = "Companion", height = 16 },
            { sourceId = "delve.companion.leveltext", defaultText = "Level ?", height = 18 },
            { sourceId = "delve.companion.xptext", defaultText = "", height = 16 },
            { isHeader = true, defaultText = "|cffFFD100Boons:|r", height = 16 },
            { sourceId = "delve.companion.boons", defaultText = "", hideOnError = true, height = 16 },
            { sourceId = "delve.companion.groups", defaultText = "", hideOnError = true, prefix = "|cffFFD100Groups:|r ", height = 18 },
        },
        layoutData = {
            sectionSpacing = 8,
            rowSpacing = 4,
            padding = 8,
        },
        events = {
            "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
            "UPDATE_FACTION", "UNIT_AURA",
            "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
            "SCENARIO_CRITERIA_UPDATE", "CRITERIA_COMPLETE",
        },
        visibility = { conditions = { { type = "delve_only" } } },
        -- Marketplace metadata
        description = "Shows delve companion name, level, XP, boons, and enemy group progress",
        author = "CouchPotato Addons",
        tags = { "delve", "companion", "boons", "groups" },
        uid = "DCS_builtin01",
    }
end

return DelveCompanionStatsPanel
