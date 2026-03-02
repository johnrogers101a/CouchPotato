-- CouchPotato/UI/HUD.lua
-- Controller-optimized HUD: cast bar, target info, resource display
-- Designed for "couch distance" readability — large, clear, minimal
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local HUD = CP:NewModule("HUD")

HUD.frames = {}   -- all created frames

function HUD:OnEnable()
    self:CreateFrames()
    self:RegisterEvent("UNIT_HEALTH", "OnHealthUpdate")
    self:RegisterEvent("UNIT_POWER_UPDATE", "OnPowerUpdate")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("UNIT_SPELLCAST_START", "OnSpellCastStart")
    self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnSpellCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "OnChannelStart")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnChannelStop")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED", "OnSpellCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnSpellCastStop")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
end

function HUD:CreateFrames()
    -- Container frame
    local container = CreateFrame("Frame", "CouchPotatoHUD", UIParent)
    container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    container:SetSize(800, 600)
    self.frames.container = container
    
    -- Player health bar (bottom left)
    self:CreatePlayerHealth()
    
    -- Player power bar (bottom left, under health)
    self:CreatePlayerPower()
    
    -- Cast bar (bottom center)
    self:CreateCastBar()
    
    -- Target display (top center)
    self:CreateTargetFrame()
    
    -- Initial update
    self:OnHealthUpdate()
    self:OnPowerUpdate()
    self:OnTargetChanged()
end

function HUD:CreatePlayerHealth()
    local healthFrame = CreateFrame("Frame", "CouchPotatoHealthFrame", UIParent)
    healthFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 40, 60)
    healthFrame:SetSize(280, 40)
    
    -- Background
    local bg = healthFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(healthFrame)
    bg:SetColorTexture(0, 0, 0, 0.7)
    
    -- Health bar
    local healthBar = CreateFrame("StatusBar", nil, healthFrame)
    healthBar:SetPoint("TOPLEFT", healthFrame, "TOPLEFT", 4, -4)
    healthBar:SetPoint("BOTTOMRIGHT", healthFrame, "BOTTOMRIGHT", -4, 4)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    
    -- Class color
    local _, class = UnitClass("player")
    local classColor = RAID_CLASS_COLORS[class]
    if classColor then
        healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
    else
        healthBar:SetStatusBarColor(0, 1, 0)
    end
    
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthFrame.bar = healthBar
    
    -- Health text
    local healthText = healthFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    healthText:SetText("100%")
    healthFrame.text = healthText
    
    -- Label
    local label = healthFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOM", healthFrame, "TOP", 0, 2)
    label:SetText("Health")
    label:SetTextColor(0.7, 0.7, 0.7)
    
    self.frames.health = healthFrame
end

function HUD:CreatePlayerPower()
    local powerFrame = CreateFrame("Frame", "CouchPotatoPowerFrame", UIParent)
    powerFrame:SetPoint("TOPLEFT", self.frames.health, "BOTTOMLEFT", 0, -8)
    powerFrame:SetSize(280, 28)
    
    -- Background
    local bg = powerFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(powerFrame)
    bg:SetColorTexture(0, 0, 0, 0.7)
    
    -- Power bar
    local powerBar = CreateFrame("StatusBar", nil, powerFrame)
    powerBar:SetPoint("TOPLEFT", powerFrame, "TOPLEFT", 4, -4)
    powerBar:SetPoint("BOTTOMRIGHT", powerFrame, "BOTTOMRIGHT", -4, 4)
    powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    powerBar:SetStatusBarColor(0, 0.5, 1)  -- default blue (mana)
    powerBar:SetMinMaxValues(0, 100)
    powerBar:SetValue(100)
    powerFrame.bar = powerBar
    
    -- Power text
    local powerText = powerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    powerText:SetPoint("CENTER", powerBar, "CENTER", 0, 0)
    powerText:SetText("100")
    powerFrame.text = powerText
    
    self.frames.power = powerFrame
end

