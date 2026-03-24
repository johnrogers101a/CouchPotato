-- CouchPotato/ConfigWindow.lua
-- Shared configuration window for the CouchPotato suite.
-- Error Log tab: displays captured errors, supports export and clear.
--
-- Exposes (via CouchPotatoShared.ConfigWindow):
--   Show()   — open window
--   Hide()   — close window
--   Toggle() — toggle visibility
--
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotatoShared

local WINDOW_W = 540
local WINDOW_H = 400
local ENTRY_HEIGHT = 44  -- compact height per error entry

-------------------------------------------------------------------------------
-- Scroll content helpers
-------------------------------------------------------------------------------

local function FormatTimestamp(ts)
    -- ts is GetTime() value (seconds since WoW session start); show as seconds
    if type(ts) == "number" then
        return string.format("%.1fs", ts)
    end
    return "?"
end

local function BuildErrorEntryText(entry)
    local ts   = FormatTimestamp(entry.timestamp)
    local name = entry.addonName or "?"
    local msg  = entry.message or ""
    -- Truncate message for compact display
    if #msg > 100 then msg = msg:sub(1, 100) .. "..." end
    return string.format("[%s] [%s] %s", ts, name, msg)
end

-------------------------------------------------------------------------------
-- Export popup
-------------------------------------------------------------------------------

local _exportFrame = nil

local function BuildExportPopup()
    if _exportFrame then return _exportFrame end

    local f = CreateFrame("Frame", "CouchPotatoExportFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(500, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("TOOLTIP")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    tinsert(UISpecialFrames, "CouchPotatoExportFrame")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", f.TitleBg, "LEFT", 5, 0)
    title:SetText("Export Error Log")

    f.CloseButton:SetScript("OnClick", function() f:Hide() end)

    local instr = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    instr:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -36)
    instr:SetText("Select all (Ctrl+A) then copy (Ctrl+C)")

    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetSize(WINDOW_W - 80, 200)
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -56)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    f._editBox = eb

    _exportFrame = f
    return f
end

local function ShowExport(logEntries)
    local f = BuildExportPopup()
    local lines = {}
    for i, entry in ipairs(logEntries) do
        lines[#lines + 1] = string.format(
            "[%s] [%s]\nMessage: %s\nStack: %s",
            FormatTimestamp(entry.timestamp),
            entry.addonName or "?",
            entry.message or "",
            entry.stack or ""
        )
        lines[#lines + 1] = "---"
    end
    f._editBox:SetText(table.concat(lines, "\n"))
    f._editBox:HighlightText()
    f._editBox:SetFocus()
    f:Show()
    f:Raise()
end

-------------------------------------------------------------------------------
-- Main config window
-------------------------------------------------------------------------------

local _frame = nil
local _scrollContent = nil
local _entryFrames = {}

local function RebuildErrorList()
    if not _scrollContent then return end

    local log = (CouchPotatoDB and CouchPotatoDB.errorLog) or {}

    -- Reuse or create entry frames
    for i, entry in ipairs(log) do
        local ef = _entryFrames[i]
        if not ef then
            ef = CreateFrame("Frame", nil, _scrollContent)
            ef:SetHeight(ENTRY_HEIGHT)
            ef:SetPoint("TOPLEFT",  _scrollContent, "TOPLEFT",  0, -(i - 1) * ENTRY_HEIGHT)
            ef:SetPoint("TOPRIGHT", _scrollContent, "TOPRIGHT", 0, -(i - 1) * ENTRY_HEIGHT)

            local bg = ef:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.1, 0.1, 0.1, i % 2 == 0 and 0.3 or 0.1)

            local label = ef:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT",  ef, "TOPLEFT",  6, -4)
            label:SetPoint("TOPRIGHT", ef, "TOPRIGHT", -6, -4)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(true)
            ef._label = label

            _entryFrames[i] = ef
        end
        ef._label:SetText(BuildErrorEntryText(entry))
        ef:Show()
    end

    -- Hide unused frames
    for i = #log + 1, #_entryFrames do
        _entryFrames[i]:Hide()
    end

    -- Resize content frame
    local totalH = math.max(#log * ENTRY_HEIGHT, 1)
    _scrollContent:SetHeight(totalH)
end

local function _build()
    local f = CreateFrame("Frame", "CouchPotatoConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    tinsert(UISpecialFrames, "CouchPotatoConfigFrame")

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", f.TitleBg, "LEFT", 5, 0)
    title:SetText("CouchPotato v" .. CP.version)

    f.CloseButton:SetScript("OnClick", function() f:Hide() end)

    ---------------------------------------------------------------------------
    -- Tab: Error Log header
    ---------------------------------------------------------------------------
    local tabLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tabLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -36)
    tabLabel:SetText("Error Log")

    local errorCountFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    errorCountFS:SetPoint("LEFT", tabLabel, "RIGHT", 8, 0)
    f._errorCountFS = errorCountFS

    ---------------------------------------------------------------------------
    -- Buttons row
    ---------------------------------------------------------------------------
    local BTN_W, BTN_H = 120, 22

    local exportBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    exportBtn:SetSize(BTN_W, BTN_H)
    exportBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -34)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        local log = (CouchPotatoDB and CouchPotatoDB.errorLog) or {}
        ShowExport(log)
    end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(BTN_W, BTN_H)
    clearBtn:SetPoint("RIGHT", exportBtn, "LEFT", -6, 0)
    clearBtn:SetText("Clear Log")
    clearBtn:SetScript("OnClick", function()
        if CouchPotatoDB then
            CouchPotatoDB.errorLog = {}
        end
        RebuildErrorList()
        if f._errorCountFS then
            f._errorCountFS:SetText("0 entries")
        end
    end)

    ---------------------------------------------------------------------------
    -- Separator
    ---------------------------------------------------------------------------
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -58)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -58)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)

    ---------------------------------------------------------------------------
    -- ScrollFrame for error entries
    ---------------------------------------------------------------------------
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     f,   "TOPLEFT",  16, -68)
    scrollFrame:SetPoint("BOTTOMRIGHT", f,   "BOTTOMRIGHT", -32, 16)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(WINDOW_W - 60)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    _scrollContent = content

    ---------------------------------------------------------------------------
    -- OnShow: refresh list and count
    ---------------------------------------------------------------------------
    f:SetScript("OnShow", function(self)
        RebuildErrorList()
        local log = (CouchPotatoDB and CouchPotatoDB.errorLog) or {}
        self._errorCountFS:SetText(#log .. " entr" .. (#log == 1 and "y" or "ies"))
    end)

    _frame = f
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
CP.ConfigWindow = {
    Show = function()
        if not _frame then _build() end
        _frame:Show()
        _frame:Raise()
    end,
    Hide = function()
        if _frame then _frame:Hide() end
    end,
    Toggle = function()
        if not _frame then _build() end
        if _frame:IsShown() then
            _frame:Hide()
        else
            _frame:Show()
            _frame:Raise()
        end
    end,
    -- Exposed for tests
    _GetFrame = function()
        return _frame
    end,
    _Build = function()
        if not _frame then _build() end
    end,
    _RebuildErrorList = RebuildErrorList,
}
