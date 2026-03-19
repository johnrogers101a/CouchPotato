-- spec/cp_info_popup_spec.lua
-- Tests for CP:CreateInfoPopup(), CP:DumpSettings(), and /cp info

require("spec/wow_mock")
local helpers = require("spec/helpers")

describe("ControllerCompanion info popup", function()
    local CP

    before_each(function()
        helpers.resetMocks()
        _G.ControllerCompanion  = nil
        _G.ControllerCompanionDB = nil
        -- Clear the named frame so each test gets a fresh popup frame.
        _G.ControllerCompanionInfoPopup = nil

        dofile("ControllerCompanion/ControllerCompanion.lua")
        CP = _G.ControllerCompanion

        -- ADDON_LOADED initialises CP.db
        helpers.fireEvent("ADDON_LOADED", "ControllerCompanion")
    end)

    -----------------------------------------------------------------------
    -- DumpSettings
    -----------------------------------------------------------------------
    describe("DumpSettings", function()

        it("returns a non-empty string when CP.db is initialized", function()
            assert.is_not_nil(CP.db)
            local result = CP:DumpSettings()
            assert.is_string(result)
            assert.is_true(#result > 0)
        end)

        it("returns 'Settings not yet loaded' when CP.db is nil", function()
            CP.db = nil
            local result = CP:DumpSettings()
            assert.equals("Settings not yet loaded", result)
        end)

        it("output contains profile field: enabled", function()
            local result = CP:DumpSettings()
            assert.is_not_nil(result:find("enabled", 1, true),
                "expected 'enabled' in DumpSettings output")
        end)

        it("output contains profile field: debugMode", function()
            local result = CP:DumpSettings()
            assert.is_not_nil(result:find("debugMode", 1, true),
                "expected 'debugMode' in DumpSettings output")
        end)

        it("output contains profile field: uiScale", function()
            local result = CP:DumpSettings()
            assert.is_not_nil(result:find("uiScale", 1, true),
                "expected 'uiScale' in DumpSettings output")
        end)

        it("output contains char field: currentWheel", function()
            local result = CP:DumpSettings()
            assert.is_not_nil(result:find("currentWheel", 1, true),
                "expected 'currentWheel' in DumpSettings output")
        end)

        it("output contains char field: healerMode", function()
            local result = CP:DumpSettings()
            assert.is_not_nil(result:find("healerMode", 1, true),
                "expected 'healerMode' in DumpSettings output")
        end)

    end)

    -----------------------------------------------------------------------
    -- CreateInfoPopup
    -----------------------------------------------------------------------
    describe("CreateInfoPopup", function()

        it("creates CP.infoPopup (not nil after call)", function()
            assert.is_nil(CP.infoPopup)
            CP:CreateInfoPopup()
            assert.is_not_nil(CP.infoPopup)
        end)

        it("stores _editBox reference on popup", function()
            CP:CreateInfoPopup()
            assert.is_not_nil(CP.infoPopup._editBox)
        end)

        it("is a singleton — second call returns the same popup", function()
            CP:CreateInfoPopup()
            local first = CP.infoPopup
            CP:CreateInfoPopup()
            local second = CP.infoPopup
            assert.equals(first, second)
        end)

    end)

    -----------------------------------------------------------------------
    -- /cp info slash command (ChatCommand)
    -----------------------------------------------------------------------
    describe("/cp info command", function()

        it("creates CP.infoPopup when called", function()
            assert.is_nil(CP.infoPopup)
            CP:ChatCommand("info")
            assert.is_not_nil(CP.infoPopup)
        end)

        it("sets CP.infoPopup._editBox text to non-empty string", function()
            CP:ChatCommand("info")
            local text = CP.infoPopup._editBox:GetText()
            assert.is_string(text)
            assert.is_true(#text > 0)
        end)

        it("shows the popup after /cp info", function()
            CP:ChatCommand("info")
            assert.is_true(CP.infoPopup._shown)
        end)

        it("calling /cp info twice reuses the same popup (singleton)", function()
            CP:ChatCommand("info")
            local first = CP.infoPopup
            CP:ChatCommand("info")
            local second = CP.infoPopup
            assert.equals(first, second)
        end)

        it("popup text contains settings header after /cp info", function()
            CP:ChatCommand("info")
            local text = CP.infoPopup._editBox:GetText()
            assert.is_not_nil(text:find("ControllerCompanion", 1, true),
                "expected 'ControllerCompanion' in info popup text")
        end)

        it("popup text contains profile and char sections", function()
            CP:ChatCommand("info")
            local text = CP.infoPopup._editBox:GetText()
            assert.is_not_nil(text:find("Profile", 1, true),
                "expected '[Profile]' section in info popup text")
            assert.is_not_nil(text:find("Character", 1, true),
                "expected '[Character]' section in info popup text")
        end)

    end)
end)
