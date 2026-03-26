-- InfoPanels/Core/PanelTypes.lua
-- Registered panel types for the InfoPanels engine.
-- Following WeakAuras pattern: each type has {create, modify, default, properties}.
-- New types = new Register call. Zero changes to engine core.
--
-- Single Responsibility: Panel type definitions and registration.

local _, ns = ...
if not ns then ns = {} end

local Registry = ns.Registry
local Utils = ns.Utils
if not Registry then return end

local CP = _G.CouchPotatoShared
local THEME = CP and CP.THEME or {
    GOLD = {1, 0.82, 0.0, 1},
    GOLD_ACCENT = {1, 0.78, 0.1, 1},
    BG_DARK = {0, 0, 0, 0.5},
    FONT_PATH = "Fonts\\FRIZQT__.TTF",
}
local FONT_PATH = THEME.FONT_PATH

local UIFramework = ns.UIFramework

-------------------------------------------------------------------------------
-- PANEL TYPE: vertical_list
-- Simple vertical list of label:value rows. The default for user panels.
-------------------------------------------------------------------------------
Registry.RegisterPanelType("vertical_list", {
    default = {
        layout = "vertical_list",
        bindings = {},
    },
    properties = {
        rowHeight = { display = "Row Height", type = "number", min = 12, max = 40, default = 18 },
        rowSpacing = { display = "Row Spacing", type = "number", min = 0, max = 20, default = 4 },
        padding = { display = "Padding", type = "number", min = 0, max = 20, default = 8 },
    },
    create = function(contentFrame, data)
        local region = { _labels = {}, _elements = {} }
        local bindings = data.bindings or {}
        local contentWidth = contentFrame:GetWidth() or 236

        for i, binding in ipairs(bindings) do
            local label = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            -- Apply saved font, fall back to ObjectiveFont
            if binding.font and _G[binding.font] then
                pcall(function() label:SetFontObject(_G[binding.font]) end)
            else
                pcall(function() label:SetFontObject(_G.ObjectiveFont) end)
            end
            -- Apply saved color
            if binding.color then
                local c = binding.color
                label:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
            else
                label:SetTextColor(1, 1, 1, 1)
            end
            label:SetShadowOffset(1, -1)
            label:SetShadowColor(0, 0, 0, 1)
            label:SetJustifyH("LEFT")
            label:SetWidth(contentWidth)
            label:SetText((binding.label or binding.sourceId or "") .. ": ...")

            -- Wrap in a holder frame for layout
            local holder = CreateFrame("Frame", nil, contentFrame)
            holder:SetHeight(18)
            label:SetAllPoints(holder)

            region._labels[i] = { label = label, binding = binding, frame = holder }
            region._elements[i] = { frame = holder }
        end

        return region
    end,
    modify = function(contentFrame, region, data)
        local DataSources = ns.DataSources
        if not DataSources then return 36 end

        local bindings = data.bindings or {}
        for i, entry in ipairs(region._labels or {}) do
            local binding = bindings[i] or entry.binding
            local label = entry.label
            if binding and label then
                local displayVal, isErr = Utils.FetchAndFormatBinding(DataSources, binding)
                if isErr then
                    label:SetText((binding.label or "") .. ": |cff888888No data|r")
                else
                    label:SetText((binding.label or "") .. ": " .. displayVal)
                end

                -- Apply font
                if binding.font and _G[binding.font] then
                    pcall(function() label:SetFontObject(_G[binding.font]) end)
                end

                -- Apply color
                if binding.color then
                    local c = binding.color
                    label:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
                else
                    label:SetTextColor(1, 1, 1, 1)
                end
            end
        end

        -- Layout
        local layoutType = Registry.GetLayoutType("vertical_list")
        local contentH = 36
        if layoutType and layoutType.arrange then
            contentH = layoutType.arrange(contentFrame, region._elements or {}, data.layoutData)
        end
        return contentH
    end,
})

