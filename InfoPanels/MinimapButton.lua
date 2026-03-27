-- InfoPanels/MinimapButton.lua
-- Custom draggable minimap button for InfoPanels.
-- Left-click opens the InfoPanels Editor directly.
-- No external library dependencies (no LibDBIcon, no LibDataBroker).
-- Patch 12.0.1 (Interface 120001)

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

-- Icon texture: 134400 maps to INV_Misc_Note_06 (a scroll/document icon),
-- visually distinct from the CouchPotato food icon (134046).
local ICON_TEXTURE = 134400

-- 33x33 matches Blizzard's standard minimap button size.
local BUTTON_SIZE = 33

-- Convert polar angle (degrees, 0=top, clockwise) to Cartesian offset from
-- minimap centre.
--   angle   0  → top    (x=0,      y=+r)
--   angle  90  → right  (x=+r,     y=0)
--   angle 180  → bottom (x=0,      y=-r)
--   angle 270  → left   (x=-r,     y=0)
local function AngleToOffset(angle, radius)
    local rad = math.rad(90 - angle)
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    return x, y
end

local function GetMinimapRadius()
    if not Minimap then return 80 end
    local w = Minimap:GetWidth() or 160
    return w / 2
end

local function PositionButton(btn, angle)
    local radius = GetMinimapRadius() + BUTTON_SIZE / 2 - 4
    local x, y = AngleToOffset(angle, radius)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function SaveAngle(angle)
    if InfoPanelsDB then
        InfoPanelsDB.minimapAngle = angle
        iplog("Debug", "MinimapButton: position saved, angle=" .. tostring(angle))
    end
end

local function GetSavedAngle()
    if InfoPanelsDB then
        return InfoPanelsDB.minimapAngle or 195
    end
    return 195
end

-- Clamp an angle to [0, 360)
local function NormalizeAngle(angle)
    angle = angle % 360
    if angle < 0 then angle = angle + 360 end
    return angle
end

-- Calculate angle from minimap center to mouse position
local function MouseToAngle()
    if not Minimap then return 195 end
    local mx, my = GetCursorPosition()
    local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
    mx, my = mx / scale, my / scale
    local cx = Minimap:GetLeft() + Minimap:GetWidth() / 2
    local cy = Minimap:GetBottom() + Minimap:GetHeight() / 2
    local dx, dy = mx - cx, my - cy
    local angle = NormalizeAngle(90 - math.deg(math.atan2(dy, dx)))
    return angle
end

local _button = nil
local _isDragging = false
local _currentAngle = 195

local function BuildButton()
    if _button then
        iplog("Debug", "MinimapButton: BuildButton called but button already exists, skipping")
        return
    end

    _currentAngle = GetSavedAngle()

    iplog("Info", "MinimapButton: BuildButton starting, icon=" .. tostring(ICON_TEXTURE)
        .. " size=" .. BUTTON_SIZE .. " savedAngle=" .. tostring(_currentAngle))

    local btn = CreateFrame("Button", "InfoPanelsMinimapButton", Minimap)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    -- Icon layer
    local icon = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    btn._icon = icon

    -- Border ring
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(56, 56)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("InfoPanels")
        GameTooltip:AddLine("Left-click to open editor", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Left-click: open the InfoPanels Editor
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and not _isDragging then
            iplog("Info", "MinimapButton: left-click, opening InfoPanels Editor")
            if ns.Editor then
                ns.Editor.Show()
            else
                iplog("Info", "MinimapButton: ns.Editor is nil — editor not loaded?")
            end
        end
    end)

    -- Drag to reposition around minimap edge
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        iplog("Debug", "MinimapButton: drag started")
        _isDragging = true
        self:SetScript("OnUpdate", function(self2)
            _currentAngle = MouseToAngle()
            PositionButton(self2, _currentAngle)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        _isDragging = false
        self:SetScript("OnUpdate", nil)
        _currentAngle = MouseToAngle()
        PositionButton(self, _currentAngle)
        SaveAngle(_currentAngle)
        iplog("Info", "MinimapButton: drag stopped, final angle=" .. tostring(_currentAngle))
    end)

    PositionButton(btn, _currentAngle)
    _button = btn

    iplog("Info", "MinimapButton: created successfully at angle=" .. tostring(_currentAngle))
end

-- Public API
ns.MinimapButton = {
    Build = function()
        if Minimap then
            BuildButton()
        else
            iplog("Info", "MinimapButton: Build() called but Minimap frame does not exist yet")
        end
    end,
    GetButton = function()
        return _button
    end,
    GetAngle = function()
        return _currentAngle
    end,
    SetAngle = function(angle)
        _currentAngle = NormalizeAngle(angle)
        if _button then
            PositionButton(_button, _currentAngle)
        end
    end,
}
