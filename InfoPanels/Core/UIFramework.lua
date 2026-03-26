-- InfoPanels/Core/UIFramework.lua
-- Shared UI framework: gold-bordered header, collapsible content, pin/unpin,
-- draggable, position persistence. Eliminates duplicated scaffolding from
-- the former SP/DCS/DJ addons.
--
-- Single Responsibility: Frame creation and lifecycle management.
-- Open/Closed: New panel types use this framework without modifying it.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local THEME = CP and CP.THEME or {
    GOLD          = {1, 0.82, 0.0, 1},
    GOLD_LINE     = {0.9, 0.75, 0.1, 0.8},
    GOLD_ACCENT   = {1, 0.78, 0.1, 1},
    BG_DARK       = {0, 0, 0, 0.5},
    FONT_PATH     = "Fonts\\FRIZQT__.TTF",
    HEADER_HEIGHT = 24,
    COLLAPSE_BTN_SIZE = 36,
    PIN_BTN_SIZE  = 26,
    LOCK_TEXTURE   = "Interface\\Buttons\\LockButton-Locked-Up",
    UNLOCK_TEXTURE = "Interface\\Buttons\\LockButton-Unlocked-Up",
}

local UIFramework = {}
ns.UIFramework = UIFramework

local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

-------------------------------------------------------------------------------
-- GetTrackerAnchor: find the ObjectiveTracker bottom edge for docking.
-------------------------------------------------------------------------------
local function GetTrackerAnchor()
    if CP and CP.GetBaseTrackerAnchor then
        local anchor = CP.GetBaseTrackerAnchor()
        if anchor then return anchor end
    end
    return ObjectiveTrackerFrame or nil
end

-------------------------------------------------------------------------------
-- GetTrackerWidth: determine the objective tracker width for sizing panels.
-------------------------------------------------------------------------------
local function GetTrackerWidth()
    local w = 248  -- default
    if ObjectiveTrackerFrame and ObjectiveTrackerFrame.GetWidth then
        local tw = ObjectiveTrackerFrame:GetWidth()
        if tw and tw >= 100 and tw <= 400 then w = tw end
    end
    return w
end

-------------------------------------------------------------------------------
-- FormatNumber: comma-separated number formatting.
-- Delegates to Utils if available, otherwise inline implementation.
-------------------------------------------------------------------------------
function UIFramework.FormatNumber(num)
    local Utils = ns.Utils
    if Utils and Utils.FormatNumber then
        return Utils.FormatNumber(num)
    end
    if not num then return "0" end
    local s = tostring(math.floor(num))
    local result = ""
    local len = #s
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. s:sub(i, i)
    end
    return result
end

