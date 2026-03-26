-- InfoPanels/Core/LayoutTypes.lua
-- Registered layout types for the InfoPanels engine.
-- Each layout type arranges child elements within a panel's content frame.
-- New layouts are added by calling Registry.RegisterLayoutType() — no engine changes.
--
-- Single Responsibility: Layout type definitions and registration.

local _, ns = ...
if not ns then ns = {} end

local Registry = ns.Registry
if not Registry then return end

local CP = _G.CouchPotatoShared
local THEME = CP and CP.THEME or {
    GOLD = {1, 0.82, 0.0, 1},
    FONT_PATH = "Fonts\\FRIZQT__.TTF",
}

-------------------------------------------------------------------------------
-- vertical_list: Simple vertical stacking of label:value rows.
-- This is the default layout for user-created panels.
-------------------------------------------------------------------------------
Registry.RegisterLayoutType("vertical_list", {
    default = {
        rowHeight = 18,
        rowSpacing = 4,
        padding = 8,
    },
    arrange = function(contentFrame, elements, layoutData)
        layoutData = layoutData or {}
        local rowHeight = layoutData.rowHeight or 18
        local rowSpacing = layoutData.rowSpacing or 4
        local padding = layoutData.padding or 8
        local y = -padding

        for i, elem in ipairs(elements) do
            if elem.frame then
                elem.frame:ClearAllPoints()
                elem.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", padding, y)
                elem.frame:SetPoint("RIGHT", contentFrame, "RIGHT", -padding, 0)
                elem.frame:SetHeight(rowHeight)
                elem.frame:Show()
                y = y - rowHeight - rowSpacing
            end
        end

        return math.abs(y) + padding
    end,
})

-------------------------------------------------------------------------------
-- circle_row: Horizontal row of circles with connectors (for StatPriority).
-- Each element is a circle with a label on top and value below.
-- Connectors (> or =) appear between circles.
-------------------------------------------------------------------------------
Registry.RegisterLayoutType("circle_row", {
    default = {
        circleSize = 46,
        connectorWidth = 8,
        topPadding = 7,
        leftPadding = 4,
    },
    arrange = function(contentFrame, elements, layoutData)
        layoutData = layoutData or {}
        local circleSize = layoutData.circleSize or 46
        local connectorW = layoutData.connectorWidth or 8
        local topPadding = layoutData.topPadding or 7
        local leftPadding = layoutData.leftPadding or 4

        for i, elem in ipairs(elements) do
            if elem.frame then
                local x = leftPadding + (i - 1) * (circleSize + connectorW)
                elem.frame:ClearAllPoints()
                elem.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", x, -topPadding)
                elem.frame:SetSize(circleSize, circleSize)
                elem.frame:Show()
            end
            -- Connector is handled by the panel type, not the layout
        end

        return circleSize + topPadding * 2
    end,
})

-------------------------------------------------------------------------------
-- multi_section: Vertical sections with optional headers and conditional display.
-- Each element can be a header, label, or sub-section.
-------------------------------------------------------------------------------
Registry.RegisterLayoutType("multi_section", {
    default = {
        sectionSpacing = 8,
        rowSpacing = 4,
        padding = 8,
    },
    arrange = function(contentFrame, elements, layoutData)
        layoutData = layoutData or {}
        local sectionSpacing = layoutData.sectionSpacing or 8
        local rowSpacing = layoutData.rowSpacing or 4
        local padding = layoutData.padding or 8
        local y = -padding

        for i, elem in ipairs(elements) do
            if elem.frame and elem.visible ~= false then
                local isHeader = elem.isHeader
                local spacing = isHeader and sectionSpacing or rowSpacing
                if i > 1 then y = y - spacing end

                elem.frame:ClearAllPoints()
                elem.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", padding, y)
                elem.frame:SetPoint("RIGHT", contentFrame, "RIGHT", -padding, 0)
                elem.frame:SetHeight(elem.height or 16)
                elem.frame:Show()
                y = y - (elem.height or 16)
            elseif elem.frame then
                elem.frame:Hide()
            end
        end

        return math.abs(y) + padding
    end,
})

return true
