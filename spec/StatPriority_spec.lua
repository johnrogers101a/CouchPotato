-- spec/StatPriority_spec.lua
-- Busted tests for StatPriority addon (Phase 1 + Phase 2)

require("spec/wow_mock")

-- Pre-load the data file so StatPriorityData is available when the main
-- addon is loaded (mirrors how the TOC loads them in order).
dofile("StatPriority/StatPriorityData.lua")

describe("StatPriority", function()
    local ns

    before_each(function()
        -- Reset global state
        _G.StatPriorityDB   = {}
        _G.StatPriorityNS   = nil
        _G.StatPriorityFrame = nil

        -- Default spec mock: Restoration Druid (specID 105, specIndex 4)
        -- Restoration Druid has _differs = false (all 3 sources agree)
        _G._MockPlayer = _G._MockPlayer or {}
        _G._MockPlayer.spec = 4
        _G.GetSpecialization = function() return 4 end
        _G.GetSpecializationInfo = function(specIndex)
            if specIndex == 4 then
                -- specID 105 = Restoration Druid
                return 105, "Restoration Druid", "Heals allies.", "", "HEALER"
            end
            return nil
        end

        -- Load the addon (varargs will be empty; test fallback sets ns = {})
        dofile("StatPriority/StatPriority.lua")
        ns = _G.StatPriorityNS

        -- Directly initialize the addon (bypasses ADDON_LOADED event)
        ns:OnLoad()
    end)

    -- =========================================================================
    -- Test 1: OnLoad creates frame with correct structure
    -- =========================================================================
    describe("OnLoad", function()
        it("creates the main frame", function()
            assert.is_not_nil(ns.frame)
        end)

        it("creates the header frame", function()
            assert.is_not_nil(ns.headerFrame)
        end)

        it("creates the content frame", function()
            assert.is_not_nil(ns.contentFrame)
        end)

        it("creates the stats label", function()
            assert.is_not_nil(ns.statsLabel)
        end)

        it("creates the collapse button", function()
            assert.is_not_nil(ns.collapseBtn)
        end)

        it("creates the three source labels", function()
            assert.is_not_nil(ns.wowheadLabel)
            assert.is_not_nil(ns.icyveinsLabel)
            assert.is_not_nil(ns.methodLabel)
        end)

        it("creates the three URL buttons", function()
            assert.is_not_nil(ns.wowheadUrlBtn)
            assert.is_not_nil(ns.icyveinsUrlBtn)
            assert.is_not_nil(ns.methodUrlBtn)
        end)

        it("creates the URL popup frame", function()
            assert.is_not_nil(ns.urlPopup)
        end)

        it("creates the URL popup editbox", function()
            assert.is_not_nil(ns.urlPopupEditBox)
        end)

        it("frame is shown by default", function()
            assert.is_true(ns.frame:IsShown())
        end)

        it("content frame is shown by default when not collapsed", function()
            assert.is_true(ns.contentFrame:IsShown())
        end)

        it("is idempotent — calling OnLoad twice does not replace the frame", function()
            local originalFrame = ns.frame
            ns:OnLoad()
            assert.equals(originalFrame, ns.frame)
        end)

        it("has version 2.0.0", function()
            assert.equals("2.0.0", ns.version)
        end)
    end)

    -- =========================================================================
    -- Test 2: UpdateStatPriority shows correct data for a known specID
    -- =========================================================================
    describe("UpdateStatPriority", function()
        it("sets header title to spec name for known specID", function()
            ns:UpdateStatPriority()
            assert.equals("Restoration Druid", ns.headerTitle:GetText())
        end)

        it("sets stats label with > separators for known specID (unified)", function()
            ns:UpdateStatPriority()
            local text = ns.statsLabel:GetText()
            assert.is_not_nil(text)
            -- Check that core stats appear in order
            assert.is_truthy(text:find("Intellect", 1, true))
            assert.is_truthy(text:find("Haste", 1, true))
            -- Check that gold > separator is present
            assert.is_truthy(text:find(">", 1, true))
        end)

        it("shows correct stat count for Restoration Druid (5 stats)", function()
            ns:UpdateStatPriority()
            local data = StatPriorityData[105]
            assert.equals(5, #data.stats)
            assert.equals("Intellect",      data.stats[1])
            assert.equals("Haste",          data.stats[2])
            assert.equals("Mastery",        data.stats[3])
            assert.equals("Versatility",    data.stats[4])
            assert.equals("Critical Strike",data.stats[5])
        end)
    end)

    -- =========================================================================
    -- Test 3: UpdateStatPriority handles nil spec gracefully
    -- =========================================================================
    describe("UpdateStatPriority with no spec", function()
        it("shows 'No Specialization' when GetSpecialization returns nil", function()
            _G.GetSpecialization = function() return nil end
            ns:UpdateStatPriority()
            assert.equals("No Specialization", ns.headerTitle:GetText())
        end)

        it("shows empty stats text when GetSpecialization returns nil", function()
            _G.GetSpecialization = function() return nil end
            ns:UpdateStatPriority()
            assert.equals("", ns.statsLabel:GetText())
        end)

        it("shows 'No Specialization' when GetSpecialization returns 0", function()
            _G.GetSpecialization = function() return 0 end
            ns:UpdateStatPriority()
            assert.equals("No Specialization", ns.headerTitle:GetText())
        end)

        -- This simulates the ADDON_LOADED race: GetSpecialization returns a
        -- valid index but GetSpecializationInfo returns specID=0 (not yet ready).
        it("shows 'Unknown Spec' (not 'Spec 0') when specID is 0 but name is nil", function()
            _G.GetSpecialization = function() return 2 end
            _G.GetSpecializationInfo = function(specIndex)
                -- Simulates early-load state: specID=0, name=nil
                return 0, nil, nil, nil, nil
            end
            ns:UpdateStatPriority()
            local title = ns.headerTitle:GetText()
            assert.is_falsy(title:find("Spec 0", 1, true),
                "header should not show 'Spec 0' but got: " .. tostring(title))
            assert.equals("Unknown Spec", title)
        end)

        it("shows 'Unknown Spec' when specID has no data entry (API name fallback)", function()
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                -- specID 99999 does not exist in StatPriorityData
                return 99999, nil, nil, nil, nil
            end
            ns:UpdateStatPriority()
            assert.equals("Unknown Spec", ns.headerTitle:GetText())
        end)

        it("shows API spec name when specID has no data but name is available", function()
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                return 99999, "Some Future Spec", nil, nil, nil
            end
            ns:UpdateStatPriority()
            assert.equals("Some Future Spec", ns.headerTitle:GetText())
        end)
    end)

    -- =========================================================================
    -- Test 3b: PLAYER_LOGIN event triggers spec refresh
    -- =========================================================================
    describe("PLAYER_LOGIN event handling", function()
        it("specEventFrame is registered for PLAYER_LOGIN", function()
            assert.is_not_nil(ns.specEventFrame)
            -- Fire the OnEvent script with PLAYER_LOGIN to verify it calls UpdateStatPriority
            local onEvent = ns.specEventFrame:GetScript("OnEvent")
            assert.is_not_nil(onEvent)
            -- Switch spec before firing the event
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 1 then return 251, "Frost Death Knight", "", "", "DAMAGER" end
                return nil
            end
            onEvent(ns.specEventFrame, "PLAYER_LOGIN")
            assert.equals("Frost Death Knight", ns.headerTitle:GetText())
        end)

        it("PLAYER_SPECIALIZATION_CHANGED still updates spec display", function()
            local onEvent = ns.specEventFrame:GetScript("OnEvent")
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 1 then return 250, "Blood Death Knight", "", "", "TANK" end
                return nil
            end
            onEvent(ns.specEventFrame, "PLAYER_SPECIALIZATION_CHANGED")
            assert.equals("Blood Death Knight", ns.headerTitle:GetText())
        end)
    end)

    -- =========================================================================
    -- Test 4: Header title updates to spec name
    -- =========================================================================
    describe("header title updates", function()
        it("updates header when spec changes to a different known spec", function()
            -- Switch to Frost Death Knight (specID 251)
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 1 then
                    return 251, "Frost Death Knight", "", "", "DAMAGER"
                end
                return nil
            end
            ns:UpdateStatPriority()
            assert.equals("Frost Death Knight", ns.headerTitle:GetText())
        end)

        it("shows spec name from data table (not raw API name) when available", function()
            -- specID 105 maps to "Restoration Druid" in data table
            ns:UpdateStatPriority()
            assert.equals("Restoration Druid", ns.headerTitle:GetText())
        end)
    end)

    -- =========================================================================
    -- Test 5: Content label shows stats with " > " separators
    -- =========================================================================
    describe("content label format", function()
        it("stats are separated by the gold > color sequence", function()
            ns:UpdateStatPriority()
            local text = ns.statsLabel:GetText()
            -- The separator includes the WoW color escape: |cffFFD100>|r
            assert.is_truthy(text:find("|cffFFD100>|r", 1, true))
        end)

        it("first stat appears before first separator", function()
            ns:UpdateStatPriority()
            local text = ns.statsLabel:GetText()
            local intellPos = text:find("Intellect", 1, true)
            local sepPos    = text:find("|cffFFD100>|r", 1, true)
            assert.is_truthy(intellPos)
            assert.is_truthy(sepPos)
            assert.is_true(intellPos < sepPos)
        end)
    end)

    -- =========================================================================
    -- Test 6: Collapse/expand toggles content visibility
    -- =========================================================================
    describe("collapse and expand", function()
        it("content frame is hidden after collapse button click", function()
            assert.is_true(ns.contentFrame:IsShown())
            -- Simulate collapse button click
            local onClick = ns.collapseBtn:GetScript("OnClick")
            assert.is_not_nil(onClick)
            onClick()
            assert.is_false(ns.contentFrame:IsShown())
        end)

        it("collapse button text changes to + when collapsed", function()
            local onClick = ns.collapseBtn:GetScript("OnClick")
            onClick()
            assert.equals("+", ns.collapseBtnText:GetText())
        end)

        it("content frame is shown after expand button click", function()
            local onClick = ns.collapseBtn:GetScript("OnClick")
            onClick()  -- collapse
            assert.is_false(ns.contentFrame:IsShown())
            onClick()  -- expand
            assert.is_true(ns.contentFrame:IsShown())
        end)

        it("collapsed state is saved to StatPriorityDB", function()
            local onClick = ns.collapseBtn:GetScript("OnClick")
            onClick()  -- collapse
            assert.is_true(StatPriorityDB.collapsed)
            onClick()  -- expand
            assert.is_false(StatPriorityDB.collapsed)
        end)
    end)

    -- =========================================================================
    -- Test 7: Position save/restore from SavedVariables
    -- =========================================================================
    describe("position save and restore", function()
        it("does not save position before drag", function()
            -- Fresh DB has no position set
            assert.is_nil(StatPriorityDB.position)
        end)

        it("saves position on drag stop", function()
            local onDragStop = ns.headerFrame:GetScript("OnDragStop")
            assert.is_not_nil(onDragStop)
            onDragStop()
            -- After drag stop the position key should exist
            assert.is_not_nil(StatPriorityDB.position)
        end)

        it("restores saved position on load when unpinned", function()
            -- Set a saved position with pinned=false (position is only restored when unpinned)
            _G.StatPriorityDB = {
                pinned   = false,
                position = { point = "CENTER", relativePoint = "CENTER", x = 100, y = 200 }
            }
            _G.StatPriorityNS   = nil
            _G.StatPriorityFrame = nil
            dofile("StatPriority/StatPriority.lua")
            local ns2 = _G.StatPriorityNS
            ns2:OnLoad()

            -- Frame should have been given a SetPoint call with the saved values
            -- (the mock records SetPoint calls in _points)
            local points = ns2.frame._points
            local found = false
            for _, p in ipairs(points) do
                if p[1] == "CENTER" then found = true break end
            end
            assert.is_true(found)
        end)
    end)

    -- =========================================================================
    -- Test 8: Unified display when _differs is false
    -- =========================================================================
    describe("unified display (_differs = false)", function()
        -- Restoration Druid (105) has _differs = false
        it("statsLabel is shown when _differs is false", function()
            ns:UpdateStatPriority()
            assert.is_true(ns.statsLabel:IsShown())
        end)

        it("source labels are hidden when _differs is false", function()
            ns:UpdateStatPriority()
            assert.is_false(ns.wowheadLabel:IsShown())
            assert.is_false(ns.icyveinsLabel:IsShown())
            assert.is_false(ns.methodLabel:IsShown())
        end)

        it("URL buttons are hidden when _differs is false", function()
            ns:UpdateStatPriority()
            assert.is_false(ns.wowheadUrlBtn:IsShown())
            assert.is_false(ns.icyveinsUrlBtn:IsShown())
            assert.is_false(ns.methodUrlBtn:IsShown())
        end)
    end)

    -- =========================================================================
    -- Test 9: Multi-source display when _differs is true
    -- =========================================================================
    describe("multi-source display (_differs = true)", function()
        -- Switch to Frost Death Knight (specID 251) which has _differs = true
        before_each(function()
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 1 then
                    return 251, "Frost Death Knight", "", "", "DAMAGER"
                end
                return nil
            end
        end)

        it("Frost Death Knight data has _differs = true", function()
            local data = StatPriorityData[251]
            assert.is_not_nil(data)
            assert.is_true(data._differs)
        end)

        it("statsLabel is hidden when _differs is true", function()
            ns:UpdateStatPriority()
            assert.is_false(ns.statsLabel:IsShown())
        end)

        it("all three source labels are shown when _differs is true", function()
            ns:UpdateStatPriority()
            assert.is_true(ns.wowheadLabel:IsShown())
            assert.is_true(ns.icyveinsLabel:IsShown())
            assert.is_true(ns.methodLabel:IsShown())
        end)

        it("wowhead label contains cyan color code and source name", function()
            ns:UpdateStatPriority()
            local text = ns.wowheadLabel:GetText()
            assert.is_truthy(text:find("|cff00ccffWowhead:|r", 1, true))
        end)

        it("icyveins label contains green color code and source name", function()
            ns:UpdateStatPriority()
            local text = ns.icyveinsLabel:GetText()
            assert.is_truthy(text:find("|cff33cc33Icy Veins:|r", 1, true))
        end)

        it("method label contains orange color code and source name", function()
            ns:UpdateStatPriority()
            local text = ns.methodLabel:GetText()
            assert.is_truthy(text:find("|cffff6600Method:|r", 1, true))
        end)

        it("wowhead label shows per-source stat priority for Frost DK", function()
            ns:UpdateStatPriority()
            local text = ns.wowheadLabel:GetText()
            local data = StatPriorityData[251]
            -- Should contain first wowhead stat
            assert.is_truthy(text:find(data.wowhead[1], 1, true))
        end)

        it("icyveins label shows per-source stat priority for Frost DK", function()
            ns:UpdateStatPriority()
            local text = ns.icyveinsLabel:GetText()
            local data = StatPriorityData[251]
            assert.is_truthy(text:find(data.icyveins[1], 1, true))
        end)

        it("method label shows per-source stat priority for Frost DK", function()
            ns:UpdateStatPriority()
            local text = ns.methodLabel:GetText()
            local data = StatPriorityData[251]
            assert.is_truthy(text:find(data.method[1], 1, true))
        end)

        it("URL buttons are shown when _differs is true", function()
            ns:UpdateStatPriority()
            assert.is_true(ns.wowheadUrlBtn:IsShown())
            assert.is_true(ns.icyveinsUrlBtn:IsShown())
            assert.is_true(ns.methodUrlBtn:IsShown())
        end)
    end)

    -- =========================================================================
    -- Test 10: URL popup behaviour
    -- =========================================================================
    describe("URL popup", function()
        it("popup is hidden by default", function()
            assert.is_false(ns.urlPopup:IsShown())
        end)

        it("ShowURLPopup shows the popup", function()
            ns:ShowURLPopup("https://www.wowhead.com/test")
            assert.is_true(ns.urlPopup:IsShown())
        end)

        it("ShowURLPopup sets the editbox URL text", function()
            local url = "https://www.wowhead.com/test-url"
            ns:ShowURLPopup(url)
            assert.equals(url, ns.urlPopupEditBox:GetText())
        end)

        it("ShowURLPopup highlights the editbox text", function()
            ns:ShowURLPopup("https://www.example.com/")
            assert.is_true(ns.urlPopupEditBox._highlighted)
        end)

        it("URL button OnClick shows popup with correct wowhead URL for Frost DK", function()
            -- Switch to Frost DK
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 1 then return 251, "Frost Death Knight", "", "", "DAMAGER" end
                return nil
            end
            ns:UpdateStatPriority()

            -- Click the wowhead URL button
            local onClick = ns.wowheadUrlBtn:GetScript("OnClick")
            assert.is_not_nil(onClick)
            onClick(ns.wowheadUrlBtn)

            assert.is_true(ns.urlPopup:IsShown())
            local url = ns.urlPopupEditBox:GetText()
            assert.is_truthy(url:find("wowhead.com", 1, true))
            assert.is_truthy(url:find("death-knight", 1, true))
        end)

        it("URL button OnClick shows popup with correct icyveins URL for Frost DK", function()
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 1 then return 251, "Frost Death Knight", "", "", "DAMAGER" end
                return nil
            end
            ns:UpdateStatPriority()

            local onClick = ns.icyveinsUrlBtn:GetScript("OnClick")
            assert.is_not_nil(onClick)
            onClick(ns.icyveinsUrlBtn)

            local url = ns.urlPopupEditBox:GetText()
            assert.is_truthy(url:find("icy-veins.com", 1, true))
        end)

        it("URL button OnClick shows popup with correct method URL for Frost DK", function()
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 1 then return 251, "Frost Death Knight", "", "", "DAMAGER" end
                return nil
            end
            ns:UpdateStatPriority()

            local onClick = ns.methodUrlBtn:GetScript("OnClick")
            assert.is_not_nil(onClick)
            onClick(ns.methodUrlBtn)

            local url = ns.urlPopupEditBox:GetText()
            assert.is_truthy(url:find("method.gg", 1, true))
        end)
    end)

    -- =========================================================================
    -- Test 11: Pin/lock behavior
    -- =========================================================================
    describe("pin and lock behavior", function()
        it("creates a pin button (ns.pinBtn)", function()
            assert.is_not_nil(ns.pinBtn)
        end)

        it("exposes ApplyPinnedState on ns", function()
            assert.is_not_nil(ns.ApplyPinnedState)
        end)

        it("exposes ApplyUnpinnedState on ns", function()
            assert.is_not_nil(ns.ApplyUnpinnedState)
        end)

        it("default state is pinned (StatPriorityDB.pinned == true)", function()
            assert.is_true(StatPriorityDB.pinned)
        end)

        it("frame is not movable by default (pinned)", function()
            assert.is_false(ns.frame:IsMovable())
        end)

        it("ApplyUnpinnedState sets pinned=false and makes frame movable", function()
            ns.ApplyUnpinnedState()
            assert.is_false(StatPriorityDB.pinned)
            assert.is_true(ns.frame:IsMovable())
        end)

        it("ApplyPinnedState sets pinned=true and makes frame immovable", function()
            ns.ApplyUnpinnedState()  -- start unpinned
            ns.ApplyPinnedState()
            assert.is_true(StatPriorityDB.pinned)
            assert.is_false(ns.frame:IsMovable())
        end)

        it("OnDragStart does not call StartMoving when pinned", function()
            -- pinned by default, so drag should be blocked
            local onDragStart = ns.headerFrame:GetScript("OnDragStart")
            assert.is_not_nil(onDragStart)
            StatPriorityDB.pinned = true
            -- StartMoving on the frame mock would set _moving = true
            ns.frame._moving = false
            onDragStart()
            assert.is_false(ns.frame._moving)
        end)

        it("OnDragStart calls StartMoving when unpinned", function()
            StatPriorityDB.pinned = false
            local onDragStart = ns.headerFrame:GetScript("OnDragStart")
            ns.frame._moving = false
            onDragStart()
            assert.is_true(ns.frame._moving)
        end)

        it("pin button OnClick toggles from pinned to unpinned", function()
            assert.is_true(StatPriorityDB.pinned)
            local onClick = ns.pinBtn:GetScript("OnClick")
            assert.is_not_nil(onClick)
            onClick()
            assert.is_false(StatPriorityDB.pinned)
            assert.is_true(ns.frame:IsMovable())
        end)

        it("pin button OnClick toggles from unpinned back to pinned", function()
            local onClick = ns.pinBtn:GetScript("OnClick")
            onClick()  -- unpin
            assert.is_false(StatPriorityDB.pinned)
            onClick()  -- re-pin
            assert.is_true(StatPriorityDB.pinned)
            assert.is_false(ns.frame:IsMovable())
        end)

        it("OnDragStop saves position with relPoint key", function()
            StatPriorityDB.pinned = false
            local onDragStop = ns.headerFrame:GetScript("OnDragStop")
            onDragStop()
            assert.is_not_nil(StatPriorityDB.position)
            assert.is_not_nil(StatPriorityDB.position.relPoint)
        end)

        it("position restore supports legacy relativePoint key when unpinned", function()
            _G.StatPriorityDB = {
                pinned   = false,
                position = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 50, y = -50 }
            }
            _G.StatPriorityNS    = nil
            _G.StatPriorityFrame = nil
            dofile("StatPriority/StatPriority.lua")
            local ns2 = _G.StatPriorityNS
            ns2:OnLoad()
            -- Frame should have been anchored with TOPLEFT
            local points = ns2.frame._points
            local found = false
            for _, p in ipairs(points) do
                if p[1] == "TOPLEFT" then found = true; break end
            end
            assert.is_true(found)
        end)
    end)

    -- =========================================================================
    -- Test 12a: tracker anchor resolution — docks to visible content bottom
    -- =========================================================================
    describe("tracker anchor resolution (GetTrackerAnchor via ApplyPinnedState)", function()
        -- Helper: make a minimal visible tracker-module stub
        local function makeVisibleModule(name)
            return {
                _name    = name,
                _shown   = true,
                _points  = {},
                IsShown       = function(self) return self._shown end,
                GetName       = function(self) return self._name end,
                SetPoint      = function(self, ...) self._points[#self._points + 1] = { ... } end,
                ClearAllPoints = function(self) self._points = {} end,
            }
        end

        after_each(function()
            -- Clean up globals injected during tests
            _G.ObjectiveTrackerFrame     = nil
            _G.QuestObjectiveTracker     = nil
            _G.AchievementObjectiveTracker = nil
            _G.ScenarioObjectiveTracker  = nil
            _G.BonusObjectiveTracker     = nil
        end)

        it("ApplyPinnedState falls back to UIParent CENTER when no tracker is present", function()
            _G.ObjectiveTrackerFrame = nil
            ns.ApplyPinnedState()
            -- Should have a CENTER anchor on UIParent
            local found = false
            for _, p in ipairs(ns.frame._points) do
                if p[1] == "CENTER" then found = true; break end
            end
            assert.is_true(found)
        end)

        it("ApplyPinnedState anchors to last visible MODULES entry, not the container", function()
            local questMod   = makeVisibleModule("QuestObjectiveTracker")
            local achievMod  = makeVisibleModule("AchievementObjectiveTracker")
            achievMod._shown = false  -- achievement module hidden — quest is last visible

            _G.ObjectiveTrackerFrame = {
                _shown  = true,
                _points = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return "ObjectiveTrackerFrame" end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = { ... } end,
                ClearAllPoints = function(self) self._points = {} end,
                MODULES = { achievMod, questMod },  -- quest is last
            }

            ns.ApplyPinnedState()

            -- Frame should anchor to questMod (last visible MODULES entry), not ObjectiveTrackerFrame
            local foundAnchor = false
            for _, p in ipairs(ns.frame._points) do
                -- p is {point, relativeFrame, relativePoint, x, y}
                if p[2] == questMod then foundAnchor = true; break end
            end
            assert.is_true(foundAnchor, "expected anchor to last visible MODULES entry (questMod)")
        end)

        it("ApplyPinnedState skips hidden MODULES entries", function()
            local mod1 = makeVisibleModule("ModOne")
            local mod2 = makeVisibleModule("ModTwo")
            mod2._shown = false  -- mod2 hidden, mod1 is last visible

            _G.ObjectiveTrackerFrame = {
                _shown  = true,
                _points = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return "ObjectiveTrackerFrame" end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = { ... } end,
                ClearAllPoints = function(self) self._points = {} end,
                MODULES = { mod1, mod2 },
            }

            ns.ApplyPinnedState()

            local anchoredTo = nil
            for _, p in ipairs(ns.frame._points) do
                if p[2] == mod1 or p[2] == mod2 then anchoredTo = p[2]; break end
            end
            assert.equals(mod1, anchoredTo, "expected anchor to mod1 (last visible), not hidden mod2")
        end)

        it("ApplyPinnedState falls back to named module globals when MODULES is absent", function()
            local questMod = makeVisibleModule("QuestObjectiveTracker")
            _G.QuestObjectiveTracker = questMod

            _G.ObjectiveTrackerFrame = {
                _shown  = true,
                _points = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return "ObjectiveTrackerFrame" end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = { ... } end,
                ClearAllPoints = function(self) self._points = {} end,
                -- MODULES deliberately absent
            }

            ns.ApplyPinnedState()

            local foundAnchor = false
            for _, p in ipairs(ns.frame._points) do
                if p[2] == questMod then foundAnchor = true; break end
            end
            assert.is_true(foundAnchor, "expected anchor to QuestObjectiveTracker named global")
        end)

        it("ApplyPinnedState falls back to ObjectiveTrackerFrame when no module is visible", function()
            local hiddenMod = makeVisibleModule("HiddenMod")
            hiddenMod._shown = false

            local outerFrame = {
                _shown  = true,
                _points = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return "ObjectiveTrackerFrame" end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = { ... } end,
                ClearAllPoints = function(self) self._points = {} end,
                MODULES = { hiddenMod },
            }
            _G.ObjectiveTrackerFrame = outerFrame

            ns.ApplyPinnedState()

            local foundAnchor = false
            for _, p in ipairs(ns.frame._points) do
                if p[2] == outerFrame then foundAnchor = true; break end
            end
            assert.is_true(foundAnchor, "expected fallback anchor to ObjectiveTrackerFrame itself")
        end)
    end)

    -- =========================================================================
    -- Test 12: GetDisplaySpecID — spec override logic
    -- =========================================================================
    describe("GetDisplaySpecID", function()
        before_each(function()
            -- Reset loot spec mock to default (0 = follow current)
            _G._mockLootSpec = 0
            -- Ensure specOverride starts as default
            _G.StatPriorityDB.specOverride = "current"
        end)

        it("specOverride=nil returns current spec's specID", function()
            _G.StatPriorityDB.specOverride = nil
            -- Default mock: GetSpecialization()=4, GetSpecializationInfo(4)=105
            local specID = ns:GetDisplaySpecID()
            assert.equals(105, specID)
        end)

        it("specOverride='current' returns current spec's specID", function()
            _G.StatPriorityDB.specOverride = "current"
            local specID = ns:GetDisplaySpecID()
            assert.equals(105, specID)
        end)

        it("specOverride='loot' with non-zero loot spec returns loot specID", function()
            _G.StatPriorityDB.specOverride = "loot"
            _G._mockLootSpec = 251  -- Frost Death Knight
            local specID = ns:GetDisplaySpecID()
            assert.equals(251, specID)
        end)

        it("specOverride='loot' with loot spec=0 falls back to current spec", function()
            _G.StatPriorityDB.specOverride = "loot"
            _G._mockLootSpec = 0  -- "Current Spec" in WoW loot spec UI
            local specID = ns:GetDisplaySpecID()
            -- Should fall back to current spec (105 = Restoration Druid)
            assert.equals(105, specID)
        end)

        it("specOverride=integer specID returns that specID directly", function()
            _G.StatPriorityDB.specOverride = 250  -- Blood Death Knight
            local specID = ns:GetDisplaySpecID()
            assert.equals(250, specID)
        end)

        it("returns nil when GetSpecialization returns nil (no spec)", function()
            _G.StatPriorityDB.specOverride = "current"
            _G.GetSpecialization = function() return nil end
            local specID = ns:GetDisplaySpecID()
            assert.is_nil(specID)
        end)
    end)

    -- =========================================================================
    -- Test 13: UpdateStatPriority with spec overrides
    -- =========================================================================
    describe("UpdateStatPriority with spec override", function()
        before_each(function()
            _G._mockLootSpec = 0
            -- Reset to default (Restoration Druid)
            _G.GetSpecialization = function() return 4 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 4 then return 105, "Restoration Druid", "Heals allies.", "", "HEALER" end
                return nil
            end
        end)

        it("override='current' shows current spec (Restoration Druid)", function()
            _G.StatPriorityDB.specOverride = "current"
            ns:UpdateStatPriority()
            assert.equals("Restoration Druid", ns.headerTitle:GetText())
        end)

        it("override='loot' with loot specID=251 shows Frost Death Knight", function()
            _G.StatPriorityDB.specOverride = "loot"
            _G._mockLootSpec = 251
            ns:UpdateStatPriority()
            assert.equals("Frost Death Knight", ns.headerTitle:GetText())
        end)

        it("override='loot' with loot specID=0 falls back to current spec", function()
            _G.StatPriorityDB.specOverride = "loot"
            _G._mockLootSpec = 0
            ns:UpdateStatPriority()
            -- Falls back to current spec = Restoration Druid
            assert.equals("Restoration Druid", ns.headerTitle:GetText())
        end)

        it("override=integer specID=250 shows Blood Death Knight", function()
            _G.StatPriorityDB.specOverride = 250
            ns:UpdateStatPriority()
            assert.equals("Blood Death Knight", ns.headerTitle:GetText())
        end)

        it("override='loot' with loot specID=251 shows _differs content for Frost DK", function()
            _G.StatPriorityDB.specOverride = "loot"
            _G._mockLootSpec = 251
            ns:UpdateStatPriority()
            -- Frost DK has _differs=true, should show per-source labels
            assert.is_true(ns.wowheadLabel:IsShown())
            assert.is_true(ns.icyveinsLabel:IsShown())
            assert.is_true(ns.methodLabel:IsShown())
        end)
    end)

    -- =========================================================================
    -- Test 14: specOverride persistence and initialization
    -- =========================================================================
    describe("specOverride SavedVariables", function()
        it("specOverride is initialized to 'current' by OnLoad when nil", function()
            _G.StatPriorityDB = {}  -- no specOverride set
            _G.StatPriorityNS = nil
            _G.StatPriorityFrame = nil
            dofile("StatPriority/StatPriority.lua")
            local ns2 = _G.StatPriorityNS
            ns2:OnLoad()
            assert.equals("current", _G.StatPriorityDB.specOverride)
        end)

        it("specOverride value is preserved across OnLoad when already set", function()
            _G.StatPriorityDB = { specOverride = "loot" }
            _G.StatPriorityNS = nil
            _G.StatPriorityFrame = nil
            dofile("StatPriority/StatPriority.lua")
            local ns2 = _G.StatPriorityNS
            ns2:OnLoad()
            assert.equals("loot", _G.StatPriorityDB.specOverride)
        end)

        it("stale integer specOverride not matching current class is reset to 'current'", function()
            -- 99998 is not a valid spec in any test mock
            _G.StatPriorityDB = { specOverride = 99998 }
            _G.GetNumSpecializations = function() return 4 end
            _G.GetSpecializationInfo = function(i)
                local ids = { 105, 102, 103, 104 }
                return ids[i], "Spec " .. i, "", "", "DAMAGER"
            end
            _G.StatPriorityNS = nil
            _G.StatPriorityFrame = nil
            dofile("StatPriority/StatPriority.lua")
            local ns2 = _G.StatPriorityNS
            ns2:OnLoad()
            assert.equals("current", _G.StatPriorityDB.specOverride)
        end)
    end)

    -- =========================================================================
    -- Test 15: PLAYER_LOOT_SPEC_UPDATED event
    -- =========================================================================
    describe("PLAYER_LOOT_SPEC_UPDATED event", function()
        it("specEventFrame is registered for PLAYER_LOOT_SPEC_UPDATED", function()
            assert.is_not_nil(ns.specEventFrame)
            assert.is_true(ns.specEventFrame:IsEventRegistered("PLAYER_LOOT_SPEC_UPDATED"))
        end)

        it("fires UpdateStatPriority when override='loot'", function()
            _G.StatPriorityDB.specOverride = "loot"
            _G._mockLootSpec = 251  -- Frost DK
            local onEvent = ns.specEventFrame:GetScript("OnEvent")
            assert.is_not_nil(onEvent)
            onEvent(ns.specEventFrame, "PLAYER_LOOT_SPEC_UPDATED")
            assert.equals("Frost Death Knight", ns.headerTitle:GetText())
        end)

        it("does not change display when override='current' on PLAYER_LOOT_SPEC_UPDATED", function()
            _G.StatPriorityDB.specOverride = "current"
            -- Start with Restoration Druid displayed
            ns:UpdateStatPriority()
            assert.equals("Restoration Druid", ns.headerTitle:GetText())
            -- Fire loot spec update — should NOT update (override is not "loot")
            local onEvent = ns.specEventFrame:GetScript("OnEvent")
            onEvent(ns.specEventFrame, "PLAYER_LOOT_SPEC_UPDATED")
            -- Header should still show Restoration Druid (no update happened)
            assert.equals("Restoration Druid", ns.headerTitle:GetText())
        end)
    end)

    -- =========================================================================
    -- Bonus: Data table completeness (Phase 1 + Phase 2)
    -- =========================================================================
    describe("StatPriorityData", function()
        it("contains at least 39 spec entries", function()
            local count = 0
            for _ in pairs(StatPriorityData) do count = count + 1 end
            assert.is_true(count >= 39)
        end)

        it("every entry has a specName string", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.is_not_nil(entry.specName,
                    "specID " .. specID .. " missing specName")
                assert.equals("string", type(entry.specName))
            end
        end)

        it("every entry has at least 4 stats", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.is_not_nil(entry.stats,
                    "specID " .. specID .. " missing stats")
                assert.is_true(#entry.stats >= 4,
                    "specID " .. specID .. " has fewer than 4 stats")
            end
        end)

        it("every entry has a _source field", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.is_not_nil(entry._source,
                    "specID " .. specID .. " missing _source")
            end
        end)

        it("every entry has _source = 'wowhead,icyveins,method'", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.equals("wowhead,icyveins,method", entry._source,
                    "specID " .. specID .. " has unexpected _source: " .. tostring(entry._source))
            end
        end)

        it("every entry has wowhead array with at least 4 stats", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.is_not_nil(entry.wowhead,
                    "specID " .. specID .. " missing wowhead array")
                assert.is_true(#entry.wowhead >= 4,
                    "specID " .. specID .. " wowhead has fewer than 4 stats")
            end
        end)

        it("every entry has icyveins array with at least 4 stats", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.is_not_nil(entry.icyveins,
                    "specID " .. specID .. " missing icyveins array")
                assert.is_true(#entry.icyveins >= 4,
                    "specID " .. specID .. " icyveins has fewer than 4 stats")
            end
        end)

        it("every entry has method array with at least 4 stats", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.is_not_nil(entry.method,
                    "specID " .. specID .. " missing method array")
                assert.is_true(#entry.method >= 4,
                    "specID " .. specID .. " method has fewer than 4 stats")
            end
        end)

        it("every entry has urls table with all 3 source URLs", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.is_not_nil(entry.urls,
                    "specID " .. specID .. " missing urls table")
                assert.is_not_nil(entry.urls.wowhead,
                    "specID " .. specID .. " missing urls.wowhead")
                assert.is_not_nil(entry.urls.icyveins,
                    "specID " .. specID .. " missing urls.icyveins")
                assert.is_not_nil(entry.urls.method,
                    "specID " .. specID .. " missing urls.method")
            end
        end)

        it("_differs is a boolean for every entry", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.equals("boolean", type(entry._differs),
                    "specID " .. specID .. " _differs is not a boolean")
            end
        end)

        it("_differs is consistent with actual array comparison", function()
            -- Helper to check if two arrays match
            local function arrEq(a, b)
                if #a ~= #b then return false end
                for i = 1, #a do if a[i] ~= b[i] then return false end end
                return true
            end
            for specID, entry in pairs(StatPriorityData) do
                local allSame = arrEq(entry.wowhead, entry.icyveins)
                                and arrEq(entry.wowhead, entry.method)
                                and arrEq(entry.icyveins, entry.method)
                if allSame then
                    assert.is_false(entry._differs,
                        "specID " .. specID .. " should have _differs = false but is true")
                else
                    assert.is_true(entry._differs,
                        "specID " .. specID .. " should have _differs = true but is false")
                end
            end
        end)

        it("stats field matches wowhead (wowhead is canonical default)", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.equals(#entry.wowhead, #entry.stats,
                    "specID " .. specID .. " stats length does not match wowhead length")
                for i = 1, #entry.wowhead do
                    assert.equals(entry.wowhead[i], entry.stats[i],
                        "specID " .. specID .. " stats[" .. i .. "] != wowhead[" .. i .. "]")
                end
            end
        end)

        it("Restoration Druid (105) has _differs = false", function()
            local data = StatPriorityData[105]
            assert.is_not_nil(data)
            assert.is_false(data._differs)
        end)

        it("Frost Death Knight (251) has _differs = true", function()
            local data = StatPriorityData[251]
            assert.is_not_nil(data)
            assert.is_true(data._differs)
        end)
    end)

    -- =========================================================================
    -- Test 16: Multi-addon anchor chain — SP docks below DCS when DCS visible
    -- =========================================================================
    describe("multi-addon anchor chain (SP below DCS)", function()
        local function makeDCSFrame(shown)
            return {
                _name   = "DelveCompanionStatsFrame",
                _shown  = shown,
                _points = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return self._name end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = {...} end,
                ClearAllPoints = function(self) self._points = {} end,
            }
        end

        after_each(function()
            _G.DelveCompanionStatsFrame = nil
            _G.ObjectiveTrackerFrame    = nil
        end)

        it("ApplyPinnedState anchors SP below DelveCompanionStatsFrame when DCS is visible", function()
            local dcsFrame = makeDCSFrame(true)
            _G.DelveCompanionStatsFrame = dcsFrame

            ns.ApplyPinnedState()

            local anchoredToDCS = false
            for _, p in ipairs(ns.frame._points) do
                if p[2] == dcsFrame then anchoredToDCS = true; break end
            end
            assert.is_true(anchoredToDCS, "SP should anchor below DCS when DCS is visible")
        end)

        it("ApplyPinnedState does NOT anchor below DCS when DCS is hidden", function()
            local dcsFrame = makeDCSFrame(false)
            _G.DelveCompanionStatsFrame = dcsFrame
            -- No ObjectiveTrackerFrame either — should fall back to UIParent CENTER
            _G.ObjectiveTrackerFrame = nil

            ns.ApplyPinnedState()

            local anchoredToDCS = false
            for _, p in ipairs(ns.frame._points) do
                if p[2] == dcsFrame then anchoredToDCS = true; break end
            end
            assert.is_false(anchoredToDCS, "SP should NOT anchor below hidden DCS")
        end)

        it("ApplyPinnedState falls back to tracker modules when DCS is absent", function()
            _G.DelveCompanionStatsFrame = nil

            local questMod = {
                _shown   = true,
                _points  = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return "QuestObjectiveTracker" end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = {...} end,
                ClearAllPoints = function(self) self._points = {} end,
            }
            _G.ObjectiveTrackerFrame = {
                _shown  = true,
                _points = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return "ObjectiveTrackerFrame" end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = {...} end,
                ClearAllPoints = function(self) self._points = {} end,
                MODULES        = { questMod },
            }

            ns.ApplyPinnedState()

            local anchoredToMod = false
            for _, p in ipairs(ns.frame._points) do
                if p[2] == questMod then anchoredToMod = true; break end
            end
            assert.is_true(anchoredToMod, "SP should anchor to tracker module when DCS is absent")
        end)
    end)

    -- =========================================================================
    -- Test 17: Icon sizing — lock and collapse buttons are at least 26px
    -- =========================================================================
    describe("icon sizing", function()
        it("pin button is at least 26x26", function()
            assert.is_not_nil(ns.pinBtn)
            local w, h = ns.pinBtn:GetSize()
            assert.is_true(w >= 26, "pin button width should be >= 26, got " .. tostring(w))
            assert.is_true(h >= 26, "pin button height should be >= 26, got " .. tostring(h))
        end)

        it("collapse button is at least 26 wide", function()
            assert.is_not_nil(ns.collapseBtn)
            local w, _ = ns.collapseBtn:GetSize()
            assert.is_true(w >= 26, "collapse button width should be >= 26, got " .. tostring(w))
        end)
    end)
end)
