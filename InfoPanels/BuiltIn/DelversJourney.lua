-- InfoPanels/BuiltIn/DelversJourney.lua
-- Built-in panel: Delver's Journey season rank and XP.
-- PURE DATA TABLE — no customRender, no customUpdate, no function references.
-- Uses registered panel type "simple_info" via string key.
-- Uses shared Utils.IsInDelve() (DRY — no duplicated function).
--
-- Single Responsibility: DelversJourney panel data definition.

local _, ns = ...
if not ns then ns = {} end

local DelversJourneyPanel = {}
ns.DelversJourneyPanel = DelversJourneyPanel

function DelversJourneyPanel.GetDefinition()
    return {
        id = "delvers_journey",
        title = "Delver's Journey",
        builtin = true,
        panelType = "simple_info",
        gap = -14,
        rows = {
            { sourceId = "delve.season.rank", defaultText = "Rank ?", prefix = "Rank ", height = 18 },
            { sourceId = "delve.season.xp", defaultText = "", height = 16 },
        },
        layoutData = {
            rowHeight = 18,
            rowSpacing = 4,
            padding = 8,
        },
        events = {
            "PLAYER_ENTERING_WORLD", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
            "UPDATE_FACTION", "QUEST_WATCH_LIST_CHANGED", "QUEST_LOG_UPDATE",
            "ZONE_CHANGED_NEW_AREA",
        },
        visibility = { conditions = { { type = "delve_only" } } },
        -- Marketplace metadata
        description = "Shows Delver's Journey season rank and XP progress",
        author = "CouchPotato Addons",
        tags = { "delve", "season", "rank", "xp" },
        uid = "DJ_builtin01",
    }
end

return DelversJourneyPanel
