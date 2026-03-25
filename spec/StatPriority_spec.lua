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
        -- Restoration Druid has _differs = false (single archon source)
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

        it("circle display shows Int and Haste for Restoration Druid (unified)", function()
            ns:UpdateStatPriority()
            -- Circles replace the flat text label in unified mode
            assert.is_not_nil(ns.statCircles)
            local found_int, found_haste = false, false
            for _, circ in ipairs(ns.statCircles) do
                if circ.frame:IsShown() then
                    local name = circ.nameFS:GetText()
                    if name == "Int"   then found_int   = true end
                    if name == "Haste" then found_haste = true end
                end
            end
            assert.is_true(found_int,   "Expected circle for 'Int'")
            assert.is_true(found_haste, "Expected circle for 'Haste'")
        end)

        it("shows correct stat count for Restoration Druid (5 stats)", function()
            ns:UpdateStatPriority()
            local data = StatPriorityData[105]
            assert.equals(5, #data.stats)
            assert.equals("Int",  data.stats[1])
            assert.equals("Haste", data.stats[2])
            assert.equals("Mast",  data.stats[3])
            assert.equals("Crit",  data.stats[4])
            assert.equals("Vers",  data.stats[5])
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
    describe("content label format (circle display)", function()
        it("connector FontStrings exist and show '>' between different-priority stats", function()
            ns:UpdateStatPriority()
            assert.is_not_nil(ns.statConnectors)
            -- Restoration Druid: 5 different-priority stats → 4 '>' connectors
            local gt_count = 0
            for _, conn in ipairs(ns.statConnectors) do
                if conn:IsShown() and conn:GetText() == ">" then
                    gt_count = gt_count + 1
                end
            end
            assert.is_true(gt_count >= 1, "Expected at least one '>' connector")
        end)

        it("first circle (Int) precedes connector in rendered order (index 1 < connector 1)", function()
            ns:UpdateStatPriority()
            assert.is_not_nil(ns.statCircles)
            assert.is_not_nil(ns.statConnectors)
            -- Circle 1 should have Int; connector 1 should be '>'
            local circ1 = ns.statCircles[1]
            assert.is_true(circ1.frame:IsShown())
            assert.equals("Int", circ1.nameFS:GetText())
            assert.is_true(ns.statConnectors[1]:IsShown())
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
        it("statsLabel is hidden (circles used instead) when _differs is false", function()
            ns:UpdateStatPriority()
            assert.is_false(ns.statsLabel:IsShown())
        end)

        it("circles are shown when _differs is false", function()
            ns:UpdateStatPriority()
            assert.is_not_nil(ns.statCircles)
            local shown_count = 0
            for _, circ in ipairs(ns.statCircles) do
                if circ.frame:IsShown() then shown_count = shown_count + 1 end
            end
            assert.is_true(shown_count > 0, "Expected at least one circle shown")
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
    -- Test 9: Unified display for Frost DK (single archon source, _differs always false)
    -- =========================================================================
    describe("unified display for Frost DK (archon single source)", function()
        -- Switch to Frost Death Knight (specID 251)
        before_each(function()
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 1 then
                    return 251, "Frost Death Knight", "", "", "DAMAGER"
                end
                return nil
            end
        end)

        it("Frost Death Knight data has _differs = false", function()
            local data = StatPriorityData[251]
            assert.is_not_nil(data)
            assert.is_false(data._differs)
        end)

        it("statsLabel is hidden for Frost DK (circles used instead)", function()
            ns:UpdateStatPriority()
            assert.is_false(ns.statsLabel:IsShown())
        end)

        it("circles are shown for Frost DK (unified display)", function()
            ns:UpdateStatPriority()
            local shown_count = 0
            for _, circ in ipairs(ns.statCircles) do
                if circ.frame:IsShown() then shown_count = shown_count + 1 end
            end
            assert.is_true(shown_count > 0, "Expected at least one circle shown for Frost DK")
        end)

        it("source labels are hidden for Frost DK (unified display)", function()
            ns:UpdateStatPriority()
            assert.is_false(ns.wowheadLabel:IsShown())
            assert.is_false(ns.icyveinsLabel:IsShown())
            assert.is_false(ns.methodLabel:IsShown())
        end)

        it("URL buttons are hidden for Frost DK (unified display)", function()
            ns:UpdateStatPriority()
            assert.is_false(ns.wowheadUrlBtn:IsShown())
            assert.is_false(ns.icyveinsUrlBtn:IsShown())
            assert.is_false(ns.methodUrlBtn:IsShown())
        end)

        it("first circle shows Frost DK's first stat priority", function()
            ns:UpdateStatPriority()
            local data = StatPriorityData[251]
            local firstStat = data.stats[1]
            assert.is_not_nil(firstStat)
            local circ1 = ns.statCircles[1]
            assert.is_true(circ1.frame:IsShown())
            assert.equals(firstStat, circ1.nameFS:GetText())
        end)
    end)

    -- =========================================================================
    -- Test 9b: Equal-priority stats use "=" separator (Retribution Paladin specID 70)
    -- =========================================================================
    describe("equal-priority stat display", function()
        before_each(function()
            _G.GetSpecialization = function() return 2 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 2 then
                    return 70, "Retribution Paladin", "", "", "DAMAGER"
                end
                return nil
            end
        end)

        it("Retribution Paladin data has a sub-array for equal-priority stats", function()
            local data = StatPriorityData[70]
            assert.is_not_nil(data)
            local found = false
            for _, entry in ipairs(data.stats) do
                if type(entry) == "table" then found = true; break end
            end
            assert.is_true(found)
        end)

        it("Retribution Paladin has '=' connector for equal-priority stats in circles", function()
            ns:UpdateStatPriority()
            local found_eq = false
            for _, conn in ipairs(ns.statConnectors) do
                if conn:IsShown() and conn:GetText() == "=" then
                    found_eq = true; break
                end
            end
            assert.is_true(found_eq, "Expected at least one '=' connector for Ret Pala equal-priority group")
        end)

        it("Retribution Paladin has '>' connector between priority tiers in circles", function()
            ns:UpdateStatPriority()
            local found_gt = false
            for _, conn in ipairs(ns.statConnectors) do
                if conn:IsShown() and conn:GetText() == ">" then
                    found_gt = true; break
                end
            end
            assert.is_true(found_gt, "Expected at least one '>' connector for Ret Pala priority tiers")
        end)

        it("Retribution Paladin circles include both Haste and Crit", function()
            ns:UpdateStatPriority()
            local found_haste, found_crit = false, false
            for _, circ in ipairs(ns.statCircles) do
                if circ.frame:IsShown() then
                    local name = circ.nameFS:GetText()
                    if name == "Haste" then found_haste = true end
                    if name == "Crit"  then found_crit  = true end
                end
            end
            assert.is_true(found_haste, "Expected circle for 'Haste'")
            assert.is_true(found_crit,  "Expected circle for 'Crit'")
        end)

        it("Retribution Paladin first circle is Str (before equal-priority group)", function()
            ns:UpdateStatPriority()
            -- First circle should be Str (highest priority for Ret Pala)
            local data = StatPriorityData[70]
            local firstEntry = data.stats[1]
            local expectedFirst = type(firstEntry) == "table" and firstEntry[1] or firstEntry
            assert.equals(expectedFirst, ns.statCircles[1].nameFS:GetText())
        end)

        it("Retribution Paladin _differs is false (single archon source)", function()
            local data = StatPriorityData[70]
            assert.is_false(data._differs)
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

        it("URL button OnClick shows popup with archon URL for Frost DK", function()
            -- Switch to Frost DK
            _G.GetSpecialization = function() return 1 end
            _G.GetSpecializationInfo = function(specIndex)
                if specIndex == 1 then return 251, "Frost Death Knight", "", "", "DAMAGER" end
                return nil
            end
            ns:UpdateStatPriority()

            -- Click the wowhead URL button (alias for archon)
            local onClick = ns.wowheadUrlBtn:GetScript("OnClick")
            assert.is_not_nil(onClick)
            onClick(ns.wowheadUrlBtn)

            assert.is_true(ns.urlPopup:IsShown())
            local url = ns.urlPopupEditBox:GetText()
            assert.is_truthy(url:find("archon.gg", 1, true))
            assert.is_truthy(url:find("death-knight", 1, true))
        end)

        it("all URL aliases point to archon.gg for Frost DK", function()
            local data = StatPriorityData[251]
            assert.is_truthy(data.urls.archon:find("archon.gg", 1, true))
            assert.equals(data.urls.archon, data.urls.wowhead)
            assert.equals(data.urls.archon, data.urls.icyveins)
            assert.equals(data.urls.archon, data.urls.method)
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
    -- Test 12a: tracker anchor resolution — docks below ObjectiveTrackerFrame
    -- =========================================================================
    -- GetTrackerAnchor anchors to ObjectiveTrackerFrame (the outer container)
    -- rather than individual module sub-frames.  The outer container auto-sizes
    -- its height to fit visible content, so its BOTTOM is always the actual
    -- rendered content bottom.  Individual module frames (QuestObjectiveTracker
    -- etc.) carry pre-allocated excess height that does not shrink as quests
    -- complete or are removed, which caused SP to overlap visible quest content.
    -- =========================================================================
    describe("tracker anchor resolution (GetTrackerAnchor via ApplyPinnedState)", function()
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

        it("ApplyPinnedState anchors to ObjectiveTrackerFrame (outer container), not module sub-frames", function()
            -- The outer frame auto-sizes to content; its BOTTOM is the true content bottom.
            -- Anchoring to sub-frames (QuestObjectiveTracker etc.) causes overlap because
            -- those frames have excess pre-allocated height that doesn't shrink with content.
            local outerFrame = {
                _shown  = true,
                _points = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return "ObjectiveTrackerFrame" end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = { ... } end,
                ClearAllPoints = function(self) self._points = {} end,
            }
            _G.ObjectiveTrackerFrame = outerFrame

            ns.ApplyPinnedState()

            local foundAnchor = false
            for _, p in ipairs(ns.frame._points) do
                if p[2] == outerFrame then foundAnchor = true; break end
            end
            assert.is_true(foundAnchor, "expected anchor to ObjectiveTrackerFrame outer container")
        end)

        it("ApplyPinnedState uses ObjectiveTrackerFrame even when module sub-frames are present", function()
            -- Populate named module globals — SP must still anchor to the outer frame.
            _G.QuestObjectiveTracker = {
                _shown = true,
                IsShown = function(self) return self._shown end,
                GetName = function(self) return "QuestObjectiveTracker" end,
            }
            local outerFrame = {
                _shown  = true,
                _points = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return "ObjectiveTrackerFrame" end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = { ... } end,
                ClearAllPoints = function(self) self._points = {} end,
            }
            _G.ObjectiveTrackerFrame = outerFrame

            ns.ApplyPinnedState()

            local anchoredToOuter = false
            local anchoredToModule = false
            for _, p in ipairs(ns.frame._points) do
                if p[2] == outerFrame then anchoredToOuter = true end
                if p[2] == _G.QuestObjectiveTracker then anchoredToModule = true end
            end
            assert.is_true(anchoredToOuter,  "SP must anchor to ObjectiveTrackerFrame outer container")
            assert.is_false(anchoredToModule, "SP must NOT anchor to QuestObjectiveTracker sub-frame")
        end)

        it("ApplyPinnedState falls back to UIParent CENTER when ObjectiveTrackerFrame is hidden", function()
            _G.ObjectiveTrackerFrame = {
                _shown  = false,
                _points = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return "ObjectiveTrackerFrame" end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = { ... } end,
                ClearAllPoints = function(self) self._points = {} end,
            }

            ns.ApplyPinnedState()

            local found = false
            for _, p in ipairs(ns.frame._points) do
                if p[1] == "CENTER" then found = true; break end
            end
            assert.is_true(found, "expected CENTER fallback when ObjectiveTrackerFrame is hidden")
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

        it("override='loot' with loot specID=251 shows circle display for Frost DK", function()
            _G.StatPriorityDB.specOverride = "loot"
            _G._mockLootSpec = 251
            ns:UpdateStatPriority()
            -- Frost DK has _differs=false (single archon source), should show circles
            assert.is_false(ns.statsLabel:IsShown())
            assert.is_false(ns.wowheadLabel:IsShown())
            assert.is_false(ns.icyveinsLabel:IsShown())
            assert.is_false(ns.methodLabel:IsShown())
            -- At least one circle should be shown
            local shown_count = 0
            for _, circ in ipairs(ns.statCircles) do
                if circ.frame:IsShown() then shown_count = shown_count + 1 end
            end
            assert.is_true(shown_count > 0, "Expected circles shown for Frost DK via loot spec override")
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

        it("every entry has _source = 'archon'", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.equals("archon", entry._source,
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

        it("every entry has urls table with archon URL (plus backward-compat aliases)", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.is_not_nil(entry.urls,
                    "specID " .. specID .. " missing urls table")
                assert.is_not_nil(entry.urls.archon,
                    "specID " .. specID .. " missing urls.archon")
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
            -- Helper to compare entries that may be strings or sub-arrays (tables).
            local function entryEq(x, y)
                if type(x) == "table" and type(y) == "table" then
                    if #x ~= #y then return false end
                    for i = 1, #x do if x[i] ~= y[i] then return false end end
                    return true
                end
                return x == y
            end
            local function arrEq(a, b)
                if #a ~= #b then return false end
                for i = 1, #a do if not entryEq(a[i], b[i]) then return false end end
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

        it("stats field matches archon (archon is canonical default)", function()
            for specID, entry in pairs(StatPriorityData) do
                assert.equals(#entry.archon, #entry.stats,
                    "specID " .. specID .. " stats length does not match archon length")
                for i = 1, #entry.archon do
                    assert.equals(entry.archon[i], entry.stats[i],
                        "specID " .. specID .. " stats[" .. i .. "] != archon[" .. i .. "]")
                end
            end
        end)

        it("Restoration Druid (105) has _differs = false", function()
            local data = StatPriorityData[105]
            assert.is_not_nil(data)
            assert.is_false(data._differs)
        end)

        it("Frost Death Knight (251) has _differs = false (single archon source)", function()
            local data = StatPriorityData[251]
            assert.is_not_nil(data)
            assert.is_false(data._differs)
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

        it("ApplyPinnedState falls back to ObjectiveTrackerFrame when DCS is absent", function()
            _G.DelveCompanionStatsFrame = nil

            local outerFrame = {
                _shown  = true,
                _points = {},
                IsShown        = function(self) return self._shown end,
                GetName        = function(self) return "ObjectiveTrackerFrame" end,
                SetPoint       = function(self, ...) self._points[#self._points + 1] = {...} end,
                ClearAllPoints = function(self) self._points = {} end,
            }
            _G.ObjectiveTrackerFrame = outerFrame

            ns.ApplyPinnedState()

            local anchoredToOuter = false
            for _, p in ipairs(ns.frame._points) do
                if p[2] == outerFrame then anchoredToOuter = true; break end
            end
            assert.is_true(anchoredToOuter, "SP should anchor to ObjectiveTrackerFrame when DCS is absent")
        end)
    end)

    -- =========================================================================
    -- Test 17b: Circle display pool creation
    -- =========================================================================
    describe("circle stat display pool", function()
        it("creates 7 circle frames on OnLoad", function()
            assert.is_not_nil(ns.statCircles)
            assert.equals(7, #ns.statCircles)
        end)

        it("creates 6 connector FontStrings on OnLoad", function()
            assert.is_not_nil(ns.statConnectors)
            assert.equals(6, #ns.statConnectors)
        end)

        it("each circle frame has nameFS and valueFS font strings", function()
            for i, circ in ipairs(ns.statCircles) do
                assert.is_not_nil(circ.nameFS, "circle " .. i .. " missing nameFS")
                assert.is_not_nil(circ.valueFS, "circle " .. i .. " missing valueFS")
                assert.is_not_nil(circ.frame,   "circle " .. i .. " missing frame")
            end
        end)

        it("circles are hidden by default before UpdateStatPriority", function()
            -- After OnLoad+UpdateStatPriority ran in before_each, reset to check raw state
            -- We just verify circles hidden when no data (nil spec)
            _G.GetSpecialization = function() return nil end
            ns:UpdateStatPriority()
            local shown_count = 0
            for _, circ in ipairs(ns.statCircles) do
                if circ.frame:IsShown() then shown_count = shown_count + 1 end
            end
            assert.equals(0, shown_count)
        end)

        it("Restoration Druid (5 stats) shows exactly 5 circles", function()
            -- Restore Resto Druid spec
            _G.GetSpecialization = function() return 4 end
            _G.GetSpecializationInfo = function(i)
                if i == 4 then return 105, "Restoration Druid", "", "", "HEALER" end
            end
            ns:UpdateStatPriority()
            local shown_count = 0
            for _, circ in ipairs(ns.statCircles) do
                if circ.frame:IsShown() then shown_count = shown_count + 1 end
            end
            assert.equals(5, shown_count)
        end)

        it("circles show stat abbreviations in priority order for Resto Druid", function()
            _G.GetSpecialization = function() return 4 end
            _G.GetSpecializationInfo = function(i)
                if i == 4 then return 105, "Restoration Druid", "", "", "HEALER" end
            end
            ns:UpdateStatPriority()
            local data = StatPriorityData[105]
            assert.equals("Int",   ns.statCircles[1].nameFS:GetText())
            assert.equals("Haste", ns.statCircles[2].nameFS:GetText())
            assert.equals("Mast",  ns.statCircles[3].nameFS:GetText())
            assert.equals("Crit",  ns.statCircles[4].nameFS:GetText())
            assert.equals("Vers",  ns.statCircles[5].nameFS:GetText())
        end)

        it("circles show stat values (non-empty) for Resto Druid", function()
            _G.GetSpecialization = function() return 4 end
            _G.GetSpecializationInfo = function(i)
                if i == 4 then return 105, "Restoration Druid", "", "", "HEALER" end
            end
            ns:UpdateStatPriority()
            for i = 1, 5 do
                local val = ns.statCircles[i].valueFS:GetText()
                assert.is_not_nil(val, "circle " .. i .. " valueFS text is nil")
                assert.is_true(val ~= "", "circle " .. i .. " valueFS text is empty")
            end
        end)

        it("registers for UNIT_STATS and COMBAT_RATING_UPDATE events", function()
            assert.is_not_nil(ns.statEventFrame)
            assert.is_true(ns.statEventFrame:IsEventRegistered("UNIT_STATS"))
            assert.is_true(ns.statEventFrame:IsEventRegistered("COMBAT_RATING_UPDATE"))
        end)

        it("UNIT_STATS event refreshes circle values without rebuilding layout", function()
            _G.GetSpecialization = function() return 4 end
            _G.GetSpecializationInfo = function(i)
                if i == 4 then return 105, "Restoration Druid", "", "", "HEALER" end
            end
            ns:UpdateStatPriority()
            -- Change mock haste, fire event
            _G._mockHaste = 99.9
            local onEvent = ns.statEventFrame:GetScript("OnEvent")
            onEvent(ns.statEventFrame, "UNIT_STATS", "player")
            -- Circle 2 is Haste
            local hasteVal = ns.statCircles[2].valueFS:GetText()
            assert.equals("99.9%", hasteVal)
            _G._mockHaste = 28.5  -- restore
        end)

        it("UNIT_STATS event for non-player unit is ignored", function()
            _G.GetSpecialization = function() return 4 end
            _G.GetSpecializationInfo = function(i)
                if i == 4 then return 105, "Restoration Druid", "", "", "HEALER" end
            end
            ns:UpdateStatPriority()
            local initialVal = ns.statCircles[2].valueFS:GetText()
            _G._mockHaste = 55.0
            local onEvent = ns.statEventFrame:GetScript("OnEvent")
            onEvent(ns.statEventFrame, "UNIT_STATS", "target")  -- non-player
            local afterVal = ns.statCircles[2].valueFS:GetText()
            assert.equals(initialVal, afterVal, "Value should not change for non-player UNIT_STATS")
            _G._mockHaste = 28.5  -- restore
        end)
    end)

    -- =========================================================================
    -- Test 17c: GetStatValue helper
    -- =========================================================================
    describe("GetStatValue helper", function()
        it("returns comma-formatted integer for Int", function()
            _G._mockUnitStats[4] = 12450
            local val = _G.StatPriorityGetStatValue("Int")
            assert.equals("12,450", val)
        end)

        it("returns comma-formatted integer for Str", function()
            _G._mockUnitStats[1] = 1200
            local val = _G.StatPriorityGetStatValue("Str")
            assert.equals("1,200", val)
        end)

        it("returns comma-formatted integer for Agil", function()
            _G._mockUnitStats[2] = 800
            local val = _G.StatPriorityGetStatValue("Agil")
            assert.equals("800", val)
        end)

        it("returns percentage string for Haste", function()
            _G._mockHaste = 28.5
            local val = _G.StatPriorityGetStatValue("Haste")
            assert.equals("28.5%", val)
        end)

        it("returns percentage string for Crit", function()
            _G._mockCrit = 15.2
            local val = _G.StatPriorityGetStatValue("Crit")
            assert.equals("15.2%", val)
        end)

        it("returns percentage string for Mast", function()
            _G._mockMastery = 42.3
            local val = _G.StatPriorityGetStatValue("Mast")
            assert.equals("42.3%", val)
        end)

        it("returns percentage string for Vers", function()
            _G._mockVers = 8.7
            local val = _G.StatPriorityGetStatValue("Vers")
            assert.equals("8.7%", val)
        end)

        it("returns '?' for unknown stat abbreviation", function()
            local val = _G.StatPriorityGetStatValue("Unknown")
            assert.equals("?", val)
        end)

        it("returns '?' when UnitStat API is unavailable", function()
            local old = _G.UnitStat
            _G.UnitStat = nil
            local val = _G.StatPriorityGetStatValue("Int")
            _G.UnitStat = old
            assert.equals("?", val)
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
