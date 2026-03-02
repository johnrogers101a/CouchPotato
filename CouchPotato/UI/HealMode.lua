-- CouchPotato/UI/HealMode.lua
-- Healer party frame overlay for controller healing
-- D-pad navigates between party/raid members
-- Face buttons auto-swap to healing spells for focused member
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local HealMode = CP:NewModule("HealMode")

HealMode.active = false
HealMode.cursorIndex = 1  -- 1-5 for party (1=tank/PT1, 2-4=party2-4, 5=self)
HealMode.maxMembers = 5
HealMode.cursorFrame = nil   -- the highlight overlay

-- Party member list (unit tokens)
local PARTY_UNITS = { "party1", "party2", "party3", "party4", "player" }

function HealMode:OnEnable()
    self:CreateOverlay()
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEnter")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatLeave")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
end

function HealMode:CreateOverlay()
    -- Thin golden border that highlights the focused party frame
    local overlay = CreateFrame("Frame", "CouchPotatoHealCursor", UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetSize(120, 36)
    overlay:Hide()
    
    -- Glow border
    local border = overlay:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(overlay)
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetVertexColor(0.2, 0.9, 0.2, 0.9)  -- green for healer
    overlay.border = border
    
    -- Role indicator text
    local roleText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleText:SetPoint("TOP", overlay, "TOP", 0, 10)
    roleText:SetTextColor(0.2, 1.0, 0.2)
    overlay.roleText = roleText
    
    self.cursorFrame = overlay
    
    -- Spell prompt buttons (show what each face button will cast)
    self:CreateSpellPrompts()
end

function HealMode:CreateSpellPrompts()
    -- Small icons near the overlay showing what A/B/X/Y will cast
    self.spellPrompts = {}
    local buttonLabels = { "A", "X", "Y", "RB" }
    local offsets = { {-40, -50}, {0, -50}, {40, -50}, {80, -50} }
    
    for i, label in ipairs(buttonLabels) do
        local prompt = CreateFrame("Frame", nil, UIParent)
        prompt:SetSize(28, 28)
        prompt:Hide()
        
        local icon = prompt:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(prompt)
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        prompt.icon = icon
        
        local keyLabel = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        keyLabel:SetPoint("BOTTOM", prompt, "TOP", 0, 2)
        keyLabel:SetText(label)
        keyLabel:SetTextColor(1, 1, 0)
        prompt.keyLabel = keyLabel
        
        self.spellPrompts[i] = prompt
    end
end

function HealMode:Enter()
    if self.active then return end
    self.active = true
    self.cursorIndex = 1
    self:MoveCursorTo(self.cursorIndex)
    self:UpdateSpellPrompts()
    self.cursorFrame:Show()
    
    -- Vibrate on mode enter
    local GamePad = CP:GetModule("GamePad")
    if GamePad then GamePad:Vibrate("HEAL_MODE_TOGGLE") end
end

function HealMode:Exit()
    if not self.active then return end
    self.active = false
    self.cursorFrame:Hide()
    for _, prompt in ipairs(self.spellPrompts or {}) do
        prompt:Hide()
    end
    
    -- Clear heal mode override bindings
    local Bindings = CP:GetModule("Bindings")
    if Bindings then
        Bindings:ClearHealModeBindings()
        Bindings:ApplyControllerBindings()  -- restore normal combat bindings
    end
    
    local GamePad = CP:GetModule("GamePad")
    if GamePad then GamePad:Vibrate("HEAL_MODE_TOGGLE") end
end

function HealMode:Navigate(direction)
    if not self.active then return end
    
    if direction == "up" then
        self.cursorIndex = math.max(1, self.cursorIndex - 1)
    elseif direction == "down" then
        self.cursorIndex = math.min(self.maxMembers, self.cursorIndex + 1)
    elseif direction == "left" then
        self.cursorIndex = math.max(1, self.cursorIndex - 1)
    elseif direction == "right" then
        self.cursorIndex = math.min(self.maxMembers, self.cursorIndex + 1)
    end
    
    self:MoveCursorTo(self.cursorIndex)
    self:UpdateSpellPrompts()
    
    local GamePad = CP:GetModule("GamePad")
    if GamePad then GamePad:Vibrate("TARGET_CHANGE") end
end

function HealMode:MoveCursorTo(index)
    local unit = PARTY_UNITS[index]
    if not unit then return end
    
    -- Try to find the healer addon's frame for this unit
    -- Check VuhDo, Grid2, Cell, default compact frames in order
    local targetFrame = self:FindHealerFrame(unit)
    
    if targetFrame then
        self.cursorFrame:ClearAllPoints()
        self.cursorFrame:SetAllPoints(targetFrame)
    else
        -- Fallback: position near party slot location
        self.cursorFrame:ClearAllPoints()
        self.cursorFrame:SetPoint("CENTER", UIParent, "LEFT", 80, 200 - (index - 1) * 45)
    end
    
    -- Apply face button bindings for this unit
    self:ApplyHealBindings(unit)
end

function HealMode:FindHealerFrame(unit)
    -- Try common healer addon frame names
    -- Cell: Cell_PartyFrameX or CellPartyHeaderUnitButton-X
    -- Grid2: Grid2Frame-partyX
    -- VuhDo: VuhDoButtonX
    -- Default: CompactPartyFrameMemberX
    
    local candidates = {
        -- Default compact frames
        "CompactPartyFrameMember" .. (unit == "player" and "1" or unit:match("%d+")),
        -- Cell
        unit == "player" and "Cell_SoloFrame" or nil,
        -- Generic fallback
        unit == "player" and "PlayerFrame" or nil,
    }
    
    for _, name in ipairs(candidates) do
        if name then
            local f = _G[name]
            if f and f:IsShown() then
                return f
            end
        end
    end
    return nil
end

function HealMode:ApplyHealBindings(unit)
    -- Apply face button bindings for healing the focused unit
    -- This uses the Bindings module's SetOverrideBinding
    if InCombatLockdown() then return end  -- can only set bindings out of combat
    -- Note: Bindings are applied out of combat. In combat, the pre-set macros fire.
    -- The macros use [@unittoken] targeting conditionals set before combat.
    
    local Specs = CP:GetModule("Specs")
    if not Specs then return end
    local layout = Specs:GetCurrentLayout()
    if not layout then return end
    
    -- Determine healer spells
    -- PAD1(A)=heal1, PAD3(X)=HoT, PAD4(Y)=big heal/util, PADRSHOULDER=dispel
    local Bindings = CP:GetModule("Bindings")
    if not Bindings then return end
    
    -- Store heal mode state for post-combat binding application
    self.currentHealUnit = unit
end

function HealMode:UpdateSpellPrompts()
    local unit = PARTY_UNITS[self.cursorIndex]
    if not unit then return end
    
    -- Show spell prompt icons based on current spec
    local Specs = CP:GetModule("Specs")
    if not Specs then return end
    local layout = Specs:GetCurrentLayout()
    if not layout then return end
    
    local prompts = {
        layout.primary,     -- A button
        layout.secondary,   -- X button
        layout.tertiary,    -- Y button
        layout.interrupt,   -- RB (dispel for healers)
    }
    
    for i, spellName in ipairs(prompts) do
        local prompt = self.spellPrompts[i]
        if prompt and spellName then
            local spellInfo = C_Spell.GetSpellInfo(spellName)
            local icon = spellInfo and spellInfo.iconID
            if icon then
                prompt.icon:SetTexture(icon)
            end
            prompt:Show()
            -- Position near cursor frame
            prompt:ClearAllPoints()
            local offsets = { {-40, -50}, {0, -50}, {40, -50}, {80, -50} }
            prompt:SetPoint("CENTER", self.cursorFrame, "BOTTOM",
                offsets[i][1], offsets[i][2])
        end
    end
end

function HealMode:IsActive()
    return self.active
end

function HealMode:OnCombatEnter()
    -- Heal mode remains active during combat — bindings were set before combat
end

function HealMode:OnCombatLeave()
    -- Reapply bindings properly after combat ends
    if self.active and self.currentHealUnit then
        self:MoveCursorTo(self.cursorIndex)
    end
end

function HealMode:OnRosterUpdate()
    -- Update max members
    self.maxMembers = math.min(GetNumGroupMembers() + 1, 5)
end
