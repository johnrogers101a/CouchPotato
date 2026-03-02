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
        
        it("includes primary spell binding for current spec", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            
            local bindings = _G._GetOverrideBindings(Bindings.ownerFrame)
            -- Fire Mage primary = Fireball, bound to PAD2 (B button)
            assert.is_not_nil(bindings["PAD2"] or bindings["PAD1"],
                "Should have a face button binding for primary spell")
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
