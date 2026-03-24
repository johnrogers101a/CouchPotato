-- StatPriorityData.lua
-- Stat priority data for all retail specializations.
-- Keyed by specID (integer).
-- Sources: Wowhead, Icy Veins, and Method — all three researched per-spec.
-- Each entry:
--   specName  — display name
--   stats     — unified default (Wowhead canonical)
--   wowhead   — Wowhead stat priority array
--   icyveins  — Icy Veins stat priority array
--   method    — Method (method.gg) stat priority array
--   urls      — { wowhead, icyveins, method } source guide URLs
--   _differs  — true if any source array differs from the others
--   _source   — "wowhead,icyveins,method"
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

StatPriorityData = {

    -- =========================================================================
    -- Death Knight
    -- =========================================================================

    -- Blood Death Knight (specID 250)
    [250] = (function()
        local wh = { "Strength", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local iv = { "Strength", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local mt = { "Strength", "Haste", "Mastery", "Critical Strike", "Versatility" }
        return {
            specName = "Blood Death Knight",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/death-knight/blood/stat-priority-pve-tank",
                icyveins = "https://www.icy-veins.com/wow/blood-death-knight-pve-tank-stat-priority",
                method   = "https://www.method.gg/guides/death-knight/blood/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Frost Death Knight (specID 251)
    [251] = (function()
        local wh = { "Strength", "Critical Strike", "Mastery", "Haste", "Versatility" }
        local iv = { "Strength", "Critical Strike", "Haste", "Mastery", "Versatility" }
        local mt = { "Strength", "Critical Strike", "Mastery", "Haste", "Versatility" }
        return {
            specName = "Frost Death Knight",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/death-knight/frost/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/frost-death-knight-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/death-knight/frost/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Unholy Death Knight (specID 252)
    [252] = (function()
        local wh = { "Strength", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local iv = { "Strength", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local mt = { "Strength", "Haste", "Mastery", "Critical Strike", "Versatility" }
        return {
            specName = "Unholy Death Knight",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/death-knight/unholy/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/unholy-death-knight-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/death-knight/unholy/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Demon Hunter
    -- =========================================================================

    -- Havoc Demon Hunter (specID 577)
    [577] = (function()
        local wh = { "Agility", "Critical Strike", "Versatility", "Haste", "Mastery" }
        local iv = { "Agility", "Versatility", "Critical Strike", "Haste", "Mastery" }
        local mt = { "Agility", "Critical Strike", "Versatility", "Haste", "Mastery" }
        return {
            specName = "Havoc Demon Hunter",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/demon-hunter/havoc/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/havoc-demon-hunter-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/demon-hunter/havoc/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Vengeance Demon Hunter (specID 581)
    [581] = (function()
        local wh = { "Agility", "Haste", "Versatility", "Critical Strike", "Mastery" }
        local iv = { "Agility", "Haste", "Versatility", "Critical Strike", "Mastery" }
        local mt = { "Agility", "Versatility", "Haste", "Critical Strike", "Mastery" }
        return {
            specName = "Vengeance Demon Hunter",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/demon-hunter/vengeance/stat-priority-pve-tank",
                icyveins = "https://www.icy-veins.com/wow/vengeance-demon-hunter-pve-tank-stat-priority",
                method   = "https://www.method.gg/guides/demon-hunter/vengeance/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Druid
    -- =========================================================================

    -- Balance Druid (specID 102)
    [102] = (function()
        local wh = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local iv = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local mt = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        return {
            specName = "Balance Druid",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/druid/balance/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/balance-druid-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/druid/balance/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Feral Druid (specID 103)
    [103] = (function()
        local wh = { "Agility", "Critical Strike", "Haste", "Mastery", "Versatility" }
        local iv = { "Agility", "Critical Strike", "Haste", "Mastery", "Versatility" }
        local mt = { "Agility", "Critical Strike", "Haste", "Mastery", "Versatility" }
        return {
            specName = "Feral Druid",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/druid/feral/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/feral-druid-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/druid/feral/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Guardian Druid (specID 104)
    [104] = (function()
        local wh = { "Agility", "Versatility", "Mastery", "Haste", "Critical Strike" }
        local iv = { "Agility", "Mastery", "Versatility", "Haste", "Critical Strike" }
        local mt = { "Agility", "Versatility", "Mastery", "Haste", "Critical Strike" }
        return {
            specName = "Guardian Druid",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/druid/guardian/stat-priority-pve-tank",
                icyveins = "https://www.icy-veins.com/wow/guardian-druid-pve-tank-stat-priority",
                method   = "https://www.method.gg/guides/druid/guardian/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Restoration Druid (specID 105)
    [105] = (function()
        local wh = { "Intellect", "Haste", "Mastery", "Versatility", "Critical Strike" }
        local iv = { "Intellect", "Haste", "Mastery", "Versatility", "Critical Strike" }
        local mt = { "Intellect", "Haste", "Mastery", "Versatility", "Critical Strike" }
        return {
            specName = "Restoration Druid",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/druid/restoration/stat-priority-pve-healer",
                icyveins = "https://www.icy-veins.com/wow/restoration-druid-pve-healer-stat-priority",
                method   = "https://www.method.gg/guides/druid/restoration/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Evoker
    -- =========================================================================

    -- Devastation Evoker (specID 1467)
    [1467] = (function()
        local wh = { "Intellect", "Mastery", "Critical Strike", "Haste", "Versatility" }
        local iv = { "Intellect", "Critical Strike", "Mastery", "Haste", "Versatility" }
        local mt = { "Intellect", "Mastery", "Critical Strike", "Haste", "Versatility" }
        return {
            specName = "Devastation Evoker",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/evoker/devastation/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/devastation-evoker-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/evoker/devastation/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Preservation Evoker (specID 1468)
    [1468] = (function()
        local wh = { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" }
        local iv = { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" }
        local mt = { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" }
        return {
            specName = "Preservation Evoker",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/evoker/preservation/stat-priority-pve-healer",
                icyveins = "https://www.icy-veins.com/wow/preservation-evoker-pve-healer-stat-priority",
                method   = "https://www.method.gg/guides/evoker/preservation/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Augmentation Evoker (specID 1473)
    [1473] = (function()
        local wh = { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" }
        local iv = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local mt = { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" }
        return {
            specName = "Augmentation Evoker",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/evoker/augmentation/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/augmentation-evoker-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/evoker/augmentation/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Hunter
    -- =========================================================================

    -- Beast Mastery Hunter (specID 253)
    [253] = (function()
        local wh = { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local iv = { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local mt = { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" }
        return {
            specName = "Beast Mastery Hunter",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/hunter/beast-mastery/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/beast-mastery-hunter-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/hunter/beast-mastery/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Marksmanship Hunter (specID 254)
    [254] = (function()
        local wh = { "Agility", "Mastery", "Critical Strike", "Haste", "Versatility" }
        local iv = { "Agility", "Critical Strike", "Mastery", "Haste", "Versatility" }
        local mt = { "Agility", "Mastery", "Critical Strike", "Haste", "Versatility" }
        return {
            specName = "Marksmanship Hunter",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/hunter/marksmanship/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/marksmanship-hunter-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/hunter/marksmanship/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Survival Hunter (specID 255)
    [255] = (function()
        local wh = { "Agility", "Haste", "Critical Strike", "Versatility", "Mastery" }
        local iv = { "Agility", "Haste", "Versatility", "Critical Strike", "Mastery" }
        local mt = { "Agility", "Haste", "Critical Strike", "Versatility", "Mastery" }
        return {
            specName = "Survival Hunter",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/hunter/survival/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/survival-hunter-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/hunter/survival/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Mage
    -- =========================================================================

    -- Arcane Mage (specID 62)
    [62] = (function()
        local wh = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local iv = { "Intellect", "Mastery", "Haste", "Critical Strike", "Versatility" }
        local mt = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        return {
            specName = "Arcane Mage",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/mage/arcane/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/arcane-mage-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/mage/arcane/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Fire Mage (specID 63)
    [63] = (function()
        local wh = { "Intellect", "Critical Strike", "Mastery", "Versatility", "Haste" }
        local iv = { "Intellect", "Critical Strike", "Mastery", "Haste", "Versatility" }
        local mt = { "Intellect", "Critical Strike", "Mastery", "Versatility", "Haste" }
        return {
            specName = "Fire Mage",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/mage/fire/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/fire-mage-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/mage/fire/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Frost Mage (specID 64)
    [64] = (function()
        local wh = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local iv = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local mt = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        return {
            specName = "Frost Mage",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/mage/frost/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/frost-mage-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/mage/frost/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Monk
    -- =========================================================================

    -- Brewmaster Monk (specID 268)
    [268] = (function()
        local wh = { "Agility", "Critical Strike", "Haste", "Mastery", "Versatility" }
        local iv = { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local mt = { "Agility", "Critical Strike", "Haste", "Mastery", "Versatility" }
        return {
            specName = "Brewmaster Monk",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/monk/brewmaster/stat-priority-pve-tank",
                icyveins = "https://www.icy-veins.com/wow/brewmaster-monk-pve-tank-stat-priority",
                method   = "https://www.method.gg/guides/monk/brewmaster/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Mistweaver Monk (specID 270)
    [270] = (function()
        local wh = { "Intellect", "Critical Strike", "Versatility", "Haste", "Mastery" }
        local iv = { "Intellect", "Versatility", "Critical Strike", "Haste", "Mastery" }
        local mt = { "Intellect", "Critical Strike", "Versatility", "Haste", "Mastery" }
        return {
            specName = "Mistweaver Monk",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/monk/mistweaver/stat-priority-pve-healer",
                icyveins = "https://www.icy-veins.com/wow/mistweaver-monk-pve-healer-stat-priority",
                method   = "https://www.method.gg/guides/monk/mistweaver/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Windwalker Monk (specID 269)
    [269] = (function()
        local wh = { "Agility", "Critical Strike", "Versatility", "Mastery", "Haste" }
        local iv = { "Agility", "Versatility", "Critical Strike", "Mastery", "Haste" }
        local mt = { "Agility", "Critical Strike", "Versatility", "Mastery", "Haste" }
        return {
            specName = "Windwalker Monk",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/monk/windwalker/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/windwalker-monk-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/monk/windwalker/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Paladin
    -- =========================================================================

    -- Holy Paladin (specID 65)
    -- Haste and Critical Strike are equal priority per reference sources.
    [65] = (function()
        local wh = { "Intellect", "Mastery", {"Haste", "Critical Strike"}, "Versatility" }
        local iv = { "Intellect", "Mastery", {"Haste", "Critical Strike"}, "Versatility" }
        local mt = { "Intellect", "Mastery", {"Haste", "Critical Strike"}, "Versatility" }
        return {
            specName = "Holy Paladin",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/paladin/holy/stat-priority-pve-healer",
                icyveins = "https://www.icy-veins.com/wow/holy-paladin-pve-healer-stat-priority",
                method   = "https://www.method.gg/guides/paladin/holy/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Protection Paladin (specID 66)
    [66] = (function()
        local wh = { "Strength", "Haste", "Versatility", "Mastery", "Critical Strike" }
        local iv = { "Strength", "Haste", "Versatility", "Mastery", "Critical Strike" }
        local mt = { "Strength", "Haste", "Versatility", "Mastery", "Critical Strike" }
        return {
            specName = "Protection Paladin",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/paladin/protection/stat-priority-pve-tank",
                icyveins = "https://www.icy-veins.com/wow/protection-paladin-pve-tank-stat-priority",
                method   = "https://www.method.gg/guides/paladin/protection/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Retribution Paladin (specID 70)
    [70] = (function()
        local wh = { "Strength", "Haste", "Critical Strike", "Versatility", "Mastery" }
        local iv = { "Strength", "Haste", "Versatility", "Critical Strike", "Mastery" }
        local mt = { "Strength", "Haste", "Critical Strike", "Versatility", "Mastery" }
        return {
            specName = "Retribution Paladin",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/paladin/retribution/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/retribution-paladin-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/paladin/retribution/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Priest
    -- =========================================================================

    -- Discipline Priest (specID 256)
    [256] = (function()
        local wh = { "Intellect", "Haste", "Critical Strike", "Versatility", "Mastery" }
        local iv = { "Intellect", "Haste", "Critical Strike", "Versatility", "Mastery" }
        local mt = { "Intellect", "Haste", "Critical Strike", "Versatility", "Mastery" }
        return {
            specName = "Discipline Priest",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/priest/discipline/stat-priority-pve-healer",
                icyveins = "https://www.icy-veins.com/wow/discipline-priest-pve-healer-stat-priority",
                method   = "https://www.method.gg/guides/priest/discipline/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Holy Priest (specID 257)
    [257] = (function()
        local wh = { "Intellect", "Critical Strike", "Haste", "Versatility", "Mastery" }
        local iv = { "Intellect", "Haste", "Critical Strike", "Versatility", "Mastery" }
        local mt = { "Intellect", "Critical Strike", "Haste", "Versatility", "Mastery" }
        return {
            specName = "Holy Priest",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/priest/holy/stat-priority-pve-healer",
                icyveins = "https://www.icy-veins.com/wow/holy-priest-pve-healer-stat-priority",
                method   = "https://www.method.gg/guides/priest/holy/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Shadow Priest (specID 258)
    [258] = (function()
        local wh = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local iv = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local mt = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        return {
            specName = "Shadow Priest",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/priest/shadow/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/shadow-priest-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/priest/shadow/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Rogue
    -- =========================================================================

    -- Assassination Rogue (specID 259)
    [259] = (function()
        local wh = { "Agility", "Critical Strike", "Haste", "Versatility", "Mastery" }
        local iv = { "Agility", "Haste", "Critical Strike", "Versatility", "Mastery" }
        local mt = { "Agility", "Critical Strike", "Haste", "Versatility", "Mastery" }
        return {
            specName = "Assassination Rogue",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/rogue/assassination/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/assassination-rogue-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/rogue/assassination/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Outlaw Rogue (specID 260)
    [260] = (function()
        local wh = { "Agility", "Haste", "Critical Strike", "Versatility", "Mastery" }
        local iv = { "Agility", "Haste", "Critical Strike", "Versatility", "Mastery" }
        local mt = { "Agility", "Haste", "Critical Strike", "Versatility", "Mastery" }
        return {
            specName = "Outlaw Rogue",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/rogue/outlaw/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/outlaw-rogue-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/rogue/outlaw/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Subtlety Rogue (specID 261)
    [261] = (function()
        local wh = { "Agility", "Versatility", "Critical Strike", "Haste", "Mastery" }
        local iv = { "Agility", "Critical Strike", "Versatility", "Haste", "Mastery" }
        local mt = { "Agility", "Versatility", "Critical Strike", "Haste", "Mastery" }
        return {
            specName = "Subtlety Rogue",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/rogue/subtlety/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/subtlety-rogue-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/rogue/subtlety/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Shaman
    -- =========================================================================

    -- Elemental Shaman (specID 262)
    [262] = (function()
        local wh = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local iv = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local mt = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        return {
            specName = "Elemental Shaman",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/shaman/elemental/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/elemental-shaman-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/shaman/elemental/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Enhancement Shaman (specID 263)
    [263] = (function()
        local wh = { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local iv = { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local mt = { "Agility", "Haste", "Critical Strike", "Mastery", "Versatility" }
        return {
            specName = "Enhancement Shaman",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/shaman/enhancement/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/enhancement-shaman-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/shaman/enhancement/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Restoration Shaman (specID 264)
    [264] = (function()
        local wh = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local iv = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local mt = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        return {
            specName = "Restoration Shaman",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/shaman/restoration/stat-priority-pve-healer",
                icyveins = "https://www.icy-veins.com/wow/restoration-shaman-pve-healer-stat-priority",
                method   = "https://www.method.gg/guides/shaman/restoration/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Warlock
    -- =========================================================================

    -- Affliction Warlock (specID 265)
    [265] = (function()
        local wh = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local iv = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        local mt = { "Intellect", "Haste", "Mastery", "Critical Strike", "Versatility" }
        return {
            specName = "Affliction Warlock",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/warlock/affliction/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/affliction-warlock-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/warlock/affliction/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Demonology Warlock (specID 266)
    [266] = (function()
        local wh = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local iv = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local mt = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        return {
            specName = "Demonology Warlock",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/warlock/demonology/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/demonology-warlock-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/warlock/demonology/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Destruction Warlock (specID 267)
    [267] = (function()
        local wh = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        local iv = { "Intellect", "Critical Strike", "Haste", "Mastery", "Versatility" }
        local mt = { "Intellect", "Haste", "Critical Strike", "Mastery", "Versatility" }
        return {
            specName = "Destruction Warlock",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/warlock/destruction/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/destruction-warlock-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/warlock/destruction/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- =========================================================================
    -- Warrior
    -- =========================================================================

    -- Arms Warrior (specID 71)
    [71] = (function()
        local wh = { "Strength", "Critical Strike", "Haste", "Versatility", "Mastery" }
        local iv = { "Strength", "Critical Strike", "Haste", "Mastery", "Versatility" }
        local mt = { "Strength", "Critical Strike", "Haste", "Versatility", "Mastery" }
        return {
            specName = "Arms Warrior",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/warrior/arms/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/arms-warrior-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/warrior/arms/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Fury Warrior (specID 72)
    [72] = (function()
        local wh = { "Strength", "Critical Strike", "Haste", "Mastery", "Versatility" }
        local iv = { "Strength", "Critical Strike", "Haste", "Mastery", "Versatility" }
        local mt = { "Strength", "Haste", "Critical Strike", "Mastery", "Versatility" }
        return {
            specName = "Fury Warrior",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/warrior/fury/stat-priority-pve-dps",
                icyveins = "https://www.icy-veins.com/wow/fury-warrior-pve-dps-stat-priority",
                method   = "https://www.method.gg/guides/warrior/fury/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

    -- Protection Warrior (specID 73)
    [73] = (function()
        local wh = { "Strength", "Haste", "Mastery", "Versatility", "Critical Strike" }
        local iv = { "Strength", "Haste", "Mastery", "Versatility", "Critical Strike" }
        local mt = { "Strength", "Haste", "Mastery", "Versatility", "Critical Strike" }
        return {
            specName = "Protection Warrior",
            stats    = wh,
            wowhead  = wh,
            icyveins = iv,
            method   = mt,
            urls     = {
                wowhead  = "https://www.wowhead.com/guide/classes/warrior/protection/stat-priority-pve-tank",
                icyveins = "https://www.icy-veins.com/wow/protection-warrior-pve-tank-stat-priority",
                method   = "https://www.method.gg/guides/warrior/protection/stats",
            },
            _differs = anyDiffers(wh, iv, mt),
            _source  = "wowhead,icyveins,method",
        }
    end)(),

}
