-- CouchPotato/Core/Specs.lua
-- Default ability button layouts for all 39 WoW specs (Patch 12.0.1)
-- Players can customize these via the settings UI; these are the defaults.

local CP = CouchPotato
local Specs = CP:NewModule("Specs")

-- specLayouts[classID][specIndex] = layout table
local specLayouts = {}

-- Helper to register a spec layout
local function DefineSpec(classID, specIndex, specName, layout)
    if not specLayouts[classID] then
        specLayouts[classID] = {}
    end
    layout.specName = specName
    layout.classID = classID
    layout.specIndex = specIndex
    specLayouts[classID][specIndex] = layout
end

-- ============================================================================
-- WARRIOR (classID = 1)
-- ============================================================================

DefineSpec(1, 1, "Arms", {
    primary     = "Mortal Strike",
    secondary   = "Overpower",
    tertiary    = "Colossus Smash",
    dpadUp      = "Sweeping Strikes",
    dpadDown    = "Execute",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Pummel",
    majorCD     = "Avatar",
    defensiveCD = "Die by the Sword",
    movement    = "Charge",
})

DefineSpec(1, 2, "Fury", {
    primary     = "Bloodthirst",
    secondary   = "Raging Blow",
    tertiary    = "Rampage",
    dpadUp      = "Whirlwind",
    dpadDown    = "Execute",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Pummel",
    majorCD     = "Recklessness",
    defensiveCD = "Enraged Regeneration",
    movement    = "Charge",
})

DefineSpec(1, 3, "Protection", {
    primary     = "Shield Slam",
    secondary   = "Thunder Clap",
    tertiary    = "Ignore Pain",
    dpadUp      = "Revenge",
    dpadDown    = "Execute",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Pummel",
    majorCD     = "Avatar",
    defensiveCD = "Shield Wall",
    movement    = "Charge",
})

-- ============================================================================
-- PALADIN (classID = 2)
-- ============================================================================

DefineSpec(2, 1, "Retribution", {
    primary     = "Crusader Strike",
    secondary   = "Judgment",
    tertiary    = "Templar's Verdict",
    dpadUp      = "Divine Storm",
    dpadDown    = "Wake of Ashes",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Rebuke",
    majorCD     = "Avenging Wrath",
    defensiveCD = "Divine Shield",
    movement    = "Divine Steed",
})

DefineSpec(2, 2, "Protection", {
    primary     = "Shield of the Righteous",
    secondary   = "Judgment",
    tertiary    = "Hammer of the Righteous",
    dpadUp      = "Consecration",
    dpadDown    = "Word of Glory",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Avenger's Shield",
    majorCD     = "Avenging Wrath",
    defensiveCD = "Ardent Defender",
    movement    = "Divine Steed",
})

DefineSpec(2, 3, "Holy", {
    primary     = "Holy Shock",
    secondary   = "Flash of Light",
    tertiary    = "Word of Glory",
    dpadUp      = "Light of Dawn",
    dpadDown    = "Crusader Strike",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Rebuke",
    majorCD     = "Avenging Wrath",
    defensiveCD = "Divine Shield",
    movement    = "Divine Steed",
})

-- ============================================================================
-- HUNTER (classID = 3)
-- ============================================================================

DefineSpec(3, 1, "Beast Mastery", {
    primary     = "Kill Command",
    secondary   = "Barbed Shot",
    tertiary    = "Cobra Shot",
    dpadUp      = "Multi-Shot",
    dpadDown    = "Kill Shot",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Counter Shot",
    majorCD     = "Bestial Wrath",
    defensiveCD = "Survival of the Fittest",
    movement    = "Disengage",
})

DefineSpec(3, 2, "Marksmanship", {
    primary     = "Aimed Shot",
    secondary   = "Arcane Shot",
    tertiary    = "Rapid Fire",
    dpadUp      = "Multi-Shot",
    dpadDown    = "Kill Shot",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Counter Shot",
    majorCD     = "Trueshot",
    defensiveCD = "Exhilaration",
    movement    = "Disengage",
})

DefineSpec(3, 3, "Survival", {
    primary     = "Kill Command",
    secondary   = "Raptor Strike",
    tertiary    = "Wildfire Bomb",
    dpadUp      = "Carve",
    dpadDown    = "Kill Shot",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Muzzle",
    majorCD     = "Coordinated Assault",
    defensiveCD = "Exhilaration",
    movement    = "Disengage",
})

-- ============================================================================
-- ROGUE (classID = 4)
-- ============================================================================

