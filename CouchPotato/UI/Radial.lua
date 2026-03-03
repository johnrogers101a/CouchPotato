-- CouchPotato/UI/Radial.lua
-- BG3-inspired radial action wheel system
-- 8 wheels × 12 slots, all using SecureActionButtonTemplate
-- L1/R1 cycling, peek (light trigger) vs lock (hard trigger)
-- Pre-creates ALL frames at load time — none during combat
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local Radial = CP:NewModule("Radial")

local MAX_WHEELS = 8
local MAX_SLOTS = 12
local BUTTON_RADIUS = 200         -- distance from wheel center to button center (pixels) — was 120
local PEEK_THRESHOLD = 0.35       -- trigger axis 0-1, shows wheel briefly
local LOCK_THRESHOLD = 0.75       -- trigger axis 0-1, locks wheel open
local PEEK_TIMEOUT = 2.0          -- seconds before peek auto-hides
local ICON_SIZE = 64              -- button icon size in pixels — was 52
local WHEEL_FADE_TIME = 0.15      -- fade in/out time
local STICK_DEAD_ZONE = 0.25      -- stick magnitude threshold for selection
local STICK_INDEX = 1             -- 1=left stick, 2=right stick

Radial.wheels = {}          -- [1..MAX_WHEELS] = wheel container frames
Radial.wheelButtons = {}    -- [wheelIdx][slotIdx] = button frame
Radial.currentWheel = 1
Radial.isVisible = false
Radial.isLocked = false
Radial.peekTimer = nil
Radial.centerFrame = nil    -- the anchor frame (center of screen)
Radial.highlightedSlot = nil -- currently highlighted slot index (nil = none)

-- ── Interface Panel Layouts ───────────────────────────────────────────────────
-- Wheels 1-2 are fixed interface-toggle wheels (map, character pane, etc.).
-- Macros use /click on Blizzard's micro bar buttons — no event interception.
-- Button names are correct for Interface 120001 (TWW). Cardinal slots (face btns):
--   slot 1 = Y/△ (top), slot 4 = B/○ (right), slot 7 = A/✕ (bottom), slot 10 = X/□ (left)