-------------------------------------------------------------------------------
-- CreatePanelFrame: Build a standard panel frame with header, content area,
-- collapse button, pin button, and drag support.
--
-- Returns a table with:
--   .frame         - the main Frame
--   .headerFrame   - the header Button
--   .headerTitle   - the header FontString
--   .contentFrame  - the content Frame
--   .collapseBtn   - the collapse Button
--   .pinBtn        - the pin Button
--   .ApplyPinnedState()   - dock to tracker
--   .ApplyUnpinnedState() - make draggable
--   .UpdateFrameHeight(contentHeight) - resize frame
--   .SetCollapsed(collapsed)
--
-- Parameters:
--   frameName    - global name for the frame (string)
--   db           - reference to SavedVariables table for this panel
--   opts         - optional table { title, gap, chainAnchor }
-------------------------------------------------------------------------------
function UIFramework.CreatePanelFrame(frameName, db, opts)
    opts = opts or {}
    local title = opts.title or "Panel"
    local gap = opts.gap or -14

    local frameWidth = GetTrackerWidth()
    local contentWidth = frameWidth - 12

    -- Main frame
    local frame
    local fOk, fR = pcall(CreateFrame, "Frame", frameName, UIParent, "BackdropTemplate")
    if fOk and fR then frame = fR
    else
        local fOk2, fR2 = pcall(CreateFrame, "Frame", frameName, UIParent)
        if fOk2 and fR2 then frame = fR2 end
    end
    if not frame then
        iplog("Error", "CreatePanelFrame: could not create frame " .. tostring(frameName))
        return nil
    end

    frame:Hide()
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(1)
    frame:SetSize(frameWidth, 80)
    frame:SetMovable(true)
    frame:EnableMouse(true)

    -- Header
    local header = CreateFrame("Button", nil, frame)
    header:SetHeight(THEME.HEADER_HEIGHT or 26)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")

    header:SetScript("OnDragStart", function()
        if db.pinned == false then frame:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        db.position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)

    -- Header background
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(header)
    headerBg:SetColorTexture(unpack(THEME.BG_DARK))

    -- Gold border lines
    local topLine = header:CreateTexture(nil, "ARTWORK")
    topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    topLine:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    topLine:SetColorTexture(unpack(THEME.GOLD_LINE))

    local bottomLine = header:CreateTexture(nil, "ARTWORK")
    bottomLine:SetHeight(1)
    bottomLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    bottomLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    bottomLine:SetColorTexture(unpack(THEME.GOLD_LINE))

    -- Header title
    local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pcall(function() headerTitle:SetFontObject(ObjectiveTitleFont) end)
    headerTitle:SetPoint("LEFT", header, "LEFT", 8, 0)
    headerTitle:SetJustifyV("MIDDLE")
    headerTitle:SetText(title)
    headerTitle:SetTextColor(unpack(THEME.GOLD))

    -- Collapse button
    local collapseBtn = CreateFrame("Button", nil, header)
    collapseBtn:SetSize(THEME.COLLAPSE_BTN_SIZE, THEME.COLLAPSE_BTN_SIZE)
    collapseBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    local collapseBtnText = collapseBtn:CreateFontString(nil, "OVERLAY")
    collapseBtnText:SetFont(THEME.FONT_PATH, 16, "OUTLINE")
    collapseBtnText:SetAllPoints(collapseBtn)
    collapseBtnText:SetJustifyH("CENTER")
    collapseBtnText:SetJustifyV("MIDDLE")
    collapseBtnText:SetTextColor(unpack(THEME.GOLD_ACCENT))
    collapseBtnText:SetText("\226\128\147")  -- em dash (collapse indicator)
    collapseBtn:SetFontString(collapseBtnText)

    -- Pin button
    local pinBtn = CreateFrame("Button", nil, header)
    pinBtn:SetSize(THEME.PIN_BTN_SIZE, THEME.PIN_BTN_SIZE)
    pinBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -4, 0)
    pinBtn:SetNormalTexture(THEME.LOCK_TEXTURE)
    pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
    pinBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    pinBtn:EnableMouse(true)

    -- Content frame
    local contentFrame
    local cok, cr = pcall(CreateFrame, "Frame", nil, frame, "BackdropTemplate")
    if cok and cr then contentFrame = cr
    else contentFrame = CreateFrame("Frame", nil, frame) end
    contentFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    contentFrame:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    contentFrame:SetHeight(52)

    -- Panel object
    local panel = {
        frame = frame,
        headerFrame = header,
        headerTitle = headerTitle,
        contentFrame = contentFrame,
        collapseBtn = collapseBtn,
        collapseBtnText = collapseBtnText,
        pinBtn = pinBtn,
        _db = db,
        _gap = gap,
        _frameWidth = frameWidth,
        _contentWidth = contentWidth,
    }

    -- Pin/unpin state management
    -- anchor (optional): explicit frame to anchor TOPRIGHT->BOTTOMRIGHT.
    -- If nil, falls back to opts.chainAnchor() or GetTrackerAnchor().
    function panel.ApplyPinnedState(anchor)
        frame:SetMovable(false)
        if not anchor then
            anchor = opts.chainAnchor and opts.chainAnchor() or GetTrackerAnchor()
        end
        frame:ClearAllPoints()
        if anchor then
            frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, gap)
            local tw = GetTrackerWidth()
            frame:SetWidth(tw)
        else
            frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
        end
        pinBtn:SetNormalTexture(THEME.LOCK_TEXTURE)
        pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
        db.pinned = true
    end

    function panel.ApplyUnpinnedState()
        frame:SetMovable(true)
        pinBtn:SetNormalTexture(THEME.UNLOCK_TEXTURE)
        pinBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
        db.pinned = false
    end

    -- Pin toggle
    pinBtn:SetScript("OnClick", function()
        if db.pinned == false then
            panel.ApplyPinnedState()
        else
            panel.ApplyUnpinnedState()
        end
        -- Notify engine so the chain can be rebuilt
        if panel.OnPinChanged then panel.OnPinChanged() end
    end)

    -- Collapse toggle
    collapseBtn:SetScript("OnClick", function()
        if contentFrame:IsShown() then
            contentFrame:Hide()
            collapseBtnText:SetText("+")
            db.collapsed = true
            frame:SetHeight(header:GetHeight())
        else
            contentFrame:Show()
            collapseBtnText:SetText("\226\128\147")
            db.collapsed = false
            if panel.OnExpand then panel.OnExpand() end
        end
        -- Notify engine so the chain can be rebuilt after height change
        if panel.OnCollapseChanged then panel.OnCollapseChanged() end
    end)

    -- UpdateFrameHeight
    function panel.UpdateFrameHeight(contentHeight)
        local headerH = header:GetHeight() or 26
        if contentFrame:IsShown() then
            contentFrame:SetHeight(contentHeight or 52)
            frame:SetHeight(headerH + (contentHeight or 52))
        else
            frame:SetHeight(headerH)
        end
    end

    -- SetCollapsed
    function panel.SetCollapsed(collapsed)
        if collapsed then
            contentFrame:Hide()
            collapseBtnText:SetText("+")
            frame:SetHeight(header:GetHeight())
        else
            contentFrame:Show()
            collapseBtnText:SetText("\226\128\147")
        end
    end

    -- Restore saved state
    function panel.RestoreState()
        if db.collapsed then
            panel.SetCollapsed(true)
        end
        if db.pinned == false then
            panel.ApplyUnpinnedState()
            local pos = db.position
            if pos and pos.point then
                frame:ClearAllPoints()
                frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
            end
        else
            db.pinned = true
            panel.ApplyPinnedState()
        end
    end

    -- Delayed width fix
    if C_Timer then
        C_Timer.After(0.5, function()
            if frame then frame:SetWidth(frameWidth) end
        end)
    end

    return panel
end

-------------------------------------------------------------------------------
-- CreateLabel: Create a standard content label in a panel's content frame.
-------------------------------------------------------------------------------
function UIFramework.CreateLabel(contentFrame, contentWidth, anchorTo, offsetY)
    local label = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if anchorTo then
        label:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY or -4)
    else
        label:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 8, offsetY or -8)
    end
    label:SetWidth(contentWidth)
    label:SetJustifyH("LEFT")
    pcall(function() label:SetFontObject(ObjectiveFont) end)
    label:SetTextColor(1, 1, 1, 1)
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    return label
end

return UIFramework