DefineSpec(4, 1, "Assassination", {
    primary     = "Mutilate",
    secondary   = "Envenom",
    tertiary    = "Rupture",
    dpadUp      = "Fan of Knives",
    dpadDown    = "Garrote",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Kick",
    majorCD     = "Deathmark",
    defensiveCD = "Evasion",
    movement    = "Sprint",
})

DefineSpec(4, 2, "Outlaw", {
    primary     = "Sinister Strike",
    secondary   = "Between the Eyes",
    tertiary    = "Roll the Bones",
    dpadUp      = "Blade Flurry",
    dpadDown    = "Dispatch",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Kick",
    majorCD     = "Adrenaline Rush",
    defensiveCD = "Evasion",
    movement    = "Sprint",
})

DefineSpec(4, 3, "Subtlety", {
    primary     = "Shadowstrike",
    secondary   = "Eviscerate",
    tertiary    = "Shadow Dance",
    dpadUp      = "Shuriken Storm",
    dpadDown    = "Symbols of Death",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Kick",
    majorCD     = "Shadow Dance",
    defensiveCD = "Evasion",
    movement    = "Shadowstep",
})

-- ============================================================================
-- PRIEST (classID = 5)
-- ============================================================================

DefineSpec(5, 1, "Discipline", {
    primary     = "Penance",
    secondary   = "Power Word: Shield",
    tertiary    = "Atonement",
    dpadUp      = "Spirit Shell",
    dpadDown    = "Mind Blast",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Purify",
    majorCD     = "Evangelism",
    defensiveCD = "Pain Suppression",
    movement    = "Angelic Feather",
})

DefineSpec(5, 2, "Holy", {
    primary     = "Flash Heal",
    secondary   = "Heal",
    tertiary    = "Holy Word: Serenity",
    dpadUp      = "Holy Word: Sanctify",
    dpadDown    = "Prayer of Mending",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Purify",
    majorCD     = "Apotheosis",
    defensiveCD = "Guardian Spirit",
    movement    = "Angelic Feather",
})

DefineSpec(5, 3, "Shadow", {
    primary     = "Mind Blast",
    secondary   = "Vampiric Touch",
    tertiary    = "Shadow Word: Pain",
    dpadUp      = "Void Eruption",
    dpadDown    = "Devouring Plague",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Silence",
    majorCD     = "Dark Ascension",
    defensiveCD = "Dispersion",
    movement    = "Fade",
})

-- ============================================================================
-- DEATH KNIGHT (classID = 6)
-- ============================================================================

DefineSpec(6, 1, "Blood", {
    primary     = "Heart Strike",
    secondary   = "Blood Boil",
    tertiary    = "Death Strike",
    dpadUp      = "Death and Decay",
    dpadDown    = "Bone Shield",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Mind Freeze",
    majorCD     = "Empower Rune Weapon",
    defensiveCD = "Vampiric Blood",
    movement    = "Death's Advance",
})

DefineSpec(6, 2, "Frost", {
    primary     = "Obliterate",
    secondary   = "Frost Strike",
    tertiary    = "Howling Blast",
    dpadUp      = "Remorseless Winter",
    dpadDown    = "Pillar of Frost",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Mind Freeze",
    majorCD     = "Pillar of Frost",
    defensiveCD = "Icebound Fortitude",
    movement    = "Wraith Walk",
})

DefineSpec(6, 3, "Unholy", {
    primary     = "Festering Strike",
    secondary   = "Scourge Strike",
    tertiary    = "Death Coil",
    dpadUp      = "Epidemic",
    dpadDown    = "Apocalypse",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Mind Freeze",
    majorCD     = "Dark Transformation",
    defensiveCD = "Anti-Magic Shell",
    movement    = "Wraith Walk",
})

-- ============================================================================
-- SHAMAN (classID = 7)
-- ============================================================================

DefineSpec(7, 1, "Elemental", {
    primary     = "Lava Burst",
    secondary   = "Earth Shock",
    tertiary    = "Lightning Bolt",
    dpadUp      = "Chain Lightning",
    dpadDown    = "Flame Shock",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Wind Shear",
    majorCD     = "Stormkeeper",
    defensiveCD = "Astral Shift",
    movement    = "Gust of Wind",
})

DefineSpec(7, 2, "Enhancement", {
    primary     = "Stormstrike",
    secondary   = "Lava Lash",
    tertiary    = "Lightning Bolt",
    dpadUp      = "Chain Lightning",
    dpadDown    = "Flame Shock",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Wind Shear",
    majorCD     = "Feral Spirit",
    defensiveCD = "Astral Shift",
    movement    = "Gust of Wind",
})