-- Direct WoW API execute functions for interface-panel slots.
-- MicroButtons are protected in Dragonflight/TWW and cannot be :Click()ed by addons
-- without causing taint. We call the real toggle APIs instead.
local INTERFACE_WHEEL_LAYOUTS = {
    [1] = {
        name = "Interface",
        slots = {
            [1]  = { name="Character",    macro="/click CharacterMicroButton",      icon="Interface\\Buttons\\UI-MicroButton-Character-Up",    execute=function() ToggleCharacter(1) end },
            [2]  = { name="Spellbook",    macro="/click SpellbookMicroButton",      icon="Interface\\Buttons\\UI-MicroButton-Spellbook-Up",    execute=function() ToggleSpellBook("spell") end },
            [3]  = { name="Talents",      macro="/click TalentMicroButton",         icon="Interface\\Buttons\\UI-MicroButton-Talent-Up",       execute=function() ToggleTalentFrame() end },
            [4]  = { name="Map",          macro="/click WorldMapMicroButton",       icon="Interface\\Buttons\\UI-MicroButton-WorldMap-Up",     execute=function() if WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) else ShowUIPanel(WorldMapFrame) end end },
            [5]  = { name="Quests",       macro="/click QuestLogMicroButton",       icon="Interface\\Buttons\\UI-MicroButton-Quest-Up",        execute=function() ToggleQuestLog() end },
            [6]  = { name="Achievements", macro="/click AchievementMicroButton",    icon="Interface\\Buttons\\UI-MicroButton-Achievement-Up",  execute=function() ToggleAchievementFrame() end },
            [7]  = { name="Bags",         macro="/click MainMenuBarBackpackButton", icon="Interface\\Buttons\\Button-Backpack-Up",             execute=function() ToggleAllBags() end },
            [8]  = { name="Collections",  macro="/click CollectionsMicroButton",    icon="Interface\\Buttons\\UI-MicroButton-Collections-Up",  execute=function() ToggleCollectionsJournal() end },
            [9]  = { name="Social",       macro="/click SocialsMicroButton",        icon="Interface\\Buttons\\UI-MicroButton-Socials-Up",      execute=function() ToggleFriendsFrame() end },
            [10] = { name="Journal",      macro="/click EJMicroButton",             icon="Interface\\Buttons\\UI-MicroButton-EJ-Up",           execute=function() ToggleEncounterJournal() end },
            [11] = { name="Guild",        macro="/click GuildMicroButton",          icon="Interface\\Buttons\\UI-MicroButton-Guild-Up",        execute=function() ToggleGuildFrame() end },
            [12] = { name="Group",        macro="/click GroupFinderMicroButton",    icon="Interface\\Buttons\\UI-MicroButton-GroupFinder-Up",  execute=function() PVEFrame_ToggleFrame() end },
        },
    },
    [2] = {
        name = "System",
        slots = {
            [1]  = { name="PvP",         macro="/click PVPMicroButton",            icon="Interface\\Buttons\\UI-MicroButton-PVP-Up",          execute=function() TogglePVPUI() end },
            [2]  = { name="Store",       macro="/click StoreMicroButton",          icon="Interface\\Buttons\\UI-MicroButton-Store-Up",        execute=function() ToggleStoreUI() end },
            [3]  = { name="Help",        macro="/click HelpMicroButton",           icon="Interface\\Buttons\\UI-MicroButton-Help-Up",         execute=function() ToggleHelpFrame() end },
            [4]  = { name="Main Menu",   macro="/click MainMenuMicroButton",       icon="Interface\\Buttons\\UI-MicroButton-MainMenu-Up",     execute=function() ToggleGameMenu() end },
            [5]  = { name="Calendar",    macro="/click GameTimeFrame",             icon="Interface\\Icons\\INV_Misc_SunCalendar",             execute=function() GameTimeCalendar_Toggle() end },
            [6]  = { name="Screenshot",  macro="/screenshot",                      icon="Interface\\Icons\\INV_Misc_Camera_01",               execute=function() Screenshot() end },
            [7]  = { name="Professions", macro="/click ProfessionMicroButton",     icon="Interface\\Buttons\\UI-MicroButton-Profession-Up",   execute=function() if ToggleProfessionsBook then ToggleProfessionsBook() end end },
            [8]  = { name="World Map",   macro="/click WorldMapMicroButton",       icon="Interface\\Buttons\\UI-MicroButton-WorldMap-Up",     execute=function() if WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) else ShowUIPanel(WorldMapFrame) end end },
            [9]  = { name="LFD",         macro="/click LFDMicroButton",            icon="Interface\\Buttons\\UI-MicroButton-GroupFinder-Up",  execute=function() PVEFrame_ToggleFrame() end },
            [10] = { name="Mounts",      macro="/click CollectionsMicroButton",    icon="Interface\\Icons\\INV_Mount_DragonTurtle_Blue",      execute=function() ToggleCollectionsJournal(2) end },
        },
    },
}

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
    -- Guard: prevent duplicate frame creation (OnEnable can be called multiple times)
    if self.centerFrame then return end
    
    -- Center anchor frame
    self.centerFrame = CreateFrame("Frame", "CouchPotatoRadialCenter", UIParent)
    self.centerFrame:SetSize(1, 1)
    self.centerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    
    for wheelIdx = 1, MAX_WHEELS do
        -- Wheel container: regular Frame, can show/hide freely
        local wheel = CreateFrame("Frame", "CouchPotatoWheel"..wheelIdx, UIParent)
        wheel:SetSize(BUTTON_RADIUS * 2 + ICON_SIZE + 40, BUTTON_RADIUS * 2 + ICON_SIZE + 40)
        wheel:SetPoint("CENTER", self.centerFrame, "CENTER", 0, 0)
        wheel:Hide()  -- start hidden
        
        -- Wheel background ring texture
        local bg = wheel:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(BUTTON_RADIUS * 2 + ICON_SIZE + 20, BUTTON_RADIUS * 2 + ICON_SIZE + 20)
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
        
        -- Center selection label — shows the name of the currently highlighted slot
        local selLabel = wheel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        selLabel:SetPoint("CENTER", wheel, "CENTER", 0, 0)
        selLabel:SetText("")
        selLabel:SetTextColor(1, 0.9, 0.6)
        wheel.selLabel = selLabel
        
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
            border:SetSize(ICON_SIZE + 12, ICON_SIZE + 12)
            border:SetPoint("CENTER", btn, "CENTER", 0, 0)
            border:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            border:Hide()
            btn.border = border
            
            -- Keybind label: show controller button name for the 4 cardinal slots
            local keybindText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            keybindText:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            local SLOT_LABELS = { [1]="Y", [4]="B", [7]="A", [10]="X" }
            keybindText:SetText(SLOT_LABELS[slotIdx] or "")
            btn.keybindText = keybindText
            
            -- Slot number indicator
            local slotNum = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            slotNum:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            slotNum:SetText(tostring(slotIdx))
            slotNum:SetTextColor(0.7, 0.7, 0.7)
            btn.slotNum = slotNum

            -- Named slot label (shown below icon when slot has an explicit name)
            local nameLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameLabel:SetPoint("TOP", btn, "BOTTOM", 0, 0)
            nameLabel:SetWidth(64)
            nameLabel:SetJustifyH("CENTER")
            nameLabel:SetTextColor(1, 0.9, 0.6)
            nameLabel:SetText("")
            btn.nameLabel = nameLabel
            
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
                elseif self.tooltipName then
                    GameTooltip:SetText(self.tooltipName)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self.border:Hide()
                GameTooltip:Hide()
            end)
            
            self.wheelButtons[wheelIdx][slotIdx] = btn
        end
    end
    
    -- Single poll frame for stick input (created once, shared across all wheels)
    if not self.pollFrame then
        self.pollFrame = CreateFrame("Frame", "CouchPotatoPollFrame", UIParent)
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

