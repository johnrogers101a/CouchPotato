-- CouchPotato/UI/ConfigWindow.lua
-- Main configuration window — opened by  /cp  with no arguments.
--
-- Exposes:
--   CP.ConfigWindow.Show()   — open (builds frame on first call)
--   CP.ConfigWindow.Hide()   — close
--
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato

-------------------------------------------------------------------------------
-- Frame singleton — built once, reused forever
-------------------------------------------------------------------------------
local _frame = nil

local function _build()
    local f = CreateFrame("Frame", "CouchPotatoConfigFrame", UIParent,
                          "BasicFrameTemplateWithInset")
    f:SetSize(480, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- Register with UISpecialFrames so ESC closes it (taint-safe)
    tinsert(UISpecialFrames, "CouchPotatoConfigFrame")

    ---------------------------------------------------------------------------
    -- Title bar
    ---------------------------------------------------------------------------
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", f.TitleBg, "LEFT", 5, 0)
    title:SetText("CouchPotato v" .. CP.version)

    -- BasicFrameTemplateWithInset provides f.CloseButton
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)

    ---------------------------------------------------------------------------
    -- Status line (updated every time the window is shown)
    ---------------------------------------------------------------------------
    local statusFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFS:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -36)
    statusFS:SetText("Controller: —   Spec: —")
    f._statusFS = statusFS

    local function _refreshStatus()
        local ctrlText = CP:IsControllerActive()
            and "|cff00ff00Enabled|r"
            or  "|cffaaaaaaDisabled|r"
        local specText = "—"
        local Specs = CP:GetModule("Specs", true)
        if Specs then
            local layout = Specs:GetCurrentLayout()
            specText = (layout and layout.specName) or "Unknown"
        end
        statusFS:SetText(string.format("Controller: %s   Spec: %s",
            ctrlText, specText))
    end

    f:SetScript("OnShow", _refreshStatus)

    ---------------------------------------------------------------------------
    -- Thin separator line
    ---------------------------------------------------------------------------
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -54)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -54)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)

    ---------------------------------------------------------------------------
    -- Section header
    ---------------------------------------------------------------------------
    local diagHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    diagHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -68)
    diagHeader:SetText("Diagnostics")

    local diagNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    diagNote:SetPoint("TOPLEFT", diagHeader, "BOTTOMLEFT", 0, -4)
    diagNote:SetText("Output opens in a separate scrollable window you can copy from.")

    ---------------------------------------------------------------------------
    -- Buttons
    ---------------------------------------------------------------------------
    local BTN_W, BTN_H = 180, 26

    -- "Run Diagnostics"
    local runBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    runBtn:SetSize(BTN_W, BTN_H)
    runBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -104)
    runBtn:SetText("Run Diagnostics")
    runBtn:SetScript("OnClick", function()
        local Diag = CP:GetModule("Diagnostics", true)
        if Diag then
            local ok, err = pcall(function() Diag:RunTests() end)
            if not ok then CP:Print("|cffff4444ERROR|r " .. tostring(err)) end
        else
            CP:Print("Diagnostics module not loaded")
        end
    end)

    -- "Debug Dump"
    local dumpBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dumpBtn:SetSize(BTN_W, BTN_H)
    dumpBtn:SetPoint("TOPLEFT", runBtn, "BOTTOMLEFT", 0, -6)
    dumpBtn:SetText("Debug Dump")
    dumpBtn:SetScript("OnClick", function()
        local Diag = CP:GetModule("Diagnostics", true)
        if Diag then
            local ok, err = pcall(function() Diag:DumpDebug() end)
            if not ok then CP:Print("|cffff4444ERROR|r " .. tostring(err)) end
        else
            CP:Print("Diagnostics module not loaded")
        end
    end)

    ---------------------------------------------------------------------------
    -- Second separator
    ---------------------------------------------------------------------------
    local sep2 = f:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT",  dumpBtn, "BOTTOMLEFT",  -16, -10)
    sep2:SetPoint("TOPRIGHT", f,       "TOPRIGHT",     -16, 0)
    sep2:SetColorTexture(0.3, 0.3, 0.3, 0.6)

    ---------------------------------------------------------------------------
    -- Commands reference (quick-help inside the window)
    ---------------------------------------------------------------------------
    local cmdHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cmdHeader:SetPoint("TOPLEFT", sep2, "BOTTOMLEFT", 16, -10)
    cmdHeader:SetText("Slash Commands")

    local cmds = {
        "/cp            — open this window",
        "/cp show       — show radial UI",
        "/cp hide       — hide radial UI",
        "/cp status     — print addon status",
        "/cp test       — run diagnostics",
        "/cp debug      — dump binding/DB state",
        "/cp reset      — reset profile to defaults",
        "/cp reload     — reload UI",
        "/cp debugmode  — toggle verbose logging",
    }
    local cmdFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cmdFS:SetPoint("TOPLEFT", cmdHeader, "BOTTOMLEFT", 0, -4)
    cmdFS:SetJustifyH("LEFT")
    cmdFS:SetText(table.concat(cmds, "\n"))

    ---------------------------------------------------------------------------
    -- Footer
    ---------------------------------------------------------------------------
    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
    footer:SetText("CouchPotato v" .. CP.version)

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
}
