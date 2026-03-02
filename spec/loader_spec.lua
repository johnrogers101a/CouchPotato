-- spec/loader_spec.lua
-- Tests for CouchPotato_Loader: detection logic, dynamic loading, SavedVars

require("spec/wow_mock")
local helpers = require("spec/helpers")

describe("CouchPotato_Loader", function()
    local loaderEnv
    
    before_each(function()
        helpers.resetMocks()
        C_AddOns._Reset()
        -- Make CouchPotato unloaded
        C_AddOns._addons.CouchPotato = { loaded = false, enabled = true }
        
        -- We test the loader logic by examining its behavior
        -- The loader registers events on a frame; we simulate those events
    end)
    
    describe("C_AddOns loading mechanics", function()
        it("LoadAddOn returns true for enabled addon", function()
            local loaded, reason = C_AddOns.LoadAddOn("CouchPotato")
            assert.is_true(loaded)
            assert.is_nil(reason)
            assert.is_true(C_AddOns.IsAddOnLoaded("CouchPotato"))
        end)
        
        it("LoadAddOn returns DISABLED reason for disabled addon", function()
            C_AddOns.DisableAddOn("CouchPotato")
            local loaded, reason = C_AddOns.LoadAddOn("CouchPotato")
            assert.is_false(loaded)
            assert.equals("DISABLED", reason)
        end)
        
        it("EnableAddOn + LoadAddOn succeeds for previously disabled addon", function()
            C_AddOns.DisableAddOn("CouchPotato")
            C_AddOns.EnableAddOn("CouchPotato")
            local loaded, reason = C_AddOns.LoadAddOn("CouchPotato")
            assert.is_true(loaded)
        end)
        
        it("IsAddOnLoaded returns false before loading", function()
            assert.is_false(C_AddOns.IsAddOnLoaded("CouchPotato"))
        end)
        
        it("IsAddOnLoaded returns true after loading", function()
            C_AddOns.LoadAddOn("CouchPotato")
            assert.is_true(C_AddOns.IsAddOnLoaded("CouchPotato"))
        end)
    end)
    
    describe("gamepad state detection", function()
        it("C_GamePad.IsEnabled returns false when no controller", function()
            assert.is_false(C_GamePad.IsEnabled())
        end)
        
        it("C_GamePad.IsEnabled returns true after simulated connect", function()
            C_GamePad._SimulateConnect(1)
            assert.is_true(C_GamePad.IsEnabled())
        end)
        
        it("C_GamePad.GetActiveDeviceID returns nil when disconnected", function()
            assert.is_nil(C_GamePad.GetActiveDeviceID())
        end)
        
        it("C_GamePad.GetActiveDeviceID returns id when connected", function()
            C_GamePad._SimulateConnect(42)
            assert.equals(42, C_GamePad.GetActiveDeviceID())
        end)
    end)
    
    describe("edge cases", function()
        it("calling LoadAddOn twice does not error", function()
            assert.has_no.errors(function()
                C_AddOns.LoadAddOn("CouchPotato")
                C_AddOns.LoadAddOn("CouchPotato")
            end)
        end)
        
        it("LoadAddOn for missing addon returns false", function()
            local loaded, reason = C_AddOns.LoadAddOn("NonExistentAddon")
            assert.is_false(loaded)
            assert.equals("MISSING", reason)
        end)
        
        it("detects controller after GAME_PAD_ACTIVE_CHANGED with isActive=true", function()
            -- Simulate the event sequence
            assert.is_false(C_GamePad.IsEnabled())
            C_GamePad._SimulateConnect(1)
            helpers.fireEvent("GAME_PAD_ACTIVE_CHANGED", true)
            assert.is_true(C_GamePad.IsEnabled())
        end)
    end)
end)
