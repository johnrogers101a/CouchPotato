-- InfoPanels/Editor/LivePreview.lua
-- Live preview pane: shows the panel being edited, updates in real-time.
-- Supports click-to-select elements and drag-to-add bindings.
-- Single Responsibility: Real-time panel preview rendering.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local THEME = CP and CP.THEME or { GOLD = {1, 0.82, 0.0, 1}, BG_DARK = {0, 0, 0, 0.5}, FONT_PATH = "Fonts\\FRIZQT__.TTF" }
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local LivePreview = {}
ns.EditorLivePreview = LivePreview

local _previewFrame = nil
local _previewLabels = {}
local _selectedIndex = nil
local _onSelectElementCallback = nil
local _isDragging = false
local _dragSourceId = nil

-------------------------------------------------------------------------------
-- SetOnSelectElement: Callback when user clicks an element in preview.
-------------------------------------------------------------------------------
function LivePreview.SetOnSelectElement(callback)
    _onSelectElementCallback = callback
end

-------------------------------------------------------------------------------
-- Build: Create the live preview UI inside the given parent frame.
-------------------------------------------------------------------------------
function LivePreview.Build(parent, width, height)
    if _previewFrame then return _previewFrame end

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height)

    -- Header
    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -2)
    header:SetText("Live Preview")
    header:SetTextColor(1, 0.82, 0, 1)

    -- Preview panel area (simulates what the real panel looks like)
    local previewArea = CreateFrame("Frame", "IPEditorPreviewArea", container, "BackdropTemplate")
    previewArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    previewArea:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 4)

    -- Dark parchment background
    local ok = pcall(function()
        previewArea:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        previewArea:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        previewArea:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
    end)
    if not ok then
        -- Fallback: simple background
        local bg = previewArea:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
    end

    -- Preview panel title
    local previewTitle = previewArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewTitle:SetPoint("TOPLEFT", previewArea, "TOPLEFT", 8, -8)
    previewTitle:SetTextColor(1, 0.82, 0, 1)
    previewTitle:SetText("Panel Preview")
    container._previewTitle = previewTitle

    -- Gold separator line
    local sep = previewArea:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -4)
    sep:SetPoint("TOPRIGHT", previewArea, "TOPRIGHT", -8, 0)
    sep:SetColorTexture(0.9, 0.75, 0.1, 0.8)
    container._separator = sep

    -- Content area for preview labels
    local contentArea = CreateFrame("Frame", nil, previewArea)
    contentArea:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -4)
    contentArea:SetPoint("BOTTOMRIGHT", previewArea, "BOTTOMRIGHT", -8, 8)
    container._contentArea = contentArea

    -- Drop target for drag-to-add.
    -- Mouse events arrive here when the cursor is over the preview area.
    -- FinishDrop() is called on MouseUp from the source row; we check
    -- IsMouseOver() to confirm the drop landed on the preview area.
    previewArea:EnableMouse(true)
    container._previewArea = previewArea

    -- "Empty panel" message
    local emptyMsg = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyMsg:SetPoint("CENTER", contentArea, "CENTER", 0, 0)
    emptyMsg:SetText("Add Lines with {{FUNCTION_NAME}} templates\nto see a live preview here")
    emptyMsg:SetJustifyH("CENTER")
    container._emptyMsg = emptyMsg

    _previewFrame = container
    return container
end

-------------------------------------------------------------------------------
-- UpdateLines: Refresh the preview with resolved line strings.
-- panelName: string title
-- resolvedLines: array of strings (already resolved templates)
-------------------------------------------------------------------------------
function LivePreview.UpdateLines(panelName, resolvedLines)
    if not _previewFrame then return end

    if _previewFrame._previewTitle then
        _previewFrame._previewTitle:SetText(panelName or "Untitled Panel")
    end

    local contentArea = _previewFrame._contentArea
    if not contentArea then return end

    for _, entry in ipairs(_previewLabels) do
        if entry.frame then entry.frame:Hide() end
    end

    resolvedLines = resolvedLines or {}

    if _previewFrame._emptyMsg then
        if #resolvedLines == 0 then
            _previewFrame._emptyMsg:Show()
        else
            _previewFrame._emptyMsg:Hide()
        end
    end

    for i, text in ipairs(resolvedLines) do
        local entry = _previewLabels[i]
        if not entry then
            local row = CreateFrame("Button", nil, contentArea)
            row:SetSize(contentArea:GetWidth() or 260, 20)
            row:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, -(i - 1) * 22)

            local selBg = row:CreateTexture(nil, "BACKGROUND")
            selBg:SetAllPoints()
            selBg:SetColorTexture(1, 0.82, 0, 0.15)
            selBg:Hide()

            local hoverBg = row:CreateTexture(nil, "HIGHLIGHT")
            hoverBg:SetAllPoints()
            hoverBg:SetColorTexture(1, 1, 1, 0.05)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", row, "LEFT", 4, 0)
            label:SetJustifyH("LEFT")

            entry = { frame = row, label = label, selBg = selBg }
            _previewLabels[i] = entry
        end

        entry.label:SetText(text or "")
        entry.frame:Show()
    end
end

