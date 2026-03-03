-- CouchPotato/UI/Radial.lua
-- Controller vertical-list menu — replaces the radial wheel
-- Right trigger opens; D-pad up/down navigates; A selects; B closes; LB/RB cycles pages
-- Pre-creates ALL frames at load time — none during combat
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local Radial = CP:NewModule("Radial")

local MAX_WHEELS  = 8
local MAX_SLOTS   = 12
local ROW_HEIGHT  = 38           -- px per list row
local ICON_SIZE   = 30           -- icon size within a row
local WIN_PAD     = 12           -- left/right padding inside window
local WIN_INNER   = 264          -- usable content width
local WIN_WIDTH   = WIN_INNER + WIN_PAD * 2  -- 288
local HEADER_H    = 34           -- title bar height
local DOT_H       = 18           -- page-indicator dot strip
local FOOTER_H    = 26           -- hint bar height
local WIN_HEIGHT  = HEADER_H + MAX_SLOTS * ROW_HEIGHT + DOT_H + FOOTER_H
local LIST_FADE   = 0.15         -- fade-in/out seconds

-- Gold selection colour
local SEL_R, SEL_G, SEL_B = 1.0, 0.85, 0.0

-- ── Interface Page Layouts ────────────────────────────────────────────────────
-- Pages 1-2: fixed interface toggles (not user-configurable)
-- Pages 3-8: user spell/item/macro slots (saved per character)
local INTERFACE_WHEEL_LAYOUTS = {
    [1] = {
        name = "Interface",
        slots = {
            [1]  = { name="Character",    icon="Interface\\Buttons\\UI-MicroButton-Character-Up",    execute=function() ToggleCharacter(1) end },
            [2]  = { name="Spellbook",    icon="Interface\\Buttons\\UI-MicroButton-Spellbook-Up",    execute=function() ToggleSpellBook("spell") end },
            [3]  = { name="Talents",      icon="Interface\\Buttons\\UI-MicroButton-Talent-Up",       execute=function() ToggleTalentFrame() end },
            [4]  = { name="Map",          icon="Interface\\Buttons\\UI-MicroButton-WorldMap-Up",     execute=function() if WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) else ShowUIPanel(WorldMapFrame) end end },
            [5]  = { name="Quests",       icon="Interface\\Buttons\\UI-MicroButton-Quest-Up",        execute=function() ToggleQuestLog() end },
            [6]  = { name="Achievements", icon="Interface\\Buttons\\UI-MicroButton-Achievement-Up",  execute=function() ToggleAchievementFrame() end },
            [7]  = { name="Bags",         icon="Interface\\Buttons\\Button-Backpack-Up",             execute=function() ToggleAllBags() end },
            [8]  = { name="Collections",  icon="Interface\\Buttons\\UI-MicroButton-Collections-Up",  execute=function() ToggleCollectionsJournal() end },
            [9]  = { name="Social",       icon="Interface\\Buttons\\UI-MicroButton-Socials-Up",      execute=function() ToggleFriendsFrame() end },
            [10] = { name="Journal",      icon="Interface\\Buttons\\UI-MicroButton-EJ-Up",           execute=function() ToggleEncounterJournal() end },
            [11] = { name="Guild",        icon="Interface\\Buttons\\UI-MicroButton-Guild-Up",        execute=function() ToggleGuildFrame() end },
            [12] = { name="Group",        icon="Interface\\Buttons\\UI-MicroButton-GroupFinder-Up",  execute=function() PVEFrame_ToggleFrame() end },
        },
    },
    [2] = {
        name = "System",
        slots = {
            [1]  = { name="PvP",         icon="Interface\\Buttons\\UI-MicroButton-PVP-Up",          execute=function() TogglePVPUI() end },
            [2]  = { name="Store",       icon="Interface\\Buttons\\UI-MicroButton-Store-Up",        execute=function() ToggleStoreUI() end },
            [3]  = { name="Help",        icon="Interface\\Buttons\\UI-MicroButton-Help-Up",         execute=function() ToggleHelpFrame() end },
            [4]  = { name="Main Menu",   icon="Interface\\Buttons\\UI-MicroButton-MainMenu-Up",     execute=function() ToggleGameMenu() end },
            [5]  = { name="Calendar",    icon="Interface\\Icons\\INV_Misc_SunCalendar",             execute=function() GameTimeCalendar_Toggle() end },
            [6]  = { name="Screenshot",  icon="Interface\\Icons\\INV_Misc_Camera_01",               execute=function() Screenshot() end },
            [7]  = { name="Professions", icon="Interface\\Buttons\\UI-MicroButton-Profession-Up",   execute=function() if ToggleProfessionsBook then ToggleProfessionsBook() end end },
            [8]  = { name="World Map",   icon="Interface\\Buttons\\UI-MicroButton-WorldMap-Up",     execute=function() if WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) else ShowUIPanel(WorldMapFrame) end end },
            [9]  = { name="LFD",         icon="Interface\\Buttons\\UI-MicroButton-GroupFinder-Up",  execute=function() PVEFrame_ToggleFrame() end },
            [10] = { name="Mounts",      icon="Interface\\Icons\\INV_Mount_DragonTurtle_Blue",      execute=function() ToggleCollectionsJournal(2) end },
        },
    },
}

