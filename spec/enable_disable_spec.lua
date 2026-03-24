-- spec/enable_disable_spec.lua
-- Tests for /cp enable and /cp disable addon management feature.

require("spec/wow_mock")

-- Provide stubs not in wow_mock
_G.geterrorhandler = _G.geterrorhandler or function() return nil end
_G.seterrorhandler = _G.seterrorhandler or function(fn) end
_G.UISpecialFrames  = _G.UISpecialFrames or {}
_G.Minimap = _G.Minimap or {
    _width = 160, _height = 160, _left = 0, _bottom = 0,
    GetWidth  = function(self) return self._width  end,
    GetHeight = function(self) return self._height end,
    GetLeft   = function(self) return self._left   end,
    GetBottom = function(self) return self._bottom end,
    GetEffectiveScale = function(self) return 1 end,
}
setmetatable(_G.Minimap, {__index = _G.UIParent})
_G.GameFontHighlightSmall = { _name = "GameFontHighlightSmall" }
_G.GameTooltip.AddLine = _G.GameTooltip.AddLine or function() end
_G.GetCursorPosition  = _G.GetCursorPosition  or function() return 0, 0 end

-------------------------------------------------------------------------------
-- Helper: load a clean CouchPotato environment
-------------------------------------------------------------------------------
local function LoadCouchPotato()
    _G.CouchPotatoDB     = nil
    _G.CouchPotatoShared = nil
    _G.CouchPotatoLog    = nil
    _G.SlashCmdList      = _G.SlashCmdList or {}
    _G.SLASH_CP1 = nil; _G.SLASH_CP2 = nil
    _G.SLASH_CC1 = nil; _G.SLASH_CC2 = nil
    _G.UISpecialFrames = {}
    _G.CouchPotatoConfigFrame  = nil
    _G.CouchPotatoExportFrame  = nil
    _G.CouchPotatoMinimapButton = nil
    _G._rawEventListeners = {}

    local _capturedHandler = nil
    _G.geterrorhandler = function() return _capturedHandler end
    _G.seterrorhandler = function(fn) _capturedHandler = fn end

    dofile("CouchPotato/CouchPotatoLog.lua")
    dofile("CouchPotato/CouchPotato.lua")
    dofile("CouchPotato/MinimapButton.lua")
    dofile("CouchPotato/ConfigWindow.lua")

    -- Fire ADDON_LOADED to init DB
    if _G._rawEventListeners and _G._rawEventListeners["ADDON_LOADED"] then
        for _, handler in pairs(_G._rawEventListeners["ADDON_LOADED"]) do
            handler("ADDON_LOADED", "CouchPotato")
        end
    end

    return _G.CouchPotatoShared
end

-------------------------------------------------------------------------------
-- Alias resolution
-------------------------------------------------------------------------------
describe("cp enable/disable — alias resolution", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
    end)

    it("ADDON_ALIASES maps 'cc' to ControllerCompanion", function()
        assert.equals("ControllerCompanion", cp._addonAliases["cc"])
    end)

    it("ADDON_ALIASES maps 'controllercompanion' to ControllerCompanion", function()
        assert.equals("ControllerCompanion", cp._addonAliases["controllercompanion"])
    end)

    it("ADDON_ALIASES maps 'dcs' to DelveCompanionStats", function()
        assert.equals("DelveCompanionStats", cp._addonAliases["dcs"])
    end)

    it("ADDON_ALIASES maps 'delvecompanionstats' to DelveCompanionStats", function()
        assert.equals("DelveCompanionStats", cp._addonAliases["delvecompanionstats"])
    end)

    it("ADDON_ALIASES maps 'sp' to StatPriority", function()
        assert.equals("StatPriority", cp._addonAliases["sp"])
    end)

    it("ADDON_ALIASES maps 'statpriority' to StatPriority", function()
        assert.equals("StatPriority", cp._addonAliases["statpriority"])
    end)

    it("unknown alias is nil", function()
        assert.is_nil(cp._addonAliases["couchpotato"])
    end)
end)

