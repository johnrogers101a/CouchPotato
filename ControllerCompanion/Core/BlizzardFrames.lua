-- ControllerCompanion/Core/BlizzardFrames.lua
-- Hides default Blizzard UI frames when controller mode is active
-- Restores them on controller disconnect
-- CRITICAL: All hide/show calls MUST check InCombatLockdown()
-- Patch 12.0.1 (Interface 120001)

local CP = ControllerCompanion
local BlizzardFrames = CP:NewModule("BlizzardFrames")

-- Frames to suppress via RegisterStateDriver while controller mode is active
local MANAGED_FRAMES = {
    "MainMenuBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarLeft",
    "MultiBarRight",
    "PlayerFrame",
    "TargetFrame",
    "FocusFrame",
    "CastingBarFrame",
    "PossessBarFrame",
    "OverrideActionBar",
}

BlizzardFrames.hiddenFrames = {}

function BlizzardFrames:HideAll()
    if InCombatLockdown() then
        -- Queue for after combat
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatLeave")
        self.pendingHide = true
        return
    end

    for _, frameName in ipairs(MANAGED_FRAMES) do
        local frame = _G[frameName]
        if frame then
            -- Use RegisterStateDriver for secure, taint-free frame hiding.
            -- Direct frame:Hide() on protected Blizzard frames (action bars, unit frames)
            -- taints the addon's execution context in TWW. The state driver runs in a
            -- secure context and can hide any frame, including protected ones.
            -- Event unregistration is intentionally omitted — the driver re-hides the
            -- frame if Blizzard code re-shows it, so we don't need to suppress events.
            RegisterStateDriver(frame, "visibility", "hide")
            self.hiddenFrames[frameName] = true
        end
    end

    -- Party frames 1-4
    for i = 1, 4 do
        local pf = _G["PartyMemberFrame" .. i]
        if pf then
            RegisterStateDriver(pf, "visibility", "hide")
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

    for _, frameName in ipairs(MANAGED_FRAMES) do
        local frame = _G[frameName]
        if frame and self.hiddenFrames[frameName] then
            UnregisterStateDriver(frame, "visibility")
            self.hiddenFrames[frameName] = nil
        end
    end

    for i = 1, 4 do
        local pf = _G["PartyMemberFrame"..i]
        if pf and self.hiddenFrames["PartyMemberFrame"..i] then
            UnregisterStateDriver(pf, "visibility")
            self.hiddenFrames["PartyMemberFrame"..i] = nil
        end
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
    if not CP.db or not CP.db.profile then return end
    if CP.db.profile.hideBlizzardFrames and C_GamePad.IsEnabled() then
        self:HideAll()
    end
end

function BlizzardFrames:OnDisable()
    self:RestoreAll()
end
