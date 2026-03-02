-- spec/gamepad_spec.lua
-- Tests for GamePad module: detection, vibration, LED dispatch, state management

-- Load WoW mock environment first
require("spec/wow_mock")
local helpers = require("spec/helpers")

describe("GamePad Module", function()
    local CP, GamePad
    
    before_each(function()
        helpers.resetMocks()

        dofile("CouchPotato/CouchPotato.lua")
        CP = CouchPotato
        CP.db = {
            profile = {
                vibrationEnabled = true,
                ledEnabled       = true,
                peekThreshold    = 0.35,
                lockThreshold    = 0.75,
            },
            char = { currentWheel = 1, wheelLayouts = {} },
        }

        dofile("CouchPotato/Core/GamePad.lua")
        GamePad = CP:GetModule("GamePad")
        GamePad:Enable()
    end)
    
    describe("initialization", function()
        it("module exists after loading", function()
            assert.is_not_nil(GamePad)
        end)
        
        it("starts inactive when no controller connected", function()
            assert.is_false(GamePad:IsActive())
        end)
        
        it("detects active controller on enable", function()
            helpers.resetMocks()
            C_GamePad._SimulateConnect(1)
            
            -- Re-create and enable module with controller connected
            GamePad.isActive = nil
            GamePad:Enable()
            
            assert.is_true(GamePad:IsActive())
        end)
    end)
    
    describe("GAME_PAD_ACTIVE_CHANGED event", function()
        it("activates when controller becomes active", function()
            helpers.fireEvent("GAME_PAD_ACTIVE_CHANGED", true)
            assert.is_true(GamePad.isActive)
        end)
        
        it("deactivates when controller becomes inactive", function()
            GamePad.isActive = true
            helpers.fireEvent("GAME_PAD_ACTIVE_CHANGED", false)
            assert.is_false(GamePad.isActive)
        end)
    end)
    
    describe("Vibrate", function()
        it("fires vibration for valid pattern", function()
            C_GamePad._SimulateConnect(1)
            GamePad.isActive = true
            
            GamePad:Vibrate("MENU_OPEN")
            
            assert.is_true(C_GamePad._vibrating)
            assert.is_not_nil(C_GamePad._lastVibration)
            assert.equals("Low", C_GamePad._lastVibration.type)
        end)
        
        it("does not vibrate when vibration disabled", function()
            CP.db.profile.vibrationEnabled = false
            C_GamePad._SimulateConnect(1)
            GamePad.isActive = true
            
            GamePad:Vibrate("MENU_OPEN")
            
            assert.is_false(C_GamePad._vibrating)
        end)
        
        it("does not vibrate when no controller connected", function()
            -- C_GamePad not enabled
            GamePad:Vibrate("MENU_OPEN")
            assert.is_false(C_GamePad._vibrating)
        end)
        
        it("ignores unknown pattern names", function()
            C_GamePad._SimulateConnect(1)
            GamePad.isActive = true
            
            -- Should not error
            assert.has_no.errors(function()
                GamePad:Vibrate("NONEXISTENT_PATTERN")
            end)
        end)
    end)
    
    describe("LED color", function()
        it("sets LED color via SetLEDColor", function()
            C_GamePad._SimulateConnect(1)
            GamePad:SetLEDColor(1.0, 0.0, 0.0)
            
            assert.is_not_nil(C_GamePad._ledColor)
            assert.near(C_GamePad._ledColor.r, 1.0, 0.01)
            assert.near(C_GamePad._ledColor.g, 0.0, 0.01)
            assert.near(C_GamePad._ledColor.b, 0.0, 0.01)
        end)
        
        it("clears LED via ClearLEDColor", function()
            C_GamePad._SimulateConnect(1)
            GamePad:SetLEDColor(1.0, 0.0, 0.0)
            GamePad:ClearLEDColor()
            
            assert.is_nil(C_GamePad._ledColor)
        end)
    end)
    
    describe("OnSpellCast", function()
        it("does not dispatch LED when led is disabled", function()
            CP.db.profile.ledEnabled = false
            -- Should not error even without LED module loaded
            assert.has_no.errors(function()
                GamePad:OnSpellCast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 133)
            end)
        end)
    end)
end)
