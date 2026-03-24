-- MinimapButton.lua
-- Custom draggable minimap button for CouchPotato.
-- No external library dependencies (no LibDBIcon, no LibDataBroker).
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotatoShared

-- Icon texture: use the numeric FileDataID 134046 which maps to
-- INV_Misc_Food_15 and is guaranteed to resolve in WoW 12.x regardless of
-- any string-path lookup changes.  String paths like "Interface\\Icons\\..."
-- can silently fail in newer clients, rendering as an invisible (nil) texture.
local ICON_TEXTURE = 134046

local BUTTON_SIZE = 32

-- Convert polar angle (degrees, 0=top, clockwise) to Cartesian offset from
-- minimap centre.
--
-- BUG FIX (2026-03-24): Previous formula used (angle - 90) which inverted the
-- Y axis — angle 0 mapped to the bottom of the minimap instead of the top, and
-- angle 225 (default, lower-left) appeared at upper-left in-game.
-- Correct formula: rad = (90 - angle) so that:
--   angle   0  → top    (x=0,      y=+r)
--   angle  90  → right  (x=+r,     y=0)
--   angle 180  → bottom (x=0,      y=-r)
--   angle 270  → left   (x=-r,     y=0)
--   angle 225  → lower-left (x=-r*0.707, y=-r*0.707)  ← correct default pos
local function AngleToOffset(angle, radius)
    local rad = math.rad(90 - angle)   -- BUG FIX: was (angle - 90)
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Debug("CP", string.format(
            "MinimapButton: AngleToOffset angle=%.1f rad=%.4f x=%.2f y=%.2f",
            angle, rad, x, y))
    end
    return x, y
end

local function GetMinimapRadius()
    if not Minimap then return 80 end
    local w = Minimap:GetWidth() or 160
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Debug("CP", "MinimapButton: minimap width=" .. tostring(w))
    end
    return w / 2
end

local function PositionButton(btn, angle)
    local radius = GetMinimapRadius() + BUTTON_SIZE / 2 - 4
    local x, y = AngleToOffset(angle, radius)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Debug("CP", string.format(
            "MinimapButton: PositionButton angle=%.1f radius=%.1f x=%.2f y=%.2f",
            angle, radius, x, y))
    end
end

local function SaveAngle(angle)
    if CouchPotatoDB then
        CouchPotatoDB.minimapAngle = angle
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Debug("CP", "MinimapButton: position saved, angle=" .. tostring(angle))
        end
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
    -- atan2: angle from positive X axis; convert to clockwise-from-top.
    -- NOTE: this must be the inverse of AngleToOffset.
    -- AngleToOffset: x = cos(90-angle), y = sin(90-angle)
    -- So: atan2(y, x) = 90-angle  →  angle = 90 - atan2(y,x)
    local angle = NormalizeAngle(90 - math.deg(math.atan2(dy, dx)))
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Debug("CP", string.format(
            "MinimapButton: MouseToAngle mx=%.1f my=%.1f cx=%.1f cy=%.1f dx=%.1f dy=%.1f angle=%.1f",
            mx, my, cx, cy, dx, dy, angle))
    end
    return angle
end

local _button = nil
local _isDragging = false
local _currentAngle = 225

local function BuildButton()
    if _button then
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Debug("CP", "MinimapButton: BuildButton called but button already exists, skipping")
        end
        return
    end

    _currentAngle = GetSavedAngle()

    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "MinimapButton: BuildButton starting, icon=" .. tostring(ICON_TEXTURE)
            .. " size=" .. BUTTON_SIZE .. " savedAngle=" .. tostring(_currentAngle))
    end

    local btn = CreateFrame("Button", "CouchPotatoMinimapButton", Minimap)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Debug("CP", "MinimapButton: frame created, strata=MEDIUM level=8")
    end

    -- Background circle texture
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Background")

    -- Icon: use BACKGROUND layer so it sits above the background circle but
    -- below any overlays.  20x20 keeps it comfortably inside the 32x32 button.
    -- SetTexCoord trims the built-in icon border that WoW bakes into every
    -- Interface/Icons texture, preventing a washed-out or clipped appearance.
    local icon = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    btn._icon = icon

    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Debug("CP", "MinimapButton: icon texture set to " .. tostring(ICON_TEXTURE))
    end

    -- Highlight overlay
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Border ring — MiniMap-TrackingBorder is designed for ~54x54; using SetAllPoints()
    -- would squish it to 32x32 and cover the icon entirely.  Size it to 52x52 and
    -- offset TOPLEFT by (-6, 6) so the ring frames the button without obscuring it.
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -6, 6)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Debug("CP", "MinimapButton: OnEnter — showing tooltip")
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("CouchPotato")
        GameTooltip:AddLine("Left-click to open config", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Debug("CP", "MinimapButton: OnLeave — hiding tooltip")
        end
        GameTooltip:Hide()
    end)

    -- Left-click: toggle config window
    btn:SetScript("OnClick", function(self, button)
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Debug("CP", "MinimapButton: OnClick button=" .. tostring(button)
                .. " isDragging=" .. tostring(_isDragging))
        end
        if button == "LeftButton" and not _isDragging then
            if _G.CouchPotatoLog then
                _G.CouchPotatoLog:Info("CP", "MinimapButton: left-click confirmed, toggling config window")
            end
            if CP.ConfigWindow then
                CP.ConfigWindow.Toggle()
            else
                if _G.CouchPotatoLog then
                    _G.CouchPotatoLog:Info("CP", "MinimapButton: CP.ConfigWindow is nil — config window not loaded?")
                end
            end
        end
    end)

    -- Drag to reposition around minimap edge
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Debug("CP", "MinimapButton: drag started")
        end
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
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Info("CP", "MinimapButton: drag stopped, final angle=" .. tostring(_currentAngle))
        end
    end)

    PositionButton(btn, _currentAngle)
    _button = btn

    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "MinimapButton: created successfully at angle=" .. tostring(_currentAngle))
    end
end

-- Public API
CP.MinimapButton = {
    Build = function()
        if Minimap then
            BuildButton()
        else
            if _G.CouchPotatoLog then
                _G.CouchPotatoLog:Info("CP", "MinimapButton: Build() called but Minimap frame does not exist yet")
            end
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
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Debug("CP", "MinimapButton: SetAngle -> " .. tostring(_currentAngle))
        end
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
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Info("CP", "MinimapButton: PLAYER_LOGIN received, building button")
        end
        CP.MinimapButton.Build()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
