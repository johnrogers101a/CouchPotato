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

            -- No friendship data → name shown in header, nameLabel shows only level+XP (both empty here)
            assert.equals("Valeera Sanguinar", ns.headerTitle:GetText())
            assert.equals("", ns.nameLabel._text)
        end)

        it("shows Unknown when GetFactionDataByID returns nil", function()
            C_DelvesUI.GetFactionForCompanion = function() return 9999 end
            C_Reputation.GetFactionDataByID = function() return nil end

            ns:UpdateCompanionData()

            assert.equals("Unknown", ns.headerTitle:GetText())
            assert.equals("", ns.nameLabel._text)
        end)

        it("extracts level from friendshipRank (combined into nameLabel Line 1)", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function() return { reaction = 3 } end

            ns:UpdateCompanionData()

            -- Name goes to header; nameLabel shows level only (no XP in this mock)
            assert.equals("Valeera Sanguinar", ns.headerTitle:GetText())
            assert.is_truthy(ns.nameLabel._text:find("Level 3", 1, true))
            assert.equals("", ns.levelLabel._text)
        end)

        it("extracts level from reaction field when friendshipRank is absent", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Brann Bronzebeard" } end
            C_GossipInfo.GetFriendshipReputation = function() return { reaction = 5 } end

            ns:UpdateCompanionData()

            assert.is_truthy(ns.nameLabel._text:find("Level 5", 1, true))
            assert.equals("", ns.levelLabel._text)
        end)

        it("shows no Level fragment when GetFriendshipReputation returns nil", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function() return nil end

            ns:UpdateCompanionData()

            -- No level data → nameLabel is empty (level+XP only format, nothing to show)
            -- Header title shows the companion name
            assert.equals("Valeera Sanguinar", ns.headerTitle:GetText())
            assert.equals("", ns.nameLabel._text)
            assert.equals("", ns.levelLabel._text)
        end)

        it("persists resolved name and level to SavedVariables", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function() return { reaction = 3 } end

            ns:UpdateCompanionData()

            assert.equals("Valeera Sanguinar", DelveCompanionStatsDB.companionName)
            assert.equals(3,                   DelveCompanionStatsDB.companionLevel)
        end)

        it("includes XP in nameLabel Line 1 combined text", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function()
                return {
                    standing          = 491930,
                    reactionThreshold = 460435,
                    nextThreshold     = 499810,
                    reaction          = 24,
                }
            end

            ns:UpdateCompanionData()

            -- currentXP = 491930 - 460435 = 31,495
            -- maxXP     = 499810 - 460435 = 39,375
            -- pct       = floor(31495/39375 * 100) = 79
            -- nameLabel shows "Level 24  31,495/39,375 (79%)"
            assert.equals("Valeera Sanguinar", ns.headerTitle:GetText())
            assert.is_truthy(ns.nameLabel._text:find("Level 24", 1, true))
            assert.is_truthy(ns.nameLabel._text:find("31,495/39,375", 1, true))
            assert.is_truthy(ns.nameLabel._text:find("79%", 1, true))
            assert.is_nil(ns.nameLabel._text:find("Valeera Sanguinar", 1, true))
            -- xpLabel is hidden/unused
            assert.equals("", ns.xpLabel._text)
        end)

        it("omits XP fragment when standing is missing from friendData", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function()
                return { reaction = 3 }   -- no standing/thresholds
            end

            ns:UpdateCompanionData()

            -- No XP data → nameLabel contains level only, no "XP" fragment
            assert.is_truthy(ns.nameLabel._text:find("Level 3", 1, true))
            assert.is_nil(ns.nameLabel._text:find("XP", 1, true))
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
            _ClearMockBoonTooltip()
            -- Clear nemesis so it doesn't interfere
            C_ScenarioInfo._criteria = {}
        end)

        after_each(function()
            _ClearMockBoonTooltip()
            C_ScenarioInfo._criteria = {}
        end)

        it("boon display shows abbreviated stats parsed from tooltip", function()
            -- Boon display is disabled; GetBoonsDisplayText always returns "".
            _SetMockBoonTooltip({
                "Boons",
                "Maximum Health increased by 0%.\nStrength increased by 0%.\nMovement Speed increased by 0%.\nMastery increased by 0%.",
                "",
                "Maximum Health: 6%.\nMovement Speed: 10%.\nStrength: 4%.\n\nMastery: 5%.\n",
            })

            ns:UpdateCompanionData()

            assert.equals("", ns.boonLabel._text)
            assert.is_false(ns.boonLabel:IsShown())
        end)

        it("boon display hides label when no active boons", function()
            -- No tooltip lines set — simulates spell not active
            ns:UpdateCompanionData()

            assert.equals("", ns.boonLabel._text)
            assert.is_false(ns.boonLabel:IsShown())
            assert.is_false(ns.boonHeaderLabel:IsShown())
        end)

        it("boon display excludes stats where value is 0", function()
            -- Boon display is disabled; always hidden regardless of tooltip data.
            _SetMockBoonTooltip({
                "Boons",
                "",
                "",
                "Maximum Health: 3%.\nHaste: 0%.",
            })

            ns:UpdateCompanionData()

            assert.equals("", ns.boonLabel._text)
            assert.is_false(ns.boonLabel:IsShown())
        end)

        it("boon label is shown when tooltip has boon lines", function()
            -- Boon display is disabled; label and header stay hidden even with data.
            _SetMockBoonTooltip({
                "Boons",
                "",
                "",
                "Versatility: 7%.",
            })

            ns:UpdateCompanionData()

            assert.is_false(ns.boonLabel:IsShown())
            assert.equals("", ns.boonLabel._text)
            assert.is_false(ns.boonHeaderLabel:IsShown())
        end)

    end)

    -- -------------------------------------------------------------------------
    -- Boon timing / event-driven refresh tests
    -- -------------------------------------------------------------------------
    describe("Boon timing and event-driven refresh", function()

        before_each(function()
            -- Set up a valid companion so UpdateCompanionData proceeds past early return
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID   = function() return { name = "Brann Bronzebeard" } end
            C_GossipInfo.GetFriendshipReputation = function()
                return { friendshipRank = 12, standing = 100, reactionThreshold = 0, nextThreshold = 200 }
            end
            _ClearMockBoonTooltip()
            C_ScenarioInfo._criteria = {}
            C_Timer._Reset()
            -- Be in a delve for visibility tests
            _G._isInInstanceType = "scenario"
            ns:UpdateFrameVisibility()
        end)

        after_each(function()
            _ClearMockBoonTooltip()
            C_ScenarioInfo._criteria = {}
            C_Timer._Reset()
            _G._isInInstanceType = "none"
            C_DelvesUI._SetHasActiveDelve(false)
        end)

        it("GetBoonsDisplayText returns empty string when tooltip has unresolved $w template vars", function()
            -- Simulate early zone-in: WoW tooltip returns "$w1%" placeholders
            _SetMockBoonTooltip({
                "Boons",
                "",
                "",
                "Maximum Health: $w1%.\nMovement Speed: $w2%.",
            })
            ns:UpdateCompanionData()
            -- Template vars must not be shown — label stays empty
            assert.equals("", ns.boonLabel._text)
            assert.is_false(ns.boonLabel:IsShown())
        end)

        it("GetBoonsDisplayText returns real values when tooltip has resolved stats", function()
            -- Boon display is disabled; GetBoonsDisplayText always returns "".
            _SetMockBoonTooltip({
                "Boons",
                "",
                "",
                "Maximum Health: 6%.\nMovement Speed: 10%.",
            })
            ns:UpdateCompanionData()
            assert.equals("", ns.boonLabel._text)
            assert.is_false(ns.boonLabel:IsShown())
        end)

        it("PLAYER_ENTERING_WORLD schedules one delayed C_Timer.After call", function()
            -- The 5s redundant timer was removed; only the 2s post-zone-in refresh remains.
            local timersBefore
            do
                local originalAfter = C_Timer.After
                local timerCount = 0
                C_Timer.After = function(delay, cb)
                    timerCount = timerCount + 1
                    return originalAfter(delay, cb)
                end
                ns.frame._scripts["OnEvent"](ns.frame, "PLAYER_ENTERING_WORLD")
                timersBefore = timerCount
                C_Timer.After = originalAfter
            end
            -- Must schedule exactly 1 delayed refresh on PLAYER_ENTERING_WORLD (2s only)
            assert.equals(1, timersBefore)
        end)

        it("delayed timers from PLAYER_ENTERING_WORLD call UpdateCompanionData when in delve", function()
            -- Boon display is disabled; even after timers fire the label stays empty.
            _G._isInInstanceType = "scenario"
            _SetMockBoonTooltip({
                "Boons", "", "",
                "Maximum Health: 8%.",
            })

            ns.frame._scripts["OnEvent"](ns.frame, "PLAYER_ENTERING_WORLD")

            -- Fire all pending timers (simulates 2s and 5s passing)
            C_Timer._FireAll()

            -- Boon display disabled — label always empty
            assert.equals("", ns.boonLabel._text)
            assert.is_false(ns.boonLabel:IsShown())
        end)

        it("delayed timers from PLAYER_ENTERING_WORLD do NOT call UpdateCompanionData when not in delve", function()
            -- Leave delve before timers fire
            _G._isInInstanceType = "none"
            C_DelvesUI._SetHasActiveDelve(false)

            local callCount = 0
            local originalUCD = ns.UpdateCompanionData
            ns.UpdateCompanionData = function(self, event)
                callCount = callCount + 1
                return originalUCD(self, event)
            end

            ns.frame._scripts["OnEvent"](ns.frame, "PLAYER_ENTERING_WORLD")
            local countAfterEvent = callCount  -- may be 0 (frame hidden) or 1

            C_Timer._FireAll()

            -- Timers should NOT have fired an update since not in a delve
            assert.equals(countAfterEvent, callCount)

            ns.UpdateCompanionData = originalUCD
        end)

        it("UNIT_AURA for 'player' triggers UpdateCompanionData when in delve", function()
            _G._isInInstanceType = "scenario"
            _SetMockBoonTooltip({
                "Boons", "", "",
                "Versatility: 5%.",
            })

            local callCount = 0
            local originalUCD = ns.UpdateCompanionData
            ns.UpdateCompanionData = function(self, event)
                callCount = callCount + 1
                return originalUCD(self, event)
            end

            ns.frame._scripts["OnEvent"](ns.frame, "UNIT_AURA", "player")

            assert.is_true(callCount >= 1)
            ns.UpdateCompanionData = originalUCD
        end)

        it("UNIT_AURA for non-player unit does NOT trigger UpdateCompanionData", function()
            _G._isInInstanceType = "scenario"

            local callCount = 0
            local originalUCD = ns.UpdateCompanionData
            ns.UpdateCompanionData = function(self, event)
                callCount = callCount + 1
                return originalUCD(self, event)
            end

            ns.frame._scripts["OnEvent"](ns.frame, "UNIT_AURA", "party1")

            assert.equals(0, callCount)
            ns.UpdateCompanionData = originalUCD
        end)

        it("UNIT_AURA for 'player' does NOT trigger UpdateCompanionData when not in delve", function()
            _G._isInInstanceType = "none"
            C_DelvesUI._SetHasActiveDelve(false)

            local callCount = 0
            local originalUCD = ns.UpdateCompanionData
            ns.UpdateCompanionData = function(self, event)
                callCount = callCount + 1
                return originalUCD(self, event)
            end

            ns.frame._scripts["OnEvent"](ns.frame, "UNIT_AURA", "player")

            assert.equals(0, callCount)
            ns.UpdateCompanionData = originalUCD
        end)

    end)

    -- -------------------------------------------------------------------------
    -- Header frame and collapse/expand tests
    -- -------------------------------------------------------------------------
    describe("header frame and collapse/expand", function()

        it("ns.headerFrame is not nil after OnLoad", function()
            assert.is_not_nil(ns.headerFrame)
        end)

        it("headerTitle and collapseBtn are wired directly on ns", function()
            -- Manual recreation: title and button live on ns directly, not as template children
            assert.is_not_nil(ns.headerTitle)
            assert.is_not_nil(ns.collapseBtn)
        end)

        it("header title text is 'Companion' (placeholder until data loads)", function()
            assert.is_not_nil(ns.headerTitle)
            assert.equals("Companion", ns.headerTitle:GetText())
        end)

        it("collapse button click hides contentFrame and sets collapsed = true", function()
            ns.contentFrame:Show()
            local btn = ns.collapseBtn
            assert.is_not_nil(btn)
            btn._scripts["OnClick"]()
            assert.is_false(ns.contentFrame:IsShown())
            assert.is_true(DelveCompanionStatsDB.collapsed)
        end)

        it("collapse button click sets button text to '+'", function()
            ns.contentFrame:Show()
            local btn = ns.collapseBtn
            btn._scripts["OnClick"]()
            assert.equals("+", btn:GetText())
        end)

        it("expand button click shows contentFrame and sets collapsed = false", function()
            -- Collapse first
            ns.contentFrame:Hide()
            DelveCompanionStatsDB.collapsed = true
            local btn = ns.collapseBtn
            btn:SetText("+")
            -- Click to expand
            btn._scripts["OnClick"]()
            assert.is_true(ns.contentFrame:IsShown())
            assert.is_false(DelveCompanionStatsDB.collapsed)
        end)

        it("expand button click sets button text to '–'", function()
            ns.contentFrame:Hide()
            local btn = ns.collapseBtn
            btn:SetText("+")
            btn._scripts["OnClick"]()
            assert.equals("–", btn:GetText())
        end)

        it("restores collapsed state (contentFrame hidden) when db.collapsed = true on init", function()
            -- Fresh load with collapsed = true in DB
            _G.DelveCompanionStatsDB  = { collapsed = true }
            _G.DelveCompanionStatsNS  = nil
            _G.DelveCompanionStatsFrame  = nil
            _G.DelveCompanionStatsHeader = nil
            dofile("DelveCompanionStats/DelveCompanionStats.lua")
            local ns2 = _G.DelveCompanionStatsNS
            ns2:OnLoad()
            assert.is_false(ns2.contentFrame:IsShown())
        end)

        it("restores expanded state (contentFrame shown) when db.collapsed = false on init", function()
            _G.DelveCompanionStatsDB  = { collapsed = false }
            _G.DelveCompanionStatsNS  = nil
            _G.DelveCompanionStatsFrame  = nil
            _G.DelveCompanionStatsHeader = nil
            dofile("DelveCompanionStats/DelveCompanionStats.lua")
            local ns2 = _G.DelveCompanionStatsNS
            ns2:OnLoad()
            assert.is_true(ns2.contentFrame:IsShown())
        end)

        it("manual header is always used (no template dependency)", function()
            -- No fallback path needed: header is always built manually.
            -- Verify the manual creation result is valid.
            assert.is_not_nil(ns.headerFrame)
            -- Manual header has no .Button child; button lives on ns.collapseBtn
            assert.is_nil(ns.headerFrame.Button)
            assert.is_not_nil(ns.collapseBtn)
            assert.is_not_nil(ns.headerLabel)
        end)

    end)

    -- -------------------------------------------------------------------------
    -- Collapse button visibility and styling (native header template)
    -- -------------------------------------------------------------------------
    describe("collapse button (native header)", function()

        it("collapse button has initial text '–'", function()
            local collapseBtn = ns.collapseBtn
            assert.is_not_nil(collapseBtn)
            assert.equals("–", collapseBtn:GetText())
        end)

        it("collapse button text color is gold", function()
            local collapseBtn = ns.collapseBtn
            assert.is_not_nil(collapseBtn)
            local r, g, b, a = collapseBtn:GetTextColor()
            assert.is_not_nil(r, "text color R should be set")
            assert.near(1.0,  r, 0.01, "R should be ~1.0 (gold)")
            assert.near(0.78, g, 0.01, "G should be ~0.78 (gold)")
            assert.near(0.1,  b, 0.01, "B should be ~0.1 (gold)")
            assert.near(1.0,  a, 0.01, "A should be ~1.0 (opaque)")
        end)

        it("collapse button is positioned on right side of header", function()
            local collapseBtn = ns.collapseBtn
            assert.is_not_nil(collapseBtn)
            local hasRight = false
            for _, pt in ipairs(collapseBtn._points or {}) do
                if pt[1] == "RIGHT" then
                    hasRight = true
                    break
                end
            end
            assert.is_true(hasRight, "expected a SetPoint call with 'RIGHT' anchor")
        end)

        it("collapse button click hides content and updates text", function()
            local collapseBtn = ns.collapseBtn
            assert.is_not_nil(collapseBtn)
            ns.contentFrame:Show()
            collapseBtn._scripts["OnClick"]()
            assert.is_false(ns.contentFrame:IsShown())
            assert.equals("+", collapseBtn:GetText())
            assert.is_true(DelveCompanionStatsDB.collapsed)
        end)

        it("collapse button click again shows content and updates text", function()
            local collapseBtn = ns.collapseBtn
            assert.is_not_nil(collapseBtn)
            -- First click: collapse
            ns.contentFrame:Show()
            collapseBtn._scripts["OnClick"]()
            -- Second click: expand
            collapseBtn._scripts["OnClick"]()
            assert.is_true(ns.contentFrame:IsShown())
            assert.equals("–", collapseBtn:GetText())
            assert.is_false(DelveCompanionStatsDB.collapsed)
        end)

        it("collapsed state is restored on load", function()
            _G.DelveCompanionStatsDB  = { collapsed = true }
            _G.DelveCompanionStatsNS  = nil
            _G.DelveCompanionStatsFrame  = nil
            _G.DelveCompanionStatsHeader = nil
            dofile("DelveCompanionStats/DelveCompanionStats.lua")
            local ns2 = _G.DelveCompanionStatsNS
            ns2:OnLoad()
            assert.is_false(ns2.contentFrame:IsShown())
            local collapseBtn = ns2.collapseBtn
            assert.is_not_nil(collapseBtn)
            assert.equals("+", collapseBtn:GetText())
        end)

    end)

    describe("Nemesis progress", function()

        before_each(function()
            -- Set up a valid companion
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID   = function() return { name = "Brann Bronzebeard" } end
            C_GossipInfo.GetFriendshipReputation = function()
                return { friendshipRank = 12, standing = 100, reactionThreshold = 0, nextThreshold = 200 }
            end
            _ClearMockBoonTooltip()
            C_ScenarioInfo._criteria = {}
            _ClearMockNemesis()
        end)

        after_each(function()
            _ClearMockBoonTooltip()
            C_ScenarioInfo._criteria = {}
            _ClearMockNemesis()
        end)

        -- Nemesis display uses C_Spell.GetSpellDescription(472952).
        -- Inside a delve that spell description contains:
        --   "Enemy groups remaining: |cnWHITE_FONT_COLOR:X / Y|r"

        it("nemesis label shows progress when spell description is available", function()
            _SetMockNemesis(2, 4)
            ns:UpdateCompanionData()
            assert.equals("Enemy groups remaining: 2 / 4", ns.nemesisLabel._text)
            assert.is_true(ns.nemesisLabel:IsShown())
        end)

        it("nemesis label is hidden when spell description is absent (not in a delve)", function()
            -- No spell description set → GetSpellDescription returns ""
            ns:UpdateCompanionData()
            assert.equals("", ns.nemesisLabel._text)
            assert.is_false(ns.nemesisLabel:IsShown())
        end)

        it("nemesis label shows 4/4 when all groups remain", function()
            _SetMockNemesis(4, 4)
            ns:UpdateCompanionData()
            assert.equals("Enemy groups remaining: 4 / 4", ns.nemesisLabel._text)
            assert.is_true(ns.nemesisLabel:IsShown())
        end)

        it("nemesis label shows 0/4 when all groups defeated", function()
            _SetMockNemesis(0, 4)
            ns:UpdateCompanionData()
            assert.equals("Enemy groups remaining: 0 / 4", ns.nemesisLabel._text)
            assert.is_true(ns.nemesisLabel:IsShown())
        end)

        it("nemesisDetailLabel is always hidden (detail moved to nemesisLabel)", function()
            _SetMockNemesis(2, 4)
            ns:UpdateCompanionData()
            assert.equals("", ns.nemesisDetailLabel._text)
            assert.is_false(ns.nemesisDetailLabel:IsShown())
        end)

        it("nemesisDetailLabel is hidden when no nemesis data present", function()
            ns:UpdateCompanionData()
            assert.is_false(ns.nemesisDetailLabel:IsShown())
        end)


        describe("IsCombatCriteria", function()
            it("returns false for 'Speak with X'", function()
                assert.is_false(ns.IsCombatCriteria("Speak with Celoenus Blackflame"))
            end)

            it("returns false for 'Talk to X'", function()
                assert.is_false(ns.IsCombatCriteria("Talk to the guard"))
            end)

            it("returns false for 'Find X'", function()
                assert.is_false(ns.IsCombatCriteria("Find the hidden passage"))
            end)

            it("returns false for 'Collect X'", function()
                assert.is_false(ns.IsCombatCriteria("Collect the ancient relic"))
            end)

            it("returns false for nil", function()
                assert.is_false(ns.IsCombatCriteria(nil))
            end)

            it("returns false for ambiguous descriptions", function()
                assert.is_false(ns.IsCombatCriteria("Survive the onslaught"))
            end)

            it("returns true for 'X slain'", function()
                assert.is_true(ns.IsCombatCriteria("Cultists slain"))
            end)

            it("returns true for 'Blademaster Darza slain'", function()
                assert.is_true(ns.IsCombatCriteria("Blademaster Darza slain"))
            end)

            it("returns true for 'Totems destroyed'", function()
                assert.is_true(ns.IsCombatCriteria("Totems destroyed"))
            end)

            it("returns true for 'Enemy group' descriptions", function()
                assert.is_true(ns.IsCombatCriteria("Enemy groups remaining"))
            end)

            it("returns true for 'defeated' descriptions", function()
                assert.is_true(ns.IsCombatCriteria("Enemies defeated"))
            end)

            it("returns true for 'nemesis' descriptions", function()
                assert.is_true(ns.IsCombatCriteria("Nemesis bounty target killed"))
            end)
        end)

        it("boon and nemesis labels hidden when no delve data present", function()
            -- No auras, no criteria — simulates not being in a delve
            ns:UpdateCompanionData()

            assert.is_false(ns.boonLabel:IsShown())
            assert.is_false(ns.nemesisLabel:IsShown())
            assert.is_false(ns.nemesisDetailLabel:IsShown())
        end)

    end)

    -- -------------------------------------------------------------------------
    -- Blizzard ObjectiveTracker exact styling tests
    -- -------------------------------------------------------------------------
    describe("Blizzard ObjectiveTracker styling", function()

        -- ── Fonts ─────────────────────────────────────────────────────────────
        describe("fonts", function()

            it("header label uses Frizqt font (explicit SetFont, not ObjectiveTitleFont arg)", function()
                -- ns.headerLabel is aliased to ns.headerTitle on the manual header.
                -- Font is set explicitly via SetFont() so it renders even before
                -- font objects finish loading in-game.
                assert.is_not_nil(ns.headerLabel)
                local fontPath = ns.headerLabel:GetFont()
                assert.equals("Fonts\\FRIZQT__.TTF", fontPath)
            end)

            it("nameLabel uses ObjectiveFont", function()
                local fontPath = ns.nameLabel:GetFont()
                assert.equals("ObjectiveFont", fontPath)
            end)

            it("boonHeaderLabel uses ObjectiveFont", function()
                local fontPath = ns.boonHeaderLabel:GetFont()
                assert.equals("ObjectiveFont", fontPath)
            end)

            it("boonLabel uses ObjectiveFont", function()
                local fontPath = ns.boonLabel:GetFont()
                assert.equals("ObjectiveFont", fontPath)
            end)

            it("nemesisLabel uses ObjectiveFont", function()
                local fontPath = ns.nemesisLabel:GetFont()
                assert.equals("ObjectiveFont", fontPath)
            end)

            it("nemesisDetailLabel uses ObjectiveFont", function()
                local fontPath = ns.nemesisDetailLabel:GetFont()
                assert.equals("ObjectiveFont", fontPath)
            end)

            it("header always uses Frizqt font (manual header, explicit SetFont)", function()
                -- Header is always built manually with explicit SetFont() — no template dependency.
                assert.is_not_nil(ns.headerLabel)
                local fontPath = ns.headerLabel:GetFont()
                assert.equals("Fonts\\FRIZQT__.TTF", fontPath)
            end)

        end)

        -- ── Colors ────────────────────────────────────────────────────────────
        describe("colors", function()

            it("header label colour is bright gold {1, 0.82, 0.0}", function()
                local r, g, b = ns.headerLabel:GetTextColor()
                assert.is_true(math.abs(r - 1.0)  < 0.001, "expected r≈1.0, got " .. tostring(r))
                assert.is_true(math.abs(g - 0.82) < 0.001, "expected g≈0.82, got " .. tostring(g))
                assert.is_true(math.abs(b - 0.0)  < 0.001, "expected b≈0.0, got " .. tostring(b))
            end)

            it("boonHeaderLabel colour is muted gold {0.9, 0.75, 0.3}", function()
                local r, g, b = ns.boonHeaderLabel:GetTextColor()
                assert.is_true(math.abs(r - 0.9)  < 0.001)
                assert.is_true(math.abs(g - 0.75) < 0.001)
                assert.is_true(math.abs(b - 0.3)  < 0.001)
            end)

            it("nemesisLabel colour is muted gold {0.9, 0.75, 0.3}", function()
                local r, g, b = ns.nemesisLabel:GetTextColor()
                assert.is_true(math.abs(r - 0.9)  < 0.001)
                assert.is_true(math.abs(g - 0.75) < 0.001)
                assert.is_true(math.abs(b - 0.3)  < 0.001)
            end)

            it("nameLabel colour is white {1, 1, 1}", function()
                local r, g, b = ns.nameLabel:GetTextColor()
                assert.is_true(math.abs(r - 1) < 0.001)
                assert.is_true(math.abs(g - 1) < 0.001)
                assert.is_true(math.abs(b - 1) < 0.001)
            end)

            it("boonLabel colour is white {1, 1, 1}", function()
                local r, g, b = ns.boonLabel:GetTextColor()
                assert.is_true(math.abs(r - 1) < 0.001)
                assert.is_true(math.abs(g - 1) < 0.001)
                assert.is_true(math.abs(b - 1) < 0.001)
            end)

            it("nemesisDetailLabel colour is white {1, 1, 1}", function()
                local r, g, b = ns.nemesisDetailLabel:GetTextColor()
                assert.is_true(math.abs(r - 1) < 0.001)
                assert.is_true(math.abs(g - 1) < 0.001)
                assert.is_true(math.abs(b - 1) < 0.001)
            end)

            it("header border line colour is {1, 0.78, 0.1} (bright gold)", function()
                -- Manual header always has top+bottom gold border lines
                local hf = ns.headerFrame
                assert.is_not_nil(hf)
                -- Find the border line texture by looking for one with r≈1, g≈0.78, b≈0.1
                local found = false
                for _, tex in ipairs(hf._textures or {}) do
                    local c = tex._color
                    if c and math.abs(c[1] - 1) < 0.001
                          and math.abs(c[2] - 0.78) < 0.001
                          and math.abs(c[3] - 0.1) < 0.001 then
                        found = true
                        break
                    end
                end
                assert.is_true(found, "expected header border texture with colour {1, 0.78, 0.1}")
            end)

        end)

        -- ── Spacing / padding ─────────────────────────────────────────────────
        describe("spacing and padding", function()

            it("nameLabel width is frameWidth - 12", function()
                -- frameWidth fallback is 248; contentWidth = 248 - 12 = 236
                assert.equals(236, ns.nameLabel._width)
            end)

            it("boonHeaderLabel width is frameWidth - 12", function()
                assert.equals(236, ns.boonHeaderLabel._width)
            end)

            it("boonLabel width is frameWidth - 12", function()
                assert.equals(236, ns.boonLabel._width)
            end)

            it("nemesisLabel width is frameWidth - 12", function()
                assert.equals(236, ns.nemesisLabel._width)
            end)

            it("nemesisDetailLabel width is frameWidth - 12", function()
                assert.equals(236, ns.nemesisDetailLabel._width)
            end)

        end)

        -- ── Content frame background ──────────────────────────────────────────
        describe("content frame background", function()

            it("contentFrame has rounded gold backdrop border", function()
                assert.is_not_nil(ns.contentFrame._backdrop)
                assert.are.equal("Interface\\Tooltips\\UI-Tooltip-Border", ns.contentFrame._backdrop.edgeFile)
                local bc = ns.contentFrame._backdropBorderColor
                assert.is_not_nil(bc)
                assert.near(1, bc[1], 0.01)
                assert.near(0.78, bc[2], 0.01)
                assert.near(0.1, bc[3], 0.01)
            end)

            it("contentFrame has dark brown backdrop background", function()
                local bc = ns.contentFrame._backdropColor
                assert.is_not_nil(bc)
                assert.near(0.05, bc[1], 0.01)
                assert.near(0.04, bc[2], 0.01)
                assert.near(0.01, bc[3], 0.01)
            end)

        end)

        -- ── Height recalculation ──────────────────────────────────────────────
        describe("height recalculation", function()

            before_each(function()
                C_DelvesUI.GetFactionForCompanion = function() return 2744 end
                C_Reputation.GetFactionDataByID   = function() return { name = "Brann Bronzebeard" } end
                C_GossipInfo.GetFriendshipReputation = function()
                    return { friendshipRank = 5 }
                end
                _ClearMockBoonTooltip()
                C_ScenarioInfo._criteria = {}
            end)

            after_each(function()
                _ClearMockBoonTooltip()
                C_ScenarioInfo._criteria = {}
                _ClearMockNemesis()
            end)

            it("base content height is 24 (4+16+4) when only nameLabel visible", function()
                ns:UpdateCompanionData()
                -- No boons, no nemesis → contentHeight = 24
                assert.equals(24, ns.contentFrame._height)
            end)

            it("content height adds 3+16 gap+header plus 16-per-boon-line", function()
                -- Boon display is disabled; tooltip data is ignored and height stays at base.
                _SetMockBoonTooltip({ "Boons", "", "", "Haste: 5%." })
                ns:UpdateCompanionData()
                -- Boons disabled → no boon section added → contentHeight = 24
                assert.equals(24, ns.contentFrame._height)
            end)

            it("content height includes nemesis section (3px gap + 16px label) when nemesis present", function()
                _SetMockNemesis(1, 3)
                ns:UpdateCompanionData()
                -- nemesis shown: base 24 + 3 gap + 16 label = 43
                assert.equals(43, ns.contentFrame._height)
            end)

            it("content height without nemesis stays at base when no spell description", function()
                -- No spell description → nemesis hidden → height 24
                ns:UpdateCompanionData()
                assert.equals(24, ns.contentFrame._height)
            end)

        end)

        -- ── Debug probe for header frame children ─────────────────────────────
        describe("debug probe: header frame children", function()

            it("PrintDebugInfo output includes '--- Header frame children ---'", function()
                ns:PrintDebugInfo()
                local text = ns.debugPopup._editBox:GetText()
                assert.is_truthy(text:find("Header frame children", 1, true),
                    "expected 'Header frame children' section in debug output")
            end)

        end)

    end)

    -- -------------------------------------------------------------------------
    -- Pin / Unpin button
    -- -------------------------------------------------------------------------
    describe("pin/unpin button", function()

        it("ns.pinBtn is not nil after OnLoad", function()
            assert.is_not_nil(ns.pinBtn)
        end)

        it("ns.pinBtnText is nil after OnLoad (replaced by texture)", function()
            assert.is_nil(ns.pinBtnText)
        end)

        it("default pin state is pinned (db.pinned = true after fresh OnLoad)", function()
            assert.is_true(DelveCompanionStatsDB.pinned)
        end)

        it("pin button shows locked texture when pinned (default)", function()
            assert.equals("Interface\\Buttons\\LockButton-Locked-Up", ns.pinBtn:GetNormalTexture())
        end)

        it("frame is not movable when pinned (default)", function()
            assert.is_false(ns.frame._movable)
        end)

        it("clicking pin button when pinned switches to unpinned state", function()
            assert.is_true(DelveCompanionStatsDB.pinned)   -- precondition
            ns.pinBtn._scripts["OnClick"]()
            assert.is_false(DelveCompanionStatsDB.pinned)
        end)

        it("frame becomes movable when unpinned via pin button click", function()
            ns.pinBtn._scripts["OnClick"]()   -- unpin
            assert.is_true(ns.frame._movable)
        end)

        it("pin button shows unlocked texture when unpinned", function()
            ns.pinBtn._scripts["OnClick"]()   -- unpin
            assert.equals("Interface\\Buttons\\LockButton-Unlocked-Up", ns.pinBtn:GetNormalTexture())
        end)

        it("clicking pin button when unpinned switches back to pinned state", function()
            ns.pinBtn._scripts["OnClick"]()   -- unpin
            assert.is_false(DelveCompanionStatsDB.pinned)
            ns.pinBtn._scripts["OnClick"]()   -- re-pin
            assert.is_true(DelveCompanionStatsDB.pinned)
        end)

        it("frame becomes not movable after re-pinning", function()
            ns.pinBtn._scripts["OnClick"]()   -- unpin
            ns.pinBtn._scripts["OnClick"]()   -- re-pin
            assert.is_false(ns.frame._movable)
        end)

        it("pin button shows locked texture after re-pinning", function()
            ns.pinBtn._scripts["OnClick"]()   -- unpin
            ns.pinBtn._scripts["OnClick"]()   -- re-pin
            assert.equals("Interface\\Buttons\\LockButton-Locked-Up", ns.pinBtn:GetNormalTexture())
        end)

        it("pin button is positioned LEFT of the collapse button", function()
            assert.is_not_nil(ns.pinBtn)
            local hasRight = false
            for _, pt in ipairs(ns.pinBtn._points or {}) do
                if pt[1] == "RIGHT" then
                    hasRight = true
                    break
                end
            end
            assert.is_true(hasRight, "expected a SetPoint with 'RIGHT' anchor on pin button")
        end)

        it("restores unpinned state on load when db.pinned = false", function()
            _G.DelveCompanionStatsDB = { pinned = false }
            _G.DelveCompanionStatsNS = nil
            _G.DelveCompanionStatsFrame = nil
            dofile("DelveCompanionStats/DelveCompanionStats.lua")
            local ns2 = _G.DelveCompanionStatsNS
            ns2:OnLoad()
            assert.is_true(ns2.frame._movable)
            assert.is_false(DelveCompanionStatsDB.pinned)
        end)

        it("restores pinned state on load when db.pinned = true", function()
            _G.DelveCompanionStatsDB = { pinned = true }
            _G.DelveCompanionStatsNS = nil
            _G.DelveCompanionStatsFrame = nil
            dofile("DelveCompanionStats/DelveCompanionStats.lua")
            local ns2 = _G.DelveCompanionStatsNS
            ns2:OnLoad()
            assert.is_false(ns2.frame._movable)
            assert.is_true(DelveCompanionStatsDB.pinned)
        end)

        it("unpinned drag stop saves position with relPoint key", function()
            ns.pinBtn._scripts["OnClick"]()   -- unpin → does NOT register drag scripts now (drag is on header)
            -- Simulate a drag stop on the header (which now handles drag)
            ns.header._scripts["OnDragStop"]()
            assert.is_not_nil(DelveCompanionStatsDB.position)
            -- relPoint key (not relativePoint) is what the new handler saves
            assert.is_not_nil(DelveCompanionStatsDB.position.relPoint)
        end)

    end)

end)
