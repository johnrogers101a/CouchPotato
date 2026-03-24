-- StatPriorityData.lua
-- Stat priority data for all retail specializations.
-- Keyed by specID (integer).
-- Source: archon.gg (data-driven stat priorities from top raid logs).
-- Each entry:
--   specName  — display name
--   stats     — unified default (archon canonical)
--   archon    — archon.gg stat priority array (authoritative)
--   wowhead   — alias for archon (backward compat)
--   icyveins  — alias for archon (backward compat)
--   method    — alias for archon (backward compat)
--   urls      — { archon, wowhead, icyveins, method } source guide URLs (all archon)
--   _differs  — always false (single source)
--   _source   — "archon"
-- Interface: 120001 (Patch 12.0.1 Midnight)

-- Helper: returns true if two ordered stat arrays differ.
-- Entries may be strings or sub-arrays (tables) for equal-priority groups.
local function entriesEqual(x, y)
    if type(x) == "table" and type(y) == "table" then
        if #x ~= #y then return false end
        for i = 1, #x do
            if x[i] ~= y[i] then return false end
        end
        return true
    end
    return x == y
end

local function arraysDiffer(a, b)
    if #a ~= #b then return true end
    for i = 1, #a do
        if not entriesEqual(a[i], b[i]) then return true end
    end
    return false
end

local function anyDiffers(wh, iv, mt)
    return arraysDiffer(wh, iv) or arraysDiffer(wh, mt) or arraysDiffer(iv, mt)
end

-- Helper to build a spec entry from a single archon source array.
local function archonEntry(specName, archonStats, archonUrl)
    return {
        specName = specName,
        stats    = archonStats,
        archon   = archonStats,
        wowhead  = archonStats,
        icyveins = archonStats,
        method   = archonStats,
        urls     = {
            archon   = archonUrl,
            wowhead  = archonUrl,
            icyveins = archonUrl,
            method   = archonUrl,
        },
        _differs = false,
        _source  = "archon",
    }
end