-------------------------------------------------------------------------------
-- Update: Refresh the preview with current bindings (legacy).
-- bindings: array of { sourceId, label, format, font, color }
-- panelName: string title
-------------------------------------------------------------------------------
function LivePreview.Update(panelName, bindings)
    if not _previewFrame then return end

    -- Update title
    if _previewFrame._previewTitle then
        _previewFrame._previewTitle:SetText(panelName or "Untitled Panel")
    end

    local contentArea = _previewFrame._contentArea
    if not contentArea then return end

    -- Hide old labels
    for _, entry in ipairs(_previewLabels) do
        if entry.frame then entry.frame:Hide() end
    end

    bindings = bindings or {}

    -- Show/hide empty message
    if _previewFrame._emptyMsg then
        if #bindings == 0 then
            _previewFrame._emptyMsg:Show()
        else
            _previewFrame._emptyMsg:Hide()
        end
    end

    local DataSources = ns.DataSources

    for i, binding in ipairs(bindings) do
        local entry = _previewLabels[i]
        if not entry then
            local row = CreateFrame("Button", nil, contentArea)
            row:SetSize(contentArea:GetWidth() or 260, 20)
            row:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, -(i - 1) * 22)

            -- Selection highlight
            local selBg = row:CreateTexture(nil, "BACKGROUND")
            selBg:SetAllPoints()
            selBg:SetColorTexture(1, 0.82, 0, 0.15)
            selBg:Hide()

            -- Hover highlight
            local hoverBg = row:CreateTexture(nil, "HIGHLIGHT")
            hoverBg:SetAllPoints()
            hoverBg:SetColorTexture(1, 1, 1, 0.05)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", row, "LEFT", 4, 0)
            label:SetJustifyH("LEFT")

            entry = { frame = row, label = label, selBg = selBg }
            _previewLabels[i] = entry
        end

        -- Fetch current value
        local displayLabel = binding.label or binding.sourceId or ""
        local displayValue = "..."

        if DataSources then
            local Utils = ns.Utils
            local formatted, isErr = Utils and Utils.FetchAndFormatBinding(DataSources, binding)
            if isErr or not formatted then
                displayValue = "|cff888888No data|r"
            else
                displayValue = formatted
            end
        end

        -- Apply color if set
        local colorPrefix = ""
        local colorSuffix = ""
        if binding.color then
            local c = binding.color
            colorPrefix = string.format("|cff%02x%02x%02x",
                math.floor((c.r or 1) * 255),
                math.floor((c.g or 1) * 255),
                math.floor((c.b or 1) * 255))
            colorSuffix = "|r"
        end

        entry.label:SetText(colorPrefix .. displayLabel .. ": " .. displayValue .. colorSuffix)

        -- Apply font if set
        if binding.font then
            pcall(function() entry.label:SetFontObject(binding.font) end)
        end

        -- Click to select
        local capturedIndex = i
        entry.frame:SetScript("OnClick", function()
            _selectedIndex = capturedIndex
            LivePreview._highlightSelected()
            if _onSelectElementCallback then
                _onSelectElementCallback(capturedIndex, binding)
            end
        end)

        -- Update selection visual
        if capturedIndex == _selectedIndex then
            entry.selBg:Show()
        else
            entry.selBg:Hide()
        end

        entry.frame:Show()
    end
end

-------------------------------------------------------------------------------
-- _highlightSelected: Update visual selection in preview.
-------------------------------------------------------------------------------
function LivePreview._highlightSelected()
    for i, entry in ipairs(_previewLabels) do
        if entry.frame and entry.frame:IsShown() then
            if i == _selectedIndex then
                entry.selBg:Show()
            else
                entry.selBg:Hide()
            end
        end
    end
end

-------------------------------------------------------------------------------
-- GetSelectedIndex: Return the currently selected element index.
-------------------------------------------------------------------------------
function LivePreview.GetSelectedIndex()
    return _selectedIndex
end

-------------------------------------------------------------------------------
-- Drag support for drag-from-browser-to-preview.
--
-- Flow:
--   1. Source row OnMouseDown  → StartDrag(sourceId)  — arm the drag state
--   2. Source row OnMouseUp    → FinishDrop()          — check cursor location
--      a. If cursor is over the preview area: add the binding, clear state
--      b. Otherwise: just clear state (cancelled drag)
-------------------------------------------------------------------------------
function LivePreview.StartDrag(sourceId)
    _isDragging = true
    _dragSourceId = sourceId
    iplog("Info", "LivePreview: drag started for " .. tostring(sourceId))
end

-- FinishDrop: called on MouseUp from the source row.
-- If the cursor is currently over the preview area, treat it as a successful drop.
function LivePreview.FinishDrop()
    if not _isDragging or not _dragSourceId then return end

    local sourceId = _dragSourceId
    -- Clear drag state first to avoid re-entrancy.
    _isDragging = false
    _dragSourceId = nil

    -- Check whether the cursor landed on the preview area.
    -- Check both the inner previewArea and the outer preview container frame
    -- to handle cases where anchoring gives the container size but the inner
    -- area hasn't settled its bounds yet.
    local previewArea = _previewFrame and _previewFrame._previewArea
    local overPreview = (previewArea and previewArea:IsMouseOver())
                     or (_previewFrame and _previewFrame:IsMouseOver())
    if overPreview then
        iplog("Info", "LivePreview: drop accepted for " .. tostring(sourceId))
        if ns.Editor and ns.Editor._addBinding then
            ns.Editor._addBinding(sourceId)
        end
    else
        iplog("Info", "LivePreview: drag cancelled (not over preview area)")
    end
end

-- StopDrag: cancel any in-progress drag without attempting a drop.
function LivePreview.StopDrag()
    _isDragging = false
    _dragSourceId = nil
end

return LivePreview
