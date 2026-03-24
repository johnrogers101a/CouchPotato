-- spec/StatPriority_spec.lua
-- Busted tests for StatPriority addon

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
    end)

    -- =========================================================================
    -- Test 2: UpdateStatPriority shows correct data for a known specID
    -- =========================================================================
    describe("UpdateStatPriority", function()
        it("sets header title to spec name for known specID", function()
            ns:UpdateStatPriority()
            assert.equals("Restoration Druid", ns.headerTitle:GetText())
        end)

        it("sets stats label with > separators for known specID", function()
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
    -- Bonus: Data table completeness
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
    end)
end)