StatPriorityData = {

    -- =========================================================================
    -- Death Knight
    -- =========================================================================

    -- Blood Death Knight (specID 250)
    [250] = archonEntry("Blood Death Knight",
        { "Strength", "Critical Strike", "Haste", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/blood/death-knight/raid/overview/heroic/all-bosses"),

    -- Frost Death Knight (specID 251)
    [251] = archonEntry("Frost Death Knight",
        { "Strength", "Critical Strike", "Mastery", "Haste", "Versatility" },
        "https://www.archon.gg/wow/builds/frost/death-knight/raid/overview/heroic/all-bosses"),

    -- Unholy Death Knight (specID 252)
    [252] = archonEntry("Unholy Death Knight",
        { "Strength", "Mastery", "Critical Strike", "Haste", "Versatility" },
        "https://www.archon.gg/wow/builds/unholy/death-knight/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Demon Hunter
    -- =========================================================================

    -- Havoc Demon Hunter (specID 577)
    [577] = archonEntry("Havoc Demon Hunter",
        { "Agility", "Critical Strike", "Mastery", "Haste", "Versatility" },
        "https://www.archon.gg/wow/builds/havoc/demon-hunter/raid/overview/heroic/all-bosses"),

    -- Vengeance Demon Hunter (specID 581)
    [581] = archonEntry("Vengeance Demon Hunter",
        { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/vengeance/demon-hunter/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Druid
    -- =========================================================================

    -- Balance Druid (specID 102)
    [102] = archonEntry("Balance Druid",
        { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" },
        "https://www.archon.gg/wow/builds/balance/druid/raid/overview/heroic/all-bosses"),

    -- Feral Druid (specID 103)
    [103] = archonEntry("Feral Druid",
        { "Agility", "Mastery", {"Critical Strike", "Haste"}, "Versatility" },
        "https://www.archon.gg/wow/builds/feral/druid/raid/overview/heroic/all-bosses"),

    -- Guardian Druid (specID 104)
    [104] = archonEntry("Guardian Druid",
        { "Agility", "Haste", {"Versatility", "Critical Strike"}, "Mastery" },
        "https://www.archon.gg/wow/builds/guardian/druid/raid/overview/heroic/all-bosses"),

    -- Restoration Druid (specID 105)
    [105] = archonEntry("Restoration Druid",
        { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" },
        "https://www.archon.gg/wow/builds/restoration/druid/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Evoker
    -- =========================================================================

    -- Devastation Evoker (specID 1467)
    [1467] = archonEntry("Devastation Evoker",
        { "Intellect", "Critical Strike", "Haste", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/devastation/evoker/raid/overview/heroic/all-bosses"),

    -- Preservation Evoker (specID 1468)
    [1468] = archonEntry("Preservation Evoker",
        { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" },
        "https://www.archon.gg/wow/builds/preservation/evoker/raid/overview/heroic/all-bosses"),

    -- Augmentation Evoker (specID 1473)
    [1473] = archonEntry("Augmentation Evoker",
        { "Intellect", "Critical Strike", "Haste", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/augmentation/evoker/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Hunter
    -- =========================================================================

    -- Beast Mastery Hunter (specID 253)
    [253] = archonEntry("Beast Mastery Hunter",
        { "Agility", "Mastery", "Critical Strike", "Haste", "Versatility" },
        "https://www.archon.gg/wow/builds/beast-mastery/hunter/raid/overview/heroic/all-bosses"),

    -- Marksmanship Hunter (specID 254)
    [254] = archonEntry("Marksmanship Hunter",
        { "Agility", "Critical Strike", "Mastery", "Haste", "Versatility" },
        "https://www.archon.gg/wow/builds/marksmanship/hunter/raid/overview/heroic/all-bosses"),

    -- Survival Hunter (specID 255)
    [255] = archonEntry("Survival Hunter",
        { "Agility", "Mastery", "Critical Strike", "Haste", "Versatility" },
        "https://www.archon.gg/wow/builds/survival/hunter/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Mage
    -- =========================================================================

    -- Arcane Mage (specID 62)
    [62] = archonEntry("Arcane Mage",
        { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" },
        "https://www.archon.gg/wow/builds/arcane/mage/raid/overview/heroic/all-bosses"),

    -- Fire Mage (specID 63)
    [63] = archonEntry("Fire Mage",
        { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" },
        "https://www.archon.gg/wow/builds/fire/mage/raid/overview/heroic/all-bosses"),

    -- Frost Mage (specID 64)
    [64] = archonEntry("Frost Mage",
        { "Intellect", "Mastery", "Critical Strike", "Haste", "Versatility" },
        "https://www.archon.gg/wow/builds/frost/mage/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Monk
    -- =========================================================================

    -- Brewmaster Monk (specID 268)
    [268] = archonEntry("Brewmaster Monk",
        { "Agility", "Critical Strike", "Versatility", "Mastery", "Haste" },
        "https://www.archon.gg/wow/builds/brewmaster/monk/raid/overview/heroic/all-bosses"),

    -- Mistweaver Monk (specID 270)
    [270] = archonEntry("Mistweaver Monk",
        { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/mistweaver/monk/raid/overview/heroic/all-bosses"),

    -- Windwalker Monk (specID 269)
    [269] = archonEntry("Windwalker Monk",
        { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/windwalker/monk/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Paladin
    -- =========================================================================

    -- Holy Paladin (specID 65)
    [65] = archonEntry("Holy Paladin",
        { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" },
        "https://www.archon.gg/wow/builds/holy/paladin/raid/overview/heroic/all-bosses"),

    -- Protection Paladin (specID 66)
    [66] = archonEntry("Protection Paladin",
        { "Strength", "Haste", "Critical Strike", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/protection/paladin/raid/overview/heroic/all-bosses"),

    -- Retribution Paladin (specID 70)
    [70] = archonEntry("Retribution Paladin",
        { "Strength", "Mastery", {"Critical Strike", "Haste"}, "Versatility" },
        "https://www.archon.gg/wow/builds/retribution/paladin/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Priest
    -- =========================================================================

    -- Discipline Priest (specID 256)
    [256] = archonEntry("Discipline Priest",
        { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/discipline/priest/raid/overview/heroic/all-bosses"),

    -- Holy Priest (specID 257)
    [257] = archonEntry("Holy Priest",
        { "Intellect", "Critical Strike", "Mastery", "Haste", "Versatility" },
        "https://www.archon.gg/wow/builds/holy/priest/raid/overview/heroic/all-bosses"),

    -- Shadow Priest (specID 258)
    [258] = archonEntry("Shadow Priest",
        { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" },
        "https://www.archon.gg/wow/builds/shadow/priest/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Rogue
    -- =========================================================================

    -- Assassination Rogue (specID 259)
    [259] = archonEntry("Assassination Rogue",
        { "Agility", "Critical Strike", "Haste", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/assassination/rogue/raid/overview/heroic/all-bosses"),

    -- Outlaw Rogue (specID 260)
    [260] = archonEntry("Outlaw Rogue",
        { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/outlaw/rogue/raid/overview/heroic/all-bosses"),

    -- Subtlety Rogue (specID 261)
    [261] = archonEntry("Subtlety Rogue",
        { "Agility", "Mastery", "Haste", "Critical Strike", "Versatility" },
        "https://www.archon.gg/wow/builds/subtlety/rogue/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Shaman
    -- =========================================================================

    -- Elemental Shaman (specID 262)
    [262] = archonEntry("Elemental Shaman",
        { "Intellect", "Mastery", "Critical Strike", "Haste", "Versatility" },
        "https://www.archon.gg/wow/builds/elemental/shaman/raid/overview/heroic/all-bosses"),

    -- Enhancement Shaman (specID 263)
    [263] = archonEntry("Enhancement Shaman",
        { "Agility", "Mastery", "Haste", "Critical Strike", "Versatility" },
        "https://www.archon.gg/wow/builds/enhancement/shaman/raid/overview/heroic/all-bosses"),

    -- Restoration Shaman (specID 264)
    [264] = archonEntry("Restoration Shaman",
        { "Intellect", "Critical Strike", "Mastery", "Haste", "Versatility" },
        "https://www.archon.gg/wow/builds/restoration/shaman/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Warlock
    -- =========================================================================

    -- Affliction Warlock (specID 265)
    [265] = archonEntry("Affliction Warlock",
        { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/affliction/warlock/raid/overview/heroic/all-bosses"),

    -- Demonology Warlock (specID 266)
    [266] = archonEntry("Demonology Warlock",
        { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/demonology/warlock/raid/overview/heroic/all-bosses"),

    -- Destruction Warlock (specID 267)
    [267] = archonEntry("Destruction Warlock",
        { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/destruction/warlock/raid/overview/heroic/all-bosses"),

    -- =========================================================================
    -- Warrior
    -- =========================================================================

    -- Arms Warrior (specID 71)
    [71] = archonEntry("Arms Warrior",
        { "Strength", "Critical Strike", "Haste", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/arms/warrior/raid/overview/heroic/all-bosses"),

    -- Fury Warrior (specID 72)
    [72] = archonEntry("Fury Warrior",
        { "Strength", "Mastery", "Haste", "Critical Strike", "Versatility" },
        "https://www.archon.gg/wow/builds/fury/warrior/raid/overview/heroic/all-bosses"),

    -- Protection Warrior (specID 73)
    [73] = archonEntry("Protection Warrior",
        { "Strength", "Haste", "Critical Strike", "Mastery", "Versatility" },
        "https://www.archon.gg/wow/builds/protection/warrior/raid/overview/heroic/all-bosses"),

}
