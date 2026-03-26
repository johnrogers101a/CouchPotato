-- InfoPanels/Editor/Editor.lua
-- Main editor facade: Blizzard-native frame chrome, tab navigation,
-- and orchestration of sub-components.
--
-- NEW ARCHITECTURE:
--   Left column: Panel list (same as before)
--   Middle column: "Lines" editor — text boxes for each line with {{FUNCTION}} templates
--   Right column: Live Preview
--   Bottom tabs: "Functions" tab (edit function code), "Properties", "Visibility"
--                "Textures" tab hidden for now
--
-- Single Responsibility: Editor lifecycle and UI orchestration.
-- Combat lockdown: editor disables during combat.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local THEME = CP and CP.THEME or { FONT_PATH = "Fonts\\FRIZQT__.TTF", GOLD = {1, 0.82, 0.0, 1} }
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local Editor = {}
ns.Editor = Editor

local _editorFrame = nil
local _currentDefinition = nil
local _selectedLines = {}  -- array of { template = "..." }
local _pendingOpenAfterCombat = false
local _idCounter = 0

local function generateUniqueId(prefix)
    _idCounter = _idCounter + 1
    local ts = GetTime and math.floor(GetTime() * 1000) or 0
    return (prefix or "user_panel") .. "_" .. ts .. "_" .. _idCounter
end

local EC = nil
local function getConst()
    if not EC then EC = ns.EditorConstants or {} end
    return EC
end

-------------------------------------------------------------------------------
-- Combat lockdown handling
-------------------------------------------------------------------------------
local function IsInCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if _pendingOpenAfterCombat then
        _pendingOpenAfterCombat = false
        Editor.Show()
    end
end)

-------------------------------------------------------------------------------
-- Line editor entries (middle column)
-------------------------------------------------------------------------------
local _lineEntries = {}  -- { frame, editBox, removeBtn }

local function _rebuildLineEditors()
    if not _editorFrame then return end
    local scrollChild = _editorFrame._linesScrollChild
    if not scrollChild then return end

    -- Hide all existing entries
    for _, entry in ipairs(_lineEntries) do
        if entry.frame then entry.frame:Hide() end
    end

    local entryHeight = 30
    local entryWidth = scrollChild:GetWidth() or 300

    for i, line in ipairs(_selectedLines) do
        local entry = _lineEntries[i]
        if not entry then
            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetHeight(entryHeight)

            -- Line number label
            local numLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            numLabel:SetPoint("LEFT", row, "LEFT", 2, 0)
            numLabel:SetWidth(20)
            numLabel:SetJustifyH("RIGHT")

            -- Edit box for template text
            local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            eb:SetPoint("LEFT", numLabel, "RIGHT", 4, 0)
            eb:SetPoint("RIGHT", row, "RIGHT", -30, 0)
            eb:SetHeight(20)
            eb:SetAutoFocus(false)
            eb:SetMaxLetters(500)

            -- Remove button
            local rmBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            rmBtn:SetSize(24, 24)
            rmBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            rmBtn:SetText("X")

            entry = { frame = row, editBox = eb, removeBtn = rmBtn, numLabel = numLabel }
            _lineEntries[i] = entry
        end

        entry.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * entryHeight)
        entry.frame:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        entry.numLabel:SetText(tostring(i))
        entry.editBox:SetText(line.template or "")

        -- Capture index
        local capturedIndex = i
        entry.editBox:SetScript("OnTextChanged", function(self)
            if _selectedLines[capturedIndex] then
                _selectedLines[capturedIndex].template = self:GetText()
                Editor._updatePreview()
            end
        end)
        entry.editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        entry.editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        entry.removeBtn:SetScript("OnClick", function()
            Editor._removeLine(capturedIndex)
        end)

        entry.frame:Show()
    end

    scrollChild:SetHeight(math.max(#_selectedLines * entryHeight, 1))
end

-------------------------------------------------------------------------------
-- Functions editor (bottom tab)
-------------------------------------------------------------------------------
local _funcEditorFrame = nil
local _funcListEntries = {}
local _currentEditFunc = nil

local function _buildFunctionsTab(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints(parent)

    -- Left side: function list (~35% of bottom section width, capped to leave
    -- at least 250px for the code editor on the right side.
    -- Min of 180 ensures DELVE_COMPANION_LEVEL (~141px) fits without truncation.
    local listWidth = math.floor(parent:GetWidth() * 0.35)
    if listWidth < 180 then listWidth = 180 end
    if listWidth > 180 then listWidth = 180 end
    local listHeader = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -2)
    listHeader:SetText("Functions")
    listHeader:SetTextColor(1, 0.82, 0, 1)

    -- New Function button
    local newFuncBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    newFuncBtn:SetSize(math.max(listWidth - 8, 120), 26)
    newFuncBtn:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -4)
    newFuncBtn:SetText("New Function")
    newFuncBtn:SetScript("OnClick", function()
        Editor._newFunction()
    end)

    -- Function list scroll
    local funcScroll = CreateFrame("ScrollFrame", "IPEditorFuncListScroll", container, "UIPanelScrollFrameTemplate")
    funcScroll:SetPoint("TOPLEFT", newFuncBtn, "BOTTOMLEFT", 0, -4)
    funcScroll:SetPoint("BOTTOM", container, "BOTTOM", 0, 4)
    funcScroll:SetWidth(listWidth)

    -- Ensure scrollbar is always visible when content overflows
    if funcScroll.ScrollBar then
        funcScroll.ScrollBar:SetAlpha(1)
    end

    local funcScrollChild = CreateFrame("Frame", nil, funcScroll)
    funcScrollChild:SetWidth(listWidth - 24)
    funcScrollChild:SetHeight(1)
    funcScroll:SetScrollChild(funcScrollChild)
    container._funcScrollChild = funcScrollChild

    -- Right side: code editor
    local codeHeader = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    codeHeader:SetPoint("TOPLEFT", container, "TOPLEFT", listWidth + 8, -2)
    codeHeader:SetText("Code (Lua — must return a string)")
    codeHeader:SetTextColor(1, 0.82, 0, 1)

    -- Function name input
    local nameLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", codeHeader, "BOTTOMLEFT", 0, -4)
    nameLabel:SetText("Name:")

    local nameInput = CreateFrame("EditBox", "IPEditorFuncName", container, "InputBoxTemplate")
    nameInput:SetSize(200, 20)
    nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 4, 0)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(50)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    container._funcNameInput = nameInput

    -- Code edit box
    local codeScroll = CreateFrame("ScrollFrame", "IPEditorFuncCodeScroll", container, "UIPanelScrollFrameTemplate")
    codeScroll:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -6)
    codeScroll:SetPoint("RIGHT", container, "RIGHT", -20, 0)
    codeScroll:SetPoint("BOTTOM", container, "BOTTOM", 0, 32)

    local codeEB = CreateFrame("EditBox", nil, codeScroll)
    codeEB:SetMultiLine(true)
    codeEB:SetAutoFocus(false)
    codeEB:SetFontObject("GameFontHighlightSmall")
    local codeWidth = math.max(codeScroll:GetWidth() or 0, 250)
    codeEB:SetWidth(codeWidth)
    codeEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    codeScroll:SetScrollChild(codeEB)

    -- Dynamically update EditBox width when container resizes
    codeScroll:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then
            codeEB:SetWidth(math.max(w, 250))
        end
    end)
    container._funcCodeEB = codeEB

    -- Save & Delete buttons
    local saveFuncBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    saveFuncBtn:SetSize(80, 22)
    saveFuncBtn:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", listWidth + 8, 6)
    saveFuncBtn:SetText("Save")
    saveFuncBtn:SetScript("OnClick", function()
        Editor._saveCurrentFunction()
    end)

    local delFuncBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    delFuncBtn:SetSize(80, 22)
    delFuncBtn:SetPoint("LEFT", saveFuncBtn, "RIGHT", 8, 0)
    delFuncBtn:SetText("Delete")
    delFuncBtn:SetScript("OnClick", function()
        Editor._deleteCurrentFunction()
    end)

    -- Test button
    local testFuncBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    testFuncBtn:SetSize(80, 22)
    testFuncBtn:SetPoint("LEFT", delFuncBtn, "RIGHT", 8, 0)
    testFuncBtn:SetText("Test")
    testFuncBtn:SetScript("OnClick", function()
        Editor._testCurrentFunction()
    end)

    _funcEditorFrame = container
    return container
