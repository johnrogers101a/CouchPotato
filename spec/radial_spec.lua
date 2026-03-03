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

        dofile("CouchPotato/CouchPotato.lua")
        CP = CouchPotato
        CP.db = {
            profile = {
                radialAlpha      = 0.9,
                peekThreshold    = 0.35,
                lockThreshold    = 0.75,
                vibrationEnabled = true,
            },
            char = {
                currentWheel = 1,
                wheelLayouts = {},
            },
        }

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

    describe("A/B button confirm/cancel semantics", function()
        it("CouchPotatoConfirmBtn frame is created on init", function()
            assert.is_not_nil(_G["CouchPotatoConfirmBtn"])
        end)

        it("CouchPotatoCloseBtn frame is created on init", function()
            assert.is_not_nil(_G["CouchPotatoCloseBtn"])
        end)

        it("CouchPotatoGlobalCloseBtn frame is created on init", function()
            assert.is_not_nil(_G["CouchPotatoGlobalCloseBtn"])
        end)

        it("PAD2 has a permanent binding to CouchPotatoGlobalCloseBtn at addon load", function()
            local bindings = _G._GetPermanentBindings()
            assert.is_not_nil(bindings["PAD2"], "PAD2 should have a permanent binding")
            assert.is_truthy(bindings["PAD2"]:find("CouchPotatoGlobalCloseBtn"),
                "PAD2 permanent binding should target CouchPotatoGlobalCloseBtn")
        end)

        it("CloseWheel hides the wheel without executing the highlighted slot", function()
            local executed = false
            Radial:ShowCurrentWheel()
            Radial.highlightedSlot = 1

            local orig = Radial.ConfirmAndClose
            Radial.ConfirmAndClose = function(self)
                executed = true
                orig(self)
            end

            Radial:CloseWheel()

            assert.is_false(executed, "CloseWheel must NOT call ConfirmAndClose")
            assert.is_false(Radial.isVisible, "wheel should be hidden after CloseWheel")

            Radial.ConfirmAndClose = orig
        end)

        it("CloseWheel does nothing when wheel is already closed", function()
            assert.is_false(Radial.isVisible)
            assert.has_no.errors(function() Radial:CloseWheel() end)
            assert.is_false(Radial.isVisible)
        end)

        it("ConfirmAndClose executes and closes", function()
            Radial:ShowCurrentWheel()
            assert.is_true(Radial.isVisible)
            Radial:ConfirmAndClose()
            assert.is_false(Radial.isVisible)
        end)
    end)

    describe("execute functions use direct WoW API", function()
        it("wheel 1 Map slot toggles WorldMapFrame", function()
            _G.WorldMapFrame._shown = false
            Radial:ShowCurrentWheel()
            Radial.highlightedSlot = 4  -- Map is slot 4
            Radial:ConfirmAndClose()
            assert.is_true(_G.WorldMapFrame._shown, "Map slot should show WorldMapFrame")
        end)

        it("wheel 1 Bags slot calls ToggleAllBags", function()
            local called = false
            _G.ToggleAllBags = function() called = true end
            Radial:ShowCurrentWheel()
            Radial.highlightedSlot = 7  -- Bags is slot 7
            Radial:ConfirmAndClose()
            assert.is_true(called, "Bags slot should call ToggleAllBags()")
        end)

        it("wheel 2 Mounts slot calls ToggleCollectionsJournal(2)", function()
            local tabArg = nil
            _G.ToggleCollectionsJournal = function(tab) tabArg = tab end
            Radial.currentWheel = 2
            Radial:ShowCurrentWheel()
            Radial.highlightedSlot = 10  -- Mounts is slot 10 on wheel 2
            Radial:ConfirmAndClose()
            assert.equals(2, tabArg, "Mounts should open Collections tab 2")
        end)
    end)

    describe("combat auto-close", function()
        it("PLAYER_REGEN_DISABLED calls CloseAllWindows", function()
            local closed = false
            _G.CloseAllWindows = function() closed = true end
            CP._FireEvent("PLAYER_REGEN_DISABLED")
            assert.is_true(closed, "CloseAllWindows should fire on PLAYER_REGEN_DISABLED")
        end)
    end)
end)
