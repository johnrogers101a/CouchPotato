-- InfoPanels/Editor/PropertiesPanel.lua
-- Properties panel: edit selected element's font, color, size, format, label.
-- Single Responsibility: Element property editing UI.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local PropertiesPanel = {}
ns.EditorPropertiesPanel = PropertiesPanel

local _propFrame = nil
local _currentBinding = nil
local _currentIndex = nil
local _onChangeCallback = nil

-------------------------------------------------------------------------------
-- SetOnChange: Callback when a property is modified.
-- Signature: callback(index, binding)
-------------------------------------------------------------------------------
function PropertiesPanel.SetOnChange(callback)
    _onChangeCallback = callback
end

-------------------------------------------------------------------------------
-- Build: Create the properties panel UI inside the given parent frame.
-------------------------------------------------------------------------------
function PropertiesPanel.Build(parent, width, height)
    if _propFrame then return _propFrame end

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height)

    -- Header
    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -2)
    header:SetText("Properties")
    header:SetTextColor(1, 0.82, 0, 1)

    -- "No selection" message
    local noSelMsg = container:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    noSelMsg:SetPoint("CENTER", container, "CENTER", 0, 0)
    noSelMsg:SetText("Click an element in the preview\nto edit its properties")
    noSelMsg:SetJustifyH("CENTER")
    container._noSelMsg = noSelMsg

    -- Properties form (hidden until selection)
    local form = CreateFrame("Frame", nil, container)
    form:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    form:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 4)
    form:Hide()
    container._form = form

    -- Label field
    local labelLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelLabel:SetPoint("TOPLEFT", form, "TOPLEFT", 0, 0)
    labelLabel:SetText("Label:")
    labelLabel:SetTextColor(0.8, 0.8, 0.8, 1)

    local labelInput = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    labelInput:SetSize(width - 60, 18)
    labelInput:SetPoint("LEFT", labelLabel, "RIGHT", 4, 0)
    labelInput:SetAutoFocus(false)
    labelInput:SetMaxLetters(100)
    container._labelInput = labelInput

    labelInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        PropertiesPanel._applyChange("label", self:GetText())
    end)
    labelInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Format field
    local formatLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formatLabel:SetPoint("TOPLEFT", labelLabel, "BOTTOMLEFT", 0, -8)
    formatLabel:SetText("Format:")
    formatLabel:SetTextColor(0.8, 0.8, 0.8, 1)

    local formatInput = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    formatInput:SetSize(width - 70, 18)
    formatInput:SetPoint("LEFT", formatLabel, "RIGHT", 4, 0)
    formatInput:SetAutoFocus(false)
    formatInput:SetMaxLetters(50)
    container._formatInput = formatInput

    formatInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        PropertiesPanel._applyChange("format", self:GetText())
    end)
    formatInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Font selector (simple dropdown-like buttons)
    local fontLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontLabel:SetPoint("TOPLEFT", formatLabel, "BOTTOMLEFT", 0, -8)
    fontLabel:SetText("Font:")
    fontLabel:SetTextColor(0.8, 0.8, 0.8, 1)

    local EC = ns.EditorConstants or {}
    local fontOptions = EC.FONT_OPTIONS or {
        { value = "GameFontNormal", label = "Normal" },
        { value = "GameFontHighlightSmall", label = "Small" },
    }

    local fontX = 0
    container._fontButtons = {}
    local fontBtnContainer = CreateFrame("Frame", nil, form)
    fontBtnContainer:SetSize(width - 10, 22)
    fontBtnContainer:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -2)

    for i, opt in ipairs(fontOptions) do
        local btn = CreateFrame("Button", nil, fontBtnContainer)
        btn:SetSize(50, 22)
        btn:SetPoint("TOPLEFT", fontBtnContainer, "TOPLEFT", fontX, 0)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.2, 0.2, 0.2, 0.6)

        local selBg = btn:CreateTexture(nil, "BORDER")
        selBg:SetAllPoints()
        selBg:SetColorTexture(1, 0.82, 0, 0.3)
        selBg:Hide()

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetAllPoints()
        label:SetText(opt.label)

        btn._selBg = selBg
        btn._value = opt.value
        container._fontButtons[i] = btn

        btn:SetScript("OnClick", function()
            for _, b in ipairs(container._fontButtons) do b._selBg:Hide() end
            selBg:Show()
            PropertiesPanel._applyChange("font", opt.value)
        end)

        fontX = fontX + 54
    end

    -- Color presets
    local colorLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colorLabel:SetPoint("TOPLEFT", fontBtnContainer, "BOTTOMLEFT", 0, -8)
    colorLabel:SetText("Color:")
    colorLabel:SetTextColor(0.8, 0.8, 0.8, 1)

    local colorPresets = EC.COLOR_PRESETS or {
        { r = 1, g = 1, b = 1, label = "White" },
        { r = 1, g = 0.82, b = 0, label = "Gold" },
    }

    local colorContainer = CreateFrame("Frame", nil, form)
    colorContainer:SetSize(width - 10, 22)
    colorContainer:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -2)

    container._colorSwatches = {}
    for i, preset in ipairs(colorPresets) do
        local swatch = CreateFrame("Button", nil, colorContainer)
        swatch:SetSize(20, 20)
        swatch:SetPoint("TOPLEFT", colorContainer, "TOPLEFT", (i - 1) * 24, 0)

        local tex = swatch:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetColorTexture(preset.r, preset.g, preset.b, 1)

        local border = swatch:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0.4, 0.4, 0.4, 1)

        -- Selected-state highlight border (bright gold outline)
        local selBorder = swatch:CreateTexture(nil, "OVERLAY")
        selBorder:SetPoint("TOPLEFT", -2, 2)
        selBorder:SetPoint("BOTTOMRIGHT", 2, -2)
        selBorder:SetColorTexture(1, 0.82, 0, 1)
        selBorder:Hide()
        swatch._selBorder = selBorder

        -- Re-layer: put color tex on top of sel border
        tex:SetDrawLayer("OVERLAY", 1)

        container._colorSwatches[i] = swatch

        swatch:SetScript("OnClick", function()
            -- Clear all selected states, then highlight this one
            for _, s in ipairs(container._colorSwatches) do
                if s._selBorder then s._selBorder:Hide() end
            end
            selBorder:Show()
            PropertiesPanel._applyChange("color", { r = preset.r, g = preset.g, b = preset.b })
        end)

        swatch:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                if GameTooltip.SetText then GameTooltip:SetText(preset.label) end
                GameTooltip:Show()
            end
        end)
        swatch:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    -- Remove binding button
    local removeBtn = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    removeBtn:SetSize(100, 20)
    removeBtn:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 0, 0)
    removeBtn:SetText("Remove")
    removeBtn:SetScript("OnClick", function()
        if _currentIndex and ns.Editor then
            ns.Editor._removeBinding(_currentIndex)
            PropertiesPanel.ClearSelection()
        end
    end)

    _propFrame = container
    return container