end

function Editor._refreshFuncList()
    if not _funcEditorFrame then return end
    local scrollChild = _funcEditorFrame._funcScrollChild
    if not scrollChild then return end

    -- Hide all
    for _, e in ipairs(_funcListEntries) do
        if e.button then e.button:Hide() end
    end

    local Functions = ns.Functions
    if not Functions then return end

    local sorted = Functions.GetAllSorted()
    local rowHeight = 22
    local rowSpacing = 2

    for i, item in ipairs(sorted) do
        local entry = _funcListEntries[i]
        if not entry then
            local btn = CreateFrame("Button", nil, scrollChild)
            btn:SetSize(scrollChild:GetWidth(), rowHeight)
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * (rowHeight + rowSpacing))

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)

            local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 0.82, 0, 0.15)

            local selBg = btn:CreateTexture(nil, "BORDER")
            selBg:SetAllPoints()
            selBg:SetColorTexture(1, 0.82, 0, 0.3)
            selBg:Hide()

            local tag = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            tag:SetPoint("RIGHT", btn, "RIGHT", -4, 0)

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", btn, "LEFT", 4, 0)
            label:SetPoint("RIGHT", tag, "LEFT", -2, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)

            entry = { button = btn, label = label, tag = tag, selBg = selBg }
            _funcListEntries[i] = entry
        end

        entry.label:SetText(item.name)
        entry.tag:SetText("")  -- built-in shown in tooltip only, not inline tag

        -- Tooltip showing full name on hover (in case of truncation)
        local fullName = item.name
        entry.button:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetText then GameTooltip:SetText(fullName) end
                if item.info.builtin and GameTooltip.AddLine then
                    GameTooltip:AddLine("Built-in function", 0.5, 0.5, 0.5)
                end
                GameTooltip:Show()
            end
        end)
        entry.button:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        entry._name = item.name

        entry.button:SetScript("OnClick", function()
            Editor._editFunction(item.name)
            -- Highlight
            for _, e in ipairs(_funcListEntries) do
                if e.selBg then e.selBg:Hide() end
            end
            entry.selBg:Show()
        end)
        entry.button:Show()
    end

    scrollChild:SetHeight(math.max(#sorted * (rowHeight + rowSpacing), 1))
end

function Editor._editFunction(name)
    local Functions = ns.Functions
    if not Functions then return end

    local info = Functions.Get(name)
    if not info then return end

    _currentEditFunc = name

    if _funcEditorFrame then
        if _funcEditorFrame._funcNameInput then
            _funcEditorFrame._funcNameInput:SetText(name)
            -- Disable name editing for built-in functions
            if info.builtin then
                _funcEditorFrame._funcNameInput:Disable()
            else
                _funcEditorFrame._funcNameInput:Enable()
            end
        end
        if _funcEditorFrame._funcCodeEB then
            _funcEditorFrame._funcCodeEB:SetText(info.code or "-- Built-in function (code is native Lua)")
        end
    end
end

function Editor._newFunction()
    _currentEditFunc = nil
    if _funcEditorFrame then
        if _funcEditorFrame._funcNameInput then
            _funcEditorFrame._funcNameInput:SetText("MY_FUNCTION")
            _funcEditorFrame._funcNameInput:Enable()
        end
        if _funcEditorFrame._funcCodeEB then
            _funcEditorFrame._funcCodeEB:SetText('-- Your Lua code here. Must return a string.\nreturn "Hello World"')
        end
    end
end

function Editor._saveCurrentFunction()
    if not _funcEditorFrame then return end
    local Functions = ns.Functions
    if not Functions then return end

    local name = _funcEditorFrame._funcNameInput and _funcEditorFrame._funcNameInput:GetText() or ""
    local code = _funcEditorFrame._funcCodeEB and _funcEditorFrame._funcCodeEB:GetText() or ""

    if name == "" then
        iplog("Warn", "Editor: function name is empty")
        return
    end

    -- Don't allow saving over built-in functions
    local existing = Functions.Get(name)
    if existing and existing.builtin then
        iplog("Warn", "Editor: cannot overwrite built-in function " .. name)
        return
    end

    local ok, err = Functions.SaveUserFunction(name, code)
    if ok then
        _currentEditFunc = name:upper()
        Editor._refreshFuncList()
        iplog("Info", "Editor: saved function " .. name)
    else
        iplog("Error", "Editor: failed to save function: " .. tostring(err))
    end
end

function Editor._deleteCurrentFunction()
    if not _currentEditFunc then return end
    local Functions = ns.Functions
    if not Functions then return end

    local ok, err = Functions.DeleteUserFunction(_currentEditFunc)
    if ok then
        _currentEditFunc = nil
        Editor._newFunction()
        Editor._refreshFuncList()
        iplog("Info", "Editor: deleted function")
    else
        iplog("Warn", "Editor: " .. tostring(err))
    end
end

function Editor._testCurrentFunction()
    if not _funcEditorFrame then return end
    local Functions = ns.Functions
    if not Functions then return end

    local code = _funcEditorFrame._funcCodeEB and _funcEditorFrame._funcCodeEB:GetText() or ""
    local name = _funcEditorFrame._funcNameInput and _funcEditorFrame._funcNameInput:GetText() or "TEST"

    local val, err = Functions._executeCode(code, name)
    local msg = "Test result for " .. name .. ": "
    if val then
        msg = msg .. tostring(val)
    else
        msg = msg .. "|cffff4444" .. tostring(err) .. "|r"
    end

    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Print("IP", msg)
    end
    iplog("Info", msg)
end

-------------------------------------------------------------------------------
-- BuildEditorFrame: Create the main editor with Blizzard-native chrome.
-------------------------------------------------------------------------------
local function BuildEditorFrame()
    if _editorFrame then return _editorFrame end

    local C = getConst()
    local FRAME_W = C.FRAME_WIDTH or 860
    local FRAME_H = C.FRAME_HEIGHT or 580
    local SIDEBAR_W = C.SIDEBAR_WIDTH or 200
    local PREVIEW_W = C.PREVIEW_WIDTH or 280

    ---------------------------------------------------------------------------
    -- Main frame
    ---------------------------------------------------------------------------
    local f
    local usePortrait = false

    local ok1, result1 = pcall(function()
        return CreateFrame("Frame", "InfoPanelsEditorFrame", UIParent, "ButtonFrameTemplate")
    end)
    if ok1 and result1 then
        f = result1
        usePortrait = true
    else
        local ok2, result2 = pcall(function()
            return CreateFrame("Frame", "InfoPanelsEditorFrame", UIParent, "BasicFrameTemplateWithInset")
        end)
        if ok2 and result2 then
            f = result2
        else
            f = CreateFrame("Frame", "InfoPanelsEditorFrame", UIParent)
        end
    end

    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    tinsert(UISpecialFrames, "InfoPanelsEditorFrame")

    -- Portrait icon
    if usePortrait then
        pcall(function()
            if f.PortraitContainer and f.PortraitContainer.portrait then
                f.PortraitContainer.portrait:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
            elseif SetPortraitToTexture and f.portrait then
                SetPortraitToTexture(f.portrait, "Interface\\Icons\\INV_Misc_Gear_01")
            end
        end)
    end

    -- Title
    if f.TitleContainer and f.TitleContainer.TitleText then
        f.TitleContainer.TitleText:SetText("Info Panels Editor")
    elseif f.TitleBg then
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", f.TitleBg, "TOP", 0, -2)
        title:SetText("Info Panels Editor")
    else
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", f, "TOP", 0, -8)
        title:SetText("Info Panels Editor")
    end

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    end

    ---------------------------------------------------------------------------
    -- Content area
    ---------------------------------------------------------------------------
    local contentTop = -60
    local contentBottom = 30  -- space for bottom tabs

    local workArea = CreateFrame("Frame", nil, f)
    workArea:SetPoint("TOPLEFT", f, "TOPLEFT", 8, contentTop)
    workArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, contentBottom)

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
    -- Bottom tabs: Functions, Properties, Visibility (Textures hidden)
    ---------------------------------------------------------------------------
    local tabNames = { "Functions", "Properties", "Visibility" }
    local tabs = {}

    -- Helper: build a Blizzard-style tab button with proper tab textures.
    -- Tries CharacterFrameTabButtonTemplate first; if unavailable, constructs
    -- the tab manually with explicit texture regions.
    local ACTIVE_TEX   = "Interface\\CharacterFrame\\UI-CharacterFrame-ActiveTab"
    local INACTIVE_TEX = "Interface\\CharacterFrame\\UI-CharacterFrame-InActiveTab"
    local TAB_HEIGHT   = 32
    local TAB_PADDING  = 15

    local function createTabButton(index, labelText, parent)
        -- Attempt the Blizzard template first
        local tab
        local ok, result = pcall(function()
            return CreateFrame("Button", "IPEditorTab" .. index, parent, "CharacterFrameTabButtonTemplate")
        end)
        if ok and result then
            tab = result
            tab._isManualTab = false
        else
            tab = CreateFrame("Button", "IPEditorTab" .. index, parent)
            tab._isManualTab = true
        end

        tab:SetID(index)
        tab:SetHeight(TAB_HEIGHT)

        if tab._isManualTab then
            -- Fallback: manually create Left/Right/Middle textures
            local left = tab:CreateTexture(nil, "BACKGROUND")
            left:SetWidth(20)
            left:SetHeight(TAB_HEIGHT)
            left:SetPoint("BOTTOMLEFT")
            tab.Left = left

            local right = tab:CreateTexture(nil, "BACKGROUND")
            right:SetWidth(20)
            right:SetHeight(TAB_HEIGHT)
            right:SetPoint("BOTTOMRIGHT")
            tab.Right = right

            local middle = tab:CreateTexture(nil, "BACKGROUND")
            middle:SetHeight(TAB_HEIGHT)
            middle:SetPoint("LEFT", tab.Left, "RIGHT")
            middle:SetPoint("RIGHT", tab.Right, "LEFT")
            tab.Middle = middle

            tab.Left:SetTexture(INACTIVE_TEX)
            tab.Right:SetTexture(INACTIVE_TEX)
            tab.Middle:SetTexture(INACTIVE_TEX)
            tab.Left:SetTexCoord(0, 0.15625, 0, 1)
            tab.Right:SetTexCoord(0.84375, 1, 0, 1)
            tab.Middle:SetTexCoord(0.15625, 0.84375, 0, 1)

            -- Text label for manual tab
            local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("CENTER", 0, 2)
            tab:SetFontString(fs)
        else
            -- Blizzard template tab: use PanelTemplates API
            -- Initial state: deselected (PanelTemplates manages the built-in textures)
            if PanelTemplates_DeselectTab then
                PanelTemplates_DeselectTab(tab)
            end
            if PanelTemplates_TabResize then
                PanelTemplates_TabResize(tab, TAB_PADDING)
            end

            -- Alias the template's actual texture children to tab.Left/Right/Middle
            -- so T14 can check tab.Left:GetTexture() and get the correct result.
            -- The template creates LeftActive/LeftDisabled (or similar) texture children.
            tab.Left = tab.LeftActive or tab.LeftDisabled or tab.Left
            tab.Right = tab.RightActive or tab.RightDisabled or tab.Right
            tab.Middle = tab.MiddleActive or tab.MiddleDisabled or tab.Middle
        end

        -- Text label
        if not tab:GetFontString() then
            local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("CENTER", 0, 2)
            tab:SetFontString(fs)
        end
        tab:SetText(labelText)
        tab:GetFontString():SetPoint("CENTER", 0, 2)

        -- Size to fit text + padding (for manual tabs; template tabs get resized by PanelTemplates)
        if tab._isManualTab then
            local textWidth = tab:GetFontString():GetStringWidth() or 60
            tab:SetWidth(textWidth + TAB_PADDING * 2)
        end

        -- Highlight texture for mouseover
        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture(ACTIVE_TEX)
        hl:SetTexCoord(0.15625, 0.84375, 0, 1)
        hl:SetAlpha(0.4)

        return tab
    end

    for i, name in ipairs(tabNames) do
        local tab = createTabButton(i, name, f)

        if i == 1 then
            tab:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, -30)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -16, 0)
        end

        tab:SetScript("OnClick", function()
            Editor._selectTab(i)
        end)

        tabs[i] = tab
    end
    f._tabs = tabs

    -- Store texture paths on the frame for state management
    f._tabActiveTex   = ACTIVE_TEX
    f._tabInactiveTex = INACTIVE_TEX

    ---------------------------------------------------------------------------
    -- Layout: Three columns
    -- [Left: Panel List] | [Center: Lines editor (top) + Tab content (bottom)] | [Right: Preview]
    ---------------------------------------------------------------------------

    -- Left sidebar: Panel List
    local sidebarFrame = CreateFrame("Frame", nil, workArea)
    sidebarFrame:SetPoint("TOPLEFT", workArea, "TOPLEFT", 0, 0)
    sidebarFrame:SetSize(SIDEBAR_W, workArea:GetHeight() or (FRAME_H - 92))
    sidebarFrame:SetPoint("BOTTOMLEFT", workArea, "BOTTOMLEFT", 0, 0)

    local sidebarBorder = sidebarFrame:CreateTexture(nil, "ARTWORK")
    sidebarBorder:SetWidth(1)
    sidebarBorder:SetPoint("TOPRIGHT", sidebarFrame, "TOPRIGHT", 0, 0)
    sidebarBorder:SetPoint("BOTTOMRIGHT", sidebarFrame, "BOTTOMRIGHT", 0, 0)
    sidebarBorder:SetColorTexture(0.4, 0.4, 0.4, 0.5)

    -- Panel name input
    local nameLabel = sidebarFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", sidebarFrame, "TOPLEFT", 4, -4)
    nameLabel:SetText("Panel Name:")
    nameLabel:SetTextColor(unpack(THEME.GOLD))

    local nameInput = CreateFrame("EditBox", "IPEditorNameInput", sidebarFrame, "InputBoxTemplate")
    nameInput:SetSize(SIDEBAR_W - 12, 20)
    nameInput:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 2, -2)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(50)
    f._nameInput = nameInput

    nameInput:SetScript("OnTextChanged", function(self) Editor._updatePreview() end)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Panel list (stops above the action button container: 82px buttons + 8px gap)
    local panelListBottomOffset = 90
    local PanelList = ns.EditorPanelList
    if PanelList then
        local listFrame = PanelList.Build(sidebarFrame, SIDEBAR_W - 4, 0)
        listFrame:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", -2, -8)
        listFrame:SetPoint("BOTTOMLEFT", sidebarFrame, "BOTTOMLEFT", 0, panelListBottomOffset)
        listFrame:SetPoint("BOTTOMRIGHT", sidebarFrame, "BOTTOMRIGHT", -4, panelListBottomOffset)

        PanelList.SetOnSelect(function(id)
            Editor.EditPanel(id)
        end)
    end

    -- Action buttons with spacing (UX fix #3)
    local btnContainerHeight = 82  -- 3 rows * 22px + 2 gaps * 6px + 4px padding
    local btnContainer = CreateFrame("Frame", nil, sidebarFrame)
    btnContainer:SetSize(SIDEBAR_W - 8, btnContainerHeight)
    btnContainer:SetPoint("BOTTOMLEFT", sidebarFrame, "BOTTOMLEFT", 2, 4)

    local halfW = math.floor((SIDEBAR_W - 20) / 2)  -- narrower for spacing
    local btnSpacing = 6  -- UX fix #3: spacing between buttons

    local saveBtn = CreateFrame("Button", nil, btnContainer, "UIPanelButtonTemplate")
    saveBtn:SetSize(halfW, 22)
    saveBtn:SetPoint("TOPLEFT", btnContainer, "TOPLEFT", 0, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function() Editor.SaveCurrentPanel() end)

    local exportBtn = CreateFrame("Button", nil, btnContainer, "UIPanelButtonTemplate")
    exportBtn:SetSize(halfW, 22)
    exportBtn:SetPoint("LEFT", saveBtn, "RIGHT", btnSpacing, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function() Editor.ExportCurrentPanel() end)

    local deleteBtn = CreateFrame("Button", nil, btnContainer, "UIPanelButtonTemplate")
    deleteBtn:SetSize(halfW, 22)
    deleteBtn:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -btnSpacing)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function() Editor.DeleteCurrentPanel() end)

    local extDataBtn = CreateFrame("Button", nil, btnContainer, "UIPanelButtonTemplate")
    extDataBtn:SetSize(halfW, 22)
    extDataBtn:SetPoint("LEFT", deleteBtn, "RIGHT", btnSpacing, 0)
    extDataBtn:SetText("Ext. Data")
    extDataBtn:SetScript("OnClick", function() Editor._showExternalDataEntry() end)

    local importBtn2 = CreateFrame("Button", nil, btnContainer, "UIPanelButtonTemplate")
    importBtn2:SetSize(halfW, 22)
    importBtn2:SetPoint("TOPLEFT", deleteBtn, "BOTTOMLEFT", 0, -btnSpacing)
    importBtn2:SetText("Import")
    importBtn2:SetScript("OnClick", function() Editor.ShowImportDialog() end)

    local dupeBtn2 = CreateFrame("Button", nil, btnContainer, "UIPanelButtonTemplate")
    dupeBtn2:SetSize(halfW, 22)
    dupeBtn2:SetPoint("LEFT", importBtn2, "RIGHT", btnSpacing, 0)
    dupeBtn2:SetText("Duplicate")
    dupeBtn2:SetScript("OnClick", function() Editor.DuplicateCurrentPanel() end)

    -- Right column: Live Preview
    local previewFrame = CreateFrame("Frame", nil, workArea)
    previewFrame:SetSize(PREVIEW_W, 0)
    previewFrame:SetPoint("TOPRIGHT", workArea, "TOPRIGHT", 0, 0)
    previewFrame:SetPoint("BOTTOMRIGHT", workArea, "BOTTOMRIGHT", 0, 0)

    local previewBorder = previewFrame:CreateTexture(nil, "ARTWORK")
    previewBorder:SetWidth(1)
    previewBorder:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 0, 0)
    previewBorder:SetPoint("BOTTOMLEFT", previewFrame, "BOTTOMLEFT", 0, 0)
    previewBorder:SetColorTexture(0.4, 0.4, 0.4, 0.5)

    local LivePreview = ns.EditorLivePreview
    if LivePreview then
        local lpFrame = LivePreview.Build(previewFrame, PREVIEW_W, 0)
        lpFrame:SetAllPoints(previewFrame)
    end

    -- Center column: Lines editor (top half) + Tab content (bottom half)
    local centerFrame = CreateFrame("Frame", nil, workArea)
    centerFrame:SetPoint("TOPLEFT", sidebarFrame, "TOPRIGHT", 4, 0)
    centerFrame:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMLEFT", -4, 0)
    f._centerFrame = centerFrame

    -- Lines header
    local linesHeader = centerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    linesHeader:SetPoint("TOPLEFT", centerFrame, "TOPLEFT", 4, -2)
    linesHeader:SetText("Lines")
    linesHeader:SetTextColor(1, 0.82, 0, 1)

    -- Hint text
    local linesHint = centerFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    linesHint:SetPoint("LEFT", linesHeader, "RIGHT", 8, 0)
    linesHint:SetText("Use {{FUNCTION_NAME}} for dynamic values")

    -- Add Line button
    local addLineBtn = CreateFrame("Button", nil, centerFrame, "UIPanelButtonTemplate")
    addLineBtn:SetSize(80, 24)
    addLineBtn:SetPoint("TOPRIGHT", centerFrame, "TOPRIGHT", -4, -2)
    addLineBtn:SetText("Add Line")
    addLineBtn:SetScript("OnClick", function()
        Editor._addLine("")
    end)

    -- Lines scroll area (top ~60-65% of center, bottom section gets ~35-40%)
    local linesScroll = CreateFrame("ScrollFrame", "IPEditorLinesScroll", centerFrame, "UIPanelScrollFrameTemplate")
    linesScroll:SetPoint("TOPLEFT", linesHeader, "BOTTOMLEFT", 0, -4)
    linesScroll:SetPoint("RIGHT", centerFrame, "RIGHT", -24, 0)
    -- Use proportional height: 60% of work area for lines+preview, 40% for bottom tabs
    local workAreaH = (FRAME_H - 60 - 30)  -- contentTop offset + contentBottom
    local linesHeight = math.floor(workAreaH * 0.60) - 30  -- minus header/button space
    if linesHeight < 160 then linesHeight = 160 end
    linesScroll:SetHeight(linesHeight)

    local linesScrollChild = CreateFrame("Frame", nil, linesScroll)
    linesScrollChild:SetWidth(centerFrame:GetWidth() and centerFrame:GetWidth() - 32 or 300)
    linesScrollChild:SetHeight(1)
    linesScroll:SetScrollChild(linesScrollChild)
    f._linesScrollChild = linesScrollChild

    -- Separator between lines and tab content
    local centerSep = centerFrame:CreateTexture(nil, "ARTWORK")
    centerSep:SetHeight(1)
    centerSep:SetPoint("TOPLEFT", linesScroll, "BOTTOMLEFT", 0, -4)
    centerSep:SetPoint("TOPRIGHT", centerFrame, "TOPRIGHT", -4, 0)
    centerSep:SetColorTexture(0.4, 0.4, 0.4, 0.5)

    -- Tab content area (bottom half of center)
    local tabContentFrame = CreateFrame("Frame", nil, centerFrame)
    tabContentFrame:SetPoint("TOPLEFT", centerSep, "BOTTOMLEFT", 0, -4)
    tabContentFrame:SetPoint("BOTTOMRIGHT", centerFrame, "BOTTOMRIGHT", 0, 0)
    f._tabContentFrame = tabContentFrame

    -- Tab 1: Functions editor
    local funcTab = _buildFunctionsTab(tabContentFrame)
    funcTab:Show()
    f._tabFrames = f._tabFrames or {}
    f._tabFrames[1] = funcTab

    -- Tab 2: Properties Panel
    local PropertiesPanel = ns.EditorPropertiesPanel
    if PropertiesPanel then
        local ppFrame = PropertiesPanel.Build(tabContentFrame, tabContentFrame:GetWidth() or 350, 0)
        ppFrame:SetAllPoints(tabContentFrame)
        ppFrame:Hide()
        f._tabFrames[2] = ppFrame
    end

    -- Tab 3: Visibility conditions
    local visTab = CreateFrame("Frame", nil, tabContentFrame)
    visTab:SetAllPoints(tabContentFrame)
    visTab:Hide()
    f._tabFrames[3] = visTab

    local visInstr = visTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    visInstr:SetPoint("TOPLEFT", visTab, "TOPLEFT", 8, -8)
    visInstr:SetText("Visibility Conditions")
    visInstr:SetTextColor(1, 0.82, 0, 1)

    local visDesc = visTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    visDesc:SetPoint("TOPLEFT", visInstr, "BOTTOMLEFT", 0, -4)
    visDesc:SetText("Check conditions below. All checked conditions must be true (AND logic).")
    visDesc:SetJustifyH("LEFT")

    local VIS_CONDITIONS = {
        { key = "always",       label = "Always visible",        type = "always" },
        { key = "in_delve",     label = "Only in Delves",        sourceId = "delve.indelve",   operator = "truthy" },
        { key = "in_dungeon",   label = "Only in Dungeons",      type = "instance_check", instanceType = "party" },
        { key = "in_raid",      label = "Only in Raids",         type = "instance_check", instanceType = "raid" },
        { key = "in_pvp",       label = "Only in PvP",           type = "instance_check", instanceType = "pvp" },
        { key = "in_openworld", label = "Only in open world",    type = "instance_check", instanceType = "none" },
        { key = "in_group",     label = "Only when in a group",  type = "group_check",    inGroup = true },
        { key = "solo",         label = "Only when solo",        type = "group_check",    inGroup = false },
        { key = "in_combat",    label = "Only in combat",        type = "combat_check",   inCombat = true },
        { key = "out_combat",   label = "Only out of combat",    type = "combat_check",   inCombat = false },
    }

    local visCheckboxes = {}
    local VIS_CB_SPACING = 24
    local VIS_CB_TOP = -36

    for i, cond in ipairs(VIS_CONDITIONS) do
        local cb = CreateFrame("CheckButton", "IPEditorVisCB" .. i, visTab, "UICheckButtonTemplate")
        local col = (i <= 5) and 0 or 1
        local row = (i <= 5) and (i - 1) or (i - 6)
        local xOffset = 12 + col * 220
        local yOffset = VIS_CB_TOP - row * VIS_CB_SPACING
        cb:SetPoint("TOPLEFT", visTab, "TOPLEFT", xOffset, yOffset)
        cb:SetSize(22, 22)

        local cbLabel = visTab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cbLabel:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cbLabel:SetText(cond.label)

        cb._condKey = cond.key
        cb._condDef = cond

        cb:SetScript("OnClick", function(self)
            Editor._onVisibilityChanged()
        end)

        visCheckboxes[cond.key] = cb
    end
    f._visCheckboxes = visCheckboxes
    f._visConditions = VIS_CONDITIONS

    ---------------------------------------------------------------------------
    -- Help text
    ---------------------------------------------------------------------------
    local HELP_TEXTS = {
        [1] = "Browse and edit Functions. Use {{FUNCTION_NAME}} in your Lines to insert dynamic values.",
        [2] = "Edit properties for the selected panel: font, color, format.",
        [3] = "Set Visibility conditions. All checked conditions must be true (AND logic).",
    }

    local helpLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    helpLabel:SetPoint("BOTTOMLEFT", workArea, "TOPLEFT", 4, 2)
    helpLabel:SetPoint("RIGHT", workArea, "RIGHT", -80, 0)
    helpLabel:SetJustifyH("LEFT")
    helpLabel:SetWordWrap(true)
    helpLabel:SetText(HELP_TEXTS[1] or "")
    f._helpLabel = helpLabel
    f._helpTexts = HELP_TEXTS

    local db = _G.InfoPanelsDB or {}
    local hideHelp = db.hideHelp or false

    local helpToggle = CreateFrame("CheckButton", "IPEditorHelpToggle", f, "UICheckButtonTemplate")
    helpToggle:SetSize(20, 20)
    helpToggle:SetPoint("TOPRIGHT", workArea, "TOPRIGHT", -4, 18)
    helpToggle:SetChecked(hideHelp)

    local helpToggleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    helpToggleLabel:SetPoint("RIGHT", helpToggle, "LEFT", -2, 0)
    helpToggleLabel:SetText("Hide Help")

    if hideHelp then helpLabel:Hide() end

    helpToggle:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        db = _G.InfoPanelsDB or {}
        db.hideHelp = checked
        _G.InfoPanelsDB = db
        if checked then helpLabel:Hide() else helpLabel:Show() end
    end)
    f._helpToggle = helpToggle

    f._activeTab = 1

    _editorFrame = f
    return f
