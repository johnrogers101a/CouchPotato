-- MinimapButton.lua
-- Custom draggable minimap button for CouchPotato.
-- No external library dependencies (no LibDBIcon, no LibDataBroker).
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotatoShared

-- Icon texture: use a potato-themed built-in icon
local ICON_TEXTURE = "Interface\\Icons\\INV_Misc_Food_Cooked_SpicedFishBite"

local BUTTON_SIZE = 32

-- Convert polar angle (degrees, 0=top, clockwise) to Cartesian offset from minimap center
local function AngleToOffset(angle, radius)
    local rad = math.rad(angle - 90)  -- offset so 0 = top
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    return x, y
end

local function GetMinimapRadius()
    if not Minimap then return 80 end
    return (Minimap:GetWidth() or 160) / 2
end

local function PositionButton(btn, angle)
    local radius = GetMinimapRadius() + BUTTON_SIZE / 2 - 4
    local x, y = AngleToOffset(angle, radius)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function SaveAngle(angle)
    if CouchPotatoDB then
        CouchPotatoDB.minimapAngle = angle
    end
end

local function GetSavedAngle()
    if CouchPotatoDB then
        return CouchPotatoDB.minimapAngle or 225
    end
    return 225
end

-- Clamp an angle to [0, 360)
local function NormalizeAngle(angle)
    angle = angle % 360
    if angle < 0 then angle = angle + 360 end
    return angle
end

-- Calculate angle from minimap center to mouse position
local function MouseToAngle()
    if not Minimap then return 225 end
    local mx, my = GetCursorPosition()
    local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
    mx, my = mx / scale, my / scale
    local cx = Minimap:GetLeft() + Minimap:GetWidth() / 2
    local cy = Minimap:GetBottom() + Minimap:GetHeight() / 2
    local dx, dy = mx - cx, my - cy
    -- atan2: angle from positive X axis; convert to clockwise-from-top
    local angle = math.deg(math.atan2(dy, dx))
    angle = NormalizeAngle(-angle + 90)  -- flip y-axis, shift to top=0
    return angle
end

local _button = nil
local _isDragging = false
local _currentAngle = 225

local function BuildButton()
    if _button then return end

    _currentAngle = GetSavedAngle()

    local btn = CreateFrame("Button", "CouchPotatoMinimapButton", Minimap)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    -- Background circle texture
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Background")

    -- Icon
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(BUTTON_SIZE - 8, BUTTON_SIZE - 8)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON_TEXTURE)
    btn._icon = icon

    -- Highlight overlay
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Border ring
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("CouchPotato")
        GameTooltip:AddLine("Left-click to open config", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Left-click: toggle config window
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and not _isDragging then
            if CP.ConfigWindow then
                CP.ConfigWindow.Toggle()
            end
        end
    end)

    -- Drag to reposition around minimap edge
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
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
    end)

    PositionButton(btn, _currentAngle)
    _button = btn
end

-- Public API
CP.MinimapButton = {
    Build = function()
        if Minimap then
            BuildButton()
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

-- Build the button after DB is initialized (deferred via PLAYER_LOGIN)
local _loginFrame = CreateFrame("Frame")
_loginFrame:RegisterEvent("PLAYER_LOGIN")
_loginFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        CP.MinimapButton.Build()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