-- ── Stick-based slot selection ────────────────────────────────────────────────

-- Returns stick angle in degrees (math convention: 0=right, 90=up), or nil if in dead zone
function Radial:GetStickAngle()
    local ms = C_GamePad.GetDeviceMappedState()
    if not ms or not ms.sticks then return nil end
    local stick = ms.sticks[STICK_INDEX]
    if not stick or (stick.len or 0) < STICK_DEAD_ZONE then return nil end
    return math.deg(math.atan2(stick.y, stick.x))
end

-- Maps an angle (degrees) to a slot index (1-MAX_SLOTS)
-- Slots start at top (90°) and go clockwise, 30° apart
function Radial:AngleToSlot(angleDeg)
    return math.floor(((90 - angleDeg) * MAX_SLOTS / 360 + 0.5) % MAX_SLOTS) + 1
end

-- Shows/hides the selection highlight on a specific slot
function Radial:SetSlotHighlight(wheelIdx, slotIdx, state)
    if not slotIdx then return end
    local btn = self.wheelButtons[wheelIdx] and self.wheelButtons[wheelIdx][slotIdx]
    if not btn then return end
    if state then
        btn.border:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        btn.border:SetVertexColor(1, 0.85, 0, 1)
        btn.border:SetSize(ICON_SIZE + 12, ICON_SIZE + 12)
        btn.border:Show()
        btn:SetScale(1.3)
    else
        btn.border:Hide()
        btn:SetScale(1.0)
    end
end

-- Updates the center label to show the highlighted slot's name
function Radial:UpdateSelectionLabel()
    local wheel = self.wheels[self.currentWheel]
    if not wheel or not wheel.selLabel then return end
    
    local slot = self.highlightedSlot
    if slot then
        local wheelDef = INTERFACE_WHEEL_LAYOUTS[self.currentWheel]
        local slotDef = wheelDef and wheelDef.slots[slot]
        local name = slotDef and slotDef.name
        if not name then
            local btn = self.wheelButtons[self.currentWheel] and self.wheelButtons[self.currentWheel][slot]
            name = btn and btn.tooltipName
        end
        wheel.selLabel:SetText(name or ("Slot " .. slot))
    else
        wheel.selLabel:SetText("")
    end
end

-- Called every frame while wheel is open — polls stick and updates selection
function Radial:UpdateStickSelection()
    if not self.isVisible then return end
    local angle = self:GetStickAngle()
    if angle == nil then return end  -- dead zone: keep current selection
    
    local newSlot = self:AngleToSlot(angle)
    if newSlot == self.highlightedSlot then return end
    
    self:SetSlotHighlight(self.currentWheel, self.highlightedSlot, false)
    self.highlightedSlot = newSlot
    self:SetSlotHighlight(self.currentWheel, newSlot, true)
    self:UpdateSelectionLabel()