-------------------------------------------------------------------------------
-- State storage in CouchPotatoDB.addonStates
-------------------------------------------------------------------------------
describe("cp enable/disable — state storage", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
    end)

    it("addonStates defaults: all three addons are true", function()
        assert.is_true(_G.CouchPotatoDB.addonStates.ControllerCompanion)
        assert.is_true(_G.CouchPotatoDB.addonStates.DelveCompanionStats)
        assert.is_true(_G.CouchPotatoDB.addonStates.StatPriority)
    end)

    it("disable sets addonStates[addon] to false", function()
        cp._handleEnableDisable("disable", "dcs")
        assert.is_false(_G.CouchPotatoDB.addonStates.DelveCompanionStats)
    end)

    it("enable sets addonStates[addon] to true after disable", function()
        cp._handleEnableDisable("disable", "sp")
        cp._handleEnableDisable("enable", "sp")
        assert.is_true(_G.CouchPotatoDB.addonStates.StatPriority)
    end)

    it("disabling ControllerCompanion sets state to false", function()
        cp._handleEnableDisable("disable", "cc")
        assert.is_false(_G.CouchPotatoDB.addonStates.ControllerCompanion)
    end)

    it("state persists: disable then enable then disable leaves it false", function()
        cp._handleEnableDisable("disable", "sp")
        cp._handleEnableDisable("enable", "sp")
        cp._handleEnableDisable("disable", "sp")
        assert.is_false(_G.CouchPotatoDB.addonStates.StatPriority)
    end)
end)

-------------------------------------------------------------------------------
-- Chat feedback messages
-------------------------------------------------------------------------------
describe("cp enable/disable — chat feedback", function()
    local cp
    local messages

    before_each(function()
        cp = LoadCouchPotato()
        messages = {}
        _G.CouchPotatoLog = {
            Print = function(self, prefix, msg)
                table.insert(messages, msg or prefix)
            end,
            Info  = function() end,
            Warn  = function() end,
            Error = function() end,
        }
    end)

    it("disable prints '<Addon> disabled.'", function()
        cp._handleEnableDisable("disable", "dcs")
        local found = false
        for _, m in ipairs(messages) do
            if m:find("DelveCompanionStats") and m:find("disabled") then found = true; break end
        end
        assert.is_true(found, "Expected 'DelveCompanionStats disabled.' message")
    end)

    it("enable prints '<Addon> enabled.'", function()
        cp._handleEnableDisable("disable", "sp")
        messages = {}  -- clear
        cp._handleEnableDisable("enable", "sp")
        local found = false
        for _, m in ipairs(messages) do
            if m:find("StatPriority") and m:find("enabled") then found = true; break end
        end
        assert.is_true(found, "Expected 'StatPriority enabled.' message")
    end)

    it("already-disabled prints '<Addon> is already disabled.'", function()
        cp._handleEnableDisable("disable", "cc")
        messages = {}
        cp._handleEnableDisable("disable", "cc")
        local found = false
        for _, m in ipairs(messages) do
            if m:find("ControllerCompanion") and m:find("already") and m:find("disabled") then found = true; break end
        end
        assert.is_true(found, "Expected 'already disabled' message")
    end)

    it("already-enabled prints '<Addon> is already enabled.'", function()
        cp._handleEnableDisable("enable", "sp")
        local found = false
        for _, m in ipairs(messages) do
            if m:find("StatPriority") and m:find("already") and m:find("enabled") then found = true; break end
        end
        assert.is_true(found, "Expected 'already enabled' message")
    end)

    it("unknown addon prints error listing valid names", function()
        cp._handleEnableDisable("disable", "bogus")
        local found = false
        for _, m in ipairs(messages) do
            if m:find("bogus") or m:find("Unknown") then found = true; break end
        end
        assert.is_true(found, "Expected unknown-addon error message")
    end)

    it("no addon name prints status list", function()
        cp._handleEnableDisable("disable", nil)
        -- Should list addons (at least one message mentioning ControllerCompanion)
        local found = false
        for _, m in ipairs(messages) do
            if m:find("ControllerCompanion") or m:find("enabled") or m:find("disabled") or m:find("Suite") then
                found = true; break
            end
        end
        assert.is_true(found, "Expected status list output")
    end)
end)