end

-------------------------------------------------------------------------------
-- _selectTab
-------------------------------------------------------------------------------
function Editor._selectTab(tabIndex)
    if not _editorFrame then return end

    _editorFrame._activeTab = tabIndex

    local tabFrames = _editorFrame._tabFrames or {}
    for _, tf in pairs(tabFrames) do
        if tf and tf.Hide then tf:Hide() end
    end

    if tabFrames[tabIndex] then
        tabFrames[tabIndex]:Show()
    end

    local tabs = _editorFrame._tabs or {}
    local activeTex   = _editorFrame._tabActiveTex   or "Interface\\CharacterFrame\\UI-CharacterFrame-ActiveTab"
    local inactiveTex = _editorFrame._tabInactiveTex or "Interface\\CharacterFrame\\UI-CharacterFrame-InActiveTab"

    for i, tab in ipairs(tabs) do
        local isSelected = (i == tabIndex)

        if tab._isManualTab then
            -- Manual fallback: set textures directly
            local tex = isSelected and activeTex or inactiveTex
            if tab.Left  then tab.Left:SetTexture(tex) end
            if tab.Right then tab.Right:SetTexture(tex) end
            if tab.Middle then tab.Middle:SetTexture(tex) end
        else
            -- Blizzard template: use PanelTemplates API
            if isSelected then
                if PanelTemplates_SelectTab then PanelTemplates_SelectTab(tab) end
            else
                if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab) end
            end
            -- Re-alias after state change so tab.Left points to the currently visible texture
            tab.Left = tab.LeftActive or tab.LeftDisabled or tab.Left
            tab.Right = tab.RightActive or tab.RightDisabled or tab.Right
            tab.Middle = tab.MiddleActive or tab.MiddleDisabled or tab.Middle
        end

        -- Text color: gold for selected, dim for inactive
        local fs = tab:GetFontString()
        if fs then
            if isSelected then
                fs:SetTextColor(1, 0.82, 0)
            else
                fs:SetTextColor(0.6, 0.6, 0.6)
            end
        end
    end

    if _editorFrame._helpLabel and _editorFrame._helpTexts then
        _editorFrame._helpLabel:SetText(_editorFrame._helpTexts[tabIndex] or "")
    end

    -- Refresh functions list when switching to Functions tab
    if tabIndex == 1 then
        Editor._refreshFuncList()
    end

    iplog("Info", "Editor: switched to tab " .. tabIndex)