end

-- Starts the per-frame stick polling loop
function Radial:StartStickPolling()
    if not self.pollFrame then return end
    self.pollFrame:SetScript("OnUpdate", function()
        Radial:UpdateStickSelection()
    end)
end

-- Stops the per-frame stick polling loop and clears any active selection highlight
function Radial:StopStickPolling()
    if not self.pollFrame then return end
    self.pollFrame:SetScript("OnUpdate", nil)
    if self.currentWheel and self.highlightedSlot then
        self:SetSlotHighlight(self.currentWheel, self.highlightedSlot, false)
    end
    self.highlightedSlot = nil
    self:UpdateSelectionLabel()
end

-- Opens the wheel (called on trigger press)
function Radial:OpenWheel()
    if self.isVisible then return end
    self.highlightedSlot = nil
    self:ShowCurrentWheel()
    self:StartStickPolling()
end

-- Closes the wheel WITHOUT executing the highlighted slot (cancel — B button or trigger release)
function Radial:CloseWheel()
    if not self.isVisible then return end
    self:HideCurrentWheel()
end

-- Confirms the current selection and closes the wheel (called by A button)
function Radial:ConfirmAndClose()
    if not self.isVisible then return end
    
    local slot = self.highlightedSlot
    if slot then
        local wheelDef = INTERFACE_WHEEL_LAYOUTS[self.currentWheel]
        local slotDef = wheelDef and wheelDef.slots[slot]
        if slotDef and slotDef.execute then
            local ok, err = pcall(slotDef.execute)
            if not ok then CP:Print("CouchPotato: " .. tostring(err)) end
        elseif not InCombatLockdown() then
            -- User-configured wheels (3+): click the SecureActionButton directly
            local btn = self.wheelButtons[self.currentWheel] and self.wheelButtons[self.currentWheel][slot]
            if btn then btn:Click("LeftButton") end
        end
    end
    
    self:HideCurrentWheel()
end

function Radial:ShowCurrentWheel()
    local wheel = self.wheels[self.currentWheel]
    if not wheel then return end

    -- Reset selection state for the new wheel
    self.highlightedSlot = nil
    local prevWheel = self.wheels[self.currentWheel]
    if prevWheel and prevWheel.selLabel then prevWheel.selLabel:SetText("") end

    for i = 1, MAX_WHEELS do
        if i ~= self.currentWheel and self.wheels[i] then
            self.wheels[i]:Hide()
        end
    end

    wheel:Show()
    wheel:SetAlpha(0)
    local alpha = (CP.db and CP.db.profile and CP.db.profile.radialAlpha) or 0.9
    if UIFrameFadeIn then
        UIFrameFadeIn(wheel, WHEEL_FADE_TIME, 0, alpha)
    else
        wheel:SetAlpha(alpha)
    end

    self.isVisible = true

    -- Tell Bindings to remap face buttons to this wheel's cardinal slots
    local Bindings = CP:GetModule("Bindings", true)
    if Bindings then Bindings:ApplyWheelBindings(self.currentWheel) end
end

function Radial:HideCurrentWheel()
    self:StopStickPolling()
    for i = 1, MAX_WHEELS do
        if self.wheels[i] then self.wheels[i]:Hide() end
    end
    self.isVisible = false
    self.isLocked  = false

    -- Restore direct spell bindings on face buttons
    local Bindings = CP:GetModule("Bindings", true)
    if Bindings then Bindings:RestoreDirectBindings() end
end

function Radial:CycleWheelNext()
    if self.isVisible then
        self:SetSlotHighlight(self.currentWheel, self.highlightedSlot, false)
        self.highlightedSlot = nil
    end
    self.currentWheel = self.currentWheel % MAX_WHEELS + 1
    self:UpdateWheelDots()
    if self.isVisible then
        self:ShowCurrentWheel()  -- also re-applies wheel bindings for new wheel
    end
end

function Radial:CycleWheelPrev()
    if self.isVisible then
        self:SetSlotHighlight(self.currentWheel, self.highlightedSlot, false)
        self.highlightedSlot = nil
    end
    self.currentWheel = (self.currentWheel - 2) % MAX_WHEELS + 1
    self:UpdateWheelDots()
    if self.isVisible then
        self:ShowCurrentWheel()
    end
