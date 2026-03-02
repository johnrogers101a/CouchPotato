-- STUB: Replace with real AceAddon-3.0 for production
-- Functional stub for development and testing
-- Real library: https://repos.wowace.com/wow/ace3/trunk/AceAddon-3.0

local MAJOR, MINOR = "AceAddon-3.0", 12
local AceAddon, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not AceAddon then return end

-- Localize globals
local pairs = pairs
local type = type
local error = error
local rawget = rawget
local setmetatable = setmetatable
local string_format = string.format

-- Addon registry
AceAddon.addons = AceAddon.addons or {}
AceAddon.initQueue = AceAddon.initQueue or {}
AceAddon.enableQueue = AceAddon.enableQueue or {}

-- Event frame for lifecycle hooks
local eventFrame = AceAddon.frame or CreateFrame("Frame")
AceAddon.frame = eventFrame

-- Mixin support: embed other libraries' methods into an object
local function Embed(target, ...)
    for i = 1, select("#", ...) do
        local libname = select(i, ...)
        local lib = LibStub:GetLibrary(libname, true)
        if lib and lib.Embed then
            lib:Embed(target)
        end
    end
end

-- Create new addon object
function AceAddon:NewAddon(name, ...)
    if type(name) ~= "string" then
        error(string_format("Bad argument #1 to `NewAddon' (string expected, got %s)", type(name)), 2)
    end
    if self.addons[name] then
        error(string_format("Addon '%s' already exists", name), 2)
    end

    local addon = {
        name = name,
        modules = {},
        orderedModules = {},
        enabledState = false,
        defaultModuleState = true,
    }

    -- Embed requested mixins
    Embed(addon, ...)

    -- Module creation
    function addon:NewModule(moduleName, ...)
        if type(moduleName) ~= "string" then
            error(string_format("Bad argument #1 to `NewModule' (string expected, got %s)", type(moduleName)), 2)
        end
        if self.modules[moduleName] then
            error(string_format("Module '%s' already exists", moduleName), 2)
        end

        local mod = {
            name = moduleName,
            moduleName = moduleName,
            enabledState = false,
        }
        Embed(mod, ...)
        
        self.modules[moduleName] = mod
        self.orderedModules[#self.orderedModules + 1] = mod
        
        return mod
    end

    function addon:GetModule(moduleName, silent)
        local mod = self.modules[moduleName]
        if not mod and not silent then
            error(string_format("Module '%s' does not exist", moduleName), 2)
        end
        return mod
    end

    function addon:IterateModules()
        return pairs(self.modules)
    end

    function addon:Enable()
        if self.enabledState then return end
        self.enabledState = true
        if self.OnEnable then
            self:OnEnable()
        end
        -- Enable all modules with default enabled state
        for _, mod in pairs(self.orderedModules) do
            if mod.defaultModuleState ~= false then
                if mod.OnEnable then
                    mod.enabledState = true
                    mod:OnEnable()
                end
            end
        end
    end

    function addon:Disable()
        if not self.enabledState then return end
        -- Disable all modules first
        for _, mod in pairs(self.orderedModules) do
            if mod.enabledState and mod.OnDisable then
                mod:OnDisable()
                mod.enabledState = false
            end
        end
        self.enabledState = false
        if self.OnDisable then
            self:OnDisable()
        end
    end

    function addon:IsEnabled()
        return self.enabledState
    end

    -- Register addon
    self.addons[name] = addon
    self.initQueue[#self.initQueue + 1] = addon
    
    -- Expose as global
    _G[name] = addon
    
    return addon
end

function AceAddon:GetAddon(name, silent)
    local addon = self.addons[name]
    if not addon and not silent then
        error(string_format("Addon '%s' not found", name), 2)
    end
    return addon
end

function AceAddon:IterateAddons()
    return pairs(self.addons)
end

-- Lifecycle event handling
local initialized = false
local enabled = false

local function OnEvent(self, event, arg1)
    if event == "ADDON_LOADED" then
        -- Fire OnInitialize for addons that match
        for i, addon in pairs(AceAddon.initQueue) do
            if addon.OnInitialize then
                addon:OnInitialize()
            end
            AceAddon.enableQueue[#AceAddon.enableQueue + 1] = addon
            AceAddon.initQueue[i] = nil
        end
    elseif event == "PLAYER_LOGIN" then
        -- Fire OnEnable for all queued addons
        for _, addon in pairs(AceAddon.enableQueue) do
            addon:Enable()
        end
        enabled = true
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
