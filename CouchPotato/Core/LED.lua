-- CouchPotato/Core/LED.lua
-- DualSense LED color management by spell school
-- Uses C_GamePad.SetLedColor(ColorMixin) - DualSense/DualShock only
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local LED = CP:NewModule("LED")
local band = bit.band

-- Spell school bit flags (WoW)
-- 1   = Physical (silver/white)
-- 2   = Holy (golden yellow)
-- 4   = Fire (orange-red)
-- 8   = Nature (green)
-- 16  = Frost (ice blue)
-- 32  = Shadow (deep purple)
-- 64  = Arcane (magenta/pink)

local SCHOOL_COLORS = {
    [1]  = { r = 0.85, g = 0.85, b = 0.85 },  -- Physical: silver
    [2]  = { r = 1.00, g = 0.92, b = 0.00 },  -- Holy: gold
    [4]  = { r = 1.00, g = 0.30, b = 0.00 },  -- Fire: orange-red
    [8]  = { r = 0.10, g = 0.80, b = 0.10 },  -- Nature: green
    [16] = { r = 0.20, g = 0.70, b = 1.00 },  -- Frost: ice blue
    [32] = { r = 0.55, g = 0.00, b = 0.85 },  -- Shadow: purple
    [64] = { r = 0.95, g = 0.20, b = 0.95 },  -- Arcane: magenta
}

-- Default color when no spell context: dim white
local DEFAULT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

function LED:OnEnable()
    -- Set default color
    self:SetColor(DEFAULT_COLOR.r, DEFAULT_COLOR.g, DEFAULT_COLOR.b)
end

function LED:OnDisable()
    self:ClearColor()
end

-- Set LED color
function LED:SetColor(r, g, b)
    if not CP.db.profile.ledEnabled then return end
    if not C_GamePad.IsEnabled() then return end
    
    local color = CreateColor(r, g, b)
    C_GamePad.SetLedColor(color)
    self.currentColor = { r = r, g = g, b = b }
end

-- Clear LED color
function LED:ClearColor()
    C_GamePad.ClearLedColor()
    self.currentColor = nil
end

-- Get primary school from school mask (lowest set bit)
function LED:GetSchoolFromMask(schoolMask)
    if schoolMask <= 0 then return 1 end  -- default Physical
    
    local bit = 1
    while bit <= 64 do
        if band(schoolMask, bit) > 0 then
            return bit
        end
        bit = bit * 2
    end
    
    return 1
end

-- Set color based on spell school mask
function LED:SetColorForSchool(schoolMask)
    local school = self:GetSchoolFromMask(schoolMask)
    local color = SCHOOL_COLORS[school] or DEFAULT_COLOR
    self:SetColor(color.r, color.g, color.b)
end

-- Set color based on spell ID
function LED:SetColorForSpell(spellID)
    -- Try new API first (Patch 10.0+)
    if C_Spell and C_Spell.GetSpellInfo then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and spellInfo.schoolMask then
            self:SetColorForSchool(spellInfo.schoolMask)
            return
        end
    end
    
    -- Fallback to older API
    local name, _, _, _, _, _, schoolMask = GetSpellInfo(spellID)
    if schoolMask then
        self:SetColorForSchool(schoolMask)
    end
end

-- Update LED to class color
function LED:UpdateForCurrentSpec()
    local _, className = UnitClass("player")
    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[className]
    
    if classColor then
        self:SetColor(classColor.r, classColor.g, classColor.b)
    else
        self:SetColor(DEFAULT_COLOR.r, DEFAULT_COLOR.g, DEFAULT_COLOR.b)
    end
end
