-- STUB: Replace with real AceConsole-3.0 for production
-- Functional stub for development and testing
-- Real library: https://repos.wowace.com/wow/ace3/trunk/AceConsole-3.0

local MAJOR, MINOR = "AceConsole-3.0", 7
local AceConsole, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not AceConsole then return end

-- Localize globals
local select = select
local tostring = tostring
local type = type
local string_format = string.format
local string_upper = string.upper
local string_gsub = string.gsub

-- Track registered commands
AceConsole.commands = AceConsole.commands or {}

-- Mixin methods
local mixins = {}

function mixins:Print(...)
    local text = ""
    for i = 1, select("#", ...) do
        local val = select(i, ...)
        text = text .. (i > 1 and " " or "") .. tostring(val)
    end
    
    local name = self.name or "Addon"
    local prefix = "|cff33ff99" .. name .. "|r: "
    
    local chatFrame = DEFAULT_CHAT_FRAME or ChatFrame1
    if chatFrame then
        chatFrame:AddMessage(prefix .. text)
    end
end

function mixins:Printf(fmt, ...)
    self:Print(string_format(fmt, ...))
end

function mixins:RegisterChatCommand(cmd, handler)
    if type(cmd) ~= "string" then
        error(string_format("Bad argument #1 to `RegisterChatCommand' (string expected, got %s)", type(cmd)), 2)
    end
    
    cmd = string_gsub(cmd, "^/", "") -- Remove leading slash if present
    local cmdUpper = string_upper(cmd)
    
    -- Create slash command entry
    _G["SLASH_" .. cmdUpper .. "1"] = "/" .. cmd
    
    local selfRef = self
    local handlerFunc
    
    if type(handler) == "string" then
        -- Handler is a method name
        handlerFunc = function(msg)
            local method = selfRef[handler]
            if method then
                method(selfRef, msg)
            end
        end
    elseif type(handler) == "function" then
        handlerFunc = function(msg)
            handler(selfRef, msg)
        end
    else
        error(string_format("Bad argument #2 to `RegisterChatCommand' (string or function expected, got %s)", type(handler)), 2)
    end
    
    SlashCmdList[cmdUpper] = handlerFunc
    AceConsole.commands[cmd] = self
end

function mixins:UnregisterChatCommand(cmd)
    cmd = string_gsub(cmd, "^/", "")
    local cmdUpper = string_upper(cmd)
    _G["SLASH_" .. cmdUpper .. "1"] = nil
    SlashCmdList[cmdUpper] = nil
    AceConsole.commands[cmd] = nil
end

-- Embed mixin methods into target
function AceConsole:Embed(target)
    for name, method in pairs(mixins) do
        target[name] = method
    end
end

AceConsole.embeds = AceConsole.embeds or setmetatable({}, {__mode = "k"})