-------------------------------------------------------------------------------
-- PANEL TYPE: circle_row
-- Horizontal row of stat circles with > or = connectors (StatPriority).
-- Data table drives everything: stats array, connectorType per position.
-------------------------------------------------------------------------------
Registry.RegisterPanelType("circle_row", {
    default = {
        layout = "circle_row",
        stats = {},          -- array: strings or sub-arrays for equal groups
        specOverride = nil,
    },
    properties = {
        circleSize = { display = "Circle Size", type = "number", min = 30, max = 80, default = 46 },
        connectorWidth = { display = "Connector Width", type = "number", min = 4, max = 20, default = 8 },
    },
    create = function(contentFrame, data)
        local region = { _circles = {}, _connectors = {}, _elements = {} }

        local circleSize = (data.layoutData and data.layoutData.circleSize) or 46
        local connectorW = (data.layoutData and data.layoutData.connectorWidth) or 8

        -- Pre-create 7 circles and 6 connectors (max stat slots)
        for i = 1, 7 do
            local circ = CreateFrame("Frame", nil, contentFrame)
            circ:SetSize(circleSize, circleSize)

            local ring = circ:CreateTexture(nil, "BORDER")
            ring:SetSize(circleSize + 8, circleSize + 8)
            ring:SetPoint("CENTER")
            ring:SetTexture("Interface\\COMMON\\Indicator-Gray")
            ring:SetVertexColor(1, 0.82, 0, 1)

            local bg = circ:CreateTexture(nil, "ARTWORK")
            bg:SetSize(circleSize - 4, circleSize - 4)
            bg:SetPoint("CENTER")
            bg:SetTexture("Interface\\COMMON\\Indicator-Gray")
            bg:SetVertexColor(0.08, 0.06, 0.02, 0.95)

            local nameFS = circ:CreateFontString(nil, "OVERLAY")
            nameFS:SetFont(FONT_PATH, 9, "OUTLINE")
            nameFS:SetPoint("CENTER", circ, "CENTER", 0, 8)
            nameFS:SetJustifyH("CENTER")
            nameFS:SetJustifyV("MIDDLE")
            nameFS:SetTextColor(unpack(THEME.GOLD))

            local valueFS = circ:CreateFontString(nil, "OVERLAY")
            valueFS:SetFont(FONT_PATH, 8, "OUTLINE")
            valueFS:SetPoint("CENTER", circ, "CENTER", 0, -7)
            valueFS:SetJustifyH("CENTER")
            valueFS:SetJustifyV("MIDDLE")
            valueFS:SetTextColor(1, 1, 1, 1)

            circ:Hide()
            region._circles[i] = { frame = circ, nameFS = nameFS, valueFS = valueFS }
            region._elements[i] = { frame = circ }
        end

        for i = 1, 6 do
            local conn = contentFrame:CreateFontString(nil, "OVERLAY")
            conn:SetFont(FONT_PATH, 10, "OUTLINE")
            conn:SetWidth(connectorW)
            conn:SetJustifyH("CENTER")
            conn:SetJustifyV("MIDDLE")
            conn:SetTextColor(unpack(THEME.GOLD))
            conn:SetText(">")
            conn:Hide()
            region._connectors[i] = conn
        end

        return region
    end,
    modify = function(contentFrame, region, data)
        local circleSize = (data.layoutData and data.layoutData.circleSize) or 46
        local connectorW = (data.layoutData and data.layoutData.connectorWidth) or 8
        local topPadding = 7
        local leftPadding = 4

        -- Resolve stats array from data
        local statsArray = data.stats or {}
        local circleStats = {}
        local connectors = {}

        local ci = 0
        local numEntries = #statsArray
        for ei, entry in ipairs(statsArray) do
            if type(entry) == "table" then
                for j, subStat in ipairs(entry) do
                    ci = ci + 1
                    circleStats[ci] = subStat
                    if j < #entry then
                        connectors[ci] = "="
                    elseif ei < numEntries then
                        connectors[ci] = ">"
                    end
                end
            else
                ci = ci + 1
                circleStats[ci] = entry
                if ei < numEntries then
                    connectors[ci] = ">"
                end
            end
        end

        -- Abbreviation -> registered DataSources ID mapping
        local statAbbrevToSourceId = {
            Str   = "player.strength",
            Agil  = "player.agility",
            Int   = "player.intellect",
            Haste = "player.haste",
            Crit  = "player.crit",
            Mast  = "player.mastery",
            Vers  = "player.versatility",
        }

        -- GetStatValue helper (string key -> display value via DataSources registry)
        local DataSources = ns.DataSources
        local function GetStatValue(statAbbrev)
            local sourceId = statAbbrevToSourceId[statAbbrev]
            if sourceId and DataSources then
                local val, err = DataSources.Fetch(sourceId)
                if not err and val ~= nil then
                    -- Primary stats return numbers; apply comma formatting
                    if type(val) == "number" then return Utils.CommaFormat(val) end
                    return tostring(val)
                end
            end
            return "?"
        end

        -- Expose for tests via addon namespace (not global scope)
        ns.StatPriorityGetStatValue = GetStatValue

        local numCircles = #circleStats
        for i = 1, #region._circles do
            local circ = region._circles[i]
            if i <= numCircles then
                local x = leftPadding + (i - 1) * (circleSize + connectorW)
                circ.frame:ClearAllPoints()
                circ.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", x, -topPadding)
                circ.frame:SetSize(circleSize, circleSize)
                circ.nameFS:SetText(circleStats[i])
                circ.valueFS:SetText(GetStatValue(circleStats[i]))
                circ.frame:Show()
            else
                circ.frame:Hide()
            end
        end

        for i = 1, #region._connectors do
            local conn = region._connectors[i]
            if connectors[i] then
                local x = leftPadding + (i - 1) * (circleSize + connectorW) + circleSize + 1
                conn:ClearAllPoints()
                conn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", x, -(topPadding + circleSize / 2 - 7))
                conn:SetText(connectors[i])
                conn:Show()
            else
                conn:Hide()
            end
        end

        return circleSize + topPadding * 2
    end,
})

