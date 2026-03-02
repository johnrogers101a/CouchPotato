-- CouchPotato/UI/DiagnosticsWindow.lua
-- Scrollable output window for /cp test and /cp debug results.
--
-- Exposes:
--   CP.DiagnosticsWindow.Show(lines)
--       lines: table of strings (may still contain WoW color codes —
--              this module strips them before display).
--
-- The window contains a MultiLineEditBox inside a ScrollFrame so the
-- player can Ctrl+A, Ctrl+C to select and copy the full output.
--
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato

-------------------------------------------------------------------------------
-- Color-code stripper (same pattern used in Diagnostics.lua)
-------------------------------------------------------------------------------
local function stripColors(s)
    return s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

-------------------------------------------------------------------------------
-- Frame singleton — built on first Show() call
-------------------------------------------------------------------------------
local _frame   = nil
local _editBox = nil

local function _build()
    local f = CreateFrame("Frame", "CPDiagOutputFrame", UIParent,
                          "BasicFrameTemplateWithInset")
    f:SetSize(540, 440)
    -- Offset slightly from the config window so both can be open at once
    f:SetPoint("CENTER", UIParent, "CENTER", 60, -20)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- Register with UISpecialFrames so ESC closes it (taint-safe)
    tinsert(UISpecialFrames, "CPDiagOutputFrame")

    ---------------------------------------------------------------------------
    -- Title bar
    ---------------------------------------------------------------------------
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", f.TitleBg, "LEFT", 5, 0)
    title:SetText("Diagnostics Output")

    -- BasicFrameTemplateWithInset provides f.CloseButton
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)

    ---------------------------------------------------------------------------
    -- Copy-hint label just below the title bar
    ---------------------------------------------------------------------------
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -34)
    hint:SetText("|cffaaaaaa Ctrl+A  Ctrl+C  to copy|r")

    ---------------------------------------------------------------------------
    -- ScrollFrame (UIPanelScrollFrameTemplate ships a scrollbar for free)
    ---------------------------------------------------------------------------
    local sf = CreateFrame("ScrollFrame", "CPDiagOutputScrollFrame", f,
                           "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     12, -52)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)

    ---------------------------------------------------------------------------
    -- EditBox as the scroll child
    --   • SetMaxLetters(0)  — no limit on text length
    --   • SetAutoFocus(false) — never steals keyboard focus on show
    --   • Read-only feel: user can Ctrl+A / Ctrl+C but typing is not blocked
    --     (blocking input via SetEnabled(false) also disables selection/copy)
    ---------------------------------------------------------------------------
    local eb = CreateFrame("EditBox", "CPDiagOutputEditBox", sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(480)
    eb:SetMaxLetters(0)
    -- ESC key: first press clears focus; second press (or if no focus) closes
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)

    _frame   = f
    _editBox = eb
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
CP.DiagnosticsWindow = {
    ---Show the window populated with the given lines.
    ---@param lines table  array of strings (color codes will be stripped)
    Show = function(lines)
        if not _frame then _build() end

        -- Strip WoW color escape codes before display
        local plain = {}
        for i = 1, #lines do
            plain[i] = stripColors(tostring(lines[i]))
        end

        _editBox:SetText(table.concat(plain, "\n"))
        _editBox:SetCursorPosition(0)   -- scroll to top

        _frame:Show()
        _frame:Raise()
    end,
}