-- ── Module state ──────────────────────────────────────────────────────────────
Radial.listWindow    = nil   -- single outer window Frame
Radial.wheels        = {}    -- [1..MAX_WHEELS] page container Frames (children of listWindow)
Radial.wheelButtons  = {}    -- [wheelIdx][slotIdx] row button Frames
Radial.currentWheel  = 1
Radial.isVisible     = false
Radial.isLocked      = false -- compat stub; always false in list mode
Radial.peekTimer     = nil   -- compat stub
Radial.selectedIndex = nil   -- currently highlighted slot index (nil = none)

-- ── Frame creation ────────────────────────────────────────────────────────────

function Radial:CreateListFrames()
    if self.listWindow then return end

    -- ── Outer window ─────────────────────────────────────────────────────────
    local win = CreateFrame("Frame", "CouchPotatoListWindow", UIParent)
    win:SetSize(WIN_WIDTH, WIN_HEIGHT)
    win:SetPoint("CENTER", UIParent, "CENTER", -180, 0)
    win:SetFrameStrata("DIALOG")
    win:Hide()
    self.listWindow = win

    -- Window background
    local bg = win:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(win)
    bg:SetColorTexture(0.04, 0.04, 0.10, 0.96)

    -- ── Header bar ───────────────────────────────────────────────────────────
    local headerBg = win:CreateTexture(nil, "BACKGROUND")
    headerBg:SetSize(WIN_WIDTH, HEADER_H)
    headerBg:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    headerBg:SetColorTexture(0.0, 0.0, 0.0, 0.5)

    win.titleText = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.titleText:SetPoint("LEFT", win, "TOPLEFT", WIN_PAD, -(HEADER_H / 2))
    win.titleText:SetTextColor(SEL_R, SEL_G, SEL_B, 1)

    win.pageLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.pageLabel:SetPoint("RIGHT", win, "TOPRIGHT", -WIN_PAD, -(HEADER_H / 2))
    win.pageLabel:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Gold separator line under header
    local sep = win:CreateTexture(nil, "OVERLAY")
    sep:SetSize(WIN_WIDTH - 8, 1)
    sep:SetPoint("TOPLEFT", win, "TOPLEFT", 4, -HEADER_H)
    sep:SetColorTexture(SEL_R, SEL_G, SEL_B, 0.35)

    -- ── Footer hint ──────────────────────────────────────────────────────────
    win.footerText = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.footerText:SetPoint("BOTTOM", win, "BOTTOM", 0, DOT_H + 6)
    win.footerText:SetTextColor(0.5, 0.5, 0.5, 1)
    win.footerText:SetText("[A] Select  [B] Close  [LB/RB] Page")

    -- ── Page-indicator dots ──────────────────────────────────────────────────
    win.dots = {}
    local dotSize  = 6
    local dotGap   = 10
    local dotsW    = MAX_WHEELS * (dotSize + dotGap) - dotGap
    for i = 1, MAX_WHEELS do
        local dot = win:CreateTexture(nil, "OVERLAY")
        dot:SetSize(dotSize, dotSize)
        local xOff = (i - 1) * (dotSize + dotGap) - dotsW / 2 + dotSize / 2
        dot:SetPoint("BOTTOM", win, "BOTTOM", xOff, 6)
        dot:SetColorTexture(0.4, 0.4, 0.4, 0.8)
        win.dots[i] = dot
    end

    -- ── Per-page frames (each holds MAX_SLOTS vertically stacked rows) ───────
    local contentTop = -(HEADER_H + 2)  -- y offset from window top-left

    for wheelIdx = 1, MAX_WHEELS do
        local page = CreateFrame("Frame", "CouchPotatoPage"..wheelIdx, win)
        page:SetSize(WIN_INNER, MAX_SLOTS * ROW_HEIGHT)
        page:SetPoint("TOPLEFT", win, "TOPLEFT", WIN_PAD, contentTop)
        page:Hide()  -- shown by ShowCurrentWheel
        self.wheels[wheelIdx] = page
        self.wheelButtons[wheelIdx] = {}

        for slotIdx = 1, MAX_SLOTS do
            local yOff = -(slotIdx - 1) * ROW_HEIGHT

            -- SecureActionButtonTemplate: combat-safe for user pages (3+)
            local row = CreateFrame("CheckButton",
                string.format("CouchPotatoPage%dRow%d", wheelIdx, slotIdx),
                page, "SecureActionButtonTemplate")
            row:SetSize(WIN_INNER, ROW_HEIGHT - 2)
            row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, yOff)
            row:RegisterForClicks("AnyDown")
            row:SetAttribute("type", "empty")

            -- Row background (alternating shade for readability)
            local shade = (slotIdx % 2 == 0) and 0.08 or 0.04
            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints(row)
            rowBg:SetColorTexture(shade, shade, shade + 0.03, 0.9)
            row.rowBg = rowBg

            -- Left accent bar: visible only on the selected row
            local accent = row:CreateTexture(nil, "OVERLAY")
            accent:SetSize(3, ROW_HEIGHT - 8)
            accent:SetPoint("LEFT", row, "LEFT", 0, 0)
            accent:SetColorTexture(SEL_R, SEL_G, SEL_B, 1)
            accent:Hide()
            row.accentBar = accent

            -- Icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon:SetPoint("LEFT", row, "LEFT", 8, 0)
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon = icon

            -- Name label
            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameLabel:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            nameLabel:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            nameLabel:SetJustifyH("LEFT")
            nameLabel:SetTextColor(0.9, 0.9, 0.9, 1)
            nameLabel:SetText("")
            row.nameLabel = nameLabel

            -- Glow overlay (additive blend; alpha 0 = off, ~0.55 = selected)
            local glow = row:CreateTexture(nil, "OVERLAY")
            glow:SetAllPoints(row)
            glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            glow:SetBlendMode("ADD")
            glow:SetAlpha(0)
            row.glowOverlay = glow

            self.wheelButtons[wheelIdx][slotIdx] = row
        end
    end
