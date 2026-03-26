-- InfoPanels/Editor/DataSourceBrowser.lua
-- Searchable, categorized data source browser with human-readable names.
-- Supports drag-to-preview and click-to-add.
-- Single Responsibility: Data source discovery and selection UI.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local EC = nil  -- lazy-loaded EditorConstants
local function getConst()
    if not EC then EC = ns.EditorConstants or {} end
    return EC
end

local DataSourceBrowser = {}
ns.EditorDataSourceBrowser = DataSourceBrowser

local _browserFrame = nil
local _entries = {}
local _onAddCallback = nil
local _searchTimer = nil
local _currentCategory = nil

-------------------------------------------------------------------------------
-- SetOnAdd: Callback when user adds a data source binding.
-------------------------------------------------------------------------------
function DataSourceBrowser.SetOnAdd(callback)
    _onAddCallback = callback
end

-------------------------------------------------------------------------------
-- Build: Create the data source browser UI inside the given parent frame.
-------------------------------------------------------------------------------
function DataSourceBrowser.Build(parent, width, height)
    if _browserFrame then return _browserFrame end

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height)

    -- Header
    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -2)
    header:SetText("Data Sources")
    header:SetTextColor(1, 0.82, 0, 1)

    -- Search box (Blizzard SearchBoxTemplate style)
    local searchBox = CreateFrame("EditBox", "IPEditorSearchBox", container, "InputBoxTemplate")
    searchBox:SetSize(width - 12, 20)
    searchBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, -4)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(100)

    -- Magnifying glass icon
    local searchIcon = searchBox:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", searchBox, "LEFT", -16, 0)
    searchIcon:SetTexture("Interface\\COMMON\\UI-Searchbox-Icon")

    -- Placeholder text
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
    placeholder:SetText("Search functions...")
    searchBox._placeholder = placeholder

    searchBox:SetScript("OnEditFocusGained", function(self)
        self._placeholder:Hide()
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self._placeholder:Show() end
    end)

    -- Category filter dropdown area
    local catContainer = CreateFrame("Frame", nil, container)
    catContainer:SetSize(width - 8, 20)
    catContainer:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -2, -4)
    container._catContainer = catContainer

    -- Build category buttons (horizontal tab-like buttons)
    DataSourceBrowser._buildCategoryTabs(catContainer, width - 8)

    -- Results scroll area
    local scrollFrame = CreateFrame("ScrollFrame", "IPEditorDSBrowserScroll", container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", catContainer, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -24, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width - 36)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    container._scrollChild = scrollChild
    container._searchBox = searchBox

    -- Search handler with debounce
    searchBox:SetScript("OnTextChanged", function(self)
        local query = self:GetText()
        if query ~= "" then self._placeholder:Hide() end
        -- Simple debounce: just refresh immediately for prototype
        DataSourceBrowser._refreshResults(query, _currentCategory)
    end)

    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    _browserFrame = container
    return container
end

-------------------------------------------------------------------------------
-- _buildCategoryTabs: Create horizontal category filter buttons.
-------------------------------------------------------------------------------
function DataSourceBrowser._buildCategoryTabs(parent, totalWidth)
    local DataSources = ns.DataSources
    if not DataSources then return end

    local cats = DataSources.GetCategories()
    table.insert(cats, 1, "All")

    local btnWidth = math.min(math.floor(totalWidth / math.min(#cats, 6)), 80)
    local x = 0
    parent._catButtons = {}

    for i, cat in ipairs(cats) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(btnWidth, 22)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.2, 0.2, 0.2, 0.6)

        local selBg = btn:CreateTexture(nil, "BORDER")
        selBg:SetAllPoints()
        selBg:SetColorTexture(1, 0.82, 0, 0.25)
        if i == 1 then selBg:Show() else selBg:Hide() end

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.1)

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetAllPoints()
        label:SetText(cat)

        btn._selBg = selBg
        btn._cat = (cat == "All") and nil or cat
        parent._catButtons[i] = btn

        btn:SetScript("OnClick", function()
            _currentCategory = btn._cat
            -- Update selection visuals
            for _, b in ipairs(parent._catButtons) do
                b._selBg:Hide()
            end
            selBg:Show()
            -- Refresh results
            local query = _browserFrame and _browserFrame._searchBox and _browserFrame._searchBox:GetText() or ""
            DataSourceBrowser._refreshResults(query, _currentCategory)
        end)

        x = x + btnWidth + 2
        -- Wrap to next row if needed
        if x + btnWidth > totalWidth and i < #cats then
            -- For simplicity in prototype, just let them overflow
        end
    end
end

-------------------------------------------------------------------------------
-- _refreshResults: Update the result list based on search query + category.
-------------------------------------------------------------------------------
function DataSourceBrowser._refreshResults(query, category)
    if not _browserFrame then return end
    local scrollChild = _browserFrame._scrollChild
    if not scrollChild then return end

    local DataSources = ns.DataSources
    if not DataSources then return end

    -- Hide old entries
    for _, e in ipairs(_entries) do
        if e.row then e.row:Hide() end
    end

    local results = {}
    local maxResults = (getConst().MAX_SEARCH_RESULTS or 500)

    if query and query ~= "" then
        -- Search mode
        local searchResults = DataSources.Search(query)
        for _, id in ipairs(searchResults) do
            if #results >= maxResults then break end
            local source = DataSources.Get(id)
            if not category or (source and source.category == category) then
                results[#results + 1] = { id = id, source = source }
            end
        end
    elseif category then
        -- Category browse mode
        local ids = DataSources.GetSourcesInCategory(category)
        for _, id in ipairs(ids) do
            if #results >= maxResults then break end
            local source = DataSources.Get(id)
            results[#results + 1] = { id = id, source = source }
        end
    else
        -- Show all (sorted)
        local all = DataSources.GetAllSorted()
        for _, item in ipairs(all) do
            if #results >= maxResults then break end
            results[#results + 1] = { id = item.id, source = item.info }
        end
    end

    local rowHeight = getConst().ROW_HEIGHT or 22
    local childWidth = scrollChild:GetWidth()

    for i, result in ipairs(results) do
        local entry = _entries[i]
        if not entry then
            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetSize(childWidth, rowHeight)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * rowHeight)
            row:EnableMouse(true)

            -- Alternating row background
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.12, 0.12, 0.12, i % 2 == 0 and 0.4 or 0.2)

            -- Hover highlight
            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 0.82, 0, 0.1)

            -- Source name
            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameLabel:SetPoint("LEFT", row, "LEFT", 4, 0)
            nameLabel:SetJustifyH("LEFT")
            nameLabel:SetWidth(childWidth - 100)

            -- Category tag
            local catLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            catLabel:SetPoint("RIGHT", row, "RIGHT", -44, 0)
            catLabel:SetJustifyH("RIGHT")

            -- Add button
            local addBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            addBtn:SetSize(60, 22)
            addBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            addBtn:SetText("Add")

            -- Enable drag-to-preview via OnMouseDown/OnMouseUp tracking.
            -- WoW's OnDragStart/OnDragStop intercept mouse-up events system-wide,
            -- preventing the preview area's OnMouseUp from firing. Using
            -- OnMouseDown/OnMouseUp avoids that interception entirely.
            row:SetScript("OnMouseDown", function(self, button)
                if button == "LeftButton" and self._sourceId and ns.EditorLivePreview then
                    ns.EditorLivePreview.StartDrag(self._sourceId)
                end
            end)
            row:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" and ns.EditorLivePreview then
                    ns.EditorLivePreview.FinishDrop()
                end
            end)

            entry = { row = row, nameLabel = nameLabel, catLabel = catLabel, addBtn = addBtn }
            _entries[i] = entry
        end

        local source = result.source
        local displayName = source and source.name or result.id
        local catText = source and source.category or ""

        entry.nameLabel:SetText(displayName)
        entry.catLabel:SetText("|cff888888" .. catText .. "|r")
        entry.row._sourceId = result.id

        entry.addBtn:SetScript("OnClick", function()
            if _onAddCallback then
                _onAddCallback(result.id)
            end
        end)

        -- Tooltip on hover
        entry.row:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                if GameTooltip.AddLine then
                    GameTooltip:AddLine(displayName, 1, 0.82, 0)
                    if source and source.description then
                        GameTooltip:AddLine(source.description, 1, 1, 1, true)
                    end
                    GameTooltip:AddLine("ID: " .. result.id, 0.5, 0.5, 0.5)
                    GameTooltip:AddLine("Click Add or drag to preview", 0, 1, 0)
                end
                GameTooltip:Show()
            end
        end)
        entry.row:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        entry.row:Show()
    end

    scrollChild:SetHeight(math.max(#results * rowHeight, 1))
end

-------------------------------------------------------------------------------
-- Refresh: Re-query with current search text and category.
-------------------------------------------------------------------------------
function DataSourceBrowser.Refresh()
    if not _browserFrame then return end
    local query = _browserFrame._searchBox and _browserFrame._searchBox:GetText() or ""
    DataSourceBrowser._refreshResults(query, _currentCategory)
end

return DataSourceBrowser
