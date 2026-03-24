-- CouchPotato/ConfigWindow.lua
-- Shared configuration window for the CouchPotato suite.
-- Error Log tab: displays captured errors, supports export and clear.
-- Debug Log tab: displays all debug/info/warn/error entries from CouchPotatoDB.debugLog.
--
-- Exposes (via CouchPotatoShared.ConfigWindow):
--   Show()   — open window
--   Hide()   — close window
--   Toggle() — toggle visibility
--
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotatoShared

local WINDOW_W = 580
local WINDOW_H = 420
local ENTRY_HEIGHT = 44  -- compact height per error entry
local DEBUG_ENTRY_HEIGHT = 20  -- compact height per debug entry

-- Level colors (for debug log display)
local LEVEL_COLORS = {
    DEBUG = "|cff888888",
    INFO  = "|cffffffff",
    WARN  = "|cffffff00",
    ERROR = "|cffff4444",
}

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

local function BuildDebugEntryText(entry)
    local ts    = FormatTimestamp(entry.timestamp)
    local level = entry.level or "INFO"
    local addon = entry.addon or "?"
    local msg   = entry.message or ""
    if #msg > 120 then msg = msg:sub(1, 120) .. "..." end
    local color = LEVEL_COLORS[level] or "|cffffffff"
    return string.format("%s[%s]|r [%s] [%s] %s", color, level, ts, addon, msg)
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
    title:SetText("Export Log")

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