end

-- Peek kept for API completeness
function Radial:PeekWheel()
    if self.isLocked then return end
    self:ShowCurrentWheel()
    C_Timer.After(PEEK_TIMEOUT, function()
        if not Radial.isLocked then Radial:HideCurrentWheel() end
    end)
end

-- Lock: keep wheel open (RT held)
function Radial:LockWheel()
    self.isLocked = true
    if not self.isVisible then self:ShowCurrentWheel() end
end

function Radial:UnlockWheel()
    self.isLocked = false
    -- Short delay so the spell fires before the wheel disappears
    C_Timer.After(0.15, function()
        if not Radial.isLocked then Radial:HideCurrentWheel() end
    end)
end

function Radial:InitTriggerDetection()
    -- handled in InitGamePadButtonHandling
end

function Radial:InitGamePadButtonHandling()
    if self.buttonFrame then return end
    
    -- PADRTRIGGER: AnyDown = open wheel, AnyUp = cancel/close without executing
    self.triggerBtn = CreateFrame("Button", "CouchPotatoTriggerBtn", UIParent)
    self.triggerBtn:RegisterForClicks("AnyDown", "AnyUp")
    self.triggerBtn:SetScript("OnClick", function(self, mouseButton, down)
        if down then
            Radial:OpenWheel()
        else
            Radial:CloseWheel()
        end
    end)

    -- PAD1 (A button): confirm/execute highlighted slot + close (bound only when wheel is open)
    self.confirmBtn = CreateFrame("Button", "CouchPotatoConfirmBtn", UIParent)
    self.confirmBtn:RegisterForClicks("AnyDown")
    self.confirmBtn:SetScript("OnClick", function()
        Radial:ConfirmAndClose()
    end)

    -- PAD2 (B button): cancel/close without executing (bound only when wheel is open)
    self.closeBtn = CreateFrame("Button", "CouchPotatoCloseBtn", UIParent)
    self.closeBtn:RegisterForClicks("AnyDown")
    self.closeBtn:SetScript("OnClick", function()
        Radial:CloseWheel()
    end)

    -- PAD2 permanent global close: when wheel is NOT open, B closes all open windows.
    -- Uses a regular click binding (priority 1 = addon layer). When the wheel opens,
    -- SetOverrideBindingClick for PAD2 → CouchPotatoCloseBtn takes precedence; when the
    -- wheel closes and overrides are cleared, PAD2 falls back to this binding.
    -- Plain button — CloseAllWindows() is not a protected action; using
    -- SecureActionButtonTemplate here and then overriding its OnClick with
    -- insecure Lua would taint the button and defeat the purpose.
    self.globalCloseBtn = CreateFrame("Button", "CouchPotatoGlobalCloseBtn", UIParent)
    self.globalCloseBtn:RegisterForClicks("AnyDown")
    self.globalCloseBtn:SetScript("OnClick", function() CloseAllWindows() end)
    SetBindingClick("PAD2", "CouchPotatoGlobalCloseBtn", "LeftButton")

    -- PADLSHOULDER → cycle wheel left
    self.lsBtn = CreateFrame("Button", "CouchPotatoLSBtn", UIParent)
    self.lsBtn:RegisterForClicks("AnyDown")
    self.lsBtn:SetScript("OnClick", function()
        Radial:CycleWheelPrev()
    end)
    
    -- PADRSHOULDER → cycle wheel right
    self.rsBtn = CreateFrame("Button", "CouchPotatoRSBtn", UIParent)
    self.rsBtn:RegisterForClicks("AnyDown")
    self.rsBtn:SetScript("OnClick", function()
        Radial:CycleWheelNext()
    end)
    
    self.buttonFrame = self.triggerBtn
end

