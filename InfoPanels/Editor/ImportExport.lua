-- InfoPanels/Editor/ImportExport.lua
-- Import/export dialogs and external data entry (paste box).
-- Single Responsibility: Profile string import/export UI + external data entry.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local ImportExport = {}
ns.EditorImportExport = ImportExport

local _exportPopup = nil
local _importPopup = nil
local _externalDataPopup = nil

-------------------------------------------------------------------------------
-- ShowExport: Display an export dialog with the profile string.
-------------------------------------------------------------------------------
function ImportExport.ShowExport(profileString, shareText)
    if _exportPopup then _exportPopup:Hide() end

    local f = CreateFrame("Frame", "IPEditorExportPopup", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(520, 280)
    f:SetPoint("CENTER")
    f:SetFrameStrata("TOOLTIP")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", f.TitleBg, "LEFT", 5, 0)
    title:SetText("Export Panel")

    f.CloseButton:SetScript("OnClick", function() f:Hide() end)

    -- Share-friendly text (for Discord/forums)
    if shareText then
        local shareLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        shareLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -32)
        shareLabel:SetText("Share text (for Discord/forums):")
        shareLabel:SetTextColor(1, 0.82, 0, 1)

        local shareBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        shareBox:SetSize(480, 20)
        shareBox:SetPoint("TOPLEFT", shareLabel, "BOTTOMLEFT", 2, -2)
        shareBox:SetAutoFocus(false)
        shareBox:SetText(shareText or "")
        shareBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end

    -- Instructions
    local instr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instr:SetPoint("TOPLEFT", f, "TOPLEFT", 16, shareText and -72 or -32)
    instr:SetText("Import string — Select All (Ctrl+A) then Copy (Ctrl+C):")
    instr:SetTextColor(1, 0.82, 0, 1)

    -- Edit box with profile string
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", instr, "BOTTOMLEFT", -4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 32)

    local eb = CreateFrame("EditBox", nil, scrollFrame)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetWidth(460)
    eb:SetText(profileString or "")
    eb:HighlightText()
    eb:SetFocus()
    scrollFrame:SetScrollChild(eb)

    eb:SetScript("OnEscapePressed", function() f:Hide() end)

    -- Also write to debug log for copy access
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Print("IP", "Export string: " .. (profileString or ""))
    end

    tinsert(UISpecialFrames, "IPEditorExportPopup")
    _exportPopup = f
    f:Show()

    iplog("Info", "ImportExport: export dialog shown, string length=" .. #(profileString or ""))
end

-------------------------------------------------------------------------------
-- ShowImport: Display an import dialog with paste box.
-------------------------------------------------------------------------------
function ImportExport.ShowImport(onImportSuccess)
    if _importPopup then _importPopup:Hide() end

    local f = CreateFrame("Frame", "IPEditorImportPopup", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(520, 240)
    f:SetPoint("CENTER")
    f:SetFrameStrata("TOOLTIP")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", f.TitleBg, "LEFT", 5, 0)
    title:SetText("Import Panel")

    f.CloseButton:SetScript("OnClick", function() f:Hide() end)

    -- Instructions
    local instr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instr:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -32)
    instr:SetText("Paste an InfoPanels profile string below:")
    instr:SetTextColor(1, 0.82, 0, 1)

    -- Edit box for pasting
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 60)

    local eb = CreateFrame("EditBox", nil, scrollFrame)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetWidth(460)
    eb:SetText("")
    eb:SetFocus()
    scrollFrame:SetScrollChild(eb)

    eb:SetScript("OnEscapePressed", function() f:Hide() end)

    -- Status label
    local statusLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 36)

    -- Import button
    local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    importBtn:SetSize(100, 24)
    importBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        local text = eb:GetText()
        local ProfileCodec = ns.ProfileCodec
        if not ProfileCodec then
            statusLabel:SetText("|cffff4444ProfileCodec not loaded|r")
            return
        end

        local definition, err = ProfileCodec.Import(text)
        if not definition then
            statusLabel:SetText("|cffff4444" .. tostring(err) .. "|r")
            iplog("Warn", "ImportExport: import failed: " .. tostring(err))
            return
        end

        -- Save and instantiate
        local db = _G.InfoPanelsDB or {}
        db.userPanels = db.userPanels or {}
        db.userPanels[definition.id] = definition
        _G.InfoPanelsDB = db

        local PanelEngine = ns.PanelEngine
        if PanelEngine then
            if PanelEngine.GetPanel(definition.id) then
                PanelEngine.DestroyPanel(definition.id)
            end
            local panelDb = db.panels and db.panels[definition.id] or {}
            db.panels = db.panels or {}
            db.panels[definition.id] = panelDb
            PanelEngine.CreatePanel(definition, panelDb)
            PanelEngine.UpdatePanel(definition.id)
            PanelEngine.ShowPanel(definition.id)
        end

        statusLabel:SetText("|cff44ff44Imported: " .. (definition.title or definition.id) .. "|r")
        iplog("Info", "ImportExport: imported panel '" .. tostring(definition.title) .. "'")

        if onImportSuccess then onImportSuccess(definition) end
        f:Hide()
    end)

    tinsert(UISpecialFrames, "IPEditorImportPopup")
    _importPopup = f
    f:Show()
end

-------------------------------------------------------------------------------
-- ShowExternalDataEntry: Paste box for entering external/website data.
-- sourceId: the external data source to write to.
-------------------------------------------------------------------------------
function ImportExport.ShowExternalDataEntry(sourceId, sourceName)
    if _externalDataPopup then _externalDataPopup:Hide() end

    local f = CreateFrame("Frame", "IPEditorExtDataPopup", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(420, 200)
    f:SetPoint("CENTER")
    f:SetFrameStrata("TOOLTIP")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", f.TitleBg, "LEFT", 5, 0)
    title:SetText("Enter Data: " .. (sourceName or sourceId or ""))

    f.CloseButton:SetScript("OnClick", function() f:Hide() end)

    local instr = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    instr:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -32)
    instr:SetText("Paste data from a website or type a value:")

    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetSize(380, 80)
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -50)
    eb:SetFocus()
    eb:SetScript("OnEscapePressed", function() f:Hide() end)

    local statusLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 36)

    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 24)
    saveBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local text = eb:GetText()
        local DataSources = ns.DataSources
        if not DataSources then
            statusLabel:SetText("|cffff4444DataSources not loaded|r")
            return
        end
        local ok, err = DataSources.StoreExternal(sourceId, text)
        if ok then
            statusLabel:SetText("|cff44ff44Saved|r")
            iplog("Info", "ImportExport: stored external data for " .. tostring(sourceId))
            f:Hide()
        else
            statusLabel:SetText("|cffff4444" .. tostring(err) .. "|r")
        end
    end)

    tinsert(UISpecialFrames, "IPEditorExtDataPopup")
    _externalDataPopup = f
    f:Show()
end

return ImportExport