local function ShowExport(logEntries, isDebug)
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "ConfigWindow: export clicked, entries=" .. tostring(#logEntries) .. " debug=" .. tostring(isDebug or false))
    end
    local f = BuildExportPopup()
    local lines = {}
    if isDebug then
        for _, entry in ipairs(logEntries) do
            lines[#lines + 1] = string.format(
                "[%s] [%s] [%s] %s",
                FormatTimestamp(entry.timestamp),
                entry.level or "INFO",
                entry.addon or "?",
                entry.message or ""
            )
        end
    else
        for _, entry in ipairs(logEntries) do
            lines[#lines + 1] = string.format(
                "[%s] [%s]\nMessage: %s\nStack: %s",
                FormatTimestamp(entry.timestamp),
                entry.addonName or "?",
                entry.message or "",
                entry.stack or ""
            )
            lines[#lines + 1] = "---"
        end
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

-- Debug log tab state
local _debugScrollContent = nil
local _debugEntryFrames = {}
local _activeTab = "error"  -- "error" or "debug"
local _errorTabContent = nil
local _debugTabContent = nil

local function RebuildErrorList()
    if not _scrollContent then return end

    local log = (CouchPotatoDB and CouchPotatoDB.errorLog) or {}

    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Debug("CP", "ConfigWindow: rebuilding error list, count=" .. tostring(#log))
    end

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

local function RebuildDebugList()
    if not _debugScrollContent then return end

    local log = (CouchPotatoDB and CouchPotatoDB.debugLog) or {}

    -- Show newest first (reverse order)
    local reversed = {}
    for i = #log, 1, -1 do
        reversed[#reversed + 1] = log[i]
    end

    for i, entry in ipairs(reversed) do
        local ef = _debugEntryFrames[i]
        if not ef then
            ef = CreateFrame("Frame", nil, _debugScrollContent)
            ef:SetHeight(DEBUG_ENTRY_HEIGHT)
            ef:SetPoint("TOPLEFT",  _debugScrollContent, "TOPLEFT",  0, -(i - 1) * DEBUG_ENTRY_HEIGHT)
            ef:SetPoint("TOPRIGHT", _debugScrollContent, "TOPRIGHT", 0, -(i - 1) * DEBUG_ENTRY_HEIGHT)

            local bg = ef:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.05, 0.05, 0.05, i % 2 == 0 and 0.4 or 0.15)

            local label = ef:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT",  ef, "TOPLEFT",  4, -2)
            label:SetPoint("TOPRIGHT", ef, "TOPRIGHT", -4, -2)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            ef._label = label

            _debugEntryFrames[i] = ef
        end
        ef._label:SetText(BuildDebugEntryText(entry))
        ef:Show()
    end

    -- Hide unused frames
    for i = #reversed + 1, #_debugEntryFrames do
        _debugEntryFrames[i]:Hide()
    end

    local totalH = math.max(#reversed * DEBUG_ENTRY_HEIGHT, 1)
    _debugScrollContent:SetHeight(totalH)
end

local function ShowErrorTab()
    _activeTab = "error"
    if _errorTabContent then _errorTabContent:Show() end
    if _debugTabContent  then _debugTabContent:Hide()  end
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "ConfigWindow: switched to Error Log tab")
    end
end

local function ShowDebugTab()
    _activeTab = "debug"
    if _errorTabContent then _errorTabContent:Hide() end
    if _debugTabContent  then _debugTabContent:Show()  end
    RebuildDebugList()
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "ConfigWindow: switched to Debug Log tab")
    end
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

    f.CloseButton:SetScript("OnClick", function()
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Info("CP", "ConfigWindow: closed via X button")
        end
        f:Hide()
    end)

    ---------------------------------------------------------------------------
    -- Tab buttons row
    ---------------------------------------------------------------------------
    local BTN_W, BTN_H = 110, 22

    local errorTabBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    errorTabBtn:SetSize(BTN_W, BTN_H)
    errorTabBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -34)
    errorTabBtn:SetText("Error Log")
    errorTabBtn:SetScript("OnClick", function()
        ShowErrorTab()
        RebuildErrorList()
        local log = (CouchPotatoDB and CouchPotatoDB.errorLog) or {}
        if f._errorCountFS then
            f._errorCountFS:SetText(#log .. " entr" .. (#log == 1 and "y" or "ies"))
        end
    end)

    local debugTabBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    debugTabBtn:SetSize(BTN_W, BTN_H)
    debugTabBtn:SetPoint("LEFT", errorTabBtn, "RIGHT", 4, 0)
    debugTabBtn:SetText("Debug Log")
    debugTabBtn:SetScript("OnClick", function()
        ShowDebugTab()
        local log = (CouchPotatoDB and CouchPotatoDB.debugLog) or {}
        if f._debugCountFS then
            f._debugCountFS:SetText(#log .. " entr" .. (#log == 1 and "y" or "ies"))
        end
    end)

    -- Entry count label (shared, repositioned below tabs)
    local errorCountFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    errorCountFS:SetPoint("LEFT", debugTabBtn, "RIGHT", 10, 0)
    f._errorCountFS = errorCountFS

    local debugCountFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    debugCountFS:SetPoint("LEFT", errorCountFS, "RIGHT", 4, 0)
    debugCountFS:Hide()
    f._debugCountFS = debugCountFS

    ---------------------------------------------------------------------------
    -- Action buttons (Export / Clear) — top-right corner
    ---------------------------------------------------------------------------
    local exportBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    exportBtn:SetSize(BTN_W, BTN_H)
    exportBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -34)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        if _activeTab == "debug" then
            local log = (CouchPotatoDB and CouchPotatoDB.debugLog) or {}
            ShowExport(log, true)
        else
            local log = (CouchPotatoDB and CouchPotatoDB.errorLog) or {}
            ShowExport(log, false)
        end
    end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(BTN_W, BTN_H)
    clearBtn:SetPoint("RIGHT", exportBtn, "LEFT", -6, 0)
    clearBtn:SetText("Clear Log")
    clearBtn:SetScript("OnClick", function()
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Info("CP", "ConfigWindow: clear clicked for tab=" .. _activeTab)
        end
        if _activeTab == "debug" then
            if CouchPotatoDB then CouchPotatoDB.debugLog = {} end
            RebuildDebugList()
            if f._debugCountFS then f._debugCountFS:SetText("0 entries") end
        else
            if CouchPotatoDB then CouchPotatoDB.errorLog = {} end
            RebuildErrorList()
            if f._errorCountFS then f._errorCountFS:SetText("0 entries") end
        end
    end)

    ---------------------------------------------------------------------------
    -- Separator
    ---------------------------------------------------------------------------
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -60)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -60)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)

    ---------------------------------------------------------------------------
    -- Error tab content panel
    ---------------------------------------------------------------------------
    local errorPanel = CreateFrame("Frame", nil, f)
    errorPanel:SetPoint("TOPLEFT",     f, "TOPLEFT",   0, -64)
    errorPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    _errorTabContent = errorPanel

    local scrollFrame = CreateFrame("ScrollFrame", nil, errorPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     errorPanel, "TOPLEFT",  16, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", errorPanel, "BOTTOMRIGHT", -32, 16)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(WINDOW_W - 60)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    _scrollContent = content

    ---------------------------------------------------------------------------
    -- Debug tab content panel
    ---------------------------------------------------------------------------
    local debugPanel = CreateFrame("Frame", nil, f)
    debugPanel:SetPoint("TOPLEFT",     f, "TOPLEFT",   0, -64)
    debugPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    debugPanel:Hide()
    _debugTabContent = debugPanel

    local debugScrollFrame = CreateFrame("ScrollFrame", nil, debugPanel, "UIPanelScrollFrameTemplate")
    debugScrollFrame:SetPoint("TOPLEFT",     debugPanel, "TOPLEFT",  16, -4)
    debugScrollFrame:SetPoint("BOTTOMRIGHT", debugPanel, "BOTTOMRIGHT", -32, 16)

    local debugContent = CreateFrame("Frame", nil, debugScrollFrame)
    debugContent:SetWidth(WINDOW_W - 60)
    debugContent:SetHeight(1)
    debugScrollFrame:SetScrollChild(debugContent)
    _debugScrollContent = debugContent

    ---------------------------------------------------------------------------
    -- OnShow: refresh list and count
    ---------------------------------------------------------------------------
    f:SetScript("OnShow", function(self)
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Info("CP", "ConfigWindow: opened")
        end
        if _activeTab == "debug" then
            RebuildDebugList()
            local log = (CouchPotatoDB and CouchPotatoDB.debugLog) or {}
            self._debugCountFS:SetText(#log .. " entr" .. (#log == 1 and "y" or "ies"))
        else
            RebuildErrorList()
            local log = (CouchPotatoDB and CouchPotatoDB.errorLog) or {}
            self._errorCountFS:SetText(#log .. " entr" .. (#log == 1 and "y" or "ies"))
        end
    end)

    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Info("CP", "ConfigWindow: frame created successfully")
    end

    _frame = f
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
CP.ConfigWindow = {
    Show = function()
        if not _frame then _build() end
        if _G.CouchPotatoLog then
            _G.CouchPotatoLog:Info("CP", "ConfigWindow: Show() called")
        end
        _frame:Show()
        _frame:Raise()
    end,
    Hide = function()
        if _frame then
            if _G.CouchPotatoLog then
                _G.CouchPotatoLog:Info("CP", "ConfigWindow: Hide() called")
            end
            _frame:Hide()
        end
    end,
    Toggle = function()
        if not _frame then _build() end
        if _frame:IsShown() then
            if _G.CouchPotatoLog then
                _G.CouchPotatoLog:Info("CP", "ConfigWindow: toggled closed")
            end
            _frame:Hide()
        else
            if _G.CouchPotatoLog then
                _G.CouchPotatoLog:Info("CP", "ConfigWindow: toggled open")
            end
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
    _RebuildDebugList = RebuildDebugList,
}
