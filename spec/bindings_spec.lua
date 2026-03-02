-- spec/bindings_spec.lua
-- Tests for Bindings module: SetBinding (permanent) for direct mode,
-- SetOverrideBindingClick (transient) for wheel mode, combat safety.

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

        it("ownerFrame uses SecureHandlerStateTemplate", function()
            assert.equals("SecureHandlerStateTemplate", Bindings.ownerFrame._template)
        end)
        
        it("does not apply bindings when no controller is active on enable", function()
            -- No controller connected in default mock state
            helpers.assertNoBindings(Bindings.ownerFrame)
            helpers.assertNoPermanentBindings()
        end)

        it("registers UPDATE_BINDINGS event", function()
            assert.is_true(Bindings._ownedEvents["UPDATE_BINDINGS"] == true)
        end)
    end)
    
    describe("ApplyControllerBindings (direct mode)", function()
        it("writes face-button spells to the permanent binding layer", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            
            -- Direct mode uses SetBinding — permanent layer, NOT override layer
            local permanent = _G._GetPermanentBindings()
            local count = 0
            for _ in pairs(permanent) do count = count + 1 end
            assert.is_true(count > 0, "Should have applied at least one permanent binding")
        end)

        it("binds face buttons to correct spells for Fire Mage", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()

            local permanent = _G._GetPermanentBindings()
            assert.equals("SPELL Fireball",    permanent["PAD4"], "PAD4 (Y) should be primary spell")
            assert.equals("SPELL Pyroblast",   permanent["PAD2"], "PAD2 (B) should be secondary spell")
            assert.equals("SPELL Fire Blast",  permanent["PAD1"], "PAD1 (A) should be tertiary spell")
            assert.equals("SPELL Counterspell",permanent["PAD3"], "PAD3 (X) should be interrupt")
        end)

        it("calls SaveBindings after applying", function()
            C_GamePad._SimulateConnect(1)
            local before = _G._GetSaveBindingsCalls()
            Bindings:ApplyControllerBindings()
            assert.is_true(_G._GetSaveBindingsCalls() > before,
                "SaveBindings should be called after applying direct bindings")
        end)
        
        it("does not bind RT/LT (Radial owns them)", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()

            local permanent = _G._GetPermanentBindings()
            local override  = _G._GetOverrideBindings(Bindings.ownerFrame)
            assert.is_nil(permanent["PADRTRIGGER"], "RT must not be in permanent bindings")
            assert.is_nil(permanent["PADLTRIGGER"], "LT must not be in permanent bindings")
            assert.is_nil(override["PADRTRIGGER"],  "RT must not be in override bindings")
            assert.is_nil(override["PADLTRIGGER"],  "LT must not be in override bindings")
        end)
        
        it("queues apply during combat — no SetBinding called", function()
            _G._SetCombatState(true)
            Bindings:ApplyControllerBindings()
            
            assert.is_true(Bindings.pendingApply)
            helpers.assertNoBindings(Bindings.ownerFrame)
            helpers.assertNoPermanentBindings()
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
            -- Permanent bindings should now be set
            local permanent = _G._GetPermanentBindings()
            assert.is_not_nil(permanent["PAD4"], "PAD4 should be bound after combat ends")
        end)
    end)
    
    describe("ApplyWheelBindings (wheel mode — transient overrides)", function()
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
            -- PAD3 (X/left) → slot 10
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

        it("RestoreDirectBindings clears wheel overrides and sets permanent spells", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyWheelBindings(1)
            assert.is_true(Bindings.wheelOpen)

            Bindings:RestoreDirectBindings()
            assert.is_false(Bindings.wheelOpen)

            -- Wheel-mode override bindings for face buttons are cleared
            local override = _G._GetOverrideBindings(Bindings.ownerFrame)
            assert.is_nil(override["PAD4"], "PAD4 wheel override should be gone after restore")

            -- Permanent layer now has the spell bindings
            local permanent = _G._GetPermanentBindings()
            assert.is_not_nil(permanent["PAD4"], "PAD4 should have a permanent binding after restore")
            assert.is_truthy(permanent["PAD4"]:find("^SPELL "),
                "PAD4 permanent binding should be a SPELL, got: " .. tostring(permanent["PAD4"]))
        end)
    end)

    describe("GetBindingAction reflects binding layers", function()
        it("permanent layer has SPELL binding after ApplyDirectBindings", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyDirectBindings()

            -- Direct bindings are permanent — checkOverride=false reads permanent layer only
            local binding = GetBindingAction("PAD4", false)
            assert.is_not_nil(binding, "PAD4 should have a permanent binding")
            assert.equals("SPELL Fireball", binding)
        end)

        it("checkOverride=true also finds permanent binding when no override exists", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyDirectBindings()

            -- No override on face buttons in direct mode; falls through to permanent
            local binding = GetBindingAction("PAD4", true)
            assert.equals("SPELL Fireball", binding)
        end)

        it("override layer has CLICK binding after ApplyWheelBindings", function()
            Bindings:ApplyWheelBindings(1)

            -- Wheel mode uses transient override — checkOverride=true required
            local binding = GetBindingAction("PAD4", true)
            assert.is_not_nil(binding)
            assert.is_truthy(binding:find("^CLICK "),
                "PAD4 in wheel mode should be a CLICK binding")
        end)

        it("permanent layer is nil after ClearControllerBindings", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyDirectBindings()
            Bindings:ClearControllerBindings()

            -- Original saved binding was nil → should be nil after restore
            assert.is_nil(GetBindingAction("PAD4", false))
        end)
    end)

    describe("ClearControllerBindings", function()
        it("restores original permanent bindings and clears overrides", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            
            Bindings:ClearControllerBindings()
            helpers.assertNoBindings(Bindings.ownerFrame)
            helpers.assertNoPermanentBindings()
        end)

        it("calls SaveBindings after restoring", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            local before = _G._GetSaveBindingsCalls()

            Bindings:ClearControllerBindings()
            assert.is_true(_G._GetSaveBindingsCalls() > before,
                "SaveBindings should be called after clearing bindings")
        end)
        
        it("queues clear during combat", function()
            _G._SetCombatState(true)
            Bindings:ClearControllerBindings()
            
            assert.is_true(Bindings.pendingClear)
        end)
        
        it("clears after combat ends", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            
            _G._SetCombatState(true)
            Bindings:ClearControllerBindings()
            assert.is_true(Bindings.pendingClear)
            
            _G._SetCombatState(false)
            helpers.fireEvent("PLAYER_REGEN_ENABLED")
            
            assert.is_false(Bindings.pendingClear)
            helpers.assertNoBindings(Bindings.ownerFrame)
            helpers.assertNoPermanentBindings()
        end)
    end)

    describe("UPDATE_BINDINGS debounce", function()
        it("does not apply immediately — schedules a timer", function()
            C_GamePad._SimulateConnect(1)
            helpers.assertNoPermanentBindings()  -- nothing set yet

            helpers.fireEvent("UPDATE_BINDINGS")

            -- Timer is pending but not fired
            helpers.assertNoPermanentBindings()
            assert.is_not_nil(Bindings._applyTimer, "A debounce timer should be pending")
        end)

        it("applies bindings when the timer fires", function()
            C_GamePad._SimulateConnect(1)
            helpers.fireEvent("UPDATE_BINDINGS")

            -- Fire all pending C_Timer.After callbacks
            C_Timer._FireAll()

            local permanent = _G._GetPermanentBindings()
            assert.is_not_nil(permanent["PAD4"], "PAD4 should be bound after debounce fires")
            assert.is_nil(Bindings._applyTimer, "Timer handle should be cleared after firing")
        end)

        it("cancels and reschedules on rapid successive events", function()
            C_GamePad._SimulateConnect(1)
            helpers.fireEvent("UPDATE_BINDINGS")
            local firstTimer = Bindings._applyTimer

            helpers.fireEvent("UPDATE_BINDINGS")
            local secondTimer = Bindings._applyTimer

            -- A new timer was scheduled (old one was cancelled)
            assert.is_not_nil(secondTimer)
            assert.is_true(firstTimer ~= secondTimer or firstTimer == nil,
                "A new timer should replace the first")
        end)

        it("does nothing during wheel-open state", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyWheelBindings(1)
            _G._ResetBindings()  -- clear any bindings from wheel open

            helpers.fireEvent("UPDATE_BINDINGS")
            C_Timer._FireAll()

            -- wheelOpen=true → ApplyDirectBindings should NOT run
            helpers.assertNoPermanentBindings()
        end)
    end)
    
    describe("combat safety — CRITICAL", function()
        it("NEVER calls SetBinding during combat", function()
            local combatCallDetected = false
            local originalSB = _G.SetBinding
            _G.SetBinding = function(key, command)
                if InCombatLockdown() then
                    combatCallDetected = true
                    error("TAINT: SetBinding called during combat!")
                end
                return originalSB(key, command)
            end
            
            _G._SetCombatState(true)
            C_GamePad._SimulateConnect(1)
            
            -- Should queue, NOT call SetBinding
            assert.has_no.errors(function()
                Bindings:ApplyControllerBindings()
            end)
            assert.is_false(combatCallDetected,
                "SetBinding was called during combat — taint risk!")
            
            _G.SetBinding = originalSB
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

        it("NEVER calls SaveBindings during combat", function()
            local combatCallDetected = false
            local originalSave = _G.SaveBindings
            _G.SaveBindings = function(setID)
                if InCombatLockdown() then
                    combatCallDetected = true
                    error("TAINT: SaveBindings called during combat!")
                end
                return originalSave(setID)
            end

            _G._SetCombatState(true)
            C_GamePad._SimulateConnect(1)

            assert.has_no.errors(function()
                Bindings:ApplyControllerBindings()
            end)
            assert.is_false(combatCallDetected,
                "SaveBindings was called during combat!")

            _G.SaveBindings = originalSave
        end)
    end)
end)
