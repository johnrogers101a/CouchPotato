-- spec/config_window_checkboxes_spec.lua
-- Tests for addon show/hide checkboxes in the /cp config window Settings tab.

require("spec/wow_mock")

-- Provide stubs not in wow_mock
_G.geterrorhandler = _G.geterrorhandler or function() return nil end
_G.seterrorhandler = _G.seterrorhandler or function(fn) end
_G.UISpecialFrames  = _G.UISpecialFrames or {}
_G.UIDropDownMenu_Initialize  = _G.UIDropDownMenu_Initialize  or function() end
_G.UIDropDownMenu_SetWidth    = _G.UIDropDownMenu_SetWidth    or function() end
_G.UIDropDownMenu_SetText     = _G.UIDropDownMenu_SetText     or function() end
_G.UIDropDownMenu_SetSelectedValue = _G.UIDropDownMenu_SetSelectedValue or function() end
_G.UIDropDownMenu_CreateInfo  = _G.UIDropDownMenu_CreateInfo  or function() return {} end
_G.UIDropDownMenu_AddButton   = _G.UIDropDownMenu_AddButton   or function() end
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
_G.GameFontNormalLarge = { _name = "GameFontNormalLarge" }

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
-- Checkbox existence
-------------------------------------------------------------------------------
describe("config window checkboxes — existence", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
        cp.ConfigWindow._Build()
    end)

    it("frame has _addonCheckboxes table after build", function()
        local f = cp.ConfigWindow._GetFrame()
        assert.is_table(f._addonCheckboxes)
    end)

    it("DelveCompanionStats checkbox exists", function()
        local f = cp.ConfigWindow._GetFrame()
        assert.is_not_nil(f._addonCheckboxes["DelveCompanionStats"])
    end)

    it("StatPriority checkbox exists", function()
        local f = cp.ConfigWindow._GetFrame()
        assert.is_not_nil(f._addonCheckboxes["StatPriority"])
    end)

    it("ControllerCompanion checkbox exists", function()
        local f = cp.ConfigWindow._GetFrame()
        assert.is_not_nil(f._addonCheckboxes["ControllerCompanion"])
    end)

    it("there is no CouchPotato checkbox (hub must always be active)", function()
        local f = cp.ConfigWindow._GetFrame()
        assert.is_nil(f._addonCheckboxes["CouchPotato"])
    end)
end)

-------------------------------------------------------------------------------
-- Checkbox initial state reflects addonStates
-------------------------------------------------------------------------------
describe("config window checkboxes — initial state", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
    end)

    it("checkbox is checked when addonState is true (default)", function()
        cp.ConfigWindow._Build()
        cp.ConfigWindow._RefreshAddonCheckboxes()
        local f = cp.ConfigWindow._GetFrame()
        assert.is_true(f._addonCheckboxes["DelveCompanionStats"]:GetChecked())
        assert.is_true(f._addonCheckboxes["StatPriority"]:GetChecked())
        assert.is_true(f._addonCheckboxes["ControllerCompanion"]:GetChecked())
    end)

    it("checkbox is unchecked when addonState is false", function()
        _G.CouchPotatoDB.addonStates.StatPriority = false
        cp.ConfigWindow._Build()
        cp.ConfigWindow._RefreshAddonCheckboxes()
        local f = cp.ConfigWindow._GetFrame()
        assert.is_false(f._addonCheckboxes["StatPriority"]:GetChecked())
    end)
end)

-------------------------------------------------------------------------------
-- Checkbox OnClick toggles addon state and calls enable/disable
-------------------------------------------------------------------------------
describe("config window checkboxes — OnClick", function()
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
        cp.ConfigWindow._Build()
    end)

    after_each(function()
        _G.DelveCompanionStatsNS = nil
        _G.StatPriorityNS = nil
        _G.InCombatLockdown = nil
    end)

    local function clickCheckbox(f, addonKey, checked)
        local cb = f._addonCheckboxes[addonKey]
        cb._checked = checked   -- simulate the visual state change from click
        local handler = cb:GetScript("OnClick")
        if handler then handler(cb) end
    end

    it("unchecking DCS sets addonStates to false and hides frame", function()
        local f = cp.ConfigWindow._GetFrame()
        clickCheckbox(f, "DelveCompanionStats", false)
        assert.is_false(_G.CouchPotatoDB.addonStates.DelveCompanionStats)
        assert.is_false(_G.DelveCompanionStatsNS.frame:IsShown())
    end)

    it("checking DCS after uncheck sets addonStates to true and shows frame", function()
        _G.CouchPotatoDB.addonStates.DelveCompanionStats = false
        _G.DelveCompanionStatsNS._cpDisabled = true
        _G.DelveCompanionStatsNS.frame._shown = false
        local f = cp.ConfigWindow._GetFrame()
        clickCheckbox(f, "DelveCompanionStats", true)
        assert.is_true(_G.CouchPotatoDB.addonStates.DelveCompanionStats)
        assert.is_true(_G.DelveCompanionStatsNS.frame:IsShown())
    end)

    it("unchecking StatPriority sets addonStates to false and hides frame", function()
        local f = cp.ConfigWindow._GetFrame()
        clickCheckbox(f, "StatPriority", false)
        assert.is_false(_G.CouchPotatoDB.addonStates.StatPriority)
        assert.is_false(_G.StatPriorityNS.frame:IsShown())
    end)

    it("checking StatPriority after uncheck calls UpdateStatPriority", function()
        _G.CouchPotatoDB.addonStates.StatPriority = false
        _G.StatPriorityNS._cpDisabled = true
        _G.StatPriorityNS.frame._shown = false
        local f = cp.ConfigWindow._GetFrame()
        clickCheckbox(f, "StatPriority", true)
        assert.is_true(_G.StatPriorityNS._updateCalled)
    end)
end)

-------------------------------------------------------------------------------
-- RefreshAddonCheckboxes syncs from DB
-------------------------------------------------------------------------------
describe("config window checkboxes — RefreshAddonCheckboxes", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
        cp.ConfigWindow._Build()
    end)

    it("reflects state changes made via /cp disable", function()
        cp._handleEnableDisable("disable", "sp")
        cp.ConfigWindow._RefreshAddonCheckboxes()
        local f = cp.ConfigWindow._GetFrame()
        assert.is_false(f._addonCheckboxes["StatPriority"]:GetChecked())
    end)

    it("reflects re-enable state changes", function()
        cp._handleEnableDisable("disable", "dcs")
        cp._handleEnableDisable("enable", "dcs")
        cp.ConfigWindow._RefreshAddonCheckboxes()
        local f = cp.ConfigWindow._GetFrame()
        assert.is_true(f._addonCheckboxes["DelveCompanionStats"]:GetChecked())
    end)
end)
