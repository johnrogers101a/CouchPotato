-- spec/blizzard_frames_spec.lua
-- Tests for BlizzardFrames module: taint-free hide/restore via RegisterStateDriver

require("spec/wow_mock")
local helpers = require("spec/helpers")

describe("BlizzardFrames", function()
    local CP, BlizzardFrames

    before_each(function()
        helpers.resetMocks()

        -- Seed _G with the managed frame names so lookups succeed
        local managed = {
            "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
            "MultiBarLeft", "MultiBarRight", "PlayerFrame", "TargetFrame",
            "FocusFrame", "CastingBarFrame", "PossessBarFrame", "OverrideActionBar",
        }
        for _, name in ipairs(managed) do
            _G[name] = CreateFrame("Frame", name, UIParent)
        end
        for i = 1, 4 do
            local n = "PartyMemberFrame" .. i
            _G[n] = CreateFrame("Frame", n, UIParent)
        end

        -- Reset state driver tracking table (re-seed after resetMocks)
        _G._stateDrivers = {}

        dofile("CouchPotato/CouchPotato.lua")
        CP = CouchPotato
        CP.db = { profile = { hideBlizzardFrames = true } }
        dofile("CouchPotato/Core/BlizzardFrames.lua")
        BlizzardFrames = CP._modules["BlizzardFrames"]
        BlizzardFrames.hiddenFrames = {}

        _G.InCombatLockdown = function() return false end
    end)

    describe("HideAll()", function()
        it("calls RegisterStateDriver('hide') on each managed frame", function()
            BlizzardFrames:HideAll()
            assert.is_not_nil(_G._stateDrivers[_G["MainMenuBar"]],
                "MainMenuBar should have a state driver")
            assert.equals("hide",
                _G._stateDrivers[_G["MainMenuBar"]]["visibility"],
                "MainMenuBar visibility driver should be 'hide'")
        end)

        it("marks each frame in hiddenFrames", function()
            BlizzardFrames:HideAll()
            assert.is_true(BlizzardFrames.hiddenFrames["MainMenuBar"])
            assert.is_true(BlizzardFrames.hiddenFrames["PlayerFrame"])
        end)

        it("hides PartyMemberFrame1-4", function()
            BlizzardFrames:HideAll()
            for i = 1, 4 do
                local pf = _G["PartyMemberFrame" .. i]
                assert.is_not_nil(_G._stateDrivers[pf],
                    "PartyMemberFrame" .. i .. " should have a state driver")
            end
        end)

        it("does NOT call frame:Hide() directly (taint-free)", function()
            local hideCalled = false
            _G["MainMenuBar"].Hide = function(self)
                hideCalled = true
            end
            BlizzardFrames:HideAll()
            assert.is_false(hideCalled,
                "frame:Hide() must not be called directly — use RegisterStateDriver")
        end)

        it("queues on combat lockdown, does not error", function()
            _G.InCombatLockdown = function() return true end
            assert.has_no.errors(function() BlizzardFrames:HideAll() end)
            assert.is_true(BlizzardFrames.pendingHide,
                "pendingHide flag should be set when in combat")
        end)
    end)

    describe("RestoreAll()", function()
        it("calls UnregisterStateDriver on previously hidden frames", function()
            BlizzardFrames:HideAll()
            BlizzardFrames:RestoreAll()
            assert.is_nil(
                _G._stateDrivers[_G["MainMenuBar"]] and
                _G._stateDrivers[_G["MainMenuBar"]]["visibility"],
                "MainMenuBar visibility driver should be removed after RestoreAll")
        end)

        it("clears hiddenFrames entries", function()
            BlizzardFrames:HideAll()
            BlizzardFrames:RestoreAll()
            assert.is_nil(BlizzardFrames.hiddenFrames["MainMenuBar"])
            assert.is_nil(BlizzardFrames.hiddenFrames["PlayerFrame"])
        end)

        it("does NOT call frame:Show() directly (taint-free)", function()
            BlizzardFrames:HideAll()
            local showCalled = false
            _G["MainMenuBar"].Show = function(self)
                showCalled = true
            end
            BlizzardFrames:RestoreAll()
            assert.is_false(showCalled,
                "frame:Show() must not be called directly — use UnregisterStateDriver")
        end)

        it("queues on combat lockdown, does not error", function()
            BlizzardFrames:HideAll()
            _G.InCombatLockdown = function() return true end
            assert.has_no.errors(function() BlizzardFrames:RestoreAll() end)
            assert.is_true(BlizzardFrames.pendingRestore,
                "pendingRestore flag should be set when in combat")
        end)
    end)
end)
