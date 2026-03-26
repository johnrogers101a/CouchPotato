-- InfoPanels/Core/Registry.lua
-- Central registry system inspired by WeakAuras' RegisterRegionType pattern.
-- Everything is data. Behavior is selected by string keys into registries.
-- The engine only talks to registries, never about specific types.
--
-- Single Responsibility: Type registration and lookup.
-- Open/Closed: New types added via Register calls, zero changes to engine.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local Registry = {}
ns.Registry = Registry

-------------------------------------------------------------------------------
-- Panel Type Registry
-- Each panel type: { create, modify, default, properties }
--   create(parent, data)       -> builds WoW frame hierarchy, returns region
--   modify(parent, region, data) -> applies data values to existing frames
--   default                    -> table of default property values
--   properties                 -> table mapping property names to {type, setter, display, min, max, ...}
-------------------------------------------------------------------------------
local panelTypes = {}

function Registry.RegisterPanelType(name, definition)
    if not name or not definition then
        iplog("Error", "RegisterPanelType: name and definition required")
        return
    end
    if panelTypes[name] then
        iplog("Warn", "RegisterPanelType: overwriting existing type '" .. name .. "'")
    end
    panelTypes[name] = definition
    iplog("Info", "RegisterPanelType: '" .. name .. "'")
end

function Registry.GetPanelType(name)
    return panelTypes[name]
end

function Registry.GetAllPanelTypes()
    return panelTypes
end

-------------------------------------------------------------------------------
-- Data Source Type Registry
-- Each data source type: { fetch, args, events, name, category, description }
--   fetch(args)    -> returns (value, error_string_or_nil)
--   args           -> table of argument definitions for UI generation
--   events         -> WoW events that trigger refresh
-------------------------------------------------------------------------------
local dataSourceTypes = {}

function Registry.RegisterDataSourceType(name, definition)
    if not name or not definition then
        iplog("Error", "RegisterDataSourceType: name and definition required")
        return
    end
    if dataSourceTypes[name] then
        iplog("Warn", "RegisterDataSourceType: overwriting existing type '" .. name .. "'")
    end
    dataSourceTypes[name] = definition
    iplog("Info", "RegisterDataSourceType: '" .. name .. "'")
end

function Registry.GetDataSourceType(name)
    return dataSourceTypes[name]
end

function Registry.GetAllDataSourceTypes()
    return dataSourceTypes
end

-------------------------------------------------------------------------------
-- Layout Type Registry
-- Each layout type: { arrange, default }
--   arrange(contentFrame, children, layoutData, panelData) -> positions children
--   default -> table of default layout parameters
-------------------------------------------------------------------------------
local layoutTypes = {}

function Registry.RegisterLayoutType(name, definition)
    if not name or not definition then
        iplog("Error", "RegisterLayoutType: name and definition required")
        return
    end
    if layoutTypes[name] then
        iplog("Warn", "RegisterLayoutType: overwriting existing type '" .. name .. "'")
    end
    layoutTypes[name] = definition
    iplog("Info", "RegisterLayoutType: '" .. name .. "'")
end

function Registry.GetLayoutType(name)
    return layoutTypes[name]
end

function Registry.GetAllLayoutTypes()
    return layoutTypes
end

-------------------------------------------------------------------------------
-- Convenience: Check if a panel type exists
-------------------------------------------------------------------------------
function Registry.HasPanelType(name)
    return panelTypes[name] ~= nil
end

function Registry.HasLayoutType(name)
    return layoutTypes[name] ~= nil
end

function Registry.HasDataSourceType(name)
    return dataSourceTypes[name] ~= nil
end

-------------------------------------------------------------------------------
-- Reset (for testing)
-------------------------------------------------------------------------------
function Registry._reset()
    panelTypes = {}
    dataSourceTypes = {}
    layoutTypes = {}
end

return Registry
