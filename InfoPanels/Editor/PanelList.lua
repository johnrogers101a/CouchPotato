-- InfoPanels/Editor/PanelList.lua
-- Sidebar panel list: shows all panels (built-in + user), click to select.
-- Single Responsibility: Panel list display and selection.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local PanelList = {}
ns.EditorPanelList = PanelList

local _listFrame = nil
local _entries = {}
local _selectedId = nil
local _onSelectCallback = nil

-------------------------------------------------------------------------------
-- SetCallback: Set the function called when a panel is selected.
-------------------------------------------------------------------------------
function PanelList.SetOnSelect(callback)
    _onSelectCallback = callback
end

-------------------------------------------------------------------------------
-- GetSelectedId: Return the currently selected panel ID.
-------------------------------------------------------------------------------
function PanelList.GetSelectedId()
    return _selectedId
end

-------------------------------------------------------------------------------
-- SetSelectedId: Programmatically select a panel.
-------------------------------------------------------------------------------
function PanelList.SetSelectedId(id)
    _selectedId = id
    PanelList._highlightSelected()
end

-------------------------------------------------------------------------------
-- Build: Create the panel list UI inside the given parent frame.
-------------------------------------------------------------------------------
function PanelList.Build(parent, width, height)
    if _listFrame then return _listFrame end

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height)

    -- Header
    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -4)
    header:SetText("Panels")
    header:SetTextColor(1, 0.82, 0, 1)

    -- New Panel button
    local newBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    newBtn:SetSize(width - 8, 24)
    newBtn:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    newBtn:SetText("New Panel")
    newBtn:SetScript("OnClick", function()
        if ns.Editor then ns.Editor.StartNewPanel() end
    end)

    -- Scroll frame for panel list
    local scrollFrame = CreateFrame("ScrollFrame", "IPEditorPanelListScroll", container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 0, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -24, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width - 32)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    container._scrollChild = scrollChild
    _listFrame = container
    return container
end

-------------------------------------------------------------------------------
-- Refresh: Rebuild the panel list from engine + user panels.
-------------------------------------------------------------------------------
function PanelList.Refresh()
    if not _listFrame then return end
    local scrollChild = _listFrame._scrollChild
    if not scrollChild then return end

    -- Hide old entries
    for _, e in ipairs(_entries) do
        if e.button then e.button:Hide() end
    end

    local PanelEngine = ns.PanelEngine
    local db = _G.InfoPanelsDB or {}
    local userPanels = db.userPanels or {}

    -- Collect all panel IDs
    local allIds = {}
    local seen = {}
    if PanelEngine then
        for id in pairs(PanelEngine.GetAllPanels()) do
            if not seen[id] then
                allIds[#allIds + 1] = id
                seen[id] = true
            end
        end
    end
    for id in pairs(userPanels) do
        if not seen[id] then
            allIds[#allIds + 1] = id
            seen[id] = true
        end
    end
    table.sort(allIds)

    for i, id in ipairs(allIds) do
        local entry = _entries[i]
        if not entry then
            local btn = CreateFrame("Button", nil, scrollChild)
            btn:SetSize(scrollChild:GetWidth(), 20)
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * 22)
            btn:EnableMouse(true)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)

            local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 0.82, 0, 0.15)

            local selectedTex = btn:CreateTexture(nil, "BORDER")
            selectedTex:SetAllPoints()
            selectedTex:SetColorTexture(1, 0.82, 0, 0.3)
            selectedTex:Hide()

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", btn, "LEFT", 6, 0)
            label:SetJustifyH("LEFT")

            local builtinTag = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            builtinTag:SetPoint("RIGHT", btn, "RIGHT", -4, 0)

            entry = { button = btn, bg = bg, selectedTex = selectedTex, label = label, builtinTag = builtinTag }
            _entries[i] = entry
        end

        -- Determine display info
        local panel = PanelEngine and PanelEngine.GetPanel(id)
        local def = panel and panel.definition
        if not def then def = userPanels[id] end
        local displayName = def and def.title or id
        local isBuiltin = def and def.builtin

        entry.label:SetText(displayName)
        entry.builtinTag:SetText(isBuiltin and "|cff888888built-in|r" or "")
        entry._id = id

        entry.button:SetScript("OnClick", function()
            _selectedId = id
            PanelList._highlightSelected()
            if _onSelectCallback then _onSelectCallback(id) end
        end)
        entry.button:Show()
    end

    scrollChild:SetHeight(math.max(#allIds * 22, 1))
    PanelList._highlightSelected()
end

-------------------------------------------------------------------------------
-- _highlightSelected: Update visual selection state.
-------------------------------------------------------------------------------
function PanelList._highlightSelected()
    for _, e in ipairs(_entries) do
        if e.button and e.button:IsShown() then
            if e._id == _selectedId then
                e.selectedTex:Show()
            else
                e.selectedTex:Hide()
            end
        end
    end
end

return PanelList
