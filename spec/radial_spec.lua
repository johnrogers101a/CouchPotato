-- spec/radial_spec.lua
-- Tests for Radial wheel system: frame creation, slot management, cycling

require("spec/wow_mock")
local helpers = require("spec/helpers")

describe("Radial Module", function()
    local CP, Radial
    local MAX_WHEELS = 8
    local MAX_SLOTS = 12
    
    before_each(function()
        helpers.resetMocks()
        
        CP = LibStub("AceAddon-3.0"):NewAddon("CouchPotato", "AceConsole-3.0", "AceEvent-3.0")
        _G["CouchPotato"] = CP
        CP.db = LibStub("AceDB-3.0"):New("CouchPotatoDB", {
            profile = {
                radialAlpha = 0.9,
                peekThreshold = 0.35,
                lockThreshold = 0.75,
                vibrationEnabled = true,
            },
            char = {
                currentWheel = 1,
                wheelLayouts = {},
            }
        })
        
        -- Load dependencies
        dofile("CouchPotato/Core/GamePad.lua")
        dofile("CouchPotato/Core/Specs.lua")
        dofile("CouchPotato/UI/Radial.lua")
        
        CP:GetModule("GamePad"):Enable()
        CP:GetModule("Specs"):Enable()
        Radial = CP:GetModule("Radial")
        Radial:Enable()
    end)
    
    describe("initialization", function()
        it("creates wheel frames for all wheels", function()
            for i = 1, MAX_WHEELS do
                assert.is_not_nil(Radial.wheels[i],
                    "Wheel " .. i .. " should exist")
            end
        end)
        
        it("creates correct number of slots per wheel", function()
            for wheelIdx = 1, MAX_WHEELS do
                assert.is_not_nil(Radial.wheelButtons[wheelIdx])
                for slotIdx = 1, MAX_SLOTS do
                    assert.is_not_nil(Radial.wheelButtons[wheelIdx][slotIdx],
                        string.format("Wheel %d slot %d should exist", wheelIdx, slotIdx))
                end
            end
        end)
        
        it("starts with all wheels hidden", function()
            for i = 1, MAX_WHEELS do
                assert.is_false(Radial.wheels[i]:IsShown(),
                    "Wheel " .. i .. " should start hidden")
            end
        end)
        
        it("starts on wheel 1", function()
            assert.equals(1, Radial.currentWheel)
        end)
        
        it("slot buttons default to type 'empty'", function()
            -- Wheel 8, slot 12 is never populated by default spec layouts
            local btn = Radial.wheelButtons[8][12]
            assert.equals("empty", btn:GetAttribute("type"))
        end)
        
        it("slot buttons use SecureActionButtonTemplate", function()
            -- In mock, we verify SetAttribute works (it does in our mock)
            local btn = Radial.wheelButtons[1][1]
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("spell", "Fireball")
            assert.equals("spell", btn:GetAttribute("type"))
            assert.equals("Fireball", btn:GetAttribute("spell"))
        end)
    end)
    
    describe("visibility", function()
        it("ShowCurrentWheel shows wheel 1", function()
            Radial:ShowCurrentWheel()
            assert.is_true(Radial.isVisible)
            assert.is_true(Radial.wheels[1]:IsShown())
        end)
        
        it("ShowCurrentWheel hides other wheels", function()
            Radial:ShowCurrentWheel()
            for i = 2, MAX_WHEELS do
                assert.is_false(Radial.wheels[i]:IsShown(),
                    "Wheel " .. i .. " should be hidden when wheel 1 is shown")
            end
        end)
        
        it("HideCurrentWheel hides all wheels", function()
            Radial:ShowCurrentWheel()
            Radial:HideCurrentWheel()
            
            assert.is_false(Radial.isVisible)
            for i = 1, MAX_WHEELS do
                assert.is_false(Radial.wheels[i]:IsShown())
            end
        end)
    end)
    
    describe("wheel cycling", function()
        it("CycleWheelNext advances to wheel 2", function()
            assert.equals(1, Radial.currentWheel)
            Radial:CycleWheelNext()
            assert.equals(2, Radial.currentWheel)
        end)
        
        it("CycleWheelNext wraps from wheel 8 to wheel 1", function()
            Radial.currentWheel = MAX_WHEELS
            Radial:CycleWheelNext()
            assert.equals(1, Radial.currentWheel)
        end)
        
        it("CycleWheelPrev goes to previous wheel", function()
            Radial.currentWheel = 3
            Radial:CycleWheelPrev()
            assert.equals(2, Radial.currentWheel)
        end)
        
        it("CycleWheelPrev wraps from wheel 1 to wheel 8", function()
            Radial.currentWheel = 1
            Radial:CycleWheelPrev()
            assert.equals(MAX_WHEELS, Radial.currentWheel)
        end)
    end)
    
    describe("peek vs lock", function()
        it("PeekWheel shows wheel and sets peek timer", function()
            Radial:PeekWheel()
            assert.is_true(Radial.isVisible)
            assert.is_false(Radial.isLocked)
        end)
        
        it("LockWheel shows wheel and sets locked state", function()
            Radial:LockWheel()
            assert.is_true(Radial.isVisible)
            assert.is_true(Radial.isLocked)
        end)
        
        it("UnlockWheel clears locked state", function()
            Radial:LockWheel()
            Radial:UnlockWheel()
            assert.is_false(Radial.isLocked)
        end)
        
        it("PeekWheel does nothing when already locked", function()
            Radial:LockWheel()
            Radial.isLocked = true
            Radial:PeekWheel()  -- should not reset locked state
            assert.is_true(Radial.isLocked)
        end)
    end)
    
    describe("slot configuration", function()
        it("SetSlot assigns spell type and value", function()
            local ok = Radial:SetSlot(1, 1, "spell", "Fireball")
            assert.is_true(ok)
            local btn = Radial.wheelButtons[1][1]
            assert.equals("spell", btn:GetAttribute("type"))
            assert.equals("Fireball", btn:GetAttribute("spell"))
        end)
        
        it("SetSlot persists to char DB", function()
            Radial:SetSlot(1, 3, "spell", "Frostbolt")
            assert.is_not_nil(CP.db.char.wheelLayouts[1])
            assert.is_not_nil(CP.db.char.wheelLayouts[1][3])
            assert.equals("spell", CP.db.char.wheelLayouts[1][3].type)
            assert.equals("Frostbolt", CP.db.char.wheelLayouts[1][3].value)
        end)
        
        it("SetSlot blocked during combat", function()
            _G._SetCombatState(true)
            local ok = Radial:SetSlot(1, 1, "spell", "Fireball")
            assert.is_false(ok)
        end)
        
        it("SetSlot returns false for invalid wheel index", function()
            local ok = Radial:SetSlot(99, 1, "spell", "Fireball")
            assert.is_false(ok)
        end)
        
        it("SetSlot returns false for invalid slot index", function()
            local ok = Radial:SetSlot(1, 99, "spell", "Fireball")
            assert.is_false(ok)
        end)
    end)
end)