end

-------------------------------------------------------------------------------
-- Visibility handling
-------------------------------------------------------------------------------
function Editor._onVisibilityChanged()
    if not _editorFrame or not _editorFrame._visCheckboxes then return end
    if not _currentDefinition then return end

    local conditions = {}
    for _, condDef in ipairs(_editorFrame._visConditions) do
        local cb = _editorFrame._visCheckboxes[condDef.key]
        if cb and cb:GetChecked() then
            local entry = {}
            if condDef.type == "always" then
                entry.type = "always"
            elseif condDef.sourceId then
                entry.sourceId = condDef.sourceId
                entry.operator = condDef.operator or "truthy"
            elseif condDef.type == "instance_check" then
                entry.type = "instance_check"
                entry.instanceType = condDef.instanceType
            elseif condDef.type == "group_check" then
                entry.type = "group_check"
                entry.inGroup = condDef.inGroup
            elseif condDef.type == "combat_check" then
                entry.type = "combat_check"
                entry.inCombat = condDef.inCombat
            end
            conditions[#conditions + 1] = entry
        end
    end

    _currentDefinition.visibility = _currentDefinition.visibility or {}
    _currentDefinition.visibility.conditions = conditions
end

function Editor._refreshVisibilityTab()
    if not _editorFrame or not _editorFrame._visCheckboxes then return end

    for _, cb in pairs(_editorFrame._visCheckboxes) do
        cb:SetChecked(false)
    end

    if not _currentDefinition or not _currentDefinition.visibility then return end
    local conditions = _currentDefinition.visibility.conditions
    if not conditions then return end

    for _, cond in ipairs(conditions) do
        for _, condDef in ipairs(_editorFrame._visConditions) do
            local match = false
            if cond.type == "always" and condDef.type == "always" then
                match = true
            elseif cond.sourceId and cond.sourceId == condDef.sourceId then
                match = true
            elseif cond.type == "instance_check" and condDef.type == "instance_check"
                   and cond.instanceType == condDef.instanceType then
                match = true
            elseif cond.type == "group_check" and condDef.type == "group_check"
                   and cond.inGroup == condDef.inGroup then
                match = true
            elseif cond.type == "combat_check" and condDef.type == "combat_check"
                   and cond.inCombat == condDef.inCombat then
                match = true
            end
            if match then
                local cb = _editorFrame._visCheckboxes[condDef.key]
                if cb then cb:SetChecked(true) end
                break
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Line operations
-------------------------------------------------------------------------------
function Editor._addLine(template)
    if #_selectedLines >= 50 then
        iplog("Warn", "Editor: max 50 lines reached")
        return
    end

    _selectedLines[#_selectedLines + 1] = { template = template or "" }
    _rebuildLineEditors()
    Editor._updatePreview()
end

function Editor._removeLine(index)
    if index and index >= 1 and index <= #_selectedLines then
        table.remove(_selectedLines, index)
        _rebuildLineEditors()
        Editor._updatePreview()
    end
end

-------------------------------------------------------------------------------
-- _updatePreview
-------------------------------------------------------------------------------
function Editor._updatePreview()
    local LivePreview = ns.EditorLivePreview
    if not LivePreview then return end

    local name = ""
    if _editorFrame and _editorFrame._nameInput then
        name = _editorFrame._nameInput:GetText()
    end
    if (not name or name == "") and _currentDefinition then
        name = _currentDefinition.title or ""
    end

    -- Resolve templates for preview
    local Functions = ns.Functions
    local previewLines = {}
    for _, line in ipairs(_selectedLines) do
        local resolved = line.template or ""
        if Functions then
            resolved = Functions.ResolveTemplate(resolved)
        end
        previewLines[#previewLines + 1] = resolved
    end

    LivePreview.UpdateLines(name ~= "" and name or "Untitled Panel", previewLines)
end

-------------------------------------------------------------------------------
-- External data entry
-------------------------------------------------------------------------------
function Editor._showExternalDataEntry()
    local ImportExport = ns.EditorImportExport
    if not ImportExport then return end
    ImportExport.ShowExternalDataEntry("manual", "Manual Data Entry")
end

-------------------------------------------------------------------------------
-- Panel operations
-------------------------------------------------------------------------------
function Editor.StartNewPanel()
    local defaultName = "New Panel"
    local newId = generateUniqueId("user_new_panel")

    local definition = {
        id = newId,
        title = defaultName,
        builtin = false,
        lines = {},
    }

    local db = _G.InfoPanelsDB or {}
    db.userPanels = db.userPanels or {}
    db.userPanels[newId] = definition
    db.panels = db.panels or {}
    db.panels[newId] = db.panels[newId] or {}
    _G.InfoPanelsDB = db

    local PanelEngine = ns.PanelEngine
    if PanelEngine then
        PanelEngine.CreatePanel(definition, db.panels[newId])
    end

    _currentDefinition = definition
    _selectedLines = {}
    if _editorFrame and _editorFrame._nameInput then
        _editorFrame._nameInput:SetText(defaultName)
    end

    _rebuildLineEditors()
    Editor._refreshVisibilityTab()

    local PanelList = ns.EditorPanelList
    if PanelList then
        PanelList.Refresh()
        PanelList.SetSelectedId(newId)
    end

    Editor._updatePreview()
    iplog("Info", "Editor: created new panel " .. newId)
end

function Editor.EditPanel(id)
    local PanelEngine = ns.PanelEngine
    if not PanelEngine then return end

    local panel = PanelEngine.GetPanel(id)
    local def = panel and panel.definition

    if not def then
        local db = _G.InfoPanelsDB or {}
        def = db.userPanels and db.userPanels[id]
    end

    if not def then return end

    _currentDefinition = def
    _selectedLines = {}

    -- Load lines from definition
    if def.lines then
        for _, line in ipairs(def.lines) do
            _selectedLines[#_selectedLines + 1] = {
                template = line.template or "",
            }
        end
    end

    -- Legacy: convert bindings to lines for editing
    if #_selectedLines == 0 and def.bindings then
        for _, b in ipairs(def.bindings) do
            local funcName = (b.sourceId or ""):upper():gsub("%.", "_")
            _selectedLines[#_selectedLines + 1] = {
                template = (b.label or "") .. ": {{" .. funcName .. "}}",
            }
        end
    end

    if _editorFrame and _editorFrame._nameInput then
        _editorFrame._nameInput:SetText(def.title or "")
    end

    _rebuildLineEditors()
    Editor._refreshVisibilityTab()
    Editor._updatePreview()
    iplog("Info", "Editor: editing panel " .. tostring(id))
end

function Editor.SaveCurrentPanel()
    if not _editorFrame then return end
    local name = _editorFrame._nameInput:GetText()
    if not name or name == "" then
        iplog("Warn", "Editor.Save: no panel name")
        return
    end

    local id = _currentDefinition and _currentDefinition.id or
        generateUniqueId("user_" .. name:lower():gsub("[^%w]", "_"))

    local Utils = ns.Utils
    local definition
    if _currentDefinition and Utils then
        definition = Utils.DeepCopy(_currentDefinition)
    else
        definition = {}
    end
    definition.id = id
    definition.title = name
    definition.builtin = false

    -- Save lines from editor state
    definition.lines = {}
    for _, line in ipairs(_selectedLines) do
        definition.lines[#definition.lines + 1] = {
            template = line.template or "",
        }
    end

    -- Remove legacy bindings if we're using lines
    if #definition.lines > 0 then
        definition.bindings = nil
    end

    local db = _G.InfoPanelsDB or {}
    db.userPanels = db.userPanels or {}
    db.userPanels[id] = definition
    db.panels = db.panels or {}
    _G.InfoPanelsDB = db

    local PanelEngine = ns.PanelEngine
    if PanelEngine then
        if PanelEngine.GetPanel(id) then
            PanelEngine.DestroyPanel(id)
        end
        local panelDb = db.panels[id] or {}
        db.panels[id] = panelDb
        PanelEngine.CreatePanel(definition, panelDb)
        PanelEngine.UpdatePanel(id)
        PanelEngine.ShowPanel(id)
    end

    _currentDefinition = definition

    local PanelList = ns.EditorPanelList
    if PanelList then
        PanelList.Refresh()
        PanelList.SetSelectedId(id)
    end

    iplog("Info", "Editor.Save: saved panel " .. id)
end

function Editor.DeleteCurrentPanel()
    if not _currentDefinition then return end
    local id = _currentDefinition.id

    local popup = CreateFrame("Frame", "IPEditorDeleteConfirm", UIParent, "BasicFrameTemplateWithInset")
    popup:SetSize(300, 120)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("TOOLTIP")

    local msg = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msg:SetPoint("TOP", popup, "TOP", 0, -30)
    msg:SetText("Delete \"" .. (_currentDefinition.title or id) .. "\"?")

    popup.CloseButton:SetScript("OnClick", function() popup:Hide() end)

    local yesBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    yesBtn:SetSize(80, 24)
    yesBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", -44, 8)
    yesBtn:SetText("Delete")
    yesBtn:SetScript("OnClick", function()
        local PanelEngine = ns.PanelEngine
        if PanelEngine then PanelEngine.DestroyPanel(id) end

        local db = _G.InfoPanelsDB or {}
        if _currentDefinition.builtin then
            db.deletedBuiltins = db.deletedBuiltins or {}
            db.deletedBuiltins[id] = true
        end
        if db.userPanels then db.userPanels[id] = nil end
        if db.panels then db.panels[id] = nil end

        _currentDefinition = nil
        _selectedLines = {}

        if _editorFrame and _editorFrame._nameInput then
            _editorFrame._nameInput:SetText("")
        end

        _rebuildLineEditors()
        Editor._updatePreview()

        local PanelList = ns.EditorPanelList
        if PanelList then PanelList.Refresh() end

        iplog("Info", "Editor.Delete: deleted panel " .. id)
        popup:Hide()
    end)

    local noBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    noBtn:SetSize(80, 24)
    noBtn:SetPoint("LEFT", yesBtn, "RIGHT", 8, 0)
    noBtn:SetText("Cancel")
    noBtn:SetScript("OnClick", function() popup:Hide() end)

    tinsert(UISpecialFrames, "IPEditorDeleteConfirm")
    popup:Show()
end

function Editor.DuplicateCurrentPanel()
    if not _currentDefinition then return end
    local srcDef = _currentDefinition
    local name = (srcDef.title or "Panel") .. " (Copy)"
    local newId = generateUniqueId("user_" .. name:lower():gsub("[^%w]", "_"))

    local Utils = ns.Utils
    local definition
    if Utils then
        definition = Utils.DeepCopy(srcDef)
    else
        definition = { lines = {} }
    end
    definition.id = newId
    definition.title = name
    definition.builtin = false
    definition.uid = nil

    local db = _G.InfoPanelsDB or {}
    db.userPanels = db.userPanels or {}
    db.userPanels[newId] = definition
    db.panels = db.panels or {}
    db.panels[newId] = db.panels[newId] or {}
    _G.InfoPanelsDB = db

    local PanelEngine = ns.PanelEngine
    if PanelEngine then
        PanelEngine.CreatePanel(definition, db.panels[newId])
        PanelEngine.UpdatePanel(newId)
        PanelEngine.ShowPanel(newId)
    end

    _currentDefinition = definition
    _selectedLines = {}
    if definition.lines then
        for _, line in ipairs(definition.lines) do
            _selectedLines[#_selectedLines + 1] = { template = line.template or "" }
        end
    end

    if _editorFrame and _editorFrame._nameInput then
        _editorFrame._nameInput:SetText(name)
    end

    _rebuildLineEditors()

    local PanelList = ns.EditorPanelList
    if PanelList then
        PanelList.Refresh()
        PanelList.SetSelectedId(newId)
    end

    Editor._updatePreview()
    iplog("Info", "Editor.Duplicate: created '" .. name .. "' id=" .. newId)
end

function Editor.ExportCurrentPanel()
    if not _currentDefinition then
        Editor.SaveCurrentPanel()
        if not _currentDefinition then return end
    end

    local ProfileCodec = ns.ProfileCodec
    if not ProfileCodec then return end

    local profileString, err = ProfileCodec.Export(_currentDefinition)
    if not profileString then
        iplog("Error", "Export failed: " .. tostring(err))
        return
    end

    local shareText = ProfileCodec.GenerateShareText(_currentDefinition, profileString)
    local ImportExport = ns.EditorImportExport
    if ImportExport then
        ImportExport.ShowExport(profileString, shareText)
    end
end

function Editor.ShowImportDialog()
    local ImportExport = ns.EditorImportExport
    if ImportExport then
        ImportExport.ShowImport(function(definition)
            local PanelList = ns.EditorPanelList
            if PanelList then
                PanelList.Refresh()
                if definition and definition.id then
                    PanelList.SetSelectedId(definition.id)
                end
            end
            if definition and definition.id then
                Editor.EditPanel(definition.id)
            end
        end)
    end
end

function Editor.ShowExportDialog(text)
    local ImportExport = ns.EditorImportExport
    if ImportExport then
        ImportExport.ShowExport(text)
    end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
function Editor.Show()
    if IsInCombat() then
        _pendingOpenAfterCombat = true
        iplog("Info", "Editor: combat lockdown, will open after combat ends")
        if CP and CP._cpprint then
            CP._cpprint("Editor unavailable during combat. Will open when combat ends.")
        end
        return
    end

    if _G.CouchPotatoConfigFrame and _G.CouchPotatoConfigFrame:IsShown() then
        _G.CouchPotatoConfigFrame:Hide()
    end

    if not _editorFrame then BuildEditorFrame() end
    _editorFrame:Show()
    _editorFrame:Raise()

    local PanelList = ns.EditorPanelList
    if PanelList then PanelList.Refresh() end

    Editor._selectTab(1)
    _rebuildLineEditors()
    Editor._updatePreview()

    iplog("Info", "Editor: opened")
end

function Editor.Hide()
    if _editorFrame then _editorFrame:Hide() end
end

function Editor.Toggle()
    if not _editorFrame then
        Editor.Show()
        return
    end
    if _editorFrame:IsShown() then
        Editor.Hide()
    else
        Editor.Show()
    end
end

return Editor
