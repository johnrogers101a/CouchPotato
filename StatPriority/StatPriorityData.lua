-- StatPriorityData.lua
-- Stat priority data for all retail specializations.
-- Keyed by specID (integer). Sources: Icy Veins and Wowhead (Wowhead is tiebreaker).
-- Each entry: { specName, stats = { ... }, _source }
-- This file is self-contained and can be updated independently of addon logic.
-- Interface: 120001 (Patch 12.0.1 Midnight)

StatPriorityData = {

    -- =========================================================================
    -- Death Knight
    -- =========================================================================

    -- Blood Death Knight (specID 250)
    [250] = {
        specName = "Blood Death Knight",
        stats    = { "Strength", "Haste", "Mastery", "Critical Strike", "Versatility" },
        _source  = "both",
    },

    -- Frost Death Knight (specID 251)
    [251] = {
        specName = "Frost Death Knight",
        stats    = { "Strength", "Critical Strike", "Mastery", "Haste", "Versatility" },
        _source  = "both",
    },

    -- Unholy Death Knight (specID 252)
    [252] = {
        specName = "Unholy Death Knight",
        stats    = { "Strength", "Haste", "Critical Strike", "Mastery", "Versatility" },
        _source  = "both",
    },

    -- =========================================================================
    -- Demon Hunter
    -- =========================================================================

    -- Havoc Demon Hunter (specID 577)
    [577] = {
        specName = "Havoc Demon Hunter",
        stats    = { "Agility", "Critical Strike", "Versatility", "Haste", "Mastery" },
        _source  = "wowhead",
    },

    -- Vengeance Demon Hunter (specID 581)
    [581] = {
        specName = "Vengeance Demon Hunter",
        stats    = { "Agility", "Haste", "Versatility", "Critical Strike", "Mastery" },
        _source  = "both",
    },

    -- =========================================================================
    -- Druid
    -- =========================================================================

    -- Balance Druid (specID 102)
    [102] = {
        specName = "Balance Druid",
        stats    = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        _source  = "wowhead",
    },

    -- Feral Druid (specID 103)
    [103] = {
        specName = "Feral Druid",
        stats    = { "Agility", "Critical Strike", "Haste", "Mastery", "Versatility" },
        _source  = "both",
    },

    -- Guardian Druid (specID 104)
    [104] = {
        specName = "Guardian Druid",
        stats    = { "Agility", "Versatility", "Mastery", "Haste", "Critical Strike" },
        _source  = "both",
    },

    -- Restoration Druid (specID 105)
    [105] = {
        specName = "Restoration Druid",
        stats    = { "Intellect", "Haste", "Mastery", "Versatility", "Critical Strike" },
        _source  = "both",
    },

    -- =========================================================================
    -- Evoker
    -- =========================================================================

    -- Devastation Evoker (specID 1467)
    [1467] = {
        specName = "Devastation Evoker",
        stats    = { "Intellect", "Mastery", "Critical Strike", "Haste", "Versatility" },
        _source  = "wowhead",
    },

    -- Preservation Evoker (specID 1468)
    [1468] = {
        specName = "Preservation Evoker",
        stats    = { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" },
        _source  = "wowhead",
    },

    -- Augmentation Evoker (specID 1473)
    [1473] = {
        specName = "Augmentation Evoker",
        stats    = { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" },
        _source  = "wowhead",
    },

    -- =========================================================================
    -- Hunter
    -- =========================================================================

    -- Beast Mastery Hunter (specID 253)
    [253] = {
        specName = "Beast Mastery Hunter",
        stats    = { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" },
        _source  = "both",
    },

    -- Marksmanship Hunter (specID 254)
    [254] = {
        specName = "Marksmanship Hunter",
        stats    = { "Agility", "Mastery", "Critical Strike", "Haste", "Versatility" },
        _source  = "wowhead",
    },

    -- Survival Hunter (specID 255)
    [255] = {
        specName = "Survival Hunter",
        stats    = { "Agility", "Haste", "Critical Strike", "Versatility", "Mastery" },
        _source  = "both",
    },

    -- =========================================================================
    -- Mage
    -- =========================================================================

    -- Arcane Mage (specID 62)
    [62] = {
        specName = "Arcane Mage",
        stats    = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" },
        _source  = "wowhead",
    },

    -- Fire Mage (specID 63)
    [63] = {
        specName = "Fire Mage",
        stats    = { "Intellect", "Critical Strike", "Mastery", "Versatility", "Haste" },
        _source  = "wowhead",
    },

    -- Frost Mage (specID 64)
    [64] = {
        specName = "Frost Mage",
        stats    = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        _source  = "both",
    },

    -- =========================================================================
    -- Monk
    -- =========================================================================

    -- Brewmaster Monk (specID 268)
    [268] = {
        specName = "Brewmaster Monk",
        stats    = { "Agility", "Critical Strike", "Haste", "Mastery", "Versatility" },
        _source  = "both",
    },

    -- Mistweaver Monk (specID 270)
    [270] = {
        specName = "Mistweaver Monk",
        stats    = { "Intellect", "Critical Strike", "Versatility", "Haste", "Mastery" },
        _source  = "wowhead",
    },

    -- Windwalker Monk (specID 269)
    [269] = {
        specName = "Windwalker Monk",
        stats    = { "Agility", "Critical Strike", "Versatility", "Mastery", "Haste" },
        _source  = "wowhead",
    },

    -- =========================================================================
    -- Paladin
    -- =========================================================================

    -- Holy Paladin (specID 65)
    [65] = {
        specName = "Holy Paladin",
        stats    = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        _source  = "both",
    },

    -- Protection Paladin (specID 66)
    [66] = {
        specName = "Protection Paladin",
        stats    = { "Strength", "Haste", "Versatility", "Mastery", "Critical Strike" },
        _source  = "both",
    },

    -- Retribution Paladin (specID 70)
    [70] = {
        specName = "Retribution Paladin",
        stats    = { "Strength", "Haste", "Critical Strike", "Versatility", "Mastery" },
        _source  = "wowhead",
    },

    -- =========================================================================
    -- Priest
    -- =========================================================================

    -- Discipline Priest (specID 256)
    [256] = {
        specName = "Discipline Priest",
        stats    = { "Intellect", "Haste", "Critical Strike", "Versatility", "Mastery" },
        _source  = "both",
    },

    -- Holy Priest (specID 257)
    [257] = {
        specName = "Holy Priest",
        stats    = { "Intellect", "Critical Strike", "Haste", "Versatility", "Mastery" },
        _source  = "wowhead",
    },

    -- Shadow Priest (specID 258)
    [258] = {
        specName = "Shadow Priest",
        stats    = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" },
        _source  = "both",
    },

    -- =========================================================================
    -- Rogue
    -- =========================================================================

    -- Assassination Rogue (specID 259)
    [259] = {
        specName = "Assassination Rogue",
        stats    = { "Agility", "Critical Strike", "Haste", "Versatility", "Mastery" },
        _source  = "wowhead",
    },

    -- Outlaw Rogue (specID 260)
    [260] = {
        specName = "Outlaw Rogue",
        stats    = { "Agility", "Haste", "Critical Strike", "Versatility", "Mastery" },
        _source  = "wowhead",
    },

    -- Subtlety Rogue (specID 261)
    [261] = {
        specName = "Subtlety Rogue",
        stats    = { "Agility", "Versatility", "Critical Strike", "Haste", "Mastery" },
        _source  = "wowhead",
    },

    -- =========================================================================
    -- Shaman
    -- =========================================================================

    -- Elemental Shaman (specID 262)
    [262] = {
        specName = "Elemental Shaman",
        stats    = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        _source  = "both",
    },

    -- Enhancement Shaman (specID 263)
    [263] = {
        specName = "Enhancement Shaman",
        stats    = { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" },
        _source  = "both",
    },

    -- Restoration Shaman (specID 264)
    [264] = {
        specName = "Restoration Shaman",
        stats    = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" },
        _source  = "both",
    },

    -- =========================================================================
    -- Warlock
    -- =========================================================================

    -- Affliction Warlock (specID 265)
    [265] = {
        specName = "Affliction Warlock",
        stats    = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" },
        _source  = "both",
    },

    -- Demonology Warlock (specID 266)
    [266] = {
        specName = "Demonology Warlock",
        stats    = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        _source  = "both",
    },

    -- Destruction Warlock (specID 267)
    [267] = {
        specName = "Destruction Warlock",
        stats    = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        _source  = "wowhead",
    },

    -- =========================================================================
    -- Warrior
    -- =========================================================================

    -- Arms Warrior (specID 71)
    [71] = {
        specName = "Arms Warrior",
        stats    = { "Strength", "Critical Strike", "Haste", "Versatility", "Mastery" },
        _source  = "wowhead",
    },

    -- Fury Warrior (specID 72)
    [72] = {
        specName = "Fury Warrior",
        stats    = { "Strength", "Critical Strike", "Haste", "Mastery", "Versatility" },
        _source  = "both",
    },

    -- Protection Warrior (specID 73)
    [73] = {
        specName = "Protection Warrior",
        stats    = { "Strength", "Haste", "Mastery", "Versatility", "Critical Strike" },
        _source  = "both",
    },

}