function Radial:SetSlot(wheelIdx, slotIdx, actionType, actionValue, iconPath, slotName)
    if InCombatLockdown() then
        CP:Print("Cannot modify radial slots during combat.")
        return false
    end
    
    local btn = self.wheelButtons[wheelIdx] and self.wheelButtons[wheelIdx][slotIdx]
    if not btn then return false end
    
    btn:SetAttribute("type", actionType)  -- "spell", "item", "macro", "empty"
    
    if actionType == "spell" then
        btn:SetAttribute("spell", actionValue)
        local spellInfo = C_Spell.GetSpellInfo(actionValue)
        local iconID = spellInfo and spellInfo.iconID
        btn.icon:SetTexture(iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
    elseif actionType == "item" then
        btn:SetAttribute("item", actionValue)
        local itemInfo = C_Item.GetItemInfo(actionValue)
        local itemTexture = itemInfo and itemInfo.iconFileDataID
        btn.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
    elseif actionType == "macro" then
        btn:SetAttribute("macro", actionValue)
        btn.icon:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
    elseif actionType == "empty" then
        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Named label (hides slot number when a name is provided)
    if slotName then
        btn.tooltipName = slotName
        if btn.nameLabel then btn.nameLabel:SetText(slotName) end
        if btn.slotNum    then btn.slotNum:Hide() end
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
        -- Wheels 1-2 are always the interface panel — never load from DB
        if wheelIdx > 2 then
            for slotIdx, slotData in pairs(slots) do
                if slotData.type and slotData.value then
                    self:SetSlot(wheelIdx, slotIdx, slotData.type, slotData.value)
                end
            end
        end
    end
end

-- Populates wheels 1-2 with fixed interface-panel toggles.
-- Called last so it always wins over any DB data for those wheels.
function Radial:LoadInterfaceLayouts()
    for wheelIdx, wheelDef in pairs(INTERFACE_WHEEL_LAYOUTS) do
        local wheel = self.wheels[wheelIdx]
        if wheel and wheel.label then
            wheel.label:SetText(wheelDef.name)
        end
        for slotIdx, slotDef in pairs(wheelDef.slots) do
            local btn = self.wheelButtons[wheelIdx] and self.wheelButtons[wheelIdx][slotIdx]
            if btn and not InCombatLockdown() then
                btn:SetAttribute("type", "macro")
                btn:SetAttribute("macro", slotDef.macro)
                btn.icon:SetTexture(slotDef.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                btn.tooltipName = slotDef.name
                if btn.nameLabel then btn.nameLabel:SetText(slotDef.name) end
                if btn.slotNum    then btn.slotNum:Hide() end
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
    
    -- Map spec abilities to wheel 1 cardinal + supporting slots.
    -- Slots 1/4/7/10 are the four cardinal positions bound to face buttons:
    --   slot 1  = PAD4 (Y/△ top)    → primary
    --   slot 4  = PAD2 (B/○ right)  → interrupt
    --   slot 7  = PAD1 (A/✕ bottom) → movement
    --   slot 10 = PAD3 (X/□ left)   → tertiary   ← was missing, X did nothing
    local slotMapping = {
        [1]  = { type = "spell", value = layout.primary },
        [2]  = { type = "spell", value = layout.secondary },
        [3]  = { type = "spell", value = layout.majorCD },
        [4]  = { type = "spell", value = layout.interrupt },
        [5]  = { type = "spell", value = layout.defensiveCD },
        [6]  = { type = "spell", value = layout.dpadUp },
        [7]  = { type = "spell", value = layout.movement },
        [8]  = { type = "spell", value = layout.dpadDown },
        [9]  = { type = "spell", value = layout.secondary },
        [10] = { type = "spell", value = layout.tertiary },
    }
    
    for slotIdx, slotData in pairs(slotMapping) do
        if slotData.value then
            self:SetSlot(1, slotIdx, slotData.type, slotData.value)
        end
    end
end

function Radial:OnEnable()
    self:CreateWheelFrames()
    self:InitTriggerDetection()
    self:InitGamePadButtonHandling()
    
    -- Load DB-saved layouts for wheels 3+, then apply fixed interface layouts for wheels 1-2
    self:LoadLayoutsFromDB()
    self:LoadInterfaceLayouts()
    
    -- Register events
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEnter")
end

function Radial:OnSpecChanged()
    -- Spec changes no longer affect radial — wheels 1-2 are fixed interface panels,
    -- wheels 3+ use DB-saved player layouts.
end

function Radial:OnEnteringWorld()
    -- Re-apply interface layouts in case Blizzard frames were recreated
    if not InCombatLockdown() then
        self:LoadInterfaceLayouts()
    end
end

-- Close all open windows when the player enters combat (fires before lockdown).
function Radial:OnCombatEnter()
    CloseAllWindows()
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
