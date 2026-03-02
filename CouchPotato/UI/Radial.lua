-- CouchPotato/UI/Radial.lua
-- BG3-inspired radial action wheel system
-- 8 wheels × 12 slots, all using SecureActionButtonTemplate
-- L1/R1 cycling, peek (light trigger) vs lock (hard trigger)
-- Pre-creates ALL frames at load time — none during combat
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local Radial = CP:NewModule("Radial", "AceEvent-3.0", "AceTimer-3.0")

local MAX_WHEELS = 8
local MAX_SLOTS = 12
local BUTTON_RADIUS = 120         -- distance from wheel center to button center (pixels)
local PEEK_THRESHOLD = 0.35       -- trigger axis 0-1, shows wheel briefly
local LOCK_THRESHOLD = 0.75       -- trigger axis 0-1, locks wheel open
local PEEK_TIMEOUT = 2.0          -- seconds before peek auto-hides
local ICON_SIZE = 52              -- button icon size in pixels
local WHEEL_FADE_TIME = 0.15      -- fade in/out time

Radial.wheels = {}          -- [1..MAX_WHEELS] = wheel container frames
Radial.wheelButtons = {}    -- [wheelIdx][slotIdx] = button frame
Radial.currentWheel = 1
Radial.isVisible = false
Radial.isLocked = false
Radial.peekTimer = nil
Radial.centerFrame = nil    -- the anchor frame (center of screen)

-- Slot positions in a circle (12 slots, 30° apart, starting from top = 90°)
local function GetSlotPosition(slotIndex, radius)
    -- Slot 1 = top (90°), going clockwise
    -- In math: angle = 90 - (slotIndex - 1) * 30 degrees
    -- Convert to radians
    local angleDeg = 90 - (slotIndex - 1) * 30
    local angleRad = angleDeg * math.pi / 180
    local x = radius * math.cos(angleRad)
    local y = radius * math.sin(angleRad)
    return x, y
end

