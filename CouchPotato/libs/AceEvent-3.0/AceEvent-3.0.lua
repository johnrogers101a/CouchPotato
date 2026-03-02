-- STUB: Replace with real AceEvent-3.0 for production
-- Functional stub for development and testing
-- Real library: https://repos.wowace.com/wow/ace3/trunk/AceEvent-3.0

local MAJOR, MINOR = "AceEvent-3.0", 4
local AceEvent, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not AceEvent then return end

-- Localize globals
local pairs = pairs
local type = type
local string_format = string.format

-- Shared event frame
local eventFrame = AceEvent.frame or CreateFrame("Frame")
AceEvent.frame = eventFrame

-- Registry of event handlers: registry[event][object] = handler
AceEvent.registry = AceEvent.registry or {}
local registry = AceEvent.registry

-- Event dispatcher
local function OnEvent(self, event, ...)
    local handlers = registry[event]
    if handlers then
        for obj, handler in pairs(handlers) do
            if type(handler) == "function" then
                handler(obj, event, ...)
            elseif type(handler) == "string" then
                local method = obj[handler]
                if method then
                    method(obj, event, ...)
                end
            else
                -- Handler is true, use method matching event name
                local method = obj[event]
                if method then
                    method(obj, event, ...)
                end
            end
        end
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

-- Mixin methods
local mixins = {}

function mixins:RegisterEvent(event, handler)
    if type(event) ~= "string" then
        error(string_format("Bad argument #1 to `RegisterEvent' (string expected, got %s)", type(event)), 2)
    end

    registry[event] = registry[event] or {}
    
    -- Handler can be:
    -- nil/true: use method with same name as event
    -- string: use method with that name
    -- function: call that function
    if handler == nil then
        handler = true
    end
    
    registry[event][self] = handler
    eventFrame:RegisterEvent(event)
end

function mixins:UnregisterEvent(event)
    if registry[event] then
        registry[event][self] = nil
        -- Check if any handlers remain
        local hasHandlers = false
        for _ in pairs(registry[event]) do
            hasHandlers = true
            break
        end
        if not hasHandlers then
            eventFrame:UnregisterEvent(event)
        end
    end
end

function mixins:UnregisterAllEvents()
    for event, handlers in pairs(registry) do
        if handlers[self] then
            handlers[self] = nil
        end
    end
end

-- Embed mixin methods into target
function AceEvent:Embed(target)
    for name, method in pairs(mixins) do
        target[name] = method
    end
end

-- Metatable for CallbackHandler-style access
AceEvent.embeds = AceEvent.embeds or setmetatable({}, {__mode = "k"})
