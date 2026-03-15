-- spec/bindings_spec.lua
-- Tests for Bindings module: minimal trigger-only binding when wheel is closed,
-- SetOverrideBindingClick for wheel mode, combat safety.
--
-- NEW ARCHITECTURE:
--   Wheel closed: ONLY PADRTRIGGER is bound (opens wheel). PAD1-4 = WoW's normal action bars.
--   Wheel open:   PAD1=confirm (execute+close), PAD2=cancel (close no execute),
--                 PAD3/PAD4 NOT bound (stick controls selection), bumpers cycle wheels,
--                 trigger cancels on release.
--   Wheel closes: ClearOverrideBindings restores WoW's bindings, re-apply PADRTRIGGER only.

require("spec/wow_mock")
local helpers = require("spec/helpers")

describe("Bindings Module", function()
    local CP, Bindings, Specs
    
    before_each(function()
        helpers.resetMocks()

        dofile("ControllerCompanion/ControllerCompanion.lua")
        CP = ControllerCompanion
        CP.db = {
            profile = { vibrationEnabled = true },
            char    = { currentWheel = 1, wheelLayouts = {} },
        }

        dofile("ControllerCompanion/Core/Specs.lua")
        dofile("ControllerCompanion/Core/Bindings.lua")

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
    
    describe("ApplyControllerBindings (trigger-only mode)", function()
        it("binds ONLY the trigger button — PAD1-4 are NOT bound", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()
            
            local override = _G._GetOverrideBindings(Bindings.ownerFrame)
            -- Only PADRTRIGGER should be bound
            assert.is_not_nil(override["PADRTRIGGER"], "PADRTRIGGER should be bound")
            assert.equals("CLICK ControllerCompanionTriggerBtn:LeftButton", override["PADRTRIGGER"])
            
            -- PAD1-4 should NOT be bound (WoW handles them normally)
            assert.is_nil(override["PAD1"], "PAD1 should NOT be bound (WoW handles it)")
            assert.is_nil(override["PAD2"], "PAD2 should NOT be bound (WoW handles it)")
            assert.is_nil(override["PAD3"], "PAD3 should NOT be bound (WoW handles it)")
            assert.is_nil(override["PAD4"], "PAD4 should NOT be bound (WoW handles it)")
            
            -- Bumpers should NOT be bound (WoW handles them normally)
            assert.is_nil(override["PADLSHOULDER"], "PADLSHOULDER should NOT be bound")
            assert.is_nil(override["PADRSHOULDER"], "PADRSHOULDER should NOT be bound")
        end)

        it("does NOT touch the permanent binding layer", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyControllerBindings()

            -- Permanent (SetBinding) layer must remain untouched
            helpers.assertNoPermanentBindings()
        end)

        it("does NOT call SaveBindings (override bindings are session-only)", function()
            C_GamePad._SimulateConnect(1)
            local before = _G._GetSaveBindingsCalls()
            Bindings:ApplyControllerBindings()
            assert.equals(before, _G._GetSaveBindingsCalls(),
                "SaveBindings must NOT be called — override bindings need no persistence")
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
            -- Only trigger binding should be set
            local override = _G._GetOverrideBindings(Bindings.ownerFrame)
            assert.is_not_nil(override["PADRTRIGGER"], "PADRTRIGGER should be bound after combat ends")
            assert.is_nil(override["PAD4"], "PAD4 should NOT be bound (WoW handles it)")
        end)
    end)
    
    describe("ApplyWheelBindings (wheel mode — transient overrides)", function()
        it("binds bumpers, trigger, A/B confirm/cancel in wheel mode (PAD3/PAD4 unbound)", function()
            Bindings:ApplyWheelBindings(1)

            local bindings = _G._GetOverrideBindings(Bindings.ownerFrame)
            -- PAD3/PAD4 not bound (stick controls selection)
            assert.is_nil(bindings["PAD4"], "PAD4 should NOT be bound in wheel mode")
            assert.is_nil(bindings["PAD3"], "PAD3 should NOT be bound in wheel mode")

            -- PAD1 (A) → confirm/execute; PAD2 (B) → cancel/close
            assert.is_truthy(bindings["PAD1"] and bindings["PAD1"]:find("ControllerCompanionConfirmBtn"),
                "PAD1 should be bound to ControllerCompanionConfirmBtn")
            assert.is_truthy(bindings["PAD2"] and bindings["PAD2"]:find("ControllerCompanionCloseBtn"),
                "PAD2 should be bound to ControllerCompanionCloseBtn")
            
            -- Bumpers should be bound for wheel cycling
            assert.is_truthy(bindings["PADLSHOULDER"]:find("ControllerCompanionLSBtn"),
                "PADLSHOULDER should cycle wheels")
            assert.is_truthy(bindings["PADRSHOULDER"]:find("ControllerCompanionRSBtn"),
                "PADRSHOULDER should cycle wheels")
            
            -- Trigger should still be bound
            assert.is_truthy(bindings["PADRTRIGGER"]:find("ControllerCompanionTriggerBtn"),
                "PADRTRIGGER should be bound")
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

        it("RestoreDirectBindings clears wheel overrides and re-applies trigger only", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyWheelBindings(1)
            assert.is_true(Bindings.wheelOpen)

            Bindings:RestoreDirectBindings()
            assert.is_false(Bindings.wheelOpen)

            -- Wheel-mode bindings are cleared; only trigger is re-bound.
            local override = _G._GetOverrideBindings(Bindings.ownerFrame)
            assert.is_not_nil(override["PADRTRIGGER"], "PADRTRIGGER should still be bound after restore")
            
            -- PAD1-4 should NOT be bound — WoW handles them normally
            assert.is_nil(override["PAD1"], "PAD1 should NOT be bound after restore")
            assert.is_nil(override["PAD2"], "PAD2 should NOT be bound after restore")
            assert.is_nil(override["PAD3"], "PAD3 should NOT be bound after restore")
            assert.is_nil(override["PAD4"], "PAD4 should NOT be bound after restore")
        end)
    end)

    describe("GetBindingAction reflects binding layers", function()
        it("override layer has ONLY trigger binding after ApplyTriggerBinding", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyTriggerBinding()

            -- Only PADRTRIGGER should be bound
            local triggerBinding = GetBindingAction("PADRTRIGGER", true)
            assert.is_not_nil(triggerBinding, "PADRTRIGGER should have an override binding")
            assert.is_truthy(triggerBinding:find("^CLICK "),
                "PADRTRIGGER override should be CLICK binding")
            
            -- PAD1-4 should NOT be bound
            assert.is_nil(GetBindingAction("PAD4", true), "PAD4 should NOT have override binding")
            assert.is_nil(GetBindingAction("PAD1", true), "PAD1 should NOT have override binding")
        end)

        it("permanent layer is NOT set after ApplyTriggerBinding", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyTriggerBinding()

            -- No permanent binding should exist (we use override, not SetBinding)
            local binding = GetBindingAction("PADRTRIGGER", false)
            assert.is_nil(binding,
                "PADRTRIGGER must NOT be in the permanent layer — override layer only")
        end)

        it("override layer has bumper bindings after ApplyWheelBindings (no face buttons)", function()
            Bindings:ApplyWheelBindings(1)

            -- Wheel mode no longer binds face buttons (stick controls selection)
            -- Bumpers and trigger should be bound
            local lsBinding = GetBindingAction("PADLSHOULDER", true)
            assert.is_not_nil(lsBinding, "PADLSHOULDER should be bound")
            assert.is_truthy(lsBinding:find("^CLICK "),
                "PADLSHOULDER in wheel mode should be a CLICK binding")
                
            local rsBinding = GetBindingAction("PADRSHOULDER", true)
            assert.is_not_nil(rsBinding, "PADRSHOULDER should be bound")
        end)

        it("override layer has only trigger after ClearControllerBindings from wheel mode", function()
            C_GamePad._SimulateConnect(1)
            Bindings:ApplyWheelBindings(1)
            Bindings:RestoreDirectBindings()  -- This clears and re-applies trigger

            -- Trigger should be bound
            assert.is_not_nil(GetBindingAction("PADRTRIGGER", true),
                "PADRTRIGGER should be bound after restore")
            -- Face buttons should NOT be bound
            assert.is_nil(GetBindingAction("PAD4", true),
                "PAD4 override should be nil after RestoreDirectBindings")
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

        it("applies trigger binding when the timer fires", function()
            C_GamePad._SimulateConnect(1)
            helpers.fireEvent("UPDATE_BINDINGS")

            -- Fire all pending C_Timer.After callbacks
            C_Timer._FireAll()

            local override = _G._GetOverrideBindings(Bindings.ownerFrame)
            assert.is_not_nil(override["PADRTRIGGER"], "PADRTRIGGER should be bound after debounce fires")
            assert.is_nil(override["PAD4"], "PAD4 should NOT be bound (WoW handles it)")
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
        it("NEVER calls SetOverrideBindingClick during combat", function()
            -- Direct mode now uses SetOverrideBindingClick(isPriority=true).
            -- It must still be gated on InCombatLockdown().
            local combatCallDetected = false
            local originalSOBC = _G.SetOverrideBindingClick
            _G.SetOverrideBindingClick = function(owner, isPriority, key, buttonName, mouseButton)
                if InCombatLockdown() then
                    combatCallDetected = true
                    error("TAINT: SetOverrideBindingClick called during combat!")
                end
                return originalSOBC(owner, isPriority, key, buttonName, mouseButton)
            end
            
            _G._SetCombatState(true)
            C_GamePad._SimulateConnect(1)
            
            assert.has_no.errors(function()
                Bindings:ApplyControllerBindings()
            end)
            assert.is_false(combatCallDetected,
                "SetOverrideBindingClick was called during combat — taint risk!")
            
            _G.SetOverrideBindingClick = originalSOBC
        end)

        it("NEVER calls SetOverrideBindingSpell during combat (SetOverrideBindingSpell unused in direct mode)", function()
            -- SetOverrideBindingSpell is no longer used in direct mode.
            -- This test confirms it is never called at all (not just not during combat).
            local spellBindingCallDetected = false
            local originalSOBS = _G.SetOverrideBindingSpell
            _G.SetOverrideBindingSpell = function(owner, isPriority, key, spell)
                spellBindingCallDetected = true
                return originalSOBS(owner, isPriority, key, spell)
            end
            
            _G._SetCombatState(true)
            C_GamePad._SimulateConnect(1)
            
            assert.has_no.errors(function()
                Bindings:ApplyControllerBindings()
            end)
            assert.is_false(spellBindingCallDetected,
                "SetOverrideBindingSpell was called — direct mode must use SetOverrideBindingClick!")
            
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