function HUD:CreateCastBar()
    local castFrame = CreateFrame("Frame", "CouchPotatoCastBar", UIParent)
    castFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    castFrame:SetSize(400, 50)
    castFrame:Hide()  -- hidden until casting
    
    -- Background
    local bg = castFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(castFrame)
    bg:SetColorTexture(0, 0, 0, 0.8)
    
    -- Cast bar
    local castBar = CreateFrame("StatusBar", nil, castFrame)
    castBar:SetPoint("TOPLEFT", castFrame, "TOPLEFT", 6, -6)
    castBar:SetPoint("BOTTOMRIGHT", castFrame, "BOTTOMRIGHT", -6, 6)
    castBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    castBar:SetStatusBarColor(1, 0.7, 0)  -- orange for cast
    castBar:SetMinMaxValues(0, 1)
    castBar:SetValue(0)
    castFrame.bar = castBar
    
    -- Spell icon
    local icon = castFrame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(38, 38)
    icon:SetPoint("RIGHT", castFrame, "LEFT", -8, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    castFrame.icon = icon
    
    -- Icon border
    local iconBorder = castFrame:CreateTexture(nil, "OVERLAY")
    iconBorder:SetSize(42, 42)
    iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    
    -- Spell name
    local spellName = castFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    spellName:SetPoint("TOP", castBar, "TOP", 0, -4)
    spellName:SetText("")
    castFrame.spellName = spellName
    
    -- Cast time
    local castTime = castFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    castTime:SetPoint("BOTTOM", castBar, "BOTTOM", 0, 4)
    castTime:SetText("0.0s")
    castFrame.castTime = castTime
    
    -- Interrupt indicator (flashing red border)
    local interruptIndicator = castFrame:CreateTexture(nil, "OVERLAY")
    interruptIndicator:SetAllPoints(castFrame)
    interruptIndicator:SetColorTexture(1, 0, 0, 0)
    interruptIndicator:Hide()
    castFrame.interruptIndicator = interruptIndicator
    
    -- OnUpdate for cast progress
    castFrame:SetScript("OnUpdate", function(self, elapsed)
        if not self.casting and not self.channeling then return end
        
        local currentTime = GetTime()
        if self.casting then
            local progress = (currentTime - self.startTime) / self.duration
            progress = math.min(progress, 1)
            self.bar:SetValue(progress)
            local remaining = math.max(0, self.endTime - currentTime)
            self.castTime:SetText(string.format("%.1fs", remaining))
            
            if progress >= 1 then
                self:Hide()
                self.casting = false
            end
        elseif self.channeling then
            local progress = (self.endTime - currentTime) / self.duration
            progress = math.max(progress, 0)
            self.bar:SetValue(progress)
            local remaining = math.max(0, self.endTime - currentTime)
            self.castTime:SetText(string.format("%.1fs", remaining))
            
            if progress <= 0 then
                self:Hide()
                self.channeling = false
            end
        end
    end)
    
    self.frames.cast = castFrame
end

function HUD:CreateTargetFrame()
    local targetFrame = CreateFrame("Frame", "CouchPotatoTargetFrame", UIParent)
    targetFrame:SetPoint("TOP", UIParent, "TOP", 0, -80)
    targetFrame:SetSize(320, 60)
    targetFrame:Hide()  -- hidden when no target
    
    -- Background
    local bg = targetFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(targetFrame)
    bg:SetColorTexture(0, 0, 0, 0.7)
    
    -- Target name
    local targetName = targetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    targetName:SetPoint("TOP", targetFrame, "TOP", 0, -6)
    targetName:SetText("")
    targetFrame.targetName = targetName
    
    -- Target level
    local targetLevel = targetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetLevel:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", 8, -6)
    targetLevel:SetText("")
    targetLevel:SetTextColor(0.7, 0.7, 0.7)
    targetFrame.targetLevel = targetLevel
    
    -- Health bar
    local healthBar = CreateFrame("StatusBar", nil, targetFrame)
    healthBar:SetPoint("BOTTOMLEFT", targetFrame, "BOTTOMLEFT", 6, 6)
    healthBar:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", -6, 6)
    healthBar:SetHeight(24)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetStatusBarColor(1, 0, 0)  -- red for hostile
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    targetFrame.healthBar = healthBar
    
    -- Health text
    local healthText = targetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    healthText:SetText("100%")
    targetFrame.healthText = healthText
    
    -- Interruptible indicator
    local interruptIndicator = targetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    interruptIndicator:SetPoint("BOTTOM", targetFrame, "TOP", 0, 4)
    interruptIndicator:SetText("INTERRUPTIBLE")
    interruptIndicator:SetTextColor(1, 0.2, 0.2)
    interruptIndicator:Hide()
    targetFrame.interruptIndicator = interruptIndicator
    
    self.frames.target = targetFrame
end

function HUD:OnHealthUpdate(event, unit)
    if unit and unit ~= "player" and unit ~= "target" then return end
    
    -- Player health
    if not unit or unit == "player" then
        local health = UnitHealth("player")
        local healthMax = UnitHealthMax("player")
        if healthMax > 0 then
            local percent = (health / healthMax) * 100
            self.frames.health.bar:SetMinMaxValues(0, healthMax)
            self.frames.health.bar:SetValue(health)
            self.frames.health.text:SetText(string.format("%d%%", percent))
        end
    end
    
    -- Target health
    if not unit or unit == "target" then
        if UnitExists("target") then
            local health = UnitHealth("target")
            local healthMax = UnitHealthMax("target")
            if healthMax > 0 then
                local percent = (health / healthMax) * 100
                self.frames.target.healthBar:SetMinMaxValues(0, healthMax)
                self.frames.target.healthBar:SetValue(health)
                self.frames.target.healthText:SetText(string.format("%d%%", percent))
            end
        end
    end
end

function HUD:OnPowerUpdate(event, unit, powerType)
    if unit and unit ~= "player" then return end
    
    local power = UnitPower("player")
    local powerMax = UnitPowerMax("player")
    local powerType, powerToken = UnitPowerType("player")
    
    if powerMax > 0 then
        self.frames.power.bar:SetMinMaxValues(0, powerMax)
        self.frames.power.bar:SetValue(power)
        self.frames.power.text:SetText(tostring(power))
        
        -- Color by power type
        local color = PowerBarColor[powerType]
        if color then
            self.frames.power.bar:SetStatusBarColor(color.r, color.g, color.b)
        end
    end
end

function HUD:OnTargetChanged()
    if UnitExists("target") then
        self.frames.target:Show()
        
        -- Update name
        local name = UnitName("target")
        self.frames.target.targetName:SetText(name or "Unknown")
        
        -- Update level
        local level = UnitLevel("target")
        if level == -1 then
            self.frames.target.targetLevel:SetText("??")
        else
            self.frames.target.targetLevel:SetText(tostring(level))
        end
        
        -- Color by reaction
        if UnitIsEnemy("player", "target") then
            self.frames.target.healthBar:SetStatusBarColor(1, 0, 0)  -- red
            self.frames.target.targetName:SetTextColor(1, 0, 0)
        elseif UnitIsFriend("player", "target") then
            self.frames.target.healthBar:SetStatusBarColor(0, 1, 0)  -- green
            self.frames.target.targetName:SetTextColor(0, 1, 0)
        else
            self.frames.target.healthBar:SetStatusBarColor(1, 1, 0)  -- yellow
            self.frames.target.targetName:SetTextColor(1, 1, 0)
        end
        
        -- Update health
        self:OnHealthUpdate(nil, "target")
    else
        self.frames.target:Hide()
    end
end

function HUD:OnSpellCastStart(event, unit, castGUID, spellID)
    if unit == "player" then
        local name, _, texture, startTime, endTime, _, _, notInterruptible, spellId = UnitCastingInfo(unit)
        if name then
            local castFrame = self.frames.cast
            castFrame.spellName:SetText(name)
            castFrame.icon:SetTexture(texture)
            castFrame.startTime = startTime / 1000
            castFrame.endTime = endTime / 1000
            castFrame.duration = (endTime - startTime) / 1000
            castFrame.casting = true
            castFrame.channeling = false
            castFrame.bar:SetStatusBarColor(1, 0.7, 0)  -- orange
            castFrame:Show()
        end
    elseif unit == "target" then
        -- Check if target cast is interruptible
        local name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
        if name then
            if not notInterruptible then
                self.frames.target.interruptIndicator:Show()
            else
                self.frames.target.interruptIndicator:Hide()
            end
        end
    end
end

function HUD:OnSpellCastStop(event, unit)
    if unit == "player" then
        self.frames.cast:Hide()
        self.frames.cast.casting = false
    elseif unit == "target" then
        self.frames.target.interruptIndicator:Hide()
    end
end

function HUD:OnChannelStart(event, unit)
    if unit == "player" then
        local name, _, texture, startTime, endTime, _, notInterruptible, spellId = UnitChannelInfo(unit)
        if name then
            local castFrame = self.frames.cast
            castFrame.spellName:SetText(name)
            castFrame.icon:SetTexture(texture)
            castFrame.startTime = startTime / 1000
            castFrame.endTime = endTime / 1000
            castFrame.duration = (endTime - startTime) / 1000
            castFrame.casting = false
            castFrame.channeling = true
            castFrame.bar:SetStatusBarColor(0.2, 0.6, 1)  -- blue for channel
            castFrame:Show()
        end
    end
end

function HUD:OnChannelStop(event, unit)
    if unit == "player" then
        self.frames.cast:Hide()
        self.frames.cast.channeling = false
    end
end

function HUD:OnEnteringWorld()
    -- Refresh all displays
    self:OnHealthUpdate()
    self:OnPowerUpdate()
    self:OnTargetChanged()
end
