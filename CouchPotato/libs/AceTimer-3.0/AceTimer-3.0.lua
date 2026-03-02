-- STUB: Replace with real AceTimer-3.0 for production
-- Functional stub for development and testing
-- Real library: https://repos.wowace.com/wow/ace3/trunk/AceTimer-3.0

local MAJOR, MINOR = "AceTimer-3.0", 5
local AceTimer, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not AceTimer then return end

-- Localize globals
local type = type
local pairs = pairs
local string_format = string.format
local C_Timer = C_Timer

-- Handle storage per object
AceTimer.handles = AceTimer.handles or {}
local handles = AceTimer.handles

-- Handle counter for unique IDs
local handleCounter = 0

-- Mixin methods
local mixins = {}

function mixins:ScheduleTimer(handler, delay, ...)
    if type(handler) ~= "function" and type(handler) ~= "string" then
        error(string_format("Bad argument #1 to `ScheduleTimer' (function or string expected, got %s)", type(handler)), 2)
    end
    if type(delay) ~= "number" then
        error(string_format("Bad argument #2 to `ScheduleTimer' (number expected, got %s)", type(delay)), 2)
    end
    
    handleCounter = handleCounter + 1
    local handleId = handleCounter
    
    -- Store extra args
    local args = {...}
    local selfRef = self
    
    local timerHandle = C_Timer.NewTimer(delay, function()
        -- Mark as completed
        if handles[selfRef] then
            handles[selfRef][handleId] = nil
        end
        
        -- Call handler
        if type(handler) == "string" then
            local method = selfRef[handler]
            if method then
                method(selfRef, unpack(args))
            end
        else
            handler(unpack(args))
        end
    end)
    
    -- Store handle
    handles[selfRef] = handles[selfRef] or {}
    handles[selfRef][handleId] = timerHandle
    
    return handleId
end

function mixins:ScheduleRepeatingTimer(handler, interval, ...)
    if type(handler) ~= "function" and type(handler) ~= "string" then
        error(string_format("Bad argument #1 to `ScheduleRepeatingTimer' (function or string expected, got %s)", type(handler)), 2)
    end
    if type(interval) ~= "number" then
        error(string_format("Bad argument #2 to `ScheduleRepeatingTimer' (number expected, got %s)", type(interval)), 2)
    end
    
    handleCounter = handleCounter + 1
    local handleId = handleCounter
    
    local args = {...}
    local selfRef = self
    
    local ticker = C_Timer.NewTicker(interval, function()
        if type(handler) == "string" then
            local method = selfRef[handler]
            if method then
                method(selfRef, unpack(args))
            end
        else
            handler(unpack(args))
        end
    end)
    
    handles[selfRef] = handles[selfRef] or {}
    handles[selfRef][handleId] = ticker
    
    return handleId
end

function mixins:CancelTimer(handleId)
    if handleId == nil then return false end
    
    local myHandles = handles[self]
    if not myHandles then return false end
    
    local timerHandle = myHandles[handleId]
    if not timerHandle then return false end
    
    -- Cancel the timer/ticker
    if timerHandle.Cancel then
        timerHandle:Cancel()
    end
    
    myHandles[handleId] = nil
    return true
end

function mixins:CancelAllTimers()
    local myHandles = handles[self]
    if not myHandles then return end
    
    for handleId, timerHandle in pairs(myHandles) do
        if timerHandle.Cancel then
            timerHandle:Cancel()
        end
    end
    
    handles[self] = nil
end

function mixins:TimeLeft(handleId)
    -- Stub: not easily available with C_Timer
    return 0
end

-- Embed mixin methods into target
function AceTimer:Embed(target)
    for name, method in pairs(mixins) do
        target[name] = method
    end
end

AceTimer.embeds = AceTimer.embeds or setmetatable({}, {__mode = "k"})
