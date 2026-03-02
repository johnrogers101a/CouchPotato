-- CouchPotato/Core/BlizzardFrames.lua
-- Hides default Blizzard UI frames when controller mode is active
-- Restores them on controller disconnect
-- CRITICAL: All hide/show calls MUST check InCombatLockdown()
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local BlizzardFrames = CP:NewModule("BlizzardFrames")

-- Frames to suppress, with their event re-show handlers to also suppress
local MANAGED_FRAMES = {
    { name = "MainMenuBar",         events = { "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR" } },
    { name = "MultiBarBottomLeft",  events = {} },
    { name = "MultiBarBottomRight", events = {} },
    { name = "MultiBarLeft",        events = {} },
    { name = "MultiBarRight",       events = {} },
    { name = "PlayerFrame",         events = { "UNIT_PORTRAIT_UPDATE", "UNIT_HEALTH" } },
    { name = "TargetFrame",         events = { "PLAYER_TARGET_CHANGED" } },
    { name = "FocusFrame",          events = { "PLAYER_FOCUS_CHANGED" } },
    { name = "CastingBarFrame",     events = { "UNIT_SPELLCAST_START" } },
    { name = "PossessBarFrame",     events = {} },
    { name = "OverrideActionBar",   events = {} },
}

BlizzardFrames.hiddenFrames = {}

function BlizzardFrames:HideAll()
    if InCombatLockdown() then
        -- Queue for after combat
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatLeave")
        self.pendingHide = true
        return
    end
    
    for _, frameInfo in ipairs(MANAGED_FRAMES) do
        local frame = _G[frameInfo.name]
        if frame and frame:IsShown() then
            -- Unregister events that would re-show the frame
            for _, event in ipairs(frameInfo.events) do
                frame:UnregisterEvent(event)
            end
            frame:Hide()
            self.hiddenFrames[frameInfo.name] = true
        end
    end
    
    -- Party frames 1-4
    for i = 1, 4 do
        local pf = _G["PartyMemberFrame" .. i]
        if pf then
            pf:Hide()
            self.hiddenFrames["PartyMemberFrame"..i] = true
        end
    end
end

function BlizzardFrames:RestoreAll()
    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatLeave")
        self.pendingRestore = true
        return
    end
    
    for _, frameInfo in ipairs(MANAGED_FRAMES) do
        local frame = _G[frameInfo.name]
        if frame and self.hiddenFrames[frameInfo.name] then
            frame:Show()
            -- Re-register events (WoW re-registers them via the frame's own init — just show it)
            self.hiddenFrames[frameInfo.name] = nil
        end
    end
    
    for i = 1, 4 do
        local pf = _G["PartyMemberFrame"..i]
        if pf and self.hiddenFrames["PartyMemberFrame"..i] then
            pf:Show()
            self.hiddenFrames["PartyMemberFrame"..i] = nil
        end
    end
    
    -- Re-show MainMenuBar properly
    if MainMenuBar then
        MainMenuBar:Show()
    end
end

function BlizzardFrames:OnCombatLeave()
    if self.pendingHide then
        self.pendingHide = false
        self:HideAll()
    elseif self.pendingRestore then
        self.pendingRestore = false
        self:RestoreAll()
    end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

function BlizzardFrames:OnEnable()
    if CP.db.profile.hideBlizzardFrames and C_GamePad.IsEnabled() then
        self:HideAll()
    end
end

function BlizzardFrames:OnDisable()
    self:RestoreAll()
end
