-- spec/bindings_spec.lua
-- Tests for Bindings module: SetOverrideBindingSpell (override layer) for direct mode,
-- SetOverrideBindingClick (transient) for wheel mode, combat safety.
--
-- WHY override layer (not SetBinding)?
--   WoW's built-in gamepad preset re-applies on UPDATE_BINDINGS every login,
--   overwriting any SetBinding PAD key. SetOverrideBindingSpell sits in the
--   override layer which has higher priority and is never clobbered by presets.

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
        it("writes face-button spells to the override binding layer", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            
            -- Direct mode now uses SetOverrideBindingSpell — override layer, NOT permanent
            local override = _G._GetOverrideBindings(Bindings.ownerFrame)
            local count = 0
            for _ in pairs(override) do count = count + 1 end
            assert.is_true(count > 0, "Should have applied at least one override binding")
        end)

        it("does NOT touch the permanent binding layer", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()

            -- Permanent (SetBinding) layer must remain untouched
            helpers.assertNoPermanentBindings()
        end)

        it("binds face buttons to correct spells for Fire Mage (override layer)", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()

            local override = _G._GetOverrideBindings(Bindings.ownerFrame)
            assert.equals("SPELL Fireball",    override["PAD4"], "PAD4 (Y) should be primary spell")
            assert.equals("SPELL Pyroblast",   override["PAD2"], "PAD2 (B) should be secondary spell")
            assert.equals("SPELL Fire Blast",  override["PAD1"], "PAD1 (A) should be tertiary spell")
            assert.equals("SPELL Counterspell",override["PAD3"], "PAD3 (X) should be interrupt")
        end)

        it("does NOT call SaveBindings (override bindings are session-only)", function()
            C_GamePad._SimulateConnect(1)
            local before = _G._GetSaveBindingsCalls()
            Bindings:ApplyControllerBindings()
            assert.equals(before, _G._GetSaveBindingsCalls(),
                "SaveBindings must NOT be called — override bindings need no persistence")
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
        
        it("queues apply during combat — no override set", function()
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
            -- Override bindings should now be set
            local override = _G._GetOverrideBindings(Bindings.ownerFrame)
            assert.is_not_nil(override["PAD4"], "PAD4 should be bound after combat ends")
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

        it("RestoreDirectBindings clears wheel overrides and re-applies spell overrides", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyWheelBindings(1)
            assert.is_true(Bindings.wheelOpen)

            Bindings:RestoreDirectBindings()
            assert.is_false(Bindings.wheelOpen)

            -- Wheel-mode CLICK overrides are cleared; spell overrides are back
            local override = _G._GetOverrideBindings(Bindings.ownerFrame)
            -- PAD4 should now have a SPELL override, not a CLICK override
            assert.is_not_nil(override["PAD4"], "PAD4 should still have a binding after restore")
            assert.is_truthy(override["PAD4"]:find("^SPELL "),
                "PAD4 binding should be SPELL after restore, got: " .. tostring(override["PAD4"]))
        end)
    end)

    describe("GetBindingAction reflects binding layers", function()
        it("override layer has SPELL binding after ApplyDirectBindings", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyDirectBindings()

            -- Direct bindings are in the override layer — checkOverride=true required
            local binding = GetBindingAction("PAD4", true)
            assert.is_not_nil(binding, "PAD4 should have an override binding")
            assert.equals("SPELL Fireball", binding)
        end)

        it("permanent layer is NOT set after ApplyDirectBindings", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyDirectBindings()

            -- No permanent binding should exist (we use override, not SetBinding)
            local binding = GetBindingAction("PAD4", false)
            assert.is_nil(binding,
                "PAD4 must NOT be in the permanent layer — override layer only")
        end)

        it("override layer has CLICK binding after ApplyWheelBindings", function()
            Bindings:ApplyWheelBindings(1)

            -- Wheel mode uses transient override — checkOverride=true required
            local binding = GetBindingAction("PAD4", true)
            assert.is_not_nil(binding)
            assert.is_truthy(binding:find("^CLICK "),
                "PAD4 in wheel mode should be a CLICK binding")
        end)

        it("override layer is nil after ClearControllerBindings", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyDirectBindings()
            Bindings:ClearControllerBindings()

            assert.is_nil(GetBindingAction("PAD4", true),
                "PAD4 override should be nil after ClearControllerBindings")
        end)
    end)

    describe("ClearControllerBindings", function()
        it("clears all override bindings", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            
            Bindings:ClearControllerBindings()
            helpers.assertNoBindings(Bindings.ownerFrame)
        end)

        it("never touches the permanent binding layer", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            Bindings:ClearControllerBindings()

            -- Permanent layer should remain untouched (empty)
            helpers.assertNoPermanentBindings()
        end)

        it("does NOT call SaveBindings", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            local before = _G._GetSaveBindingsCalls()

            Bindings:ClearControllerBindings()
            assert.equals(before, _G._GetSaveBindingsCalls(),
                "SaveBindings must NOT be called — no permanent bindings to save")
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
            helpers.assertNoBindings(Bindings.ownerFrame)  -- nothing set yet

            helpers.fireEvent("UPDATE_BINDINGS")

            -- Timer is pending but not fired
            helpers.assertNoBindings(Bindings.ownerFrame)
            assert.is_not_nil(Bindings._applyTimer, "A debounce timer should be pending")
        end)

        it("applies override bindings when the timer fires", function()
            C_GamePad._SimulateConnect(1)
            helpers.fireEvent("UPDATE_BINDINGS")

            -- Fire all pending C_Timer.After callbacks
            C_Timer._FireAll()

            local override = _G._GetOverrideBindings(Bindings.ownerFrame)
            assert.is_not_nil(override["PAD4"], "PAD4 should be bound after debounce fires")
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
            helpers.assertNoBindings(Bindings.ownerFrame)
            helpers.assertNoPermanentBindings()
        end)
    end)
    
    describe("combat safety — CRITICAL", function()
        it("NEVER calls SetOverrideBindingSpell during combat", function()
            local combatCallDetected = false
            local originalSOBS = _G.SetOverrideBindingSpell
            _G.SetOverrideBindingSpell = function(owner, isPriority, key, spell)
                if InCombatLockdown() then
                    combatCallDetected = true
                    error("TAINT: SetOverrideBindingSpell called during combat!")
                end
                return originalSOBS(owner, isPriority, key, spell)
            end
            
            _G._SetCombatState(true)
            C_GamePad._SimulateConnect(1)
            
            assert.has_no.errors(function()
                Bindings:ApplyControllerBindings()
            end)
            assert.is_false(combatCallDetected,
                "SetOverrideBindingSpell was called during combat — taint risk!")
            
            _G.SetOverrideBindingSpell = originalSOBS
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

        it("NEVER calls SetBinding at any time (permanent layer is off-limits)", function()
            -- SetBinding should never be called since we switched to override bindings
            local setBindingCallDetected = false
            local originalSB = _G.SetBinding
            _G.SetBinding = function(key, command)
                setBindingCallDetected = true
                return originalSB(key, command)
            end

            C_GamePad._SimulateConnect(1)
            assert.has_no.errors(function()
                Bindings:ApplyControllerBindings()
                Bindings:ClearControllerBindings()
                Bindings:ApplyWheelBindings(1)
                Bindings:RestoreDirectBindings()
            end)
            assert.is_false(setBindingCallDetected,
                "SetBinding was called — should use SetOverrideBindingSpell instead!")

            _G.SetBinding = originalSB
        end)

        it("NEVER calls SaveBindings at any time (no permanent bindings to save)", function()
            local saveBindingsCallDetected = false
            local originalSave = _G.SaveBindings
            _G.SaveBindings = function(setID)
                saveBindingsCallDetected = true
                return originalSave(setID)
            end

            C_GamePad._SimulateConnect(1)
            assert.has_no.errors(function()
                Bindings:ApplyControllerBindings()
                Bindings:ClearControllerBindings()
            end)
            assert.is_false(saveBindingsCallDetected,
                "SaveBindings was called — override bindings need no persistence!")

            _G.SaveBindings = originalSave
        end)
    end)
end)
