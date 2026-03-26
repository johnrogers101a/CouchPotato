-- LuaCheck configuration for ControllerCompanion
-- WoW Lua 5.1 environment
-- Note: spec/wow_mock.lua uses load() for Lua 5.3+ bit operators to stay lua51-clean

std = "lua51"

max_line_length = false

-- WoW globals that are always available in the game client
globals = {
    -- Core WoW
    "UIParent", "CreateFrame", "InCombatLockdown", "GetTime",
    "RegisterStateDriver", "UnregisterStateDriver",
    "SetOverrideBinding", "SetOverrideBindingSpell", "SetOverrideBindingItem",
    "SetOverrideBindingMacro", "SetOverrideBindingClick", "ClearOverrideBindings",
    "SetBinding", "SaveBindings", "GetBinding", "GetBindingAction",
    "CreateColor", "CreateColorFromHexString",
    "UIFrameFadeIn", "UIFrameFadeOut",
    "ReloadUI",

    -- Gamepad
    "SetGamePadCursorControl", "SetGamePadFreeLook",
    "IsGamePadCursorControlEnabled", "IsGamePadFreelookEnabled",

    -- Unit info
    "UnitName", "UnitClass", "UnitLevel", "UnitHealth", "UnitHealthMax",
    "UnitPower", "UnitPowerMax", "UnitPowerType", "UnitExists",
    "UnitIsEnemy", "UnitIsFriend", "UnitIsDead",
    "UnitCastingInfo", "UnitChannelInfo",
    "GetNumGroupMembers", "GetNumRaidMembers",

    -- Spells and items
    "GetSpellInfo", "GetItemInfo", "IsSpellKnown", "GetSpellTexture",
    "GetSpecialization", "GetSpecializationInfo",
    "C_Item",

    -- Gossip/Quest
    "C_GossipInfo", "C_QuestLog",

    -- Bags
    "C_Container",

    -- Mounts
    "C_MountJournal",

    -- Timer
    "C_Timer",

    -- Addons
    "C_AddOns",

    -- Gamepad namespace
    "C_GamePad",

    -- Spell namespace
    "C_Spell",

    -- UI globals
    "DEFAULT_CHAT_FRAME", "GameTooltip", "SlashCmdList",
    "RAID_CLASS_COLORS", "CUSTOM_CLASS_COLORS",
    "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall",
    "GameFontHighlightSmall", "GameFontHighlight",
    "ObjectiveTitleFont", "ObjectiveFont",
    "NumberFontNormal", "ChatFontNormal", "STANDARD_TEXT_FONT",
    "LootFrame", "CharacterFrame", "MainMenuBar",
    "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
    "PlayerFrame", "TargetFrame", "FocusFrame",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
    "CastingBarFrame", "PossessBarFrame", "OverrideActionBar",
    "WorldMapFrame", "HideUIPanel", "ShowUIPanel", "CloseAllWindows",

    -- UI utility
    "tinsert", "tremove", "wipe", "UISpecialFrames", "strtrim", "strlower",
    "strsplit", "strjoin", "date",

    -- Binding
    "SetBindingClick",

    -- Toggle functions
    "ToggleCharacter", "ToggleSpellBook", "ToggleTalentFrame",
    "ToggleQuestLog", "ToggleAchievementFrame", "ToggleAllBags",
    "ToggleCollectionsJournal", "ToggleFriendsFrame", "ToggleEncounterJournal",
    "ToggleGuildFrame", "TogglePVPUI", "ToggleStoreUI", "ToggleHelpFrame",
    "ToggleGameMenu", "ToggleProfessionsBook",
    "PVEFrame_ToggleFrame", "GameTimeCalendar_Toggle", "Screenshot",

    -- Time
    "time",

    -- Slash command globals (set by Loader.lua and addons)
    "SLASH_CP1", "SLASH_CP2", "SLASH_CPLOAD1",
    "SLASH_INFOPANELS1", "SLASH_INFOPANELS2",
    "SLASH_IPVALIDATE1", "SLASH_IPVALIDATE2",

    -- Ace3 (embedded)
    "LibStub",

    -- Delves
    "C_DelvesUI", "ChatFrame1", "C_Reputation", "IsInInstance",
    "ScenarioObjectiveTracker", "ObjectiveTrackerFrame",
    "C_MajorFactions", "C_CurrencyInfo", "C_PartyInfo",
    "QuestObjectiveTracker",

    -- Dropdown menus (legacy API)
    "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton", "UIDropDownMenu_SetSelectedValue",
    "UIDropDownMenu_SetWidth", "UIDropDownMenu_SetText",
    "MenuUtil",

    -- Combat rating
    "GetCombatRating",

    -- Stats
    "UnitStat", "GetHaste", "GetCritChance", "GetMasteryEffect",
    "GetCombatRatingBonus", "CR_VERSATILITY_DAMAGE_DONE",
    "GetNumSpecializations", "GetSpecializationInfoByID",
    "GetLootSpecialization",

    -- Unit Auras and Scenario APIs
    "C_UnitAuras", "C_ScenarioInfo", "UnitAura",

    -- Addon globals
    "ControllerCompanion", "ControllerCompanionDB", "ControllerCompanionLoaderDB",
    "InfoPanelsDB", "InfoPanelsNS", "StatPriorityData", "StatPriorityGetStatValue",
    "LibDeflate",

    -- bit library
    "bit",
}

-- Ignore common WoW addon patterns and formatting issues
ignore = {
    "211",  -- unused variable (common in WoW event handlers and imports)
    "212",  -- unused argument (common in WoW event handlers)
    "213",  -- unused loop variable
    "231",  -- variable never accessed
    "241",  -- variable mutated but never accessed
    "311",  -- value of variable not mutated
    "331",  -- value assigned to variable is mutated but never accessed
    "542",  -- empty if branch
    "432",  -- shadowing upvalue argument (common in WoW frame callbacks)
    "611",  -- line contains only whitespace
    "612",  -- line contains trailing whitespace
    "614",  -- trailing whitespace in comment
}

-- Per-file settings
files = {
    ["spec/**"] = {
        globals = { "_MockPlayer", "_SetCombatState", "_GetOverrideBindings", "_ResetBindings",
                    "_SetMockAura", "_ClearMockAuras", "_SetMockNemesis", "_ClearMockNemesis",
                    "_SetMockBoonTooltip", "_ClearMockBoonTooltip",
                    "StatPriorityData", "StatPriorityGetStatValue" },
        ignore = { "143" },  -- accessing undefined fields (busted assertions, table.unpack compat)
    }
}
