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

        it("calculates XP as standing minus reactionThreshold over range", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function()
                return {
                    standing          = 491930,
                    reactionThreshold = 460435,
                    nextThreshold     = 499810,
                    friendshipRank    = 24,
                }
            end

            ns:UpdateCompanionData()

            -- currentXP = 491930 - 460435 = 31,495
            -- maxXP     = 499810 - 460435 = 39,375
            assert.equals("31,495 / 39,375 XP", ns.xpLabel._text)
        end)

        it("shows empty xpLabel when standing is missing from friendData", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function()
                return { friendshipRank = 3 }   -- no standing/thresholds
            end

            ns:UpdateCompanionData()

            assert.equals("", ns.xpLabel._text)
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
            -- Set up an active companion so the COMPANION STATE section includes factionID
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
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
    -- Slash command execution tests
    -- -------------------------------------------------------------------------
    describe("slash command execution", function()

        it("shows the frame when /dcs show is called", function()
            -- hide it first so we have a known starting state
            ns.frame:Hide()
            assert.is_false(ns.frame:IsShown())
            SlashCmdList["DCS"]("show")
            assert.is_true(ns.frame:IsShown())
        end)

        it("hides the frame when /dcs hide is called", function()
            ns.frame:Show()
            assert.is_true(ns.frame:IsShown())
            SlashCmdList["DCS"]("hide")
            assert.is_false(ns.frame:IsShown())
        end)

        it("resets frame position to default on /dcs reset", function()
            -- Give it a saved position first
            DelveCompanionStatsDB.position = { point = "CENTER", relativePoint = "CENTER", x = 100, y = 100 }
            SlashCmdList["DCS"]("reset")
            assert.is_nil(DelveCompanionStatsDB.position)
            -- Verify frame has a point set (was repositioned)
            local pt = ns.frame:GetPoint(1)
            assert.is_not_nil(pt)
        end)

        it("/dcs reset is idempotent (calling twice gives same state)", function()
            SlashCmdList["DCS"]("reset")
            local pt1 = ns.frame:GetPoint(1)
            SlashCmdList["DCS"]("reset")
            local pt2 = ns.frame:GetPoint(1)
            assert.equals(pt1, pt2)
            assert.is_nil(DelveCompanionStatsDB.position)
        end)

        it("/dcs debug does not raise an error when companion data is missing", function()
            -- before_each already sets GetFactionForCompanion to return nil,
            -- so companion data is absent by default.
            assert.has_no.errors(function()
                SlashCmdList["DCS"]("debug")
            end)
        end)

        it("debug output contains all required section headers", function()
            SlashCmdList["DCS"]("debug")
            local text = ns.debugPopup._editBox:GetText()
            assert.is_not_nil(text)
            assert.is_truthy(text:find("INSTANCE STATE",    1, true), "expected 'INSTANCE STATE' in debug text")
            assert.is_truthy(text:find("FRAME VISIBILITY",  1, true), "expected 'FRAME VISIBILITY' in debug text")
            assert.is_truthy(text:find("FRAME PROPERTIES",  1, true), "expected 'FRAME PROPERTIES' in debug text")
            assert.is_truthy(text:find("COMPANION STATE",   1, true), "expected 'COMPANION STATE' in debug text")
            assert.is_truthy(text:find("FRAME CONTENT",     1, true), "expected 'FRAME CONTENT' in debug text")
            assert.is_truthy(text:find("LAST KNOWN STATE",  1, true), "expected 'LAST KNOWN STATE' in debug text")
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

        it("shows frame when IsInInstance returns 'scenario' even if HasActiveDelve returns false", function()
            -- Simulate being inside a delve instance where HasActiveDelve is unreliable
            _G._isInInstanceType = "scenario"
            C_DelvesUI._SetHasActiveDelve(false)  -- HasActiveDelve returns false

            -- Frame should show because instanceType == "scenario"
            ns:UpdateFrameVisibility()
            assert.equals(true, ns.frame:IsShown())
        end)

    end)

    -- -------------------------------------------------------------------------
    -- Boon display tests
    -- -------------------------------------------------------------------------
    describe("Boon display", function()

        before_each(function()
            -- Set up a valid companion so UpdateCompanionData proceeds past early return
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID   = function() return { name = "Brann Bronzebeard" } end
            C_GossipInfo.GetFriendshipReputation = function()
                return { friendshipRank = 12, standing = 100, reactionThreshold = 0, nextThreshold = 200 }
            end
            _ClearMockAuras()
            -- Clear nemesis so it doesn't interfere
            C_Scenario._criteria = {}
        end)

        after_each(function()
            _ClearMockAuras()
            C_Scenario._criteria = {}
        end)

        it("boon display shows only boons with value > 0", function()
            _SetMockAura(1266969, 8)   -- Versatility 8%
            _SetMockAura(1266965, 0)   -- Crit Strike 0% — should be excluded

            ns:UpdateCompanionData()

            local text = ns.boonLabel._text
            assert.is_truthy(text:find("Versatility", 1, true),     "expected Versatility in boon text")
            assert.is_falsy( text:find("Crit Strike", 1, true),     "expected Crit Strike to be excluded")
        end)

        it("boon display hides label when no active boons", function()
            -- No auras set — all values nil or 0
            ns:UpdateCompanionData()

            assert.equals("", ns.boonLabel._text)
            assert.is_false(ns.boonLabel:IsShown())
        end)

        it("boon values are formatted as integers (math.floor applied)", function()
            _SetMockAura(1266969, 8.7)  -- Versatility 8.7 → should display as 8

            ns:UpdateCompanionData()

            local text = ns.boonLabel._text
            assert.is_truthy(text:find("8%%"),  "expected integer value 8 in boon text")
            assert.is_falsy( text:find("8%.7"), "expected decimal to be stripped")
        end)

        it("boon label is shown when at least one boon is active", function()
            _SetMockAura(1266969, 5)  -- Versatility 5%

            ns:UpdateCompanionData()

            assert.is_true(ns.boonLabel:IsShown())
        end)

    end)

    -- -------------------------------------------------------------------------
    -- Nemesis progress tests
    -- -------------------------------------------------------------------------
    describe("Nemesis progress", function()

        before_each(function()
            -- Set up a valid companion
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID   = function() return { name = "Brann Bronzebeard" } end
            C_GossipInfo.GetFriendshipReputation = function()
                return { friendshipRank = 12, standing = 100, reactionThreshold = 0, nextThreshold = 200 }
            end
            _ClearMockAuras()
            C_Scenario._criteria = {}
        end)

        after_each(function()
            _ClearMockAuras()
            C_Scenario._criteria = {}
        end)

        it("nemesis progress displays X/Y format", function()
            _SetMockNemesis(2, 4)

            ns:UpdateCompanionData()

            assert.equals("Nemesis: 2/4", ns.nemesisLabel._text)
        end)

        it("nemesis progress hides label if criterion not found", function()
            -- No criteria set
            ns:UpdateCompanionData()

            assert.equals("", ns.nemesisLabel._text)
            assert.is_false(ns.nemesisLabel:IsShown())
        end)

        it("nemesis label is shown when criterion is found", function()
            _SetMockNemesis(1, 4)

            ns:UpdateCompanionData()

            assert.is_true(ns.nemesisLabel:IsShown())
        end)

        it("boon and nemesis labels hidden when no delve data present", function()
            -- No auras, no criteria — simulates not being in a delve
            ns:UpdateCompanionData()

            assert.is_false(ns.boonLabel:IsShown())
            assert.is_false(ns.nemesisLabel:IsShown())
        end)

    end)
end)
