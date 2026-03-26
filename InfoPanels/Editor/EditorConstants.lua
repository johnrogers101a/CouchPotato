-- InfoPanels/Editor/EditorConstants.lua
-- Shared constants for the Editor UI.
-- Single Responsibility: Centralized configuration values.

local _, ns = ...
if not ns then ns = {} end

local EditorConstants = {}
ns.EditorConstants = EditorConstants

-- Frame dimensions
EditorConstants.FRAME_WIDTH = 960
EditorConstants.FRAME_HEIGHT = 580
EditorConstants.SIDEBAR_WIDTH = 200
EditorConstants.PREVIEW_WIDTH = 280
EditorConstants.PROPERTIES_HEIGHT = 180

-- Tab identifiers
EditorConstants.TAB_FUNCTIONS = 1
EditorConstants.TAB_PROPERTIES = 2
EditorConstants.TAB_VISIBILITY = 3

-- Search
EditorConstants.MAX_SEARCH_RESULTS = 500
EditorConstants.SEARCH_DEBOUNCE_SEC = 0.15

-- Virtual scroll row height
EditorConstants.ROW_HEIGHT = 22
EditorConstants.ICON_ROW_HEIGHT = 36

-- Texture categories for the browser
EditorConstants.TEXTURE_CATEGORIES = {
    { key = "icons",       label = "Icons" },
    { key = "backgrounds", label = "Backgrounds" },
    { key = "borders",     label = "Borders" },
    { key = "statusbars",  label = "Status Bars" },
    { key = "atlases",     label = "Atlas Textures" },
    { key = "custom",      label = "Custom (User)" },
}

-- Well-known built-in textures (curated subset for browsing)
EditorConstants.BUILTIN_TEXTURES = {
    backgrounds = {
        { path = "Interface\\DialogFrame\\UI-DialogBox-Background",       name = "Dialog Background" },
        { path = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",  name = "Dialog Dark" },
        { path = "Interface\\Tooltips\\UI-Tooltip-Background",            name = "Tooltip Background" },
        { path = "Interface\\FrameGeneral\\UI-Background-Marble",         name = "Marble" },
        { path = "Interface\\FrameGeneral\\UI-Background-Rock",           name = "Rock" },
        { path = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall", name = "Portrait Mask" },
    },
    borders = {
        { path = "Interface\\Tooltips\\UI-Tooltip-Border",     name = "Tooltip Border" },
        { path = "Interface\\DialogFrame\\UI-DialogBox-Border", name = "Dialog Border" },
    },
    statusbars = {
        { path = "Interface\\TargetingFrame\\UI-StatusBar",         name = "Default Status Bar" },
        { path = "Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill",          name = "Raid HP Fill" },
        { path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", name = "Skills Bar" },
    },
    icons = {
        { path = "Interface\\Icons\\INV_Misc_QuestionMark",   name = "Question Mark" },
        { path = "Interface\\Icons\\Achievement_Dungeon_GlsA", name = "Achievement" },
        { path = "Interface\\Icons\\Ability_Warrior_Charge",   name = "Charge" },
    },
    atlases = {
        { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Type", name = "Boss Portrait Gold" },
        { atlas = "talents-node-pvp",                                   name = "PvP Node" },
        { atlas = "Professions-Icon-Quality-Tier1-Small",               name = "Quality Tier 1" },
        { atlas = "Professions-Icon-Quality-Tier2-Small",               name = "Quality Tier 2" },
        { atlas = "Professions-Icon-Quality-Tier3-Small",               name = "Quality Tier 3" },
    },
}

-- Font options for properties panel
EditorConstants.FONT_OPTIONS = {
    { value = "GameFontNormalLarge",     label = "Large" },
    { value = "GameFontNormal",          label = "Normal" },
    { value = "GameFontHighlight",       label = "Highlight" },
    { value = "GameFontHighlightSmall",  label = "Small" },
    { value = "GameFontDisable",         label = "Disabled" },
}

-- Color presets
EditorConstants.COLOR_PRESETS = {
    { r = 1.0, g = 1.0,  b = 1.0,  label = "White" },
    { r = 1.0, g = 0.82, b = 0.0,  label = "Gold" },
    { r = 0.0, g = 1.0,  b = 0.0,  label = "Green" },
    { r = 1.0, g = 0.0,  b = 0.0,  label = "Red" },
    { r = 0.5, g = 0.5,  b = 1.0,  label = "Blue" },
    { r = 1.0, g = 0.5,  b = 0.0,  label = "Orange" },
    { r = 0.8, g = 0.8,  b = 0.8,  label = "Light Gray" },
    { r = 0.5, g = 0.5,  b = 0.5,  label = "Gray" },
}

return EditorConstants
