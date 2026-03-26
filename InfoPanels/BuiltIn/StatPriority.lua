-- InfoPanels/BuiltIn/StatPriority.lua
-- Built-in panel: Stat Priority circle display.
-- PURE DATA TABLE — no customRender, no customUpdate, no function references.
-- Uses registered panel type "circle_row" via string key.
-- Identical to user-created panels in every way.
--
-- Single Responsibility: StatPriority panel data definition.

local _, ns = ...
if not ns then ns = {} end

local StatPriorityPanel = {}
ns.StatPriorityPanel = StatPriorityPanel

-------------------------------------------------------------------------------
-- GetDisplaySpecID: Resolve which spec to show priorities for.
-- Uses spec override from DB, loot spec, or active spec.
-------------------------------------------------------------------------------
local function GetDisplaySpecID()
    local override = _G.InfoPanelsDB and _G.InfoPanelsDB.panels
        and _G.InfoPanelsDB.panels.stat_priority and _G.InfoPanelsDB.panels.stat_priority.specOverride
    if not override and _G.StatPriorityDB then
        override = _G.StatPriorityDB.specOverride
    end

    if type(override) == "number" then return override end
    if override == "loot" then
        local lootSpecID = 0
        if _G.GetLootSpecialization then lootSpecID = _G.GetLootSpecialization() or 0 end
        if lootSpecID and lootSpecID > 0 then return lootSpecID end
    end
    if not _G.GetSpecialization then return nil end
    local specIndex = _G.GetSpecialization()
    if not specIndex or specIndex <= 0 then return nil end
    if not _G.GetSpecializationInfo then return 0 end
    return select(1, _G.GetSpecializationInfo(specIndex))
end

-------------------------------------------------------------------------------
-- GetDefinition: Returns a PURE DATA TABLE. No functions.
-- The panel type "circle_row" handles all rendering via registry lookup.
-------------------------------------------------------------------------------
function StatPriorityPanel.GetDefinition()
    -- Resolve spec data at definition time (will be refreshed on update)
    local specID = GetDisplaySpecID()
    local specName = "Stat Priority"
    local statsArray = {}

    if specID and specID > 0 and _G.StatPriorityData then
        local data = _G.StatPriorityData[specID]
        if data then
            specName = data.specName or specName
            statsArray = data.stats or {}
        end
    end

    return {
        id = "stat_priority",
        title = specName,
        builtin = true,
        panelType = "circle_row",
        gap = -14,
        stats = statsArray,
        specOverride = nil,
        layoutData = {
            circleSize = 46,
            connectorWidth = 8,
        },
        dataEntry = {
            { type = "paste_box", format = "text", description = "Paste stat priorities from archon.gg" },
            { type = "drag_reorder", description = "Drag stats to reorder priority" },
        },
        events = {
            "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LOGIN",
            "PLAYER_LOOT_SPEC_UPDATED", "UNIT_STATS", "COMBAT_RATING_UPDATE",
            "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD",
            "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA",
        },
        -- Marketplace metadata
        description = "Shows stat priority for your current specialization with live stat values",
        author = "CouchPotato Addons",
        tags = { "stat-priority", "stats", "dps", "tank", "healer" },
        uid = "SP_builtin01",
    }
end

-------------------------------------------------------------------------------
-- RefreshDefinition: Update the panel definition with current spec data.
-- Called by the engine before modify() via the update cycle.
-------------------------------------------------------------------------------
function StatPriorityPanel.RefreshDefinition(definition)
    local specID = GetDisplaySpecID()
    local specName = "Stat Priority"
    local statsArray = {}

    if specID and specID > 0 and _G.StatPriorityData then
        local data = _G.StatPriorityData[specID]
        if data then
            specName = data.specName or specName
            statsArray = data.stats or {}
        end
    elseif specID and specID > 0 then
        if _G.GetSpecialization and _G.GetSpecializationInfo then
            local idx = _G.GetSpecialization()
            if idx and idx > 0 then
                local _, name = _G.GetSpecializationInfo(idx)
                if name then specName = name end
            end
        end
    end

    definition.title = specName
    definition.stats = statsArray
    return definition
end

return StatPriorityPanel
