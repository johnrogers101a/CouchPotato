-- spec/DelveCompanionStats_spec.lua
-- Tests for DelveCompanionStats: dynamic companion name/level resolution via WoW API

require("spec/wow_mock")

describe("DelveCompanionStats", function()
    local ns

    before_each(function()
        -- Reset global state
        _G.DelveCompanionStatsDB = {}
        _G.DelveCompanionStatsNS = nil
        _G.DelveCompanionStatsFrame = nil

        -- Reset API mocks to default (no companion active)
        C_DelvesUI.GetFactionForCompanion = function() return nil end
        C_Reputation.GetFactionDataByID = function() return nil end
        C_GossipInfo.GetFriendshipReputation = function() return nil end
        C_GossipInfo.GetFriendshipReputationRanks = function() return nil end

        -- Load the addon (varargs will be empty, test fallback creates ns = {})
        dofile("DelveCompanionStats/DelveCompanionStats.lua")
        ns = _G.DelveCompanionStatsNS

        -- Directly initialize the addon (bypasses the ADDON_LOADED event)
        ns:OnLoad()
    end)

    describe("hardcoded lookup table removed", function()
        it("does not expose a companionNames table", function()
            assert.is_nil(ns.companionNames)
        end)
    end)

    describe("UpdateCompanionData", function()
        it("shows No Companion when GetFactionForCompanion returns nil", function()
            C_DelvesUI.GetFactionForCompanion = function() return nil end

            ns:UpdateCompanionData()

            assert.equals("No Companion", ns.nameLabel._text)
            assert.equals("", ns.levelLabel._text)
        end)

        it("shows No Companion when GetFactionForCompanion returns 0", function()
            C_DelvesUI.GetFactionForCompanion = function() return 0 end

            ns:UpdateCompanionData()

            assert.equals("No Companion", ns.nameLabel._text)
            assert.equals("", ns.levelLabel._text)
        end)

        it("resolves companion name from GetFactionDataByID", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function(factionID)
                if factionID == 2744 then return { name = "Valeera Sanguinar" } end
                return nil
            end

            ns:UpdateCompanionData()

            assert.equals("Valeera Sanguinar", ns.nameLabel._text)
        end)

        it("shows Unknown when GetFactionDataByID returns nil", function()
            C_DelvesUI.GetFactionForCompanion = function() return 9999 end
            C_Reputation.GetFactionDataByID = function() return nil end

            ns:UpdateCompanionData()

            assert.equals("Unknown", ns.nameLabel._text)
        end)

        it("extracts level from friendshipRank", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function() return { friendshipRank = 3 } end

            ns:UpdateCompanionData()

            assert.equals("Valeera Sanguinar", ns.nameLabel._text)
            assert.equals("Level 3", ns.levelLabel._text)
        end)

        it("extracts level from reaction field when friendshipRank is absent", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Brann Bronzebeard" } end
            C_GossipInfo.GetFriendshipReputation = function() return { reaction = 5 } end

            ns:UpdateCompanionData()

            assert.equals("Level 5", ns.levelLabel._text)
        end)

        it("shows empty level when GetFriendshipReputation returns nil", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function() return nil end

            ns:UpdateCompanionData()

            assert.equals("", ns.levelLabel._text)
        end)

        it("persists resolved name and level to SavedVariables", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function() return { friendshipRank = 3 } end

            ns:UpdateCompanionData()

            assert.equals("Valeera Sanguinar", DelveCompanionStatsDB.companionName)
            assert.equals(3,                   DelveCompanionStatsDB.companionLevel)
        end)

        it("handles nil event without error", function()
            assert.has_no_error(function()
                ns:UpdateCompanionData(nil)
            end)
        end)
    end)

    describe("slash command registration", function()
        it("registers /dcs slash command", function()
            assert.is_not_nil(SLASH_DCS1)
            assert.equals("/dcs", SLASH_DCS1)
            assert.is_not_nil(SlashCmdList["DCS"])
            assert.is_function(SlashCmdList["DCS"])
        end)

        it("registers /delvecompanion slash command alias", function()
            assert.is_not_nil(SLASH_DCS2)
            assert.equals("/delvecompanion", SLASH_DCS2)
        end)
    end)

    describe("PrintDebugInfo / CreateDebugPopup", function()

        it("PrintDebugInfo creates ns.debugPopup (not nil after call)", function()
            assert.is_nil(ns.debugPopup)
            ns:PrintDebugInfo()
            assert.is_not_nil(ns.debugPopup)
        end)

        it("ns.debugPopup._editBox contains non-empty debug text after PrintDebugInfo", function()
            ns:PrintDebugInfo()
            local text = ns.debugPopup._editBox:GetText()
            assert.is_not_nil(text)
            assert.is_true(#text > 0)
        end)

        it("debug text contains expected substrings: C_DelvesUI, factionID, name", function()
            ns:PrintDebugInfo()
            local text = ns.debugPopup._editBox:GetText()
            assert.is_not_nil(text:find("C_DelvesUI",  1, true), "expected 'C_DelvesUI' in debug text")
            assert.is_not_nil(text:find("factionID",   1, true), "expected 'factionID' in debug text")
            assert.is_not_nil(text:find("name",        1, true), "expected 'name' in debug text")
        end)

        it("calling PrintDebugInfo twice reuses the same popup (singleton)", function()
            ns:PrintDebugInfo()
            local first = ns.debugPopup
            ns:PrintDebugInfo()
            local second = ns.debugPopup
            assert.equals(first, second)
        end)

        it("popup is shown after PrintDebugInfo", function()
            ns:PrintDebugInfo()
            assert.is_true(ns.debugPopup._shown)
        end)

        it("/dcs debug slash command triggers PrintDebugInfo and creates popup", function()
            assert.is_nil(ns.debugPopup)
            SlashCmdList["DCS"]("debug")
            assert.is_not_nil(ns.debugPopup)
        end)

        it("CreateDebugPopup stores _editBox reference on popup", function()
            ns:CreateDebugPopup()
            assert.is_not_nil(ns.debugPopup._editBox)
        end)

    end)

    describe("UpdateCompanionData state tracking", function()
        it("stores last-known factionID and name after update", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end

            ns:UpdateCompanionData("TEST_EVENT")

            assert.equals(2744,               ns._lastFactionID)
            assert.equals("Valeera Sanguinar", ns._lastName)
        end)

        it("clears state tracking when no companion is active", function()
            C_DelvesUI.GetFactionForCompanion = function() return nil end

            ns:UpdateCompanionData("TEST_EVENT")

            assert.is_nil(ns._lastFactionID)
            assert.is_nil(ns._lastName)
        end)

        it("UpdateCompanionData handles nil event without error", function()
            assert.has_no_error(function()
                ns:UpdateCompanionData(nil)
            end)
        end)
    end)

    -- -------------------------------------------------------------------------
    -- Frame visibility tests
    -- -------------------------------------------------------------------------
    describe("Frame visibility", function()

        after_each(function()
            -- Reset delve state so the NEXT test's outer before_each runs OnLoad
            -- with a clean (no-delve) state, preventing test pollution.
            C_DelvesUI._SetHasActiveDelve(false)
            -- Restore HasActiveDelve in case a test replaced it with an error stub.
            C_DelvesUI.HasActiveDelve = function() return C_DelvesUI._hasActiveDelve or false end
            -- Reset instance type
            _G._isInInstanceType = "none"
        end)

        it("hides frame after OnLoad when HasActiveDelve returns false", function()
            -- Outer before_each called ns:OnLoad() with _hasActiveDelve = false.
            -- UpdateFrameVisibility() inside OnLoad should have hidden the frame.
            assert.equals(false, ns.frame:IsShown())
        end)

        it("shows frame when PLAYER_ENTERING_WORLD fires and HasActiveDelve returns true", function()
            -- Frame is hidden after OnLoad; entering a delve should show it.
            C_DelvesUI._SetHasActiveDelve(true)
            ns.frame._scripts["OnEvent"](ns.frame, "PLAYER_ENTERING_WORLD")
            assert.equals(true, ns.frame:IsShown())
        end)

        it("hides frame when ZONE_CHANGED_NEW_AREA fires and HasActiveDelve returns false", function()
            -- First enter a delve so the frame is visible.
            C_DelvesUI._SetHasActiveDelve(true)
            ns.frame._scripts["OnEvent"](ns.frame, "PLAYER_ENTERING_WORLD")
            assert.equals(true, ns.frame:IsShown())

            -- Now leave the delve; the frame should hide.
            C_DelvesUI._SetHasActiveDelve(false)
            ns.frame._scripts["OnEvent"](ns.frame, "ZONE_CHANGED_NEW_AREA")
            assert.equals(false, ns.frame:IsShown())
        end)

        it("calls UpdateCompanionData when frame transitions from hidden to shown", function()
            -- Wrap ns.UpdateCompanionData with a call counter (spy).
            local callCount = 0
            local originalUCD = ns.UpdateCompanionData
            ns.UpdateCompanionData = function(self, event)
                callCount = callCount + 1
                return originalUCD(self, event)
            end

            -- Precondition: frame is hidden after OnLoad.
            assert.equals(false, ns.frame:IsShown())

            -- Trigger hidden → shown transition.
            C_DelvesUI._SetHasActiveDelve(true)
            ns.frame._scripts["OnEvent"](ns.frame, "PLAYER_ENTERING_WORLD")

            -- UpdateCompanionData must have been invoked at least once.
            assert.is_true(callCount >= 1)

            -- Restore the original implementation.
            ns.UpdateCompanionData = originalUCD
        end)

        it("keeps frame hidden when HasActiveDelve raises an error", function()
            -- Ensure we're not in a party instance so IsInDelve() falls through to HasActiveDelve.
            _G._isInInstanceType = "none"
            -- Replace HasActiveDelve with a function that throws.
            C_DelvesUI.HasActiveDelve = function() error("API unavailable") end

            -- IsInDelve() checks instanceType first ("none" → false), then calls HasActiveDelve
            -- inside a pcall, so the error is swallowed. UpdateFrameVisibility must not raise.
            assert.has_no_error(function()
                ns:UpdateFrameVisibility()
            end)
            assert.equals(false, ns.frame:IsShown())
        end)

        it("shows frame when IsInInstance returns 'party' even if HasActiveDelve returns false", function()
            -- Simulate being inside a delve instance where HasActiveDelve is unreliable
            _G._isInInstanceType = "party"
            C_DelvesUI._SetHasActiveDelve(false)  -- HasActiveDelve returns false

            -- Frame should show because instanceType == "party"
            ns:UpdateFrameVisibility()
            assert.equals(true, ns.frame:IsShown())
        end)

    end)
end)