DefineSpec(7, 3, "Restoration", {
    primary     = "Riptide",
    secondary   = "Chain Heal",
    tertiary    = "Healing Wave",
    dpadUp      = "Healing Rain",
    dpadDown    = "Healing Surge",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Wind Shear",
    majorCD     = "Healing Tide Totem",
    defensiveCD = "Spirit Link Totem",
    movement    = "Gust of Wind",
})

-- ============================================================================
-- MAGE (classID = 8)
-- ============================================================================

DefineSpec(8, 1, "Arcane", {
    primary     = "Arcane Blast",
    secondary   = "Arcane Barrage",
    tertiary    = "Arcane Missiles",
    dpadUp      = "Arcane Explosion",
    dpadDown    = "Arcane Surge",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Counterspell",
    majorCD     = "Touch of the Magi",
    defensiveCD = "Ice Block",
    movement    = "Shimmer",
})

DefineSpec(8, 2, "Fire", {
    primary     = "Fireball",
    secondary   = "Pyroblast",
    tertiary    = "Fire Blast",
    dpadUp      = "Flamestrike",
    dpadDown    = "Phoenix Flames",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Counterspell",
    majorCD     = "Combustion",
    defensiveCD = "Ice Block",
    movement    = "Shimmer",
})

DefineSpec(8, 3, "Frost", {
    primary     = "Frostbolt",
    secondary   = "Ice Lance",
    tertiary    = "Frozen Orb",
    dpadUp      = "Blizzard",
    dpadDown    = "Ice Lance",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Counterspell",
    majorCD     = "Icy Veins",
    defensiveCD = "Ice Block",
    movement    = "Shimmer",
})

-- ============================================================================
-- WARLOCK (classID = 9)
-- ============================================================================

DefineSpec(9, 1, "Affliction", {
    primary     = "Unstable Affliction",
    secondary   = "Malefic Rapture",
    tertiary    = "Agony",
    dpadUp      = "Seed of Corruption",
    dpadDown    = "Corruption",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Spell Lock",
    majorCD     = "Summon Darkglare",
    defensiveCD = "Unending Resolve",
    movement    = "Demonic Circle",
})

DefineSpec(9, 2, "Demonology", {
    primary     = "Shadow Bolt",
    secondary   = "Call Dreadstalkers",
    tertiary    = "Hand of Gul'dan",
    dpadUp      = "Implosion",
    dpadDown    = "Summon Demonic Tyrant",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Spell Lock",
    majorCD     = "Summon Demonic Tyrant",
    defensiveCD = "Unending Resolve",
    movement    = "Demonic Circle",
})

DefineSpec(9, 3, "Destruction", {
    primary     = "Incinerate",
    secondary   = "Chaos Bolt",
    tertiary    = "Immolate",
    dpadUp      = "Rain of Fire",
    dpadDown    = "Conflagrate",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Spell Lock",
    majorCD     = "Summon Infernal",
    defensiveCD = "Unending Resolve",
    movement    = "Demonic Circle",
})

-- ============================================================================
-- MONK (classID = 10)
-- ============================================================================

DefineSpec(10, 1, "Windwalker", {
    primary     = "Tiger Palm",
    secondary   = "Blackout Kick",
    tertiary    = "Rising Sun Kick",
    dpadUp      = "Fists of Fury",
    dpadDown    = "Strike of the Windlord",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Spear Hand Strike",
    majorCD     = "Storm, Earth, and Fire",
    defensiveCD = "Touch of Karma",
    movement    = "Roll",
})

DefineSpec(10, 2, "Brewmaster", {
    primary     = "Keg Smash",
    secondary   = "Blackout Kick",
    tertiary    = "Breath of Fire",
    dpadUp      = "Spinning Crane Kick",
    dpadDown    = "Purifying Brew",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Spear Hand Strike",
    majorCD     = "Invoke Niuzao, the Black Ox",
    defensiveCD = "Celestial Brew",
    movement    = "Roll",
})

DefineSpec(10, 3, "Mistweaver", {
    primary     = "Renewing Mist",
    secondary   = "Vivify",
    tertiary    = "Enveloping Mist",
    dpadUp      = "Sheilun's Gift",
    dpadDown    = "Rising Sun Kick",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Spear Hand Strike",
    majorCD     = "Invoke Yu'lon, the Jade Serpent",
    defensiveCD = "Life Cocoon",
    movement    = "Roll",
})

-- ============================================================================
-- DRUID (classID = 11)
-- ============================================================================

