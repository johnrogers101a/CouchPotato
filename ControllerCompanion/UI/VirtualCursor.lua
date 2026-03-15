-- ControllerCompanion/UI/VirtualCursor.lua
-- D-pad cursor for controller navigation of WoW UI elements
-- Snaps to interactable frames; D-pad moves focus
-- Patch 12.0.1 (Interface 120001)

local CP = ControllerCompanion
local VirtualCursor = CP:NewModule("VirtualCursor")

VirtualCursor.enabled = false
VirtualCursor.focusedElement = nil
VirtualCursor.cursorFrame = nil
VirtualCursor.navigableFrames = {}

function VirtualCursor:OnEnable()
    self:CreateCursorFrame()
    self.enabled = true
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Focus first available element if any UI is already up
    self:FindAndFocusFirst()
end

function VirtualCursor:OnDisable()
    self.enabled = false
    if self.cursorFrame then
        self.cursorFrame:Hide()
    end
    self.focusedElement = nil
end

function VirtualCursor:CreateCursorFrame()
    -- A golden ring/border that overlays the focused frame
    local cursor = CreateFrame("Frame", "ControllerCompanionCursor", UIParent)
    cursor:SetFrameStrata("TOOLTIP")  -- always on top
    cursor:SetSize(10, 10)            -- will be resized to match focused frame
    cursor:Hide()
    
    -- Border texture (golden)
    local border = cursor:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(cursor)
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetVertexColor(1.0, 0.85, 0.0, 0.9)  -- golden
    cursor.border = border
    
    self.cursorFrame = cursor
end

function VirtualCursor:Navigate(direction)
    -- direction: "up", "down", "left", "right"
    if not self.enabled then return end
    -- Find next navigable frame in the given direction
    -- Simple implementation: cycle through registered frames
    -- A more complete impl would do spatial sorting
    local frames = self:GetNavigableFrames()
    if #frames == 0 then return end
    
    local currentIdx = 1
    for i, f in ipairs(frames) do
        if f == self.focusedElement then
            currentIdx = i
            break
        end
    end
    
    local nextIdx
    if direction == "down" or direction == "right" then
        nextIdx = currentIdx % #frames + 1
    else
        nextIdx = (currentIdx - 2) % #frames + 1
    end
    
    self:SetFocus(frames[nextIdx])
end

function VirtualCursor:SetFocus(frame)
    if not frame then return end
    self.focusedElement = frame
    
    -- Anchor cursor to match the focused frame
    self.cursorFrame:ClearAllPoints()
    self.cursorFrame:SetAllPoints(frame)
    self.cursorFrame:Show()
    
    -- Notify GamePad for subtle haptic
    local GamePad = CP:GetModule("GamePad")
    if GamePad then GamePad:Vibrate("TARGET_CHANGE") end
end

function VirtualCursor:GetNavigableFrames()
    -- Return list of currently visible, interactable frames
    local frames = {}
    local candidates = {
        "GossipFrame", "QuestFrame", "MerchantFrame",
        "LootFrame", "CharacterFrame", "SpellBookFrame",
        "BankFrame", "AuctionHouseFrame", "MailFrame",
    }
    for _, name in ipairs(candidates) do
        local f = _G[name]
        if f and f:IsShown() then
            table.insert(frames, f)
        end
    end
    return frames
end

function VirtualCursor:FindAndFocusFirst()
    local frames = self:GetNavigableFrames()
    if frames[1] then
        self:SetFocus(frames[1])
    end
end

-- Toggle free cursor mode (stick-as-mouse)
function VirtualCursor:ToggleFreeMode()
    local freeMode = IsGamePadCursorControlEnabled()
    SetGamePadCursorControl(not freeMode)
    if not freeMode then
        -- Entering free mode: hide d-pad cursor
        self.cursorFrame:Hide()
    else
        -- Exiting free mode: restore d-pad cursor
        if self.enabled then
            self.cursorFrame:Show()
        end
    end
end
