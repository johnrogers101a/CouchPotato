-- CouchPotato/UI/HUD.lua
-- Controller HUD: cast bar + interrupt indicator only.
-- Health, power, party, and raid frames are handled by Blizzard's built-in
-- UI or the player's existing unit frame addon (e.g. ElvUI, SUF, etc.).
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local HUD = CP:NewModule("HUD")

HUD.frames = {}

function HUD:OnEnable()
    self:CreateFrames()
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnTargetChanged")
    self:RegisterEvent("UNIT_SPELLCAST_START", "OnSpellCastStart")
    self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnSpellCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "OnChannelStart")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnChannelStop")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED", "OnSpellCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnSpellCastStop")
end

function HUD:CreateFrames()
    self:CreateCastBar()
    self:CreateTargetFrame()
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
    -- Minimal target overlay: just name, level, and an INTERRUPTIBLE flash.
    -- Health/power bars are handled by the player's existing unit frame addon.
    local targetFrame = CreateFrame("Frame", "CouchPotatoTargetFrame", UIParent)
    targetFrame:SetPoint("TOP", UIParent, "TOP", 0, -80)
    targetFrame:SetSize(320, 40)
    targetFrame:Hide()

    local bg = targetFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(targetFrame)
    bg:SetColorTexture(0, 0, 0, 0.6)

    local targetName = targetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    targetName:SetPoint("CENTER", targetFrame, "CENTER", 10, 0)
    targetName:SetText("")
    targetFrame.targetName = targetName

    local targetLevel = targetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetLevel:SetPoint("LEFT", targetFrame, "LEFT", 8, 0)
    targetLevel:SetText("")
    targetLevel:SetTextColor(0.7, 0.7, 0.7)
    targetFrame.targetLevel = targetLevel

    -- INTERRUPTIBLE badge — shown above the cast bar when target cast is kickable
    local interruptIndicator = targetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    interruptIndicator:SetPoint("BOTTOM", targetFrame, "TOP", 0, 4)
    interruptIndicator:SetText("|cFFFF3333INTERRUPTIBLE|r")
    interruptIndicator:Hide()
    targetFrame.interruptIndicator = interruptIndicator

    self.frames.target = targetFrame
end

function HUD:OnTargetChanged()
    if UnitExists("target") then
        self.frames.target:Show()
        local name = UnitName("target") or "Unknown"
        self.frames.target.targetName:SetText(name)
        local level = UnitLevel("target")
        self.frames.target.targetLevel:SetText(level == -1 and "??" or tostring(level))
        if UnitIsEnemy("player", "target") then
            self.frames.target.targetName:SetTextColor(1, 0.2, 0.2)
        elseif UnitIsFriend("player", "target") then
            self.frames.target.targetName:SetTextColor(0.2, 1, 0.2)
        else
            self.frames.target.targetName:SetTextColor(1, 1, 0.2)
        end
    else
        self.frames.target:Hide()
        self.frames.target.interruptIndicator:Hide()
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
        -- notInterruptible from UnitCastingInfo is a secret boolean that becomes tainted
        -- when called from a tainted context; wrap in pcall to prevent error spam
        local ok, showIndicator = pcall(function()
            local name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
            return name ~= nil and not notInterruptible
        end)
        if ok and showIndicator then
            self.frames.target.interruptIndicator:Show()
        else
            self.frames.target.interruptIndicator:Hide()
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


