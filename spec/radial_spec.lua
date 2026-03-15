-- spec/radial_spec.lua
-- Tests for Radial list menu: frame creation, navigation, slot management, cycling

require("spec/wow_mock")
local helpers = require("spec/helpers")

describe("Radial Module", function()
    local CP, Radial
    local MAX_WHEELS = 8
    local MAX_SLOTS = 12
    
    before_each(function()
        helpers.resetMocks()

        dofile("ControllerCompanion/ControllerCompanion.lua")
        CP = ControllerCompanion
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

        dofile("ControllerCompanion/Core/GamePad.lua")
        dofile("ControllerCompanion/Core/Specs.lua")
        dofile("ControllerCompanion/UI/Radial.lua")

        CP:GetModule("GamePad"):Enable()
        CP:GetModule("Specs"):Enable()
        Radial = CP:GetModule("Radial")
        Radial:Enable()
    end)
    
    describe("initialization", function()
        it("creates page frames for all wheels", function()
            for i = 1, MAX_WHEELS do
                assert.is_not_nil(Radial.wheels[i],
                    "Page " .. i .. " should exist")
            end
        end)
        
        it("creates correct number of rows per page", function()
            for wheelIdx = 1, MAX_WHEELS do
                assert.is_not_nil(Radial.wheelButtons[wheelIdx])
                for slotIdx = 1, MAX_SLOTS do
                    assert.is_not_nil(Radial.wheelButtons[wheelIdx][slotIdx],
                        string.format("Page %d row %d should exist", wheelIdx, slotIdx))
                end
            end
        end)
        
        it("creates the outer list window frame", function()
            assert.is_not_nil(Radial.listWindow)
            assert.is_not_nil(_G["ControllerCompanionListWindow"])
        end)
        
        it("starts with all page frames hidden", function()
            for i = 1, MAX_WHEELS do
                assert.is_false(Radial.wheels[i]:IsShown(),
                    "Page " .. i .. " should start hidden")
            end
        end)

        it("starts with list window hidden", function()
            assert.is_false(Radial.listWindow:IsShown())
        end)
        
        it("starts on wheel 1", function()
            assert.equals(1, Radial.currentWheel)
        end)
        
        it("row buttons default to type 'empty'", function()
            -- Page 8, row 12 is never populated by default spec layouts
            local row = Radial.wheelButtons[8][12]
            assert.equals("empty", row:GetAttribute("type"))
        end)
        
        it("row buttons use SecureActionButtonTemplate", function()
            local row = Radial.wheelButtons[1][1]
            row:SetAttribute("type", "spell")
            row:SetAttribute("spell", "Fireball")
            assert.equals("spell", row:GetAttribute("type"))
            assert.equals("Fireball", row:GetAttribute("spell"))
        end)
    end)
    
    describe("visibility", function()
        it("ShowCurrentWheel shows page 1 and the list window", function()
            Radial:ShowCurrentWheel()
            assert.is_true(Radial.isVisible)
            assert.is_true(Radial.wheels[1]:IsShown())
            assert.is_true(Radial.listWindow:IsShown())
        end)
        
        it("ShowCurrentWheel hides other page frames", function()
            Radial:ShowCurrentWheel()
            for i = 2, MAX_WHEELS do
                assert.is_false(Radial.wheels[i]:IsShown(),
                    "Page " .. i .. " should be hidden when page 1 is shown")
            end
        end)
        
        it("HideCurrentWheel hides all pages and the window", function()
            Radial:ShowCurrentWheel()
            Radial:HideCurrentWheel()
            
            assert.is_false(Radial.isVisible)
            assert.is_false(Radial.listWindow:IsShown())
            for i = 1, MAX_WHEELS do
                assert.is_false(Radial.wheels[i]:IsShown())
            end
        end)

        it("HideCurrentWheel clears selectedIndex", function()
            Radial:ShowCurrentWheel()
            Radial.selectedIndex = 3
            Radial:HideCurrentWheel()
            assert.is_nil(Radial.selectedIndex)
        end)
    end)
    
    describe("wheel cycling", function()
        it("CycleWheelNext advances to page 2", function()
            assert.equals(1, Radial.currentWheel)
            Radial:CycleWheelNext()
            assert.equals(2, Radial.currentWheel)
        end)
        
        it("CycleWheelNext wraps from page 8 to page 1", function()
            Radial.currentWheel = MAX_WHEELS
            Radial:CycleWheelNext()
            assert.equals(1, Radial.currentWheel)
        end)
        
        it("CycleWheelPrev goes to previous page", function()
            Radial.currentWheel = 3
            Radial:CycleWheelPrev()
            assert.equals(2, Radial.currentWheel)
        end)
        
        it("CycleWheelPrev wraps from page 1 to page 8", function()
            Radial.currentWheel = 1
            Radial:CycleWheelPrev()
            assert.equals(MAX_WHEELS, Radial.currentWheel)
        end)
    end)

    describe("D-pad navigation", function()
        it("ControllerCompanionNavUpBtn frame is created on init", function()
            assert.is_not_nil(_G["ControllerCompanionNavUpBtn"])
        end)

        it("ControllerCompanionNavDownBtn frame is created on init", function()
            assert.is_not_nil(_G["ControllerCompanionNavDownBtn"])
        end)

        it("OpenWheel auto-selects the first visible slot", function()
            Radial:OpenWheel()
            -- Page 1 (Interface) has slot 1 = Character as first item
            assert.equals(1, Radial.selectedIndex)
        end)

        it("NavigateList(1) moves selection to next slot", function()
            Radial:OpenWheel()
            assert.equals(1, Radial.selectedIndex)
            Radial:NavigateList(1)
            assert.equals(2, Radial.selectedIndex)
        end)

        it("NavigateList(-1) moves selection to previous slot", function()
            Radial:OpenWheel()
            Radial.selectedIndex = 3
            Radial:NavigateList(-1)
            assert.equals(2, Radial.selectedIndex)
        end)

        it("NavigateList(1) wraps from last slot to first", function()
            Radial:OpenWheel()
            -- Page 1 has 12 slots; move to last
            local visible = Radial:GetVisibleSlots(1)
            Radial.selectedIndex = visible[#visible]
            Radial:NavigateList(1)
            assert.equals(visible[1], Radial.selectedIndex)
        end)

        it("NavigateList(-1) wraps from first slot to last", function()
            Radial:OpenWheel()
            local visible = Radial:GetVisibleSlots(1)
            Radial.selectedIndex = visible[1]
            Radial:NavigateList(-1)
            assert.equals(visible[#visible], Radial.selectedIndex)
        end)

        it("GetVisibleSlots returns 12 slots for interface page 1", function()
            local visible = Radial:GetVisibleSlots(1)
            assert.equals(12, #visible)
        end)

        it("GetVisibleSlots returns 10 slots for system page 2", function()
            local visible = Radial:GetVisibleSlots(2)
            assert.equals(10, #visible)
        end)

        it("GetVisibleSlots returns empty list for blank user page", function()
            local visible = Radial:GetVisibleSlots(8)
            assert.equals(0, #visible)
        end)

        it("CycleWheelNext auto-selects first slot when menu is open", function()
            Radial:OpenWheel()
            Radial.currentWheel = 1
            Radial:CycleWheelNext()
            -- Now on page 2; should select first visible slot (slot 1)
            assert.equals(2, Radial.currentWheel)
            assert.equals(1, Radial.selectedIndex)
        end)
    end)
    
    describe("peek vs lock (compat stubs)", function()
        it("PeekWheel shows list", function()
            Radial:PeekWheel()
            assert.is_true(Radial.isVisible)
            assert.is_false(Radial.isLocked)
        end)
        
        it("LockWheel shows list and sets locked state", function()
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
            Radial:PeekWheel()
            assert.is_true(Radial.isLocked)
        end)
    end)
    
    describe("slot configuration", function()
        it("SetSlot assigns spell type and value", function()
            local ok = Radial:SetSlot(1, 1, "spell", "Fireball")
            assert.is_true(ok)
            local row = Radial.wheelButtons[1][1]
            assert.equals("spell", row:GetAttribute("type"))
            assert.equals("Fireball", row:GetAttribute("spell"))
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
        it("ControllerCompanionConfirmBtn frame is created on init", function()
            assert.is_not_nil(_G["ControllerCompanionConfirmBtn"])
        end)

        it("ControllerCompanionCloseBtn frame is created on init", function()
            assert.is_not_nil(_G["ControllerCompanionCloseBtn"])
        end)

        it("ControllerCompanionGlobalCloseBtn frame is created on init", function()
            assert.is_not_nil(_G["ControllerCompanionGlobalCloseBtn"])
        end)

        it("PAD2 has a permanent binding to ControllerCompanionGlobalCloseBtn at addon load", function()
            local bindings = _G._GetPermanentBindings()
            assert.is_not_nil(bindings["PAD2"], "PAD2 should have a permanent binding")
            assert.is_truthy(bindings["PAD2"]:find("ControllerCompanionGlobalCloseBtn"),
                "PAD2 permanent binding should target ControllerCompanionGlobalCloseBtn")
        end)

        it("CloseWheel hides the list without executing the selected item", function()
            local executed = false
            Radial:ShowCurrentWheel()
            Radial.selectedIndex = 1

            local orig = Radial.ConfirmAndClose
            Radial.ConfirmAndClose = function(self)
                executed = true
                orig(self)
            end

            Radial:CloseWheel()

            assert.is_false(executed, "CloseWheel must NOT call ConfirmAndClose")
            assert.is_false(Radial.isVisible, "list should be hidden after CloseWheel")

            Radial.ConfirmAndClose = orig
        end)

        it("CloseWheel does nothing when list is already closed", function()
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
        it("page 1 Map slot toggles WorldMapFrame", function()
            _G.WorldMapFrame._shown = false
            Radial:ShowCurrentWheel()
            Radial.selectedIndex = 4  -- Map is slot 4 on Interface page
            Radial:ConfirmAndClose()
            assert.is_true(_G.WorldMapFrame._shown, "Map slot should show WorldMapFrame")
        end)

        it("page 1 Bags slot calls ToggleAllBags", function()
            local called = false
            _G.ToggleAllBags = function() called = true end
            Radial:ShowCurrentWheel()
            Radial.selectedIndex = 7  -- Bags is slot 7 on Interface page
            Radial:ConfirmAndClose()
            assert.is_true(called, "Bags slot should call ToggleAllBags()")
        end)

        it("page 2 Mounts slot calls ToggleCollectionsJournal(2)", function()
            local tabArg = nil
            _G.ToggleCollectionsJournal = function(tab) tabArg = tab end
            Radial.currentWheel = 2
            Radial:ShowCurrentWheel()
            Radial.selectedIndex = 10  -- Mounts is slot 10 on System page
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
