-- STUB: Replace with real AceDB-3.0 for production
-- Functional stub for development and testing
-- Real library: https://repos.wowace.com/wow/ace3/trunk/AceDB-3.0

local MAJOR, MINOR = "AceDB-3.0", 26
local AceDB, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not AceDB then return end

-- Localize globals
local pairs = pairs
local type = type
local setmetatable = setmetatable
local rawset = rawset
local rawget = rawget

-- Deep copy a table
local function CopyTable(src, dest)
    dest = dest or {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = CopyTable(v, dest[k])
        elseif dest[k] == nil then
            dest[k] = v
        end
    end
    return dest
end

-- Create defaults proxy that falls back to defaults table
local function CreateDefaultsProxy(data, defaults)
    return setmetatable(data, {
        __index = function(t, k)
            local def = defaults[k]
            if type(def) == "table" then
                local newtbl = {}
                rawset(t, k, newtbl)
                return CreateDefaultsProxy(newtbl, def)
            end
            return def
        end
    })
end

-- Create a new database
function AceDB:New(varName, defaults, defaultProfile)
    defaults = defaults or {}
    defaultProfile = defaultProfile or "Default"

    -- Create or retrieve SavedVariable
    local sv = _G[varName]
    if not sv then
        sv = {}
        _G[varName] = sv
    end

    -- Ensure structure exists
    sv.profiles = sv.profiles or {}
    sv.profiles[defaultProfile] = sv.profiles[defaultProfile] or {}
    sv.char = sv.char or {}

    local db = {
        sv = sv,
        defaults = defaults,
        profile = sv.profiles[defaultProfile],
        char = sv.char,
        keys = {
            profile = defaultProfile,
            char = UnitName and UnitName("player") or "Unknown",
        },
    }

    -- Apply defaults to profile
    if defaults.profile then
        db.profile = CreateDefaultsProxy(sv.profiles[defaultProfile], defaults.profile)
    end

    -- Apply defaults to char
    if defaults.char then
        db.char = CreateDefaultsProxy(sv.char, defaults.char)
    end

    -- RegisterDefaults: update defaults after creation
    function db:RegisterDefaults(newDefaults)
        if newDefaults.profile then
            CopyTable(newDefaults.profile, defaults.profile)
        end
        if newDefaults.char then
            CopyTable(newDefaults.char, defaults.char)
        end
    end

    -- ResetProfile: reset profile to defaults
    function db:ResetProfile(noHardReset)
        if not noHardReset then
            for k in pairs(self.sv.profiles[self.keys.profile]) do
                self.sv.profiles[self.keys.profile][k] = nil
            end
        end
    end

    -- SetProfile: switch to another profile
    function db:SetProfile(name)
        self.sv.profiles[name] = self.sv.profiles[name] or {}
        self.keys.profile = name
        if defaults.profile then
            self.profile = CreateDefaultsProxy(self.sv.profiles[name], defaults.profile)
        else
            self.profile = self.sv.profiles[name]
        end
    end

    -- GetProfiles: list all profile names
    function db:GetProfiles(tbl)
        tbl = tbl or {}
        for name in pairs(self.sv.profiles) do
            tbl[#tbl + 1] = name
        end
        return tbl
    end

    return db
end
