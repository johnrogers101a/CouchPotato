-- spec/bindings_spec.lua
-- Tests for Bindings module: override binding system, combat safety

require("spec/wow_mock")
local helpers = require("spec/helpers")

describe("Bindings Module", function()
    local CP, Bindings, Specs
    
    before_each(function()
        helpers.resetMocks()

        dofile("CouchPotato/CouchPotato.lua")
        CP = CouchPotato
        CP.db = {
            profile = { vibrationEnabled = true },
            char    = { currentWheel = 1, wheelLayouts = {} },
        }

        dofile("CouchPotato/Core/Specs.lua")
        dofile("CouchPotato/Core/Bindings.lua")

        Specs    = CP:GetModule("Specs")
        Bindings = CP:GetModule("Bindings")
        Specs:Enable()
        Bindings:Enable()

        -- Simulate Fire Mage (classID=8, spec=2)
        _MockPlayer.classID = 8
        _MockPlayer.class   = "MAGE"
        _MockPlayer.spec    = 2
    end)
    
    describe("initialization", function()
        it("creates ownerFrame on enable", function()
            assert.is_not_nil(Bindings.ownerFrame)
        end)
        
        it("does not apply bindings when no controller on enable", function()
            helpers.assertNoBindings(Bindings.ownerFrame)
        end)
    end)
    
    describe("ApplyControllerBindings", function()
        it("applies bindings when controller is active", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            
            local bindings = _G._GetOverrideBindings(Bindings.ownerFrame)
            -- Should have at least some bindings
            local count = 0
            for _ in pairs(bindings) do count = count + 1 end
            assert.is_true(count > 0, "Should have applied at least one binding")
        end)
        
        it("does not bind face buttons (radial wheel owns them)", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()

            local bindings = _G._GetOverrideBindings(Bindings.ownerFrame)
            -- RT/LT and face buttons are reserved for the Radial module
            assert.is_nil(bindings["PADRTRIGGER"], "RT must not be bound (Radial owns it)")
            assert.is_nil(bindings["PADLTRIGGER"], "LT must not be bound (Radial owns it)")
        end)
        
        it("queues apply during combat", function()
            _G._SetCombatState(true)
            Bindings:ApplyControllerBindings()
            
            assert.is_true(Bindings.pendingApply)
            helpers.assertNoBindings(Bindings.ownerFrame)
        end)
        
        it("applies queued bindings after combat ends", function()
            _G._SetCombatState(true)
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            assert.is_true(Bindings.pendingApply)
            
            -- Simulate combat end
            _G._SetCombatState(false)
            helpers.fireEvent("PLAYER_REGEN_ENABLED")
            
            assert.is_false(Bindings.pendingApply)
        end)
    end)
    
    describe("ApplyWheelBindings", function()
        it("binds face buttons to radial slot click targets", function()
            Bindings:ApplyWheelBindings(1)

            local bindings = _G._GetOverrideBindings(Bindings.ownerFrame)
            -- PAD4 (Y/top) → slot 1
            assert.is_not_nil(bindings["PAD4"], "PAD4 should be bound in wheel mode")
            assert.is_truthy(bindings["PAD4"]:find("CouchPotatoWheel1Slot1"),
                "PAD4 should click Wheel1Slot1, got: " .. tostring(bindings["PAD4"]))
            -- PAD2 (B/right) → slot 4
            assert.is_truthy(bindings["PAD2"]:find("CouchPotatoWheel1Slot4"),
                "PAD2 should click Wheel1Slot4")
            -- PAD1 (A/bottom) → slot 7
            assert.is_truthy(bindings["PAD1"]:find("CouchPotatoWheel1Slot7"),
                "PAD1 should click Wheel1Slot7")
            -- PAD3 (X/left) → slot 10  ← was the missing binding
            assert.is_truthy(bindings["PAD3"]:find("CouchPotatoWheel1Slot10"),
                "PAD3 should click Wheel1Slot10")
        end)

        it("sets wheelOpen flag", function()
            Bindings:ApplyWheelBindings(1)
            assert.is_true(Bindings.wheelOpen)
        end)

        it("does nothing during combat lockdown", function()
            _G._SetCombatState(true)
            Bindings:ApplyWheelBindings(1)
            helpers.assertNoBindings(Bindings.ownerFrame)
            assert.is_false(Bindings.wheelOpen)
        end)

        it("RestoreDirectBindings switches back to direct mode", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyWheelBindings(1)
            assert.is_true(Bindings.wheelOpen)

            Bindings:RestoreDirectBindings()
            assert.is_false(Bindings.wheelOpen)

            -- Direct mode: face buttons should be spell bindings again
            local bindings = _G._GetOverrideBindings(Bindings.ownerFrame)
            assert.is_not_nil(bindings["PAD4"])
            assert.is_truthy(bindings["PAD4"]:find("^SPELL "),
                "PAD4 should be a SPELL binding after restore")
        end)
    end)

    describe("GetBindingAction reflects override bindings", function()
        it("returns SPELL binding after ApplyDirectBindings", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyDirectBindings()

            -- Fire Mage primary = "Fireball"
            -- checkOverride=true required — without it WoW (and the mock) return the
            -- *default* binding (e.g. ACTIONBUTTON2), not the override we just set.
            local binding = GetBindingAction("PAD4", true)
            assert.is_not_nil(binding, "PAD4 should have a binding")
            assert.equals("SPELL Fireball", binding)
        end)

        it("returns CLICK binding after ApplyWheelBindings", function()
            Bindings:ApplyWheelBindings(1)

            -- checkOverride=true required to see the override layer
            local binding = GetBindingAction("PAD4", true)
            assert.is_not_nil(binding)
            assert.is_truthy(binding:find("^CLICK "),
                "PAD4 in wheel mode should be a CLICK binding")
        end)

        it("returns nil after ClearControllerBindings", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyDirectBindings()
            Bindings:ClearControllerBindings()

            -- checkOverride=true: override layer must be empty after clear
            assert.is_nil(GetBindingAction("PAD4", true))
        end)
    end)

    describe("ClearControllerBindings", function()
        it("clears all controller bindings", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            
            Bindings:ClearControllerBindings()
            helpers.assertNoBindings(Bindings.ownerFrame)
        end)
        
        it("queues clear during combat", function()
            _G._SetCombatState(true)
            Bindings:ClearControllerBindings()
            
            assert.is_true(Bindings.pendingClear)
        end)
        
        it("clears queued binding after combat", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            
            _G._SetCombatState(true)
            Bindings:ClearControllerBindings()
            assert.is_true(Bindings.pendingClear)
            
            _G._SetCombatState(false)
            helpers.fireEvent("PLAYER_REGEN_ENABLED")
            
            assert.is_false(Bindings.pendingClear)
            helpers.assertNoBindings(Bindings.ownerFrame)
        end)
    end)
    
    describe("combat safety — CRITICAL", function()
        it("NEVER calls SetOverrideBinding during combat", function()
            -- Override SetOverrideBinding to detect combat violations
            local combatCallDetected = false
            local originalSOB = _G.SetOverrideBinding
            _G.SetOverrideBinding = function(owner, isPriority, key, action)
                if InCombatLockdown() then
                    combatCallDetected = true
                    error("TAINT: SetOverrideBinding called during combat!")
                end
                originalSOB(owner, isPriority, key, action)
            end
            
            _G._SetCombatState(true)
            C_GamePad._SimulateConnect(1)
            
            -- This should NOT call SetOverrideBinding — should queue instead
            assert.has_no.errors(function()
                Bindings:ApplyControllerBindings()
            end)
            assert.is_false(combatCallDetected,
                "SetOverrideBinding was called during combat — taint risk!")
            
            _G.SetOverrideBinding = originalSOB
        end)
        
        it("NEVER calls ClearOverrideBindings during combat", function()
            local combatCallDetected = false
            local originalCOB = _G.ClearOverrideBindings
            _G.ClearOverrideBindings = function(owner)
                if InCombatLockdown() then
                    combatCallDetected = true
                    error("TAINT: ClearOverrideBindings called during combat!")
                end
                originalCOB(owner)
            end
            
            _G._SetCombatState(true)
            assert.has_no.errors(function()
                Bindings:ClearControllerBindings()
            end)
            assert.is_false(combatCallDetected,
                "ClearOverrideBindings was called during combat!")
            
            _G.ClearOverrideBindings = originalCOB
        end)
    end)
end)