end

-- ── Selection highlight ───────────────────────────────────────────────────────

-- Applies or clears the gold glow selection highlight on a specific row
function Radial:SetRowHighlight(wheelIdx, slotIdx, state)
    if not slotIdx then return end
    local row = self.wheelButtons[wheelIdx] and self.wheelButtons[wheelIdx][slotIdx]
    if not row then return end
    if state then
        row.rowBg:SetColorTexture(SEL_R * 0.28, SEL_G * 0.28, 0, 0.55)
        row.glowOverlay:SetAlpha(0.55)
        row.accentBar:Show()
        row.nameLabel:SetTextColor(SEL_R, SEL_G, SEL_B, 1)
    else
        local shade = (slotIdx % 2 == 0) and 0.08 or 0.04
        row.rowBg:SetColorTexture(shade, shade, shade + 0.03, 0.9)
        row.glowOverlay:SetAlpha(0)
        row.accentBar:Hide()
        row.nameLabel:SetTextColor(0.9, 0.9, 0.9, 1)
    end
end

-- ── Navigation ────────────────────────────────────────────────────────────────

-- Returns an ordered list of slot indices that have content on the given page
function Radial:GetVisibleSlots(wheelIdx)
    local result = {}
    local wheelDef = INTERFACE_WHEEL_LAYOUTS[wheelIdx]
    if wheelDef then
        for i = 1, MAX_SLOTS do
            if wheelDef.slots[i] then table.insert(result, i) end
        end
    else
        for i = 1, MAX_SLOTS do
            local row = self.wheelButtons[wheelIdx] and self.wheelButtons[wheelIdx][i]
            if row and row:GetAttribute("type") ~= "empty" then
                table.insert(result, i)
            end
        end
    end
    return result
end

