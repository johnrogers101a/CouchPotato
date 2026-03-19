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

            -- No friendship data → name only on Line 1
            assert.equals("Valeera Sanguinar", ns.nameLabel._text)
        end)

        it("shows Unknown when GetFactionDataByID returns nil", function()
            C_DelvesUI.GetFactionForCompanion = function() return 9999 end
            C_Reputation.GetFactionDataByID = function() return nil end

            ns:UpdateCompanionData()

            assert.equals("Unknown", ns.nameLabel._text)
        end)

        it("extracts level from friendshipRank (combined into nameLabel Line 1)", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function() return { friendshipRank = 3 } end

            ns:UpdateCompanionData()

            -- Level is now part of the combined nameLabel text; levelLabel stays hidden/empty
            assert.is_truthy(ns.nameLabel._text:find("Valeera Sanguinar", 1, true))
            assert.is_truthy(ns.nameLabel._text:find("L3", 1, true))
            assert.equals("", ns.levelLabel._text)
        end)

        it("extracts level from reaction field when friendshipRank is absent", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Brann Bronzebeard" } end
            C_GossipInfo.GetFriendshipReputation = function() return { reaction = 5 } end

            ns:UpdateCompanionData()

            assert.is_truthy(ns.nameLabel._text:find("L5", 1, true))
            assert.equals("", ns.levelLabel._text)
        end)

        it("shows no Level fragment when GetFriendshipReputation returns nil", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function() return nil end

            ns:UpdateCompanionData()

            -- No level data → nameLabel is just the name, no "Level" fragment
            assert.equals("Valeera Sanguinar", ns.nameLabel._text)
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

        it("includes XP in nameLabel Line 1 combined text", function()
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
            -- All three pieces appear on the single combined nameLabel line
            assert.is_truthy(ns.nameLabel._text:find("Valeera Sanguinar", 1, true))
            assert.is_truthy(ns.nameLabel._text:find("L24", 1, true))
            assert.is_truthy(ns.nameLabel._text:find("31,495 / 39,375 XP (79%)", 1, true))
            -- xpLabel is hidden/unused
            assert.equals("", ns.xpLabel._text)
        end)

        it("omits XP fragment when standing is missing from friendData", function()
            C_DelvesUI.GetFactionForCompanion = function() return 2744 end
            C_Reputation.GetFactionDataByID = function() return { name = "Valeera Sanguinar" } end
            C_GossipInfo.GetFriendshipReputation = function()
                return { friendshipRank = 3 }   -- no standing/thresholds
            end

            ns:UpdateCompanionData()

            -- No XP data → nameLabel contains name + level only, no "XP" fragment
            assert.is_truthy(ns.nameLabel._text:find("L3", 1, true))
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
            _SetMockBoonTooltip({
                "Boons",
                "Maximum Health increased by 0%.\nStrength increased by 0%.\nMovement Speed increased by 0%.\nMastery increased by 0%.",
                "",
                "Maximum Health: 6%.\nMovement Speed: 10%.\nStrength: 4%.\n\nMastery: 5%.\n",
            })

            ns:UpdateCompanionData()

            assert.equals("Max HP: 6%\nMove Spd: 10%\nStrength: 4%\nMastery: 5%", ns.boonLabel._text)
        end)

        it("boon display hides label when no active boons", function()
            -- No tooltip lines set — simulates spell not active
            ns:UpdateCompanionData()

            assert.equals("", ns.boonLabel._text)
            assert.is_false(ns.boonLabel:IsShown())
            assert.is_false(ns.boonHeaderLabel:IsShown())
        end)

        it("boon display excludes stats where value is 0", function()
            _SetMockBoonTooltip({
                "Boons",
                "",
                "",
                "Maximum Health: 3%.\nHaste: 0%.",  -- zero value, must be excluded
            })

            ns:UpdateCompanionData()

            assert.equals("Max HP: 3%", ns.boonLabel._text)
        end)

        it("boon label is shown when tooltip has boon lines", function()
            _SetMockBoonTooltip({
                "Boons",
                "",
                "",
                "Versatility: 7%.",
            })

            ns:UpdateCompanionData()

            assert.is_true(ns.boonLabel:IsShown())
            assert.equals("Vers: 7%", ns.boonLabel._text)
            -- boonHeaderLabel must also be shown
            assert.is_true(ns.boonHeaderLabel:IsShown())
            assert.equals("Boons", ns.boonHeaderLabel._text)
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
            -- Simulate boon fully applied: real numeric values
            _SetMockBoonTooltip({
                "Boons",
                "",
                "",
                "Maximum Health: 6%.\nMovement Speed: 10%.",
            })
            ns:UpdateCompanionData()
            assert.equals("Max HP: 6%\nMove Spd: 10%", ns.boonLabel._text)
            assert.is_true(ns.boonLabel:IsShown())
        end)

        it("PLAYER_ENTERING_WORLD schedules two delayed C_Timer.After calls", function()
            -- Count how many timers are registered before the event
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
            -- Must schedule exactly 2 delayed refreshes on PLAYER_ENTERING_WORLD
            assert.equals(2, timersBefore)
        end)

        it("delayed timers from PLAYER_ENTERING_WORLD call UpdateCompanionData when in delve", function()
            -- Ensure in a delve so timers fire an update
            _G._isInInstanceType = "scenario"
            _SetMockBoonTooltip({
                "Boons", "", "",
                "Maximum Health: 8%.",
            })

            ns.frame._scripts["OnEvent"](ns.frame, "PLAYER_ENTERING_WORLD")

            -- Fire all pending timers (simulates 2s and 5s passing)
            C_Timer._FireAll()

            -- After timers fire, boon label should have resolved data
            assert.equals("Max HP: 8%", ns.boonLabel._text)
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

        it("native template path: headerFrame has .Text and .Button children", function()
            -- Mock supports ObjectiveTrackerSectionHeaderTemplate — should use native path
            assert.is_not_nil(ns.headerFrame.Text)
            assert.is_not_nil(ns.headerFrame.Button)
        end)

        it("native template path: title text is 'Delve Companion'", function()
            local titleChild = ns.headerFrame.Text or ns.headerFrame.Title
            assert.is_not_nil(titleChild)
            assert.equals("Delve Companion", titleChild:GetText())
        end)

        it("collapse button click hides contentFrame and sets collapsed = true", function()
            ns.contentFrame:Show()
            local btn = ns.headerFrame.Button or ns.headerFrame.CollapseButton
            assert.is_not_nil(btn)
            btn._scripts["OnClick"]()
            assert.is_false(ns.contentFrame:IsShown())
            assert.is_true(DelveCompanionStatsDB.collapsed)
        end)

        it("collapse button click sets button text to '+'", function()
            ns.contentFrame:Show()
            local btn = ns.headerFrame.Button or ns.headerFrame.CollapseButton
            btn._scripts["OnClick"]()
            assert.equals("+", btn:GetText())
        end)

        it("expand button click shows contentFrame and sets collapsed = false", function()
            -- Collapse first
            ns.contentFrame:Hide()
            DelveCompanionStatsDB.collapsed = true
            local btn = ns.headerFrame.Button or ns.headerFrame.CollapseButton
            btn:SetText("+")
            -- Click to expand
            btn._scripts["OnClick"]()
            assert.is_true(ns.contentFrame:IsShown())
            assert.is_false(DelveCompanionStatsDB.collapsed)
        end)

        it("expand button click sets button text to '–'", function()
            ns.contentFrame:Hide()
            local btn = ns.headerFrame.Button or ns.headerFrame.CollapseButton
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

        it("falls back to custom header when template creation errors", function()
            local origCreateFrame = _G.CreateFrame
            _G.CreateFrame = function(frameType, name, parent, template)
                if template == "ObjectiveTrackerSectionHeaderTemplate" then
                    error("template not available in this environment")
                end
                return origCreateFrame(frameType, name, parent, template)
            end

            _G.DelveCompanionStatsDB  = {}
            _G.DelveCompanionStatsNS  = nil
            _G.DelveCompanionStatsFrame  = nil
            _G.DelveCompanionStatsHeader = nil
            dofile("DelveCompanionStats/DelveCompanionStats.lua")
            local ns2 = _G.DelveCompanionStatsNS
            ns2:OnLoad()

            _G.CreateFrame = origCreateFrame

            -- Fallback still provides a valid headerFrame
            assert.is_not_nil(ns2.headerFrame)
            -- Custom path creates ns.headerLabel as a FontString (no .Button child)
            assert.is_nil(ns2.headerFrame.Button)
            assert.is_not_nil(ns2.headerLabel)
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
        end)

        after_each(function()
            _ClearMockBoonTooltip()
            C_ScenarioInfo._criteria = {}
        end)

        it("nemesis progress displays 'Nemesis Strongbox (n/n)' format", function()
            _SetMockNemesis(2, 4)

            ns:UpdateCompanionData()

            assert.equals("Nemesis Strongbox (2/4)", ns.nemesisLabel._text)
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

        it("nemesis progress sums multiple criteria into one 'Nemesis Strongbox (n/n)' header", function()
            _SetMockNemesis({
                { description = "Vilebranch Skeleton Charmers slain", quantity = 0, totalQuantity = 5 },
                { description = "Totems destroyed",                   quantity = 1, totalQuantity = 6 },
            })

            ns:UpdateCompanionData()

            -- 0+1 = 1 current, 5+6 = 11 total
            assert.equals("Nemesis Strongbox (1/11)", ns.nemesisLabel._text)
        end)

        it("nemesis progress skips criteria with zero totalQuantity", function()
            _SetMockNemesis({
                { description = "Cultists slain", quantity = 0, totalQuantity = 0 },
                { description = "Totems destroyed", quantity = 2, totalQuantity = 3 },
            })

            ns:UpdateCompanionData()

            assert.equals("Nemesis Strongbox (2/3)", ns.nemesisLabel._text)
        end)

        it("nemesis counts 'Enemy groups remaining' criterion in header total", function()
            _SetMockNemesis({
                { description = "Enemy groups remaining", quantity = 1, totalQuantity = 3 },
            })

            ns:UpdateCompanionData()

            assert.equals("Nemesis Strongbox (1/3)", ns.nemesisLabel._text)
        end)

        it("nemesis hides non-combat criteria (Speak with)", function()
            _SetMockNemesis({
                { description = "Speak with Celoenus Blackflame", quantity = 0, totalQuantity = 1 },
            })

            ns:UpdateCompanionData()

            assert.equals("", ns.nemesisLabel._text)
            assert.is_false(ns.nemesisLabel:IsShown())
        end)

        it("nemesis hides label when all criteria are non-combat", function()
            _SetMockNemesis({
                { description = "Speak with Celoenus Blackflame", quantity = 0, totalQuantity = 1 },
                { description = "Find the hidden passage", quantity = 0, totalQuantity = 1 },
            })

            ns:UpdateCompanionData()

            assert.equals("", ns.nemesisLabel._text)
            assert.is_false(ns.nemesisLabel:IsShown())
        end)

        it("nemesis sums across mixed combat + non-combat (only combat contribute)", function()
            _SetMockNemesis({
                { description = "Speak with Celoenus Blackflame", quantity = 0, totalQuantity = 1 },
                { description = "Cultists slain",                 quantity = 2, totalQuantity = 5 },
                { description = "Totems destroyed",               quantity = 1, totalQuantity = 3 },
            })

            ns:UpdateCompanionData()

            -- Only combat criteria: 2+1=3 current, 5+3=8 total; non-combat excluded
            assert.equals("Nemesis Strongbox (3/8)", ns.nemesisLabel._text)
        end)

        -- -------------------------------------------------------------------------
        -- IsCombatCriteria direct unit tests
        -- -------------------------------------------------------------------------
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
        end)

    end)
end)