-------------------------------------------------------------------------------
-- Functional disable for DelveCompanionStats
-------------------------------------------------------------------------------
describe("cp enable/disable — functional disable DelveCompanionStats", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
        -- Provide a mock DelveCompanionStatsNS
        _G.DelveCompanionStatsNS = {
            _cpDisabled = false,
            frame = {
                _shown = true,
                Show = function(self) self._shown = true end,
                Hide = function(self) self._shown = false end,
                IsShown = function(self) return self._shown end,
            }
        }
    end)

    after_each(function()
        _G.DelveCompanionStatsNS = nil
    end)

    it("disable hides DCS frame and sets _cpDisabled", function()
        cp._doDisableAddon("DelveCompanionStats")
        local ns = _G.DelveCompanionStatsNS
        assert.is_true(ns._cpDisabled)
        assert.is_false(ns.frame:IsShown())
    end)

    it("enable shows DCS frame and clears _cpDisabled", function()
        cp._doDisableAddon("DelveCompanionStats")
        cp._doEnableAddon("DelveCompanionStats")
        local ns = _G.DelveCompanionStatsNS
        assert.is_false(ns._cpDisabled)
        assert.is_true(ns.frame:IsShown())
    end)

    it("disable via HandleEnableDisable hides frame", function()
        cp._handleEnableDisable("disable", "dcs")
        assert.is_false(_G.DelveCompanionStatsNS.frame:IsShown())
    end)

    it("enable via HandleEnableDisable shows frame", function()
        cp._handleEnableDisable("disable", "dcs")
        cp._handleEnableDisable("enable", "dcs")
        assert.is_true(_G.DelveCompanionStatsNS.frame:IsShown())
    end)
end)

-------------------------------------------------------------------------------
-- Functional disable for StatPriority
-------------------------------------------------------------------------------
describe("cp enable/disable — functional disable StatPriority", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
        local updateCalled = false
        _G.StatPriorityNS = {
            _cpDisabled = false,
            _updateCalled = false,
            frame = {
                _shown = true,
                Show = function(self) self._shown = true end,
                Hide = function(self) self._shown = false end,
                IsShown = function(self) return self._shown end,
            },
            UpdateStatPriority = function(self) self._updateCalled = true end,
        }
    end)

    after_each(function()
        _G.StatPriorityNS = nil
    end)

    it("disable hides SP frame and sets _cpDisabled", function()
        cp._doDisableAddon("StatPriority")
        local ns = _G.StatPriorityNS
        assert.is_true(ns._cpDisabled)
        assert.is_false(ns.frame:IsShown())
    end)

    it("enable shows SP frame, clears _cpDisabled, and calls UpdateStatPriority", function()
        cp._doDisableAddon("StatPriority")
        cp._doEnableAddon("StatPriority")
        local ns = _G.StatPriorityNS
        assert.is_false(ns._cpDisabled)
        assert.is_true(ns.frame:IsShown())
        assert.is_true(ns._updateCalled)
    end)

    it("disable via HandleEnableDisable hides SP frame", function()
        cp._handleEnableDisable("disable", "sp")
        assert.is_false(_G.StatPriorityNS.frame:IsShown())
    end)
end)

-------------------------------------------------------------------------------
-- Functional disable for ControllerCompanion
-------------------------------------------------------------------------------
describe("cp enable/disable — functional disable ControllerCompanion", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
        _G.InCombatLockdown = function() return false end
        _G.ControllerCompanion = {
            _deactivateCalled = false,
            _activateCalled   = false,
            _mainFrame = {
                _shown = true,
                Hide = function(self) self._shown = false end,
                Show = function(self) self._shown = true end,
                IsShown = function(self) return self._shown end,
            },
            OnControllerDeactivated = function(self)
                self._deactivateCalled = true
            end,
            OnControllerActivated = function(self)
                self._activateCalled = true
            end,
        }
    end)

    after_each(function()
        _G.ControllerCompanion = nil
        _G.InCombatLockdown = nil
    end)

    it("disable calls OnControllerDeactivated", function()
        cp._doDisableAddon("ControllerCompanion")
        assert.is_true(_G.ControllerCompanion._deactivateCalled)
    end)

    it("enable calls OnControllerActivated", function()
        cp._doEnableAddon("ControllerCompanion")
        assert.is_true(_G.ControllerCompanion._activateCalled)
    end)

    it("disable via HandleEnableDisable calls OnControllerDeactivated", function()
        cp._handleEnableDisable("disable", "cc")
        assert.is_true(_G.ControllerCompanion._deactivateCalled)
    end)

    it("enable via HandleEnableDisable calls OnControllerActivated", function()
        cp._handleEnableDisable("disable", "cc")
        cp._handleEnableDisable("enable", "cc")
        assert.is_true(_G.ControllerCompanion._activateCalled)
    end)
end)