function Radial:CreateWheelFrames()
    -- Center anchor frame
    self.centerFrame = CreateFrame("Frame", "CouchPotatoRadialCenter", UIParent)
    self.centerFrame:SetSize(1, 1)
    self.centerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    
    for wheelIdx = 1, MAX_WHEELS do
        -- Wheel container: regular Frame, can show/hide freely
        local wheel = CreateFrame("Frame", "CouchPotatoWheel"..wheelIdx, UIParent)
        wheel:SetSize(BUTTON_RADIUS * 2 + ICON_SIZE + 20, BUTTON_RADIUS * 2 + ICON_SIZE + 20)
        wheel:SetPoint("CENTER", self.centerFrame, "CENTER", 0, 0)
        wheel:Hide()  -- start hidden
        
        -- Wheel background ring texture
        local bg = wheel:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(BUTTON_RADIUS * 2 + ICON_SIZE, BUTTON_RADIUS * 2 + ICON_SIZE)
        bg:SetPoint("CENTER", wheel, "CENTER", 0, 0)
        bg:SetTexture("Interface\\Addons\\CouchPotato\\textures\\wheel_ring")
        bg:SetAlpha(0.6)
        -- If texture doesn't exist, use a solid color fallback
        if not bg:GetTexture() then
            bg:SetColorTexture(0, 0, 0, 0.4)
        end
        
        -- Wheel name label (e.g., "Wheel 1: Spells")
        local label = wheel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", wheel, "TOP", 0, -8)
        label:SetText("Wheel " .. wheelIdx)
        wheel.label = label
        
        -- Wheel indicator dots (show which wheel we're on)
        self:CreateWheelDots(wheel, wheelIdx)
        
        self.wheels[wheelIdx] = wheel
        self.wheelButtons[wheelIdx] = {}
        
        -- Create 12 SecureActionButton slots
        for slotIdx = 1, MAX_SLOTS do
            local x, y = GetSlotPosition(slotIdx, BUTTON_RADIUS)
            
            -- SecureActionButtonTemplate: combat-safe action button
            local btn = CreateFrame("CheckButton", 
                string.format("CouchPotatoWheel%dSlot%d", wheelIdx, slotIdx),
                wheel, 
                "SecureActionButtonTemplate")
            btn:SetSize(ICON_SIZE, ICON_SIZE)
            btn:SetPoint("CENTER", wheel, "CENTER", x, y)
            btn:RegisterForClicks("AnyUp", "AnyDown")
            
            -- Default: empty slot (no action)
            btn:SetAttribute("type", "empty")
            
            -- Visual elements
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(btn)
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            btn.icon = icon
            
            -- Slot border/highlight
            local border = btn:CreateTexture(nil, "OVERLAY")
            border:SetSize(ICON_SIZE + 4, ICON_SIZE + 4)
            border:SetPoint("CENTER", btn, "CENTER", 0, 0)
            border:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            border:Hide()
            btn.border = border
            
            -- Keybind label (shows which key activates this slot)
            local keybindText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            keybindText:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            keybindText:SetText("")
            btn.keybindText = keybindText
            
            -- Slot number indicator
            local slotNum = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            slotNum:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            slotNum:SetText(tostring(slotIdx))
            slotNum:SetTextColor(0.7, 0.7, 0.7)
            btn.slotNum = slotNum
            
            -- Cooldown frame
            local cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
            cooldown:SetAllPoints(btn)
            cooldown:SetDrawEdge(true)
            btn.cooldown = cooldown
            
            -- Scripts for visual feedback (non-combat safe)
            btn:SetScript("OnEnter", function(self)
                self.border:Show()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self:GetAttribute("spell") then
                    GameTooltip:SetSpellByID(self:GetAttribute("spell") or 0)
                elseif self:GetAttribute("item") then
                    GameTooltip:SetItemByID(self:GetAttribute("item") or 0)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self.border:Hide()
                GameTooltip:Hide()
            end)
            
            self.wheelButtons[wheelIdx][slotIdx] = btn
        end
        
        -- Center slot visual (shows current wheel name/icon in the middle)
        local centerIcon = wheel:CreateTexture(nil, "ARTWORK")
        centerIcon:SetSize(32, 32)
        centerIcon:SetPoint("CENTER", wheel, "CENTER", 0, 0)
        centerIcon:SetTexture("Interface\\Icons\\Ability_Warrior_Shieldmastery")
        wheel.centerIcon = centerIcon
    end
end

function Radial:CreateWheelDots(wheel, currentWheelIdx)
    wheel.dots = {}
    local totalWheels = MAX_WHEELS
    local dotSize = 6
    local dotSpacing = 10
    local totalWidth = totalWheels * (dotSize + dotSpacing) - dotSpacing
    
    for i = 1, totalWheels do
        local dot = wheel:CreateTexture(nil, "OVERLAY")
        dot:SetSize(dotSize, dotSize)
        local xOffset = (i - 1) * (dotSize + dotSpacing) - totalWidth / 2 + dotSize / 2
        dot:SetPoint("BOTTOM", wheel, "BOTTOM", xOffset, 12)
        dot:SetColorTexture(0.5, 0.5, 0.5, 0.7)  -- inactive: grey
        if i == currentWheelIdx then
            dot:SetColorTexture(1.0, 0.85, 0.0, 1.0)  -- active: gold
        end
        wheel.dots[i] = dot
    end
end

function Radial:ShowCurrentWheel()
    local wheel = self.wheels[self.currentWheel]
    if not wheel then return end
    
    -- Hide other wheels
    for i = 1, MAX_WHEELS do
        if i ~= self.currentWheel and self.wheels[i] then
            self.wheels[i]:Hide()
        end
    end
    
    wheel:Show()
    wheel:SetAlpha(0)
    
    -- Fade in using UIFrameFadeIn if available, else instant
    if UIFrameFadeIn then
        UIFrameFadeIn(wheel, WHEEL_FADE_TIME, 0, CP.db.profile.radialAlpha or 0.9)
    else
        wheel:SetAlpha(CP.db.profile.radialAlpha or 0.9)
    end
    
    self.isVisible = true
    
    -- Notify GamePad module to vibrate
    local GamePad = CP:GetModule("GamePad")
    if GamePad then GamePad:Vibrate("MENU_OPEN") end
end

function Radial:HideCurrentWheel()
    for i = 1, MAX_WHEELS do
        if self.wheels[i] then
            self.wheels[i]:Hide()
        end
    end
    self.isVisible = false
    self.isLocked = false
    
    if self.peekTimer then
        self:CancelTimer(self.peekTimer)
        self.peekTimer = nil
    end
    
    local GamePad = CP:GetModule("GamePad")
    if GamePad then GamePad:Vibrate("MENU_CLOSE") end
end

function Radial:CycleWheelNext()
    self.currentWheel = self.currentWheel % MAX_WHEELS + 1
    self:UpdateWheelDots()
    if self.isVisible then
        self:ShowCurrentWheel()
    end
    local GamePad = CP:GetModule("GamePad")
    if GamePad then GamePad:Vibrate("WHEEL_CYCLE") end
end

function Radial:CycleWheelPrev()
    self.currentWheel = (self.currentWheel - 2) % MAX_WHEELS + 1
    self:UpdateWheelDots()
    if self.isVisible then
        self:ShowCurrentWheel()
    end
    local GamePad = CP:GetModule("GamePad")
    if GamePad then GamePad:Vibrate("WHEEL_CYCLE") end
end

-- Peek: show wheel briefly (light trigger pull)
function Radial:PeekWheel()
    if self.isLocked then return end
    self:ShowCurrentWheel()
    
    -- Auto-hide after timeout unless locked
    if self.peekTimer then self:CancelTimer(self.peekTimer) end
    self.peekTimer = self:ScheduleTimer(function()
        if not self.isLocked then
            self:HideCurrentWheel()
        end
        self.peekTimer = nil
    end, PEEK_TIMEOUT)
    
    local GamePad = CP:GetModule("GamePad")
    if GamePad then GamePad:Vibrate("WHEEL_PEEK") end
end

-- Lock: keep wheel open (hard trigger pull)
function Radial:LockWheel()
    self.isLocked = true
    if not self.isVisible then
        self:ShowCurrentWheel()
    end
    if self.peekTimer then
        self:CancelTimer(self.peekTimer)
        self.peekTimer = nil
    end
    local GamePad = CP:GetModule("GamePad")
    if GamePad then GamePad:Vibrate("WHEEL_LOCK") end
end

function Radial:UnlockWheel()
    self.isLocked = false
    -- Start peek timer now
    if self.isVisible then
        if self.peekTimer then self:CancelTimer(self.peekTimer) end
        self.peekTimer = self:ScheduleTimer(function()
            self:HideCurrentWheel()
            self.peekTimer = nil
        end, 0.5)  -- short delay before hiding
    end
end

-- We use an OnUpdate frame to continuously read trigger axis values
-- and determine peek vs lock state
function Radial:InitTriggerDetection()
    self.triggerFrame = CreateFrame("Frame")
    self.triggerFrame.elapsed = 0
    self.triggerFrame.lastRT = 0
    
    self.triggerFrame:SetScript("OnUpdate", function(self_frame, elapsed)
        self_frame.elapsed = self_frame.elapsed + elapsed
        if self_frame.elapsed < 0.05 then return end  -- poll at ~20Hz
        self_frame.elapsed = 0
        
        local GamePad = CP:GetModule("GamePad")
        if not GamePad then return end
        
        local lt, rt = GamePad:GetTriggerValues()
        local prevRT = self_frame.lastRT
        self_frame.lastRT = rt
        
        local db = CP.db.profile
        local peek = db.peekThreshold or PEEK_THRESHOLD
        local lock = db.lockThreshold or LOCK_THRESHOLD
        
        -- Right trigger controls wheel visibility
        if rt >= lock and prevRT < lock then
            -- Crossed lock threshold
            Radial:LockWheel()
        elseif rt >= peek and prevRT < peek then
            -- Crossed peek threshold
            Radial:PeekWheel()
        elseif rt < peek and prevRT >= peek then
            -- Released trigger
            if Radial.isLocked then
                Radial:UnlockWheel()
            else
                Radial:HideCurrentWheel()
            end
        end
    end)
end

function Radial:InitGamePadButtonHandling()
    self.buttonFrame = CreateFrame("Frame", "CouchPotatoRadialInput", UIParent)
    self.buttonFrame:EnableGamePadButton(true)
    
    self.buttonFrame:SetScript("OnGamePadButtonDown", function(self_frame, button)
        if button == "PADLSHOULDER" then
            Radial:CycleWheelPrev()
        elseif button == "PADRSHOULDER" then
            Radial:CycleWheelNext()
        end
    end)
end

function Radial:SetSlot(wheelIdx, slotIdx, actionType, actionValue)
    if InCombatLockdown() then
        CP:Print("Cannot modify radial slots during combat.")
        return false
    end
    
    local btn = self.wheelButtons[wheelIdx] and self.wheelButtons[wheelIdx][slotIdx]
    if not btn then return false end
    
    btn:SetAttribute("type", actionType)  -- "spell", "item", "macro", "empty"
    
    if actionType == "spell" then
        btn:SetAttribute("spell", actionValue)
        -- Update icon
        local spellTexture = select(3, GetSpellInfo(actionValue))
        if spellTexture then
            btn.icon:SetTexture(spellTexture)
        end
    elseif actionType == "item" then
        btn:SetAttribute("item", actionValue)
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(actionValue)
        if itemTexture then btn.icon:SetTexture(itemTexture) end
    elseif actionType == "macro" then
        btn:SetAttribute("macro", actionValue)
    elseif actionType == "empty" then
        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    
    -- Save to character DB
    if CP.db and CP.db.char then
        if not CP.db.char.wheelLayouts then
            CP.db.char.wheelLayouts = {}
        end
        if not CP.db.char.wheelLayouts[wheelIdx] then
            CP.db.char.wheelLayouts[wheelIdx] = {}
        end
        CP.db.char.wheelLayouts[wheelIdx][slotIdx] = {
            type = actionType,
            value = actionValue,
        }
    end
    
    return true
end

function Radial:LoadLayoutsFromDB()
    if not CP.db or not CP.db.char then return end
    local layouts = CP.db.char.wheelLayouts
    if not layouts then return end
    
    for wheelIdx, slots in pairs(layouts) do
        for slotIdx, slotData in pairs(slots) do
            if slotData.type and slotData.value then
                self:SetSlot(wheelIdx, slotIdx, slotData.type, slotData.value)
            end
        end
    end
end

function Radial:LoadDefaultLayouts()
    -- Load the current spec's default layout into wheel 1
    local Specs = CP:GetModule("Specs")
    if not Specs then return end
    local layout = Specs:GetCurrentLayout()
    if not layout then return end
    
    -- Map spec abilities to wheel 1 slots
    local slotMapping = {
        { type = "spell", value = layout.primary },
        { type = "spell", value = layout.secondary },
        { type = "spell", value = layout.tertiary },
        { type = "spell", value = layout.interrupt },
        { type = "spell", value = layout.majorCD },
        { type = "spell", value = layout.defensiveCD },
        { type = "spell", value = layout.movement },
        { type = "spell", value = layout.dpadUp },
        { type = "spell", value = layout.dpadDown },
    }
    
    for slotIdx, slotData in ipairs(slotMapping) do
        if slotData.value then
            self:SetSlot(1, slotIdx, slotData.type, slotData.value)
        end
    end
end

function Radial:OnEnable()
    self:CreateWheelFrames()
    self:InitTriggerDetection()
    self:InitGamePadButtonHandling()
    
    -- Load saved layouts first, then defaults for empty slots
    self:LoadLayoutsFromDB()
    self:LoadDefaultLayouts()
    
    -- Register events
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
end

function Radial:OnSpecChanged()
    -- Reload default layouts when spec changes
    self:LoadDefaultLayouts()
end

function Radial:OnCombatStart()
    -- Called by GamePad module on PLAYER_REGEN_DISABLED
    -- Ensure wheels are set up (no frame creation here — already done)
    -- Just log state
end

function Radial:UpdateWheelDots()
    for wheelIdx = 1, MAX_WHEELS do
        local wheel = self.wheels[wheelIdx]
        if wheel and wheel.dots then
            for dotIdx, dot in ipairs(wheel.dots) do
                if dotIdx == self.currentWheel then
                    dot:SetColorTexture(1.0, 0.85, 0.0, 1.0)  -- gold: active
                else
                    dot:SetColorTexture(0.5, 0.5, 0.5, 0.7)   -- grey: inactive
                end
            end
        end
    end
end

-- Public API
function Radial:GetCurrentWheel() return self.currentWheel end
function Radial:IsVisible() return self.isVisible end
function Radial:IsLocked() return self.isLocked end