-- Moves the selection by +1 (down) or -1 (up), wrapping at the list ends
function Radial:NavigateList(direction)
    local visible = self:GetVisibleSlots(self.currentWheel)
    if #visible == 0 then return end

    local curPos = 1
    if self.selectedIndex then
        for i, slot in ipairs(visible) do
            if slot == self.selectedIndex then curPos = i; break end
        end
    end

    local newPos  = ((curPos - 1 + direction) % #visible) + 1
    local newSlot = visible[newPos]

    self:SetRowHighlight(self.currentWheel, self.selectedIndex, false)
    self.selectedIndex = newSlot
    self:SetRowHighlight(self.currentWheel, newSlot, true)
end

-- ── Open / Close / Execute ────────────────────────────────────────────────────

-- Opens the list menu (called on trigger press)
function Radial:OpenWheel()
    if self.isVisible then return end
    self:ShowCurrentWheel()
    -- Auto-select first visible item
    local visible = self:GetVisibleSlots(self.currentWheel)
    if #visible > 0 then
        self.selectedIndex = visible[1]
        self:SetRowHighlight(self.currentWheel, self.selectedIndex, true)
    end
end

-- Closes without executing (B button)
function Radial:CloseWheel()
    if not self.isVisible then return end
    self:HideCurrentWheel()
end

-- Executes the selected item and closes (A button)
function Radial:ConfirmAndClose()
    if not self.isVisible then return end

    local slot = self.selectedIndex
    if slot then
        local wheelDef = INTERFACE_WHEEL_LAYOUTS[self.currentWheel]
        local slotDef  = wheelDef and wheelDef.slots[slot]
        if slotDef and slotDef.execute then
            local ok, err = pcall(slotDef.execute)
            if not ok then CP:Print("CouchPotato: " .. tostring(err)) end
        elseif not InCombatLockdown() then
            -- User-configured pages (3+): click the SecureActionButton
            local row = self.wheelButtons[self.currentWheel] and
                        self.wheelButtons[self.currentWheel][slot]
            if row then row:Click("LeftButton") end
        end
    end

    self:HideCurrentWheel()
end

-- ── Show / Hide ───────────────────────────────────────────────────────────────

function Radial:ShowCurrentWheel()
    -- Show only the active page; hide all others
    for i = 1, MAX_WHEELS do
        if self.wheels[i] then
            if i == self.currentWheel then
                self.wheels[i]:Show()
            else
                self.wheels[i]:Hide()
            end
        end
    end

    self:UpdateWheelHeader()

    local win = self.listWindow
    if win then
        win:Show()
        win:SetAlpha(0)
        local alpha = (CP.db and CP.db.profile and CP.db.profile.radialAlpha) or 0.9
        if UIFrameFadeIn then
            UIFrameFadeIn(win, LIST_FADE, 0, alpha)
        else
            win:SetAlpha(alpha)
        end
    end

    self.isVisible = true

    local Bindings = CP:GetModule("Bindings", true)
    if Bindings then Bindings:ApplyWheelBindings(self.currentWheel) end
end

function Radial:HideCurrentWheel()
    -- Clear the current highlight
    if self.currentWheel and self.selectedIndex then
        self:SetRowHighlight(self.currentWheel, self.selectedIndex, false)
    end
    self.selectedIndex = nil

    -- Hide all page frames and the window
    for i = 1, MAX_WHEELS do
        if self.wheels[i] then self.wheels[i]:Hide() end
    end
    if self.listWindow then self.listWindow:Hide() end

    self.isVisible = false
    self.isLocked  = false

    local Bindings = CP:GetModule("Bindings", true)
    if Bindings then Bindings:RestoreDirectBindings() end
end

-- ── Page cycling ─────────────────────────────────────────────────────────────

function Radial:CycleWheelNext()
    self:SetRowHighlight(self.currentWheel, self.selectedIndex, false)
    self.selectedIndex = nil
    self.currentWheel = self.currentWheel % MAX_WHEELS + 1
    self:UpdateWheelDots()
    if self.isVisible then
        self:ShowCurrentWheel()
        local visible = self:GetVisibleSlots(self.currentWheel)
        if #visible > 0 then
            self.selectedIndex = visible[1]
            self:SetRowHighlight(self.currentWheel, self.selectedIndex, true)
        end
    end
end

function Radial:CycleWheelPrev()
    self:SetRowHighlight(self.currentWheel, self.selectedIndex, false)
    self.selectedIndex = nil
    self.currentWheel = (self.currentWheel - 2) % MAX_WHEELS + 1
    self:UpdateWheelDots()
    if self.isVisible then
        self:ShowCurrentWheel()
        local visible = self:GetVisibleSlots(self.currentWheel)
        if #visible > 0 then
            self.selectedIndex = visible[1]
            self:SetRowHighlight(self.currentWheel, self.selectedIndex, true)
        end
    end
end

-- ── Compat stubs (peek/lock removed; stubs keep tests/callers happy) ──────────

function Radial:PeekWheel()
    if self.isLocked then return end
    self:ShowCurrentWheel()
end

function Radial:LockWheel()
    self.isLocked = true
    if not self.isVisible then self:ShowCurrentWheel() end
end

function Radial:UnlockWheel()
    self.isLocked = false
end

-- ── Button initialisation ─────────────────────────────────────────────────────

function Radial:InitTriggerDetection()
    -- handled in InitGamePadButtonHandling
end

function Radial:InitGamePadButtonHandling()
    if self.buttonFrame then return end

    -- PADRTRIGGER: single click opens the list (no AnyUp close — trigger is open-only)
    self.triggerBtn = CreateFrame("Button", "CouchPotatoTriggerBtn", UIParent)
    self.triggerBtn:RegisterForClicks("AnyDown")
    self.triggerBtn:SetScript("OnClick", function()
        Radial:OpenWheel()
    end)

    -- PAD1 (A): confirm selected item + close
    self.confirmBtn = CreateFrame("Button", "CouchPotatoConfirmBtn", UIParent)
    self.confirmBtn:RegisterForClicks("AnyDown")
    self.confirmBtn:SetScript("OnClick", function()
        Radial:ConfirmAndClose()
    end)

    -- PAD2 (B): close without executing
    self.closeBtn = CreateFrame("Button", "CouchPotatoCloseBtn", UIParent)
    self.closeBtn:RegisterForClicks("AnyDown")
    self.closeBtn:SetScript("OnClick", function()
        Radial:CloseWheel()
    end)

    -- D-pad up: navigate list upward (−1 = toward index 1)
    self.navUpBtn = CreateFrame("Button", "CouchPotatoNavUpBtn", UIParent)
    self.navUpBtn:RegisterForClicks("AnyDown")
    self.navUpBtn:SetScript("OnClick", function()
        Radial:NavigateList(-1)
    end)

    -- D-pad down: navigate list downward (+1 = toward last index)
    self.navDownBtn = CreateFrame("Button", "CouchPotatoNavDownBtn", UIParent)
    self.navDownBtn:RegisterForClicks("AnyDown")
    self.navDownBtn:SetScript("OnClick", function()
        Radial:NavigateList(1)
    end)

    -- PAD2 permanent global close: when menu is NOT open, B closes all windows.
    -- Plain button (CloseAllWindows is not protected — no SecureActionButtonTemplate needed).
    self.globalCloseBtn = CreateFrame("Button", "CouchPotatoGlobalCloseBtn", UIParent)
    self.globalCloseBtn:RegisterForClicks("AnyDown")
    self.globalCloseBtn:SetScript("OnClick", function() CloseAllWindows() end)
    SetBindingClick("PAD2", "CouchPotatoGlobalCloseBtn", "LeftButton")

    -- PADLSHOULDER → cycle page backward
    self.lsBtn = CreateFrame("Button", "CouchPotatoLSBtn", UIParent)
    self.lsBtn:RegisterForClicks("AnyDown")
    self.lsBtn:SetScript("OnClick", function()
        Radial:CycleWheelPrev()
    end)

    -- PADRSHOULDER → cycle page forward
    self.rsBtn = CreateFrame("Button", "CouchPotatoRSBtn", UIParent)
    self.rsBtn:RegisterForClicks("AnyDown")
    self.rsBtn:SetScript("OnClick", function()
        Radial:CycleWheelNext()
    end)

    self.buttonFrame = self.triggerBtn
end

-- ── Window header & dots ──────────────────────────────────────────────────────

function Radial:UpdateWheelHeader()
    local win = self.listWindow
    if not win then return end
    local wheelDef = INTERFACE_WHEEL_LAYOUTS[self.currentWheel]
    local name = wheelDef and wheelDef.name or ("Page " .. self.currentWheel)
    if win.titleText then win.titleText:SetText(name) end
    if win.pageLabel  then win.pageLabel:SetText(self.currentWheel .. "/" .. MAX_WHEELS) end
end

function Radial:UpdateWheelDots()
    local win = self.listWindow
    if not win or not win.dots then return end
    for i, dot in ipairs(win.dots) do
        if i == self.currentWheel then
            dot:SetColorTexture(SEL_R, SEL_G, SEL_B, 1)
        else
            dot:SetColorTexture(0.4, 0.4, 0.4, 0.8)
        end
    end
end

-- ── Slot configuration ────────────────────────────────────────────────────────

function Radial:SetSlot(wheelIdx, slotIdx, actionType, actionValue, iconPath, slotName)
    if InCombatLockdown() then
        CP:Print("Cannot modify radial slots during combat.")
        return false
    end

    local row = self.wheelButtons[wheelIdx] and self.wheelButtons[wheelIdx][slotIdx]
    if not row then return false end

    row:SetAttribute("type", actionType)

    if actionType == "spell" then
        row:SetAttribute("spell", actionValue)
        local spellInfo = C_Spell.GetSpellInfo(actionValue)
        local iconID = spellInfo and spellInfo.iconID
        row.icon:SetTexture(iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
    elseif actionType == "item" then
        row:SetAttribute("item", actionValue)
        local itemInfo = C_Item.GetItemInfo(actionValue)
        local itemTexture = itemInfo and itemInfo.iconFileDataID
        row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
    elseif actionType == "macro" then
        row:SetAttribute("macro", actionValue)
        row.icon:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
    elseif actionType == "empty" then
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    if slotName then
        row.tooltipName = slotName
        if row.nameLabel then row.nameLabel:SetText(slotName) end
    end

    -- Persist to character DB
    if CP.db and CP.db.char then
        if not CP.db.char.wheelLayouts then CP.db.char.wheelLayouts = {} end
        if not CP.db.char.wheelLayouts[wheelIdx] then CP.db.char.wheelLayouts[wheelIdx] = {} end
        CP.db.char.wheelLayouts[wheelIdx][slotIdx] = { type = actionType, value = actionValue }
    end

    return true
end

function Radial:LoadLayoutsFromDB()
    if not CP.db or not CP.db.char then return end
    local layouts = CP.db.char.wheelLayouts
    if not layouts then return end
    for wheelIdx, slots in pairs(layouts) do
        if wheelIdx > 2 then  -- pages 1-2 are always fixed interface panels
            for slotIdx, slotData in pairs(slots) do
                if slotData.type and slotData.value then
                    self:SetSlot(wheelIdx, slotIdx, slotData.type, slotData.value)
                end
            end
        end
    end
end

-- Populates pages 1-2 with fixed interface-panel toggles.
-- Called after LoadLayoutsFromDB so it always wins for those pages.
function Radial:LoadInterfaceLayouts()
    for wheelIdx, wheelDef in pairs(INTERFACE_WHEEL_LAYOUTS) do
        for slotIdx, slotDef in pairs(wheelDef.slots) do
            local row = self.wheelButtons[wheelIdx] and self.wheelButtons[wheelIdx][slotIdx]
            if row and not InCombatLockdown() then
                row.icon:SetTexture(slotDef.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                if row.nameLabel then row.nameLabel:SetText(slotDef.name or "") end
                row.tooltipName = slotDef.name
            end
        end
    end
end

function Radial:LoadDefaultLayouts()
    -- Load the current spec's default layout into page 1
    local Specs = CP:GetModule("Specs")
    if not Specs then return end
    local layout = Specs:GetCurrentLayout()
    if not layout then return end

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

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function Radial:OnEnable()
    self:CreateListFrames()
    self:InitTriggerDetection()
    self:InitGamePadButtonHandling()
    self:LoadLayoutsFromDB()
    self:LoadInterfaceLayouts()
    self:UpdateWheelHeader()
    self:UpdateWheelDots()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEnter")
end

function Radial:OnSpecChanged()
    -- Pages 1-2 are fixed interface panels; pages 3+ use DB-saved layouts.
end

function Radial:OnEnteringWorld()
    if not InCombatLockdown() then
        self:LoadInterfaceLayouts()
    end
end

-- Close all open windows when the player enters combat (fires before lockdown)
function Radial:OnCombatEnter()
    CloseAllWindows()
end

-- Public API
function Radial:GetCurrentWheel() return self.currentWheel end
function Radial:IsVisible()       return self.isVisible end
function Radial:IsLocked()        return self.isLocked end