end

-------------------------------------------------------------------------------
-- ShowBinding: Display properties for a binding at the given index.
-------------------------------------------------------------------------------
function PropertiesPanel.ShowBinding(index, binding)
    if not _propFrame then return end
    _currentIndex = index
    _currentBinding = binding

    _propFrame._noSelMsg:Hide()
    _propFrame._form:Show()

    if _propFrame._labelInput then
        _propFrame._labelInput:SetText(binding.label or binding.sourceId or "")
    end
    if _propFrame._formatInput then
        _propFrame._formatInput:SetText(binding.format or "")
    end

    -- Update font selection visual
    if _propFrame._fontButtons then
        for _, btn in ipairs(_propFrame._fontButtons) do
            if btn._value == binding.font then
                btn._selBg:Show()
            else
                btn._selBg:Hide()
            end
        end
    end
end

-------------------------------------------------------------------------------
-- ClearSelection: Reset the properties panel to empty state.
-------------------------------------------------------------------------------
function PropertiesPanel.ClearSelection()
    if not _propFrame then return end
    _currentIndex = nil
    _currentBinding = nil
    _propFrame._noSelMsg:Show()
    _propFrame._form:Hide()
end

-------------------------------------------------------------------------------
-- _applyChange: Apply a property change and notify callback.
-------------------------------------------------------------------------------
function PropertiesPanel._applyChange(key, value)
    if not _currentBinding or not _currentIndex then return end
    _currentBinding[key] = value
    iplog("Info", "PropertiesPanel: changed " .. key .. " on binding " .. tostring(_currentIndex))
    if _onChangeCallback then
        _onChangeCallback(_currentIndex, _currentBinding)
    end
end

return PropertiesPanel