-------------------------------------------------------------------------------
-- PANEL TYPE: multi_section
-- Multi-section vertical display with conditional sections (DelveCompanionStats).
-- Data table specifies sections; each section has a key, label, and fetch function
-- resolved via string keys into DataSources.
-------------------------------------------------------------------------------
Registry.RegisterPanelType("multi_section", {
    default = {
        layout = "multi_section",
        sections = {},
    },
    properties = {
        sectionSpacing = { display = "Section Spacing", type = "number", min = 0, max = 20, default = 8 },
    },
    create = function(contentFrame, data)
        local region = { _sections = {}, _elements = {} }
        local sections = data.sections or {}
        local contentWidth = contentFrame:GetWidth() or 236

        for i, section in ipairs(sections) do
            local holder = CreateFrame("Frame", nil, contentFrame)
            holder:SetHeight(section.height or 16)

            local label = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pcall(function() label:SetFontObject(_G.ObjectiveFont) end)
            label:SetJustifyH("LEFT")
            label:SetWidth(contentWidth)
            label:SetShadowOffset(1, -1)
            label:SetShadowColor(0, 0, 0, 1)
            label:SetAllPoints(holder)

            if section.isHeader then
                label:SetTextColor(unpack(THEME.GOLD))
            else
                label:SetTextColor(1, 1, 1, 1)
            end

            label:SetText(section.defaultText or "")

            region._sections[i] = {
                frame = holder,
                label = label,
                section = section,
            }
            region._elements[i] = {
                frame = holder,
                isHeader = section.isHeader,
                height = section.height or 16,
                visible = true,
            }
        end

        return region
    end,
    modify = function(contentFrame, region, data)
        local DataSources = ns.DataSources
        local sections = data.sections or {}

        for i, entry in ipairs(region._sections or {}) do
            local section = sections[i] or entry.section
            local label = entry.label
            local elem = region._elements[i]

            if section.sourceId and DataSources then
                local val, err = DataSources.Fetch(section.sourceId)
                if err then
                    if section.hideOnError then
                        elem.visible = false
                    else
                        label:SetText(section.errorText or "|cff888888No data|r")
                        elem.visible = true
                    end
                else
                    local displayVal = tostring(val or "")
                    if section.format and type(val) == "number" then
                        local fmtOk, fmtResult = pcall(string.format, section.format, val)
                        if fmtOk then displayVal = fmtResult end
                    end
                    if section.prefix then
                        displayVal = section.prefix .. displayVal
                    end
                    label:SetText(displayVal)
                    elem.visible = true
                end
            elseif section.fetchKey then
                -- String key into a registered fetch function
                local fetchFn = data._fetchFunctions and data._fetchFunctions[section.fetchKey]
                if fetchFn then
                    local ok, result = pcall(fetchFn)
                    if ok and result ~= nil then
                        label:SetText(tostring(result))
                        elem.visible = true
                    else
                        if section.hideOnError then
                            elem.visible = false
                        else
                            label:SetText(section.errorText or "")
                            elem.visible = (result ~= nil)
                        end
                    end
                end
            end
        end

        -- Re-layout with multi_section layout
        local layoutType = Registry.GetLayoutType("multi_section")
        local contentH = 36
        if layoutType and layoutType.arrange then
            contentH = layoutType.arrange(contentFrame, region._elements or {}, data.layoutData)
        end
        return contentH
    end,
})