-------------------------------------------------------------------------------
-- Slash command integration
-------------------------------------------------------------------------------
describe("cp enable/disable — slash command integration", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
        _G.InCombatLockdown = function() return false end
        _G.DelveCompanionStatsNS = {
            _cpDisabled = false,
            frame = {
                _shown = true,
                Show = function(self) self._shown = true end,
                Hide = function(self) self._shown = false end,
                IsShown = function(self) return self._shown end,
            }
        }
    end)

    after_each(function()
        _G.DelveCompanionStatsNS = nil
        _G.InCombatLockdown = nil
    end)

    it("/cp enable dcs enables via slash", function()
        _G.CouchPotatoDB.addonStates.DelveCompanionStats = false
        _G.DelveCompanionStatsNS._cpDisabled = true
        _G.DelveCompanionStatsNS.frame._shown = false
        _G.SlashCmdList["CP"]("enable dcs")
        assert.is_true(_G.CouchPotatoDB.addonStates.DelveCompanionStats)
    end)

    it("/cp disable dcs disables via slash", function()
        _G.SlashCmdList["CP"]("disable dcs")
        assert.is_false(_G.CouchPotatoDB.addonStates.DelveCompanionStats)
    end)

    it("/cp with no subcommand toggles config window", function()
        cp.ConfigWindow._Build()
        local f = cp.ConfigWindow._GetFrame()
        f:Hide()
        _G.SlashCmdList["CP"]("")
        assert.is_true(f:IsShown())
    end)

    it("/cp enable (no addon) prints status list without error", function()
        assert.has_no.errors(function()
            _G.SlashCmdList["CP"]("enable")
        end)
    end)

    it("/cp disable (no addon) prints status list without error", function()
        assert.has_no.errors(function()
            _G.SlashCmdList["CP"]("disable")
        end)
    end)

    it("/cp enable/disable are case-insensitive for addon names", function()
        _G.SlashCmdList["CP"]("disable DCS")
        assert.is_false(_G.CouchPotatoDB.addonStates.DelveCompanionStats)
        _G.SlashCmdList["CP"]("enable DCS")
        assert.is_true(_G.CouchPotatoDB.addonStates.DelveCompanionStats)
    end)
end)

-------------------------------------------------------------------------------
-- Combat deferral
-------------------------------------------------------------------------------
describe("cp enable/disable — combat deferral for ControllerCompanion", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
        _G.ControllerCompanion = {
            _deactivateCalled = false,
            _mainFrame = {
                _shown = true,
                Hide = function(self) self._shown = false end,
                IsShown = function(self) return self._shown end,
            },
            OnControllerDeactivated = function(self)
                self._deactivateCalled = true
            end,
            OnControllerActivated = function(self) end,
        }
    end)

    after_each(function()
        _G.ControllerCompanion = nil
        _G.InCombatLockdown    = nil
    end)

    it("disable during combat defers OnControllerDeactivated", function()
        _G.InCombatLockdown = function() return true end
        cp._handleEnableDisable("disable", "cc")
        -- State is set immediately
        assert.is_false(_G.CouchPotatoDB.addonStates.ControllerCompanion)
        -- But deactivate was NOT called yet
        assert.is_false(_G.ControllerCompanion._deactivateCalled)
    end)

    it("disable outside combat calls OnControllerDeactivated immediately", function()
        _G.InCombatLockdown = function() return false end
        cp._handleEnableDisable("disable", "cc")
        assert.is_true(_G.ControllerCompanion._deactivateCalled)
    end)
end)

-------------------------------------------------------------------------------
-- EnsureAddonStates safety
-------------------------------------------------------------------------------
describe("cp enable/disable — EnsureAddonStates safety", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
    end)

    it("EnsureAddonStates is idempotent when DB is already initialized", function()
        assert.has_no.errors(function()
            cp._ensureAddonStates()
            cp._ensureAddonStates()
        end)
        assert.is_not_nil(_G.CouchPotatoDB.addonStates)
    end)

    it("EnsureAddonStates creates addonStates when DB exists but key is missing", function()
        _G.CouchPotatoDB.addonStates = nil
        cp._ensureAddonStates()
        assert.is_not_nil(_G.CouchPotatoDB.addonStates)
        assert.is_true(_G.CouchPotatoDB.addonStates.ControllerCompanion)
    end)

    it("EnsureAddonStates creates CouchPotatoDB when it is nil", function()
        _G.CouchPotatoDB = nil
        cp._ensureAddonStates()
        assert.is_not_nil(_G.CouchPotatoDB)
        assert.is_not_nil(_G.CouchPotatoDB.addonStates)
    end)
end)
