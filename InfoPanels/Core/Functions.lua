-- InfoPanels/Core/Functions.lua
-- Functions engine: replaces DataSources with user-editable Lua functions.
-- Each function has a NAME and CODE property. CODE is Lua that returns a string.
-- Functions are reusable across panels via {{FUNCTION_NAME}} template syntax.
--
-- Built-in functions come pre-registered (converted from old DataSources).
-- User functions are stored in InfoPanelsDB.functions and editable in the UI.
--
-- Single Responsibility: Function registration, execution, and template resolution.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local Functions = {}
ns.Functions = Functions

-- Internal registry: keyed by function name (uppercase)
local registry = {}

-- Cached return values (refreshed on events)
local cache = {}

-- Event subscriptions per function
local eventMap = {}  -- event -> { funcName1, funcName2, ... }

-- Performance guard
local MAX_FUNCTIONS = 200

-------------------------------------------------------------------------------
-- Register: Add a function to the registry.
-- Parameters:
--   name     - unique string name (uppercase, e.g. "PLAYER_HASTE")
--   info     - table with fields:
--     code      - Lua code string that returns a value (for user functions)
--     fetch     - direct Lua function (for built-in functions, bypasses loadstring)
--     events    - optional table of WoW events that trigger refresh
--     builtin   - boolean, true for pre-registered functions
--     category  - optional grouping for UI display
--     description - optional help text
-------------------------------------------------------------------------------
function Functions.Register(name, info)
    if not name or not info then return end
    name = name:upper()

    if registry[name] then
        iplog("Debug", "Functions.Register: overwriting " .. name)
    end

    info.name = name
    registry[name] = info

    -- Index events
    if info.events then
        for _, evt in ipairs(info.events) do
            if not eventMap[evt] then eventMap[evt] = {} end
            local found = false
            for _, n in ipairs(eventMap[evt]) do
                if n == name then found = true; break end
            end
            if not found then
                eventMap[evt][#eventMap[evt] + 1] = name
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Unregister: Remove a function from the registry.
-------------------------------------------------------------------------------
function Functions.Unregister(name)
    if not name then return end
    name = name:upper()
    registry[name] = nil
    cache[name] = nil

    -- Clean event index
    for evt, names in pairs(eventMap) do
        for i = #names, 1, -1 do
            if names[i] == name then
                table.remove(names, i)
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Get: Retrieve a function definition by name.
-------------------------------------------------------------------------------
function Functions.Get(name)
    if not name then return nil end
    return registry[name:upper()]
end

-------------------------------------------------------------------------------
-- GetAll: Return all registered functions.
-------------------------------------------------------------------------------
function Functions.GetAll()
    return registry
end

-------------------------------------------------------------------------------
-- GetAllSorted: Return all functions sorted by category then name.
-------------------------------------------------------------------------------
function Functions.GetAllSorted()
    local sorted = {}
    for name, info in pairs(registry) do
        sorted[#sorted + 1] = { name = name, info = info }
    end
    table.sort(sorted, function(a, b)
        local catA = a.info.category or ""
        local catB = b.info.category or ""
        if catA ~= catB then return catA < catB end
        return a.name < b.name
    end)
    return sorted
end

-------------------------------------------------------------------------------
-- Execute: Run a function and return its result as a string.
-- Uses cached value if available, otherwise executes.
-- Returns value (string), errorString
-------------------------------------------------------------------------------
function Functions.Execute(name)
    if not name then return nil, "No function name" end
    name = name:upper()

    local info = registry[name]
    if not info then
        return nil, "Unknown function: " .. name
    end

    -- Check cache first
    if cache[name] ~= nil then
        return cache[name], nil
    end

    local val, err

    if info.fetch then
        -- Built-in: direct Lua function
        local ok, result, fetchErr = pcall(info.fetch)
        if not ok then
            err = "Error: " .. tostring(result)
        elseif fetchErr then
            err = fetchErr
        else
            val = result
        end
    elseif info.code and info.code ~= "" then
        -- User function: execute via loadstring in sandbox
        val, err = Functions._executeCode(info.code, name)
    else
        err = "Function has no code: " .. name
    end

    -- Cache the result
    if val ~= nil then
        cache[name] = tostring(val)
    elseif err then
        cache[name] = "|cff888888" .. tostring(err) .. "|r"
    end

    return cache[name], err
end

-------------------------------------------------------------------------------
-- _executeCode: Execute user Lua code in a sandboxed environment.
-- Returns value, errorString
-------------------------------------------------------------------------------
function Functions._executeCode(code, name)
    if not code or code == "" then
        return nil, "Empty code"
    end

    -- Build sandbox environment with WoW API access
    local sandbox = setmetatable({}, { __index = _G })

    local fn, loadErr
    if loadstring then
        fn, loadErr = loadstring("return (function() " .. code .. " end)()")
        if fn and setfenv then
            setfenv(fn, sandbox)
        end
    elseif load then
        fn, loadErr = load("return (function() " .. code .. " end)()", name or "func", "t", sandbox)
    end

    if not fn then
        return nil, "Syntax error: " .. tostring(loadErr)
    end

    local ok, result = pcall(fn)
    if not ok then
        return nil, "Runtime error: " .. tostring(result)
    end

    if result == nil then
        return nil, "Function returned nil"
    end

    return tostring(result), nil
end

-------------------------------------------------------------------------------
-- InvalidateCache: Clear cached value for a function (or all if name is nil).
-------------------------------------------------------------------------------
function Functions.InvalidateCache(name)
    if name then
        cache[name:upper()] = nil
    else
        cache = {}
    end
end

-------------------------------------------------------------------------------
-- RefreshForEvent: Invalidate cache for all functions subscribed to an event.
-------------------------------------------------------------------------------
function Functions.RefreshForEvent(event)
    local names = eventMap[event]
    if not names then return end
    for _, name in ipairs(names) do
        cache[name] = nil
    end
end

-------------------------------------------------------------------------------
-- GetEventsForFunction: Return the events a function listens to.
-------------------------------------------------------------------------------
function Functions.GetEventsForFunction(name)
    if not name then return {} end
    name = name:upper()
    local info = registry[name]
    if not info then return {} end
    return info.events or {}
end

-------------------------------------------------------------------------------
-- GetAllEvents: Return all unique events across all functions.
-------------------------------------------------------------------------------
function Functions.GetAllEvents()
    local events = {}
    for evt in pairs(eventMap) do
        events[#events + 1] = evt
    end
    table.sort(events)
    return events
end

-------------------------------------------------------------------------------
-- ResolveTemplate: Replace {{FUNCTION_NAME}} in a template string with values.
-- Returns the resolved string.
-------------------------------------------------------------------------------
function Functions.ResolveTemplate(template)
    if not template or template == "" then return "" end

    local resolved = template:gsub("{{(.-)}}", function(name)
        local trimmed = name:match("^%s*(.-)%s*$")
        if not trimmed or trimmed == "" then return "{{" .. name .. "}}" end
        local val, err = Functions.Execute(trimmed)
        if val then return val end
        return "|cff888888??|r"
    end)

    return resolved
end

-------------------------------------------------------------------------------
-- RegisterBuiltInFunctions: Convert all old data sources to built-in functions.
-- Called at addon load time.
-------------------------------------------------------------------------------
function Functions.RegisterBuiltInFunctions()
    -- Player Stats
    local statDefs = {
        { name = "PLAYER_STRENGTH",  stat = 1, label = "Strength" },
        { name = "PLAYER_AGILITY",   stat = 2, label = "Agility" },
        { name = "PLAYER_STAMINA",   stat = 3, label = "Stamina" },
        { name = "PLAYER_INTELLECT", stat = 4, label = "Intellect" },
    }
    for _, def in ipairs(statDefs) do
        local statIndex = def.stat
        Functions.Register(def.name, {
            category = "Player Stats",
            description = def.label .. " rating",
            builtin = true,
            events = { "UNIT_STATS", "PLAYER_ENTERING_WORLD" },
            fetch = function()
                if not UnitStat then return nil, "UnitStat not available" end
                local ok, val = pcall(UnitStat, "player", statIndex)
                if ok and val then return tostring(math.floor(val + 0.5)) end
                return nil, "Could not read " .. def.label
            end,
        })
    end

    -- Secondary Stats
    local secondaryDefs = {
        { name = "PLAYER_HASTE",    fn = "GetHaste",        fmt = "%.1f%%", label = "Haste" },
        { name = "PLAYER_CRIT",     fn = "GetCritChance",   fmt = "%.1f%%", label = "Critical Strike" },
        { name = "PLAYER_MASTERY",  fn = "GetMasteryEffect", fmt = "%.1f%%", label = "Mastery" },
    }
    for _, def in ipairs(secondaryDefs) do
        local fnName = def.fn
        local fmt = def.fmt
        Functions.Register(def.name, {
            category = "Player Stats",
            description = def.label .. " percentage",
            builtin = true,
            events = { "UNIT_STATS", "PLAYER_ENTERING_WORLD", "COMBAT_RATING_UPDATE" },
            fetch = function()
                local fn = _G[fnName]
                if not fn then return nil, fnName .. " not available" end
                local ok, val = pcall(fn)
                if ok and val then return string.format(fmt, val) end
                return nil, "Could not read " .. def.label
            end,
        })
    end

    -- Versatility
    Functions.Register("PLAYER_VERSATILITY", {
        category = "Player Stats",
        description = "Versatility damage bonus percentage",
        builtin = true,
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
    Functions.Register("PLAYER_NAME", {
        category = "Player Info",
        description = "Your character's name",
        builtin = true,
        events = { "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not UnitName then return nil, "UnitName not available" end
            local ok, name = pcall(UnitName, "player")
            if ok and name then return name end
            return nil, "Could not read player name"
        end,
    })

    Functions.Register("PLAYER_LEVEL", {
        category = "Player Info",
        description = "Your character's level",
        builtin = true,
        events = { "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not UnitLevel then return nil, "UnitLevel not available" end
            local ok, level = pcall(UnitLevel, "player")
            if ok and level then return tostring(level) end
            return nil, "Could not read player level"
        end,
    })

    Functions.Register("PLAYER_CLASS", {
        category = "Player Info",
        description = "Your character's class",
        builtin = true,
        events = { "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not UnitClass then return nil, "UnitClass not available" end
            local ok, className = pcall(UnitClass, "player")
            if ok and className then return className end
            return nil, "Could not read player class"
        end,
    })

    Functions.Register("PLAYER_HEALTH", {
        category = "Player Stats",
        description = "Current health",
        builtin = true,
        events = { "UNIT_HEALTH", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not UnitHealth then return nil, "UnitHealth not available" end
            local ok, val = pcall(UnitHealth, "player")
            if ok and val then return tostring(val) end
            return nil, "Could not read health"
        end,
    })

    Functions.Register("PLAYER_HEALTH_MAX", {
        category = "Player Stats",
        description = "Maximum health",
        builtin = true,
        events = { "UNIT_MAXHEALTH", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            if not UnitHealthMax then return nil, "UnitHealthMax not available" end
            local ok, val = pcall(UnitHealthMax, "player")
            if ok and val then return tostring(val) end
            return nil, "Could not read max health"
        end,
    })

    Functions.Register("PLAYER_SPEC", {
        category = "Player Info",
        description = "Active specialization name",
        builtin = true,
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
    Functions.Register("DELVE_COMPANION_LEVEL", {
        category = "Delve Info",
        description = "Your delve companion's current level",
        builtin = true,
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
            if ok2 and fr and fr.reaction then return tostring(fr.reaction) end
            return nil, "Could not read companion level"
        end,
    })

    Functions.Register("DELVE_SEASON_RANK", {
        category = "Delve Info",
        description = "Your Delver's Journey season rank",
        builtin = true,
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
            if ok2 and rInfo and rInfo.renownLevel then return tostring(rInfo.renownLevel) end
            return nil, "Could not read season rank"
        end,
    })

    Functions.Register("DELVE_SEASON_XP", {
        category = "Delve Info",
        description = "Current / Max XP for Delver's Journey rank",
        builtin = true,
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

    Functions.Register("IN_DELVE", {
        category = "Delve Info",
        description = "Whether you are currently inside a delve (true/false)",
        builtin = true,
        events = { "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
        fetch = function()
            local Utils = ns.Utils
            if Utils and Utils.IsInDelve then
                return tostring(Utils.IsInDelve())
            end
            return "false"
        end,
    })

    iplog("Info", "RegisterBuiltInFunctions: complete")
end

-------------------------------------------------------------------------------
-- LoadUserFunctions: Load user-defined functions from SavedVariables.
-------------------------------------------------------------------------------
function Functions.LoadUserFunctions()
    local db = _G.InfoPanelsDB
    if not db or not db.functions then return end

    for name, funcDef in pairs(db.functions) do
        Functions.Register(name, {
            code = funcDef.code or "",
            events = funcDef.events or {},
            category = funcDef.category or "User",
            description = funcDef.description or "",
            builtin = false,
        })
    end

    iplog("Info", "LoadUserFunctions: loaded " .. (function()
        local count = 0
        if db.functions then for _ in pairs(db.functions) do count = count + 1 end end
        return count
    end)() .. " user functions")
end

-------------------------------------------------------------------------------
-- SaveUserFunction: Persist a user function to SavedVariables.
-------------------------------------------------------------------------------
function Functions.SaveUserFunction(name, code, events, category, description)
    if not name then return false, "No function name" end
    name = name:upper()

    local db = _G.InfoPanelsDB or {}
    db.functions = db.functions or {}
    _G.InfoPanelsDB = db

    db.functions[name] = {
        code = code or "",
        events = events or {},
        category = category or "User",
        description = description or "",
    }

    -- Register or update in runtime registry
    Functions.Register(name, {
        code = code or "",
        events = events or {},
        category = category or "User",
        description = description or "",
        builtin = false,
    })

    -- Invalidate cache
    cache[name] = nil

    iplog("Info", "SaveUserFunction: saved " .. name)
    return true
end

-------------------------------------------------------------------------------
-- DeleteUserFunction: Remove a user function from SavedVariables and registry.
-------------------------------------------------------------------------------
function Functions.DeleteUserFunction(name)
    if not name then return false, "No function name" end
    name = name:upper()

    local info = registry[name]
    if info and info.builtin then
        return false, "Cannot delete built-in function"
    end

    local db = _G.InfoPanelsDB or {}
    if db.functions then
        db.functions[name] = nil
    end

    Functions.Unregister(name)
    iplog("Info", "DeleteUserFunction: deleted " .. name)
    return true
end

return Functions