DefineSpec(11, 1, "Balance", {
    primary     = "Starsurge",
    secondary   = "Wrath",
    tertiary    = "Starfall",
    dpadUp      = "Sunfire",
    dpadDown    = "Celestial Alignment",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Typhoon",
    majorCD     = "Incarnation: Chosen of Elune",
    defensiveCD = "Barkskin",
    movement    = "Wild Charge",
})

DefineSpec(11, 2, "Feral", {
    primary     = "Rake",
    secondary   = "Shred",
    tertiary    = "Rip",
    dpadUp      = "Swipe",
    dpadDown    = "Ferocious Bite",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Skull Bash",
    majorCD     = "Berserk",
    defensiveCD = "Survival Instincts",
    movement    = "Wild Charge",
})

DefineSpec(11, 3, "Guardian", {
    primary     = "Mangle",
    secondary   = "Thrash",
    tertiary    = "Ironfur",
    dpadUp      = "Maul",
    dpadDown    = "Frenzied Regeneration",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Skull Bash",
    majorCD     = "Berserk",
    defensiveCD = "Barkskin",
    movement    = "Wild Charge",
})

DefineSpec(11, 4, "Restoration", {
    primary     = "Regrowth",
    secondary   = "Wild Growth",
    tertiary    = "Swiftmend",
    dpadUp      = "Rejuvenation",
    dpadDown    = "Tranquility",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Cyclone",
    majorCD     = "Flourish",
    defensiveCD = "Barkskin",
    movement    = "Wild Charge",
})

-- ============================================================================
-- DEMON HUNTER (classID = 12)
-- ============================================================================

DefineSpec(12, 1, "Havoc", {
    primary     = "Chaos Strike",
    secondary   = "Blade Dance",
    tertiary    = "Eye Beam",
    dpadUp      = "Fel Rush",
    dpadDown    = "Metamorphosis",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Consume Magic",
    majorCD     = "Metamorphosis",
    defensiveCD = "Blur",
    movement    = "Vengeful Retreat",
})

DefineSpec(12, 2, "Vengeance", {
    primary     = "Shear",
    secondary   = "Soul Cleave",
    tertiary    = "Sigil of Flame",
    dpadUp      = "Fel Devastation",
    dpadDown    = "Fiery Brand",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Consume Magic",
    majorCD     = "Metamorphosis",
    defensiveCD = "Demon Spikes",
    movement    = "Fel Rush",
})

-- ============================================================================
-- EVOKER (classID = 13)
-- ============================================================================

DefineSpec(13, 1, "Devastation", {
    primary     = "Disintegrate",
    secondary   = "Eternity Surge",
    tertiary    = "Fire Breath",
    dpadUp      = "Shattering Star",
    dpadDown    = "Living Flame",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Quell",
    majorCD     = "Dragonrage",
    defensiveCD = "Obsidian Scales",
    movement    = "Hover",
})

DefineSpec(13, 2, "Preservation", {
    primary     = "Spiritbloom",
    secondary   = "Dream Breath",
    tertiary    = "Emerald Blossom",
    dpadUp      = "Reversion",
    dpadDown    = "Living Flame",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Quell",
    majorCD     = "Rewind",
    defensiveCD = "Renewing Blaze",
    movement    = "Hover",
})

DefineSpec(13, 3, "Augmentation", {
    primary     = "Ebon Might",
    secondary   = "Prescience",
    tertiary    = "Eruption",
    dpadUp      = "Breath of Eons",
    dpadDown    = "Living Flame",
    dpadLeft    = nil,
    dpadRight   = nil,
    interrupt   = "Quell",
    majorCD     = "Breath of Eons",
    defensiveCD = "Obsidian Scales",
    movement    = "Hover",
})

-- ============================================================================
-- MODULE FUNCTIONS
-- ============================================================================

function Specs:OnEnable()
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
end

function Specs:GetCurrentLayout()
    local specIndex = GetSpecialization()
    local classID = select(1, UnitClass("player"))
    
    if not specIndex or not classID then return nil end
    
    return specLayouts[classID] and specLayouts[classID][specIndex]
end

function Specs:GetLayoutForSpec(classID, specIndex)
    return specLayouts[classID] and specLayouts[classID][specIndex]
end

function Specs:GetAllLayouts()
    return specLayouts
end

function Specs:OnSpecChanged()
    -- Reapply bindings for new spec
    local Bindings = CP:GetModule("Bindings", true)
    if Bindings and C_GamePad.IsEnabled() then
        Bindings:ApplyControllerBindings()
    end
    
    -- Update LED for new spec's class color
    local LED = CP:GetModule("LED", true)
    if LED then
        LED:UpdateForCurrentSpec()
    end
end
