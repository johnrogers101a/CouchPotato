-- InfoPanels/Core/DataSources.lua
-- Registry of data sources that panels can bind to.
-- Each source has a human-readable name, category, description,
-- and a fetch function that returns the current value.
--
-- Single Responsibility: Data source registration and lookup.
-- Open/Closed: New sources are added via Register(), never by modifying this file.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local DataSources = {}
ns.DataSources = DataSources

-- Internal registry: keyed by source ID
local registry = {}

-- Category index for editor browsing
local categories = {}

-------------------------------------------------------------------------------
-- Register: Add a data source to the registry.
-- Parameters:
--   id          - unique string ID (e.g. "player.haste")
--   info        - table with fields:
--     name        - human-readable display name (e.g. "Haste Rating")
--     category    - category for editor grouping (e.g. "Player Stats")
--     description - tooltip/help text
--     fetch       - function() returning (value, error_string_or_nil)
--     events      - optional table of WoW events that trigger refresh
-------------------------------------------------------------------------------
function DataSources.Register(id, info)
    if not id or not info then return end
    if registry[id] then
        iplog("Warn", "DataSources.Register: overwriting existing source " .. id)
    end
    info.id = id
    registry[id] = info

    -- Index by category
    local cat = info.category or "Other"
    if not categories[cat] then
        categories[cat] = {}
    end
    categories[cat][#categories[cat] + 1] = id
end

-------------------------------------------------------------------------------
-- Get: Retrieve a data source by ID.
-------------------------------------------------------------------------------
function DataSources.Get(id)
    return registry[id]
end

-------------------------------------------------------------------------------
-- Fetch: Safely call a data source's fetch function.
-- Returns value, errorString
-------------------------------------------------------------------------------
function DataSources.Fetch(id)
    local source = registry[id]
    if not source then
        return nil, "Unknown data source: " .. tostring(id)
    end
    if not source.fetch then
        return nil, "Data source has no fetch function: " .. tostring(id)
    end
    local ok, val, err = pcall(source.fetch)
    if not ok then
        return nil, "API error: " .. tostring(val)
    end
    return val, err
end

-------------------------------------------------------------------------------
-- GetCategories: Return sorted list of category names.
-------------------------------------------------------------------------------
function DataSources.GetCategories()
    local cats = {}
    for cat, _ in pairs(categories) do
        cats[#cats + 1] = cat
    end
    table.sort(cats)
    return cats
end

-------------------------------------------------------------------------------
-- GetSourcesInCategory: Return list of source IDs in a category.
-------------------------------------------------------------------------------
function DataSources.GetSourcesInCategory(category)
    return categories[category] or {}
end

-------------------------------------------------------------------------------
-- Search: Find sources matching a query string (case-insensitive).
-- Searches name, category, and description.
-------------------------------------------------------------------------------
function DataSources.Search(query)
    if not query or query == "" then return {} end
    local q = query:lower()
    local results = {}
    for id, info in pairs(registry) do
        local searchable = ((info.name or "") .. " " .. (info.category or "") .. " " .. (info.description or "")):lower()
        if searchable:find(q, 1, true) then
            results[#results + 1] = id
        end
    end
    table.sort(results, function(a, b)
        return (registry[a].name or a) < (registry[b].name or b)
    end)
    return results
end

-------------------------------------------------------------------------------
-- RegisterExternal: Register a data source backed by external/manual data.
-- External sources store user-entered data (e.g., pasted from websites like
-- archon.gg) rather than fetching from WoW APIs. The engine persists the data
-- in SavedVariables and the fetch function reads from that storage.
--
-- Parameters:
--   sourceId    - unique string ID (e.g. "external.stat_priority")
--   opts        - table with fields:
--     name        - human-readable display name
--     category    - category for editor grouping (default: "External Data")
--     description - tooltip/help text
--     dataEntry   - table describing how data is entered:
--       type      - "paste_box" | "click_to_edit" | "drag_reorder" | "manual"
--       format    - optional hint: "text", "number", "list", "table"
--     storage     - table reference where the value is stored (read/write)
--     storageKey  - key within storage table (default: sourceId)
-------------------------------------------------------------------------------
function DataSources.RegisterExternal(sourceId, opts)
    opts = opts or {}
    local storage = opts.storage or {}
    local storageKey = opts.storageKey or sourceId

    DataSources.Register(sourceId, {
        name = opts.name or sourceId,
        category = opts.category or "External Data",
        description = opts.description or "Manually entered data",
        events = opts.events or {},
        external = true,
        dataEntry = opts.dataEntry or { type = "manual", format = "text" },
        storage = storage,
        storageKey = storageKey,
        fetch = function()
            local val = storage[storageKey]
            if val == nil then return nil, "No data entered" end
            return val, nil
        end,
        store = function(value)
            storage[storageKey] = value
        end,
    })
end

-------------------------------------------------------------------------------
-- StoreExternal: Write a value to an external data source's storage.
-- Returns true on success, false + error on failure.
-------------------------------------------------------------------------------
function DataSources.StoreExternal(sourceId, value)
    local source = registry[sourceId]
    if not source then
        return false, "Unknown data source: " .. tostring(sourceId)
    end
    if not source.external then
        return false, "Data source is not external: " .. tostring(sourceId)
    end
    if not source.store then
        return false, "Data source has no store function: " .. tostring(sourceId)
    end
    local ok, err = pcall(source.store, value)
    if not ok then
        return false, "Store error: " .. tostring(err)
    end
    return true, nil
end

-------------------------------------------------------------------------------
-- GetAll: Return the full registry (for export/schema generation).
-------------------------------------------------------------------------------
function DataSources.GetAll()
    return registry
end

-------------------------------------------------------------------------------
-- GetAllSorted: Return all sources sorted by category then name.
-------------------------------------------------------------------------------
function DataSources.GetAllSorted()
    local sorted = {}
    for id, info in pairs(registry) do
        sorted[#sorted + 1] = { id = id, info = info }
    end
    table.sort(sorted, function(a, b)
        local catA = a.info.category or ""
        local catB = b.info.category or ""
        if catA ~= catB then return catA < catB end
        return (a.info.name or a.id) < (b.info.name or b.id)
    end)
    return sorted
end

-------------------------------------------------------------------------------
-- FetchDynamic: pcall-wrapped access to ANY WoW API by global name.
-- Supports dotted paths like "C_CurrencyInfo.GetCurrencyInfo".
-- Returns value, errorString. Nil APIs return nil, "API unavailable".
-- Nil return values show nil, "No data".
-------------------------------------------------------------------------------
function DataSources.FetchDynamic(apiPath, ...)
    if not apiPath or apiPath == "" then
        return nil, "Empty API path"
    end

    -- Resolve dotted path (e.g. "C_CurrencyInfo.GetCurrencyInfo")
    local fn = _G
    local segments = {}
    for segment in apiPath:gmatch("[^%.]+") do
        segments[#segments + 1] = segment
    end

    for i, segment in ipairs(segments) do
        if type(fn) ~= "table" then
            return nil, "API unavailable: " .. apiPath
        end
        local next = fn[segment]
        if next == nil then
            -- Parent namespace exists but leaf method is nil → "No data"
            -- Top-level global missing → "API unavailable"
            if i > 1 then
                return nil, "No data"
            end
            return nil, "API unavailable: " .. apiPath
        end
        fn = next
    end

    if type(fn) ~= "function" then
        return nil, "API unavailable: " .. apiPath .. " is not a function"
    end

    local results = { pcall(fn, ...) }
    if not results[1] then
        return nil, "API error: " .. tostring(results[2])
    end

    -- Remove the pcall success boolean
    table.remove(results, 1)
    if #results == 0 or results[1] == nil then
        return nil, "No data"
    end

    -- Return first value for simple cases, full results table for multi-return
    if #results == 1 then
        return results[1], nil
    end
    return results, nil
end

-------------------------------------------------------------------------------
-- RegisterDynamic: Register a data source wrapping any WoW API by path.
-- This enables the engine to bind to arbitrary APIs without pre-registration.
-------------------------------------------------------------------------------
function DataSources.RegisterDynamic(sourceId, apiPath, args, opts)
    opts = opts or {}
    local argsCopy = args or {}
    DataSources.Register(sourceId, {
        name = opts.name or apiPath,
        category = opts.category or "Dynamic API",
        description = opts.description or ("Dynamic binding to " .. apiPath),
        events = opts.events or {},
        fetch = function()
            return DataSources.FetchDynamic(apiPath, unpack(argsCopy))
        end,
    })
end

-------------------------------------------------------------------------------
-- DiscoverAPIs: Search WoW global namespace for functions matching a pattern.
-- Returns a sorted list of { path, type } tables.
-- Searches top-level globals and one level of C_ namespace tables.
-------------------------------------------------------------------------------
function DataSources.DiscoverAPIs(pattern)
    if not pattern or pattern == "" then return {} end
    local lowerPattern = pattern:lower()
    local results = {}

    -- Search top-level globals
    for name, val in pairs(_G) do
        if type(name) == "string" and type(val) == "function" then
            if name:lower():find(lowerPattern, 1, true) then
                results[#results + 1] = { path = name, apiType = "function" }
            end
        end
    end

    -- Search C_ namespaces (one level deep)
    for name, val in pairs(_G) do
        if type(name) == "string" and type(val) == "table" and name:sub(1, 2) == "C_" then
            for fnName, fnVal in pairs(val) do
                if type(fnName) == "string" and type(fnVal) == "function" then
                    local fullPath = name .. "." .. fnName
                    if fullPath:lower():find(lowerPattern, 1, true) then
                        results[#results + 1] = { path = fullPath, apiType = "function" }
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.path < b.path end)
    return results
end

-------------------------------------------------------------------------------
-- RegisterBuiltInSources: Register the common WoW API data sources.
-- Called at addon load time.
-------------------------------------------------------------------------------
function DataSources.RegisterBuiltInSources()
    -- Player Stats
    local statDefs = {
        { id = "player.strength",  name = "Strength",      stat = 1, primary = true },
        { id = "player.agility",   name = "Agility",       stat = 2, primary = true },
        { id = "player.stamina",   name = "Stamina",       stat = 3, primary = true },
        { id = "player.intellect", name = "Intellect",     stat = 4, primary = true },
    }
    for _, def in ipairs(statDefs) do
        local statIndex = def.stat
        DataSources.Register(def.id, {
            name = def.name,
            category = "Player Stats",
            description = def.name .. " rating",
            events = { "UNIT_STATS", "PLAYER_ENTERING_WORLD" },
            fetch = function()
                if not UnitStat then return nil, "UnitStat not available" end
                local ok, val = pcall(UnitStat, "player", statIndex)
                if ok and val then return math.floor(val + 0.5) end
                return nil, "Could not read " .. def.name
            end,
        })
    end

    -- Secondary Stats
    local secondaryDefs = {
        { id = "player.haste",       name = "Haste",         fn = "GetHaste",        fmt = "%.1f%%" },
        { id = "player.crit",        name = "Critical Strike", fn = "GetCritChance",   fmt = "%.1f%%" },
        { id = "player.mastery",     name = "Mastery",       fn = "GetMasteryEffect", fmt = "%.1f%%" },
    }
    for _, def in ipairs(secondaryDefs) do
        local fnName = def.fn
        local fmt = def.fmt
        DataSources.Register(def.id, {
            name = def.name,
            category = "Player Stats",
            description = def.name .. " percentage",
            events = { "UNIT_STATS", "PLAYER_ENTERING_WORLD", "COMBAT_RATING_UPDATE" },
            fetch = function()
                local fn = _G[fnName]
                if not fn then return nil, fnName .. " not available" end
                local ok, val = pcall(fn)
                if ok and val then return string.format(fmt, val) end
                return nil, "Could not read " .. def.name
            end,
        })
    end

    -- Versatility (special case)
    DataSources.Register("player.versatility", {
        name = "Versatility",
        category = "Player Stats",
        description = "Versatility damage bonus percentage",
        events = { "COMBAT_RATING_UPDATE", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not _G.GetCombatRatingBonus or not _G.CR_VERSATILITY_DAMAGE_DONE then
                return nil, "Versatility API not available"
            end
            local ok, val = pcall(_G.GetCombatRatingBonus, _G.CR_VERSATILITY_DAMAGE_DONE)
            if ok and val then return string.format("%.1f%%", val) end
            return nil, "Could not read Versatility"
        end,
    })

    -- Player Info
    DataSources.Register("player.name", {
        name = "Player Name",
        category = "Player Info",
        description = "Your character's name",
        events = { "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not UnitName then return nil, "UnitName not available" end
            local ok, name = pcall(UnitName, "player")
            if ok and name then return name end
            return nil, "Could not read player name"
        end,
    })

    DataSources.Register("player.level", {
        name = "Player Level",
        category = "Player Info",
        description = "Your character's level",
        events = { "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not UnitLevel then return nil, "UnitLevel not available" end
            local ok, level = pcall(UnitLevel, "player")
            if ok and level then return level end
            return nil, "Could not read player level"
        end,
    })

    DataSources.Register("player.class", {
        name = "Player Class",
        category = "Player Info",
        description = "Your character's class",
        events = { "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not UnitClass then return nil, "UnitClass not available" end
            local ok, className = pcall(UnitClass, "player")
            if ok and className then return className end
            return nil, "Could not read player class"
        end,
    })

    DataSources.Register("player.health", {
        name = "Health",
        category = "Player Stats",
        description = "Current health",
        events = { "UNIT_HEALTH", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not UnitHealth then return nil, "UnitHealth not available" end
            local ok, val = pcall(UnitHealth, "player")
            if ok and val then return val end
            return nil, "Could not read health"
        end,
    })

    DataSources.Register("player.healthmax", {
        name = "Max Health",
        category = "Player Stats",
        description = "Maximum health",
        events = { "UNIT_MAXHEALTH", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not UnitHealthMax then return nil, "UnitHealthMax not available" end
            local ok, val = pcall(UnitHealthMax, "player")
            if ok and val then return val end
            return nil, "Could not read max health"
        end,
    })

    DataSources.Register("player.spec", {
        name = "Specialization",
        category = "Player Info",
        description = "Active specialization name",
        events = { "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not GetSpecialization or not GetSpecializationInfo then
                return nil, "Spec API not available"
            end
            local idx = GetSpecialization()
            if not idx or idx <= 0 then return "None", nil end
            local ok, _, name = pcall(GetSpecializationInfo, idx)
            if ok and name then return name end
            return nil, "Could not read specialization"
        end,
    })

    -- Delve Info
    DataSources.Register("delve.companion.level", {
        name = "Companion Level",
        category = "Delve Info",
        description = "Your delve companion's current level",
        events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not C_DelvesUI or not C_DelvesUI.GetFactionForCompanion then
                return nil, "Delve API not available"
            end
            local ok, factionID = pcall(C_DelvesUI.GetFactionForCompanion)
            if not ok or not factionID or factionID == 0 then
                return nil, "No companion data"
            end
            if not C_GossipInfo or not C_GossipInfo.GetFriendshipReputation then
                return nil, "Friendship API not available"
            end
            local ok2, fr = pcall(C_GossipInfo.GetFriendshipReputation, factionID)
            if ok2 and fr and fr.reaction then return fr.reaction end
            return nil, "Could not read companion level"
        end,
    })

    DataSources.Register("delve.season.rank", {
        name = "Season Rank",
        category = "Delve Info",
        description = "Your Delver's Journey season rank",
        events = { "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not C_DelvesUI or not C_DelvesUI.GetDelvesFactionForSeason then
                return nil, "Delves season API not available"
            end
            local ok, factionID = pcall(C_DelvesUI.GetDelvesFactionForSeason)
            if not ok or not factionID or factionID == 0 then
                return nil, "No season data"
            end
            if not C_MajorFactions or not C_MajorFactions.GetMajorFactionRenownInfo then
                return nil, "Major Factions API not available"
            end
            local ok2, rInfo = pcall(C_MajorFactions.GetMajorFactionRenownInfo, factionID)
            if ok2 and rInfo and rInfo.renownLevel then return rInfo.renownLevel end
            return nil, "Could not read season rank"
        end,
    })

    DataSources.Register("delve.season.xp", {
        name = "Season XP",
        category = "Delve Info",
        description = "Current / Max XP for Delver's Journey rank",
        events = { "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "UPDATE_FACTION" },
        fetch = function()
            if not C_DelvesUI or not C_DelvesUI.GetDelvesFactionForSeason then
                return nil, "Delves season API not available"
            end
            local ok, factionID = pcall(C_DelvesUI.GetDelvesFactionForSeason)
            if not ok or not factionID or factionID == 0 then
                return nil, "No season data"
            end
            if not C_MajorFactions or not C_MajorFactions.GetMajorFactionRenownInfo then
                return nil, "Major Factions API not available"
            end
            local ok2, rInfo = pcall(C_MajorFactions.GetMajorFactionRenownInfo, factionID)
            if ok2 and rInfo then
                local earned = rInfo.renownReputationEarned or 0
                local max = rInfo.renownLevelThreshold or 0
                return earned .. " / " .. max
            end
            return nil, "Could not read season XP"
        end,
    })

    DataSources.Register("delve.indelve", {
        name = "In Delve",
        category = "Delve Info",
        description = "Whether you are currently inside a delve",
        events = { "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            local Utils = ns.Utils
            if Utils and Utils.IsInDelve then
                return Utils.IsInDelve()
            end
            return false
        end,
    })

    iplog("Info", "RegisterBuiltInSources: complete")
end

return DataSources
