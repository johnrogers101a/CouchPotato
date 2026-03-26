-- InfoPanels/Editor/TextureBrowser.lua
-- Texture browser dialog: category-based browsing, search, virtual scrolling.
-- Supports built-in textures, atlas textures, and custom user textures.
-- Single Responsibility: Texture discovery and selection UI.
--
-- UX: Uses the same Blizzard-native chrome as the main Editor panel
-- (ButtonFrameTemplate with portrait icon, title bar, and dark background).

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local TextureBrowser = {}
ns.EditorTextureBrowser = TextureBrowser

local _browserFrame = nil
local _entries = {}
local _onSelectCallback = nil
local _currentCategory = "icons"

-------------------------------------------------------------------------------
-- SetOnSelect: Callback when user selects a texture.
-- Signature: callback({ path=string, atlas=string, name=string })
-------------------------------------------------------------------------------
function TextureBrowser.SetOnSelect(callback)
    _onSelectCallback = callback
end

-------------------------------------------------------------------------------
-- _buildFrame: Construct the browser window with Blizzard-native chrome.
-- Mirrors BuildEditorFrame in Editor.lua — ButtonFrameTemplate first,
-- then BasicFrameTemplateWithInset fallback, then bare frame.
-------------------------------------------------------------------------------
local function _buildFrame()
    if _browserFrame then return _browserFrame end

    ---------------------------------------------------------------------------
    -- Main frame — same template-preference order as the main editor.
    ---------------------------------------------------------------------------
    local f
    local usePortrait = false

    local ok1, result1 = pcall(function()
        return CreateFrame("Frame", "IPEditorTextureBrowser", UIParent, "ButtonFrameTemplate")
    end)
    if ok1 and result1 then
        f = result1
        usePortrait = true
    else
        local ok2, result2 = pcall(function()
            return CreateFrame("Frame", "IPEditorTextureBrowser", UIParent, "BasicFrameTemplateWithInset")
        end)
        if ok2 and result2 then
            f = result2
        else
            f = CreateFrame("Frame", "IPEditorTextureBrowser", UIParent)
        end
    end

    f:SetSize(520, 460)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    tinsert(UISpecialFrames, "IPEditorTextureBrowser")

    ---------------------------------------------------------------------------
    -- Portrait icon — paintbrush / inscription scroll for "textures" theme.
    ---------------------------------------------------------------------------
    if usePortrait then
        pcall(function()
            local icon = "Interface\\Icons\\INV_Inscription_ParchmentVar02"
            if f.PortraitContainer and f.PortraitContainer.portrait then
                f.PortraitContainer.portrait:SetTexture(icon)
            elseif SetPortraitToTexture and f.portrait then
                SetPortraitToTexture(f.portrait, icon)
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Title bar text — GameFontNormalLarge, matching the main editor.
    ---------------------------------------------------------------------------
    if f.TitleContainer and f.TitleContainer.TitleText then
        f.TitleContainer.TitleText:SetText("Texture Browser")
    elseif f.TitleBg then
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", f.TitleBg, "TOP", 0, -2)
        title:SetText("Texture Browser")
    else
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", f, "TOP", 0, -8)
        title:SetText("Texture Browser")
    end

    ---------------------------------------------------------------------------
    -- Standard Blizzard close button (red X).
    ---------------------------------------------------------------------------
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    end

    ---------------------------------------------------------------------------
    -- Dark parchment/stone background for the content area — identical
    -- approach to the main editor's workArea background.
    ---------------------------------------------------------------------------
    local workArea = CreateFrame("Frame", nil, f)
    workArea:SetPoint("TOPLEFT",     f, "TOPLEFT",     8,  -60)
    workArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8,  32)

    local bgTex = workArea:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    pcall(function()
        bgTex:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
        bgTex:SetVertTile(true)
        bgTex:SetHorizTile(true)
    end)
    if not bgTex:GetTexture() then
        bgTex:SetColorTexture(0.06, 0.06, 0.06, 0.95)
    end

    ---------------------------------------------------------------------------
    -- Category tabs — CharacterFrameTabButtonTemplate, same as the editor.
    ---------------------------------------------------------------------------
    local EC = ns.EditorConstants or {}
    local categories = EC.TEXTURE_CATEGORIES or {
        { key = "icons",       label = "Icons"       },
        { key = "backgrounds", label = "Backgrounds" },
        { key = "statusbars",  label = "Status Bars" },
    }

    local tabs = {}
    for i, cat in ipairs(categories) do
        local tab
        local tabOk, tabResult = pcall(function()
            return CreateFrame("Button", "IPTextureBrowserTab" .. i, f, "CharacterFrameTabButtonTemplate")
        end)
        if tabOk and tabResult then
            tab = tabResult
        else
            tab = CreateFrame("Button", "IPTextureBrowserTab" .. i, f, "UIPanelButtonTemplate")
        end

        tab:SetText(cat.label)
        tab:SetID(i)
        tab._catKey = cat.key

        if i == 1 then
            tab:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, -2)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -8, 0)
        end

        pcall(function() PanelTemplates_TabResize(tab, 0) end)

        tab:SetScript("OnClick", function()
            _currentCategory = cat.key
            -- Update tab visuals
            for j, t in ipairs(tabs) do
                pcall(function()
                    if j == i then
                        PanelTemplates_SelectTab(t)
                    else
                        PanelTemplates_DeselectTab(t)
                    end
                end)
            end
            TextureBrowser._refreshResults()
        end)

        tabs[i] = tab
    end
    f._tabs = tabs

    -- Select the first tab by default
    pcall(function() PanelTemplates_SelectTab(tabs[1]) end)

    ---------------------------------------------------------------------------
    -- Search box — inside the work area, below the chrome title.
    ---------------------------------------------------------------------------
    local searchLabel = workArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", workArea, "TOPLEFT", 8, -8)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", nil, workArea, "InputBoxTemplate")
    searchBox:SetSize(220, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(100)
    f._searchBox = searchBox

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
    searchPlaceholder:SetText("Search textures...")
    searchBox._placeholder = searchPlaceholder

    searchBox:SetScript("OnEditFocusGained", function(self) self._placeholder:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self._placeholder:Show() end
    end)
    searchBox:SetScript("OnTextChanged", function()
        TextureBrowser._refreshResults()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    ---------------------------------------------------------------------------
    -- Scroll frame for texture results.
    -- Anchored inside workArea, leaving room for search row at top and
    -- custom-path row at bottom.
    ---------------------------------------------------------------------------
    local scrollFrame = CreateFrame("ScrollFrame", "IPEditorTextureScroll", workArea, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     workArea, "TOPLEFT",     4,  -34)
    scrollFrame:SetPoint("BOTTOMRIGHT", workArea, "BOTTOMRIGHT", -26, 46)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth() or 460)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    f._scrollChild = scrollChild

    -- Keep scroll child width in sync after layout settles
    scrollFrame:SetScript("OnSizeChanged", function(self)
        scrollChild:SetWidth(self:GetWidth())
    end)

    ---------------------------------------------------------------------------
    -- Custom texture path input — UIPanelButtonTemplate for "Use" button.
    ---------------------------------------------------------------------------
    local customLabel = workArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customLabel:SetPoint("BOTTOMLEFT", workArea, "BOTTOMLEFT", 8, 26)
    customLabel:SetText("Custom path:")

    local customInput = CreateFrame("EditBox", nil, workArea, "InputBoxTemplate")
    customInput:SetSize(300, 18)
    customInput:SetPoint("LEFT", customLabel, "RIGHT", 6, 0)
    customInput:SetAutoFocus(false)
    customInput:SetMaxLetters(255)

    local customBtn = CreateFrame("Button", nil, workArea, "UIPanelButtonTemplate")
    customBtn:SetSize(60, 22)
    customBtn:SetPoint("LEFT", customInput, "RIGHT", 4, 0)
    customBtn:SetText("Use")
    customBtn:SetScript("OnClick", function()
        local path = customInput:GetText()
        if path and path ~= "" then
            if _onSelectCallback then
                _onSelectCallback({ path = path, name = "Custom" })
            end
            f:Hide()
        end
    end)

    local customHint = workArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    customHint:SetPoint("BOTTOMLEFT", workArea, "BOTTOMLEFT", 8, 10)
    customHint:SetText("e.g. Interface/InfoPanels/myfile  or  134400 (file ID)")

    _browserFrame = f
    return f
end

-------------------------------------------------------------------------------
-- Show: Create (if needed) and display the texture browser dialog.
-------------------------------------------------------------------------------
function TextureBrowser.Show(onSelect)
    if onSelect then _onSelectCallback = onSelect end

    if not _browserFrame then
        _buildFrame()
    end

    _browserFrame:Show()
    _browserFrame:Raise()
    TextureBrowser._refreshResults()
end

-------------------------------------------------------------------------------
-- Hide: Hide the texture browser.
-------------------------------------------------------------------------------
function TextureBrowser.Hide()
    if _browserFrame then _browserFrame:Hide() end
end

-------------------------------------------------------------------------------
-- _refreshResults: Update the texture grid/list based on category + search.
-------------------------------------------------------------------------------
function TextureBrowser._refreshResults()
    if not _browserFrame then return end
    local scrollChild = _browserFrame._scrollChild
    if not scrollChild then return end

    -- Hide old entries
    for _, e in ipairs(_entries) do
        if e.frame then e.frame:Hide() end
    end

    local EC = ns.EditorConstants or {}
    local builtinTextures = EC.BUILTIN_TEXTURES or {}
    local textures = builtinTextures[_currentCategory] or {}

    local query = _browserFrame._searchBox and _browserFrame._searchBox:GetText() or ""
    query = query:lower()

    local filtered = {}
    local maxResults = EC.MAX_SEARCH_RESULTS or 500
    for _, tex in ipairs(textures) do
        if #filtered >= maxResults then break end
        if query == "" or
           (tex.name  and tex.name:lower():find(query, 1, true)) or
           (tex.path  and tex.path:lower():find(query, 1, true)) or
           (tex.atlas and tex.atlas:lower():find(query, 1, true)) then
            filtered[#filtered + 1] = tex
        end
    end

    local rowHeight   = EC.ICON_ROW_HEIGHT or 36
    local childWidth  = scrollChild:GetWidth() or 460

    for i, tex in ipairs(filtered) do
        local entry = _entries[i]
        if not entry then
            local row = CreateFrame("Button", nil, scrollChild)
            row:SetSize(childWidth, rowHeight)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * rowHeight)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.1, 0.1, 0.1, i % 2 == 0 and 0.4 or 0.2)

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.1)

            local preview = row:CreateTexture(nil, "ARTWORK")
            preview:SetSize(28, 28)
            preview:SetPoint("LEFT", row, "LEFT", 4, 0)

            -- Name label — GameFontHighlightSmall, matching editor row style
            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameLabel:SetPoint("LEFT", preview, "RIGHT", 6, 4)
            nameLabel:SetJustifyH("LEFT")

            -- Path/atlas label — muted secondary text
            local pathLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            pathLabel:SetPoint("LEFT", preview, "RIGHT", 6, -6)
            pathLabel:SetJustifyH("LEFT")

            entry = { frame = row, preview = preview, nameLabel = nameLabel, pathLabel = pathLabel }
            _entries[i] = entry
        end

        -- Reposition each reused row correctly
        entry.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * rowHeight)
        entry.frame:SetWidth(childWidth)

        entry.nameLabel:SetText(tex.name or "")

        if tex.atlas then
            pcall(function() entry.preview:SetAtlas(tex.atlas) end)
            entry.pathLabel:SetText("Atlas: " .. tex.atlas)
        elseif tex.path then
            pcall(function() entry.preview:SetTexture(tex.path) end)
            entry.pathLabel:SetText(tex.path)
        end

        local capturedTex = tex
        entry.frame:SetScript("OnClick", function()
            if _onSelectCallback then
                _onSelectCallback(capturedTex)
            end
            if _browserFrame then _browserFrame:Hide() end
        end)

        entry.frame:Show()
    end

    scrollChild:SetHeight(math.max(#filtered * rowHeight, 1))
end

return TextureBrowser
