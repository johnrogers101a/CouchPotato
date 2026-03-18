-- spec/DelveCompanionStats_spec.lua
-- Tests for DelveCompanionStats: companion name lookup, SavedVariables fallback, level extraction

require("spec/wow_mock")

describe("DelveCompanionStats", function()
    local ns

    before_each(function()
        -- Reset global state
        _G.DelveCompanionStatsDB = {}
        _G.DelveCompanionStatsNS = nil
        _G.DelveCompanionStatsFrame = nil

        -- Reset API mocks to default (no companion active)
        C_DelvesUI.GetCompanionInfoForActivePlayer = function() return nil end
        C_DelvesUI.GetFactionForCompanion = function() return nil end
        C_GossipInfo.GetFriendshipReputation = function() return nil end
        C_GossipInfo.GetFriendshipReputationRanks = function() return nil end
        C_Reputation.GetFactionDataByID = function() return nil end

        -- Load the addon (varargs will be empty, test fallback creates ns = {})
        dofile("DelveCompanionStats/DelveCompanionStats.lua")
        ns = _G.DelveCompanionStatsNS

        -- Directly initialize the addon (bypasses the ADDON_LOADED event)
        ns:OnLoad()
    end)

    describe("companion name lookup table", function()
        it("maps companion ID 1 to Brann Bronzebeard", function()
            assert.equals("Brann Bronzebeard", ns.companionNames[1])
        end)

        it("maps companion ID 2 to Valeera Sanguinar", function()
            assert.equals("Valeera Sanguinar", ns.companionNames[2])
        end)

        it("has all 5 known Delve companions in the lookup table", function()
            assert.equals("Brann Bronzebeard", ns.companionNames[1])
            assert.equals("Valeera Sanguinar", ns.companionNames[2])
            assert.equals("Waxmonger Squick",  ns.companionNames[3])
            assert.equals("Turalyon",          ns.companionNames[4])
            assert.equals("Thisalee Crow",     ns.companionNames[5])
        end)
    end)

    describe("UpdateCompanionData", function()
        it("displays correct name for known companion ID 1", function()
            C_DelvesUI.GetCompanionInfoForActivePlayer = function() return 1 end
            C_DelvesUI.GetFactionForCompanion = function() return 100 end

            ns:UpdateCompanionData()

            assert.equals("Brann Bronzebeard", ns.nameLabel._text)
        end)

        it("displays Unknown Companion for unknown companion ID", function()
            C_DelvesUI.GetCompanionInfoForActivePlayer = function() return 99 end
            C_DelvesUI.GetFactionForCompanion = function() return 100 end

            ns:UpdateCompanionData()

            assert.equals("Unknown Companion", ns.nameLabel._text)
        end)

        it("persists hardcoded name to SavedVariables (not faction name)", function()
            -- Set up faction API to return a faction name (should NOT be used)
            C_Reputation.GetFactionDataByID = function() return { name = "Friendship" } end
            -- Set companion ID 2 active
            C_DelvesUI.GetCompanionInfoForActivePlayer = function() return 2 end
            C_DelvesUI.GetFactionForCompanion = function() return 200 end

            ns:UpdateCompanionData()

            -- UI should show the hardcoded name, not the faction name
            assert.equals("Valeera Sanguinar", ns.nameLabel._text)
            -- SavedVariables should also use the hardcoded name
            assert.equals("Valeera Sanguinar", DelveCompanionStatsDB.companionName)
            -- Must not be the faction name
            assert.not_equals("Friendship", ns.nameLabel._text)
        end)

        it("extracts level correctly from GetFriendshipReputationRanks", function()
            C_DelvesUI.GetCompanionInfoForActivePlayer = function() return 1 end
            C_DelvesUI.GetFactionForCompanion = function() return 100 end
            C_GossipInfo.GetFriendshipReputation = function(factionID)
                return { friendshipFactionID = factionID, reaction = 5 }
            end
            C_GossipInfo.GetFriendshipReputationRanks = function(factionID)
                return { currentLevel = 7, maxLevel = 10 }
            end

            ns:UpdateCompanionData()

            assert.equals("Brann Bronzebeard", ns.nameLabel._text)
            assert.equals("Level: 7", ns.levelLabel._text)
        end)

        it("falls back to SavedVariables when no companion is active", function()
            -- No companion active
            C_DelvesUI.GetCompanionInfoForActivePlayer = function() return nil end
            -- Pre-populate SavedVariables from a previous session
            DelveCompanionStatsDB.companionName = "Brann Bronzebeard"
            DelveCompanionStatsDB.companionLevel = 5

            ns:UpdateCompanionData()

            assert.equals("Brann Bronzebeard", ns.nameLabel._text)
            assert.equals("Level: 5", ns.levelLabel._text)
        end)

        it("shows No companion data when no companion and no SavedVariables", function()
            C_DelvesUI.GetCompanionInfoForActivePlayer = function() return nil end
            DelveCompanionStatsDB = {}

            ns:UpdateCompanionData()

            assert.equals("No companion data", ns.nameLabel._text)
        end)
    end)
end)
