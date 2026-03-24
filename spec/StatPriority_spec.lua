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

        it("restores saved position on load", function()
            -- Set a saved position and reload
            _G.StatPriorityDB = {
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
end)