-------------------------------------------------------------------------------
-- PANEL TYPE: simple_info
-- Simple vertical info display with named rows (DelversJourney).
-- Like vertical_list but sections are defined in the data table, not bindings.
-------------------------------------------------------------------------------
Registry.RegisterPanelType("simple_info", {
    default = {
        layout = "vertical_list",
        rows = {},
    },
    properties = {
        padding = { display = "Padding", type = "number", min = 0, max = 20, default = 8 },
    },
    create = function(contentFrame, data)
        local region = { _rows = {}, _elements = {} }
        local rows = data.rows or {}
        local contentWidth = contentFrame:GetWidth() or 236

        for i, row in ipairs(rows) do
            local holder = CreateFrame("Frame", nil, contentFrame)
            holder:SetHeight(row.height or 18)

            local label = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pcall(function() label:SetFontObject(_G.ObjectiveFont) end)
            label:SetJustifyH("LEFT")
            label:SetWidth(contentWidth)
            label:SetTextColor(1, 1, 1, 1)
            label:SetShadowOffset(1, -1)
            label:SetShadowColor(0, 0, 0, 1)
            label:SetAllPoints(holder)
            label:SetText(row.defaultText or "")

            region._rows[i] = { frame = holder, label = label, row = row }
            region._elements[i] = { frame = holder }
        end

        return region
    end,
    modify = function(contentFrame, region, data)
        local DataSources = ns.DataSources
        local rows = data.rows or {}

        for i, entry in ipairs(region._rows or {}) do
            local row = rows[i] or entry.row
            local label = entry.label

            if row.sourceId and DataSources then
                local val, err = DataSources.Fetch(row.sourceId)
                if err then
                    label:SetText(row.errorText or "|cff888888No data|r")
                else
                    local displayVal = tostring(val or "")
                    if row.format and type(val) == "number" then
                        local fmtOk, fmtResult = pcall(string.format, row.format, val)
                        if fmtOk then displayVal = fmtResult end
                    end
                    if row.prefix then displayVal = row.prefix .. displayVal end
                    label:SetText(displayVal)
                end
            end
        end

        local layoutType = Registry.GetLayoutType("vertical_list")
        local contentH = 36
        if layoutType and layoutType.arrange then
            contentH = layoutType.arrange(contentFrame, region._elements or {}, data.layoutData)
        end
        return contentH
    end,
})

return true
