-- LuaCheck configuration for ControllerCompanion
-- WoW Lua 5.1 environment

std = "lua51"

-- WoW globals that are always available in the game client
globals = {
    -- Core WoW
    "UIParent", "CreateFrame", "InCombatLockdown", "GetTime",
    "RegisterStateDriver", "UnregisterStateDriver",
    "SetOverrideBinding", "SetOverrideBindingSpell", "SetOverrideBindingItem",
    "SetOverrideBindingMacro", "ClearOverrideBindings",
    "SetBinding", "SaveBindings", "GetBinding",
    "CreateColor", "CreateColorFromHexString",
    "UIFrameFadeIn", "UIFrameFadeOut",
    
    -- Gamepad
    "SetGamePadCursorControl", "SetGamePadFreeLook",
    "IsGamePadCursorControlEnabled", "IsGamePadFreelookEnabled",
    
    -- Unit info
    "UnitName", "UnitClass", "UnitLevel", "UnitHealth", "UnitHealthMax",
    "UnitPower", "UnitPowerMax", "UnitPowerType", "UnitExists",
    "UnitIsEnemy", "UnitIsFriend", "UnitIsDead",
    "GetNumGroupMembers", "GetNumRaidMembers",
    
    -- Spells and items
    "GetSpellInfo", "GetItemInfo", "IsSpellKnown", "GetSpellTexture",
    "GetSpecialization", "GetSpecializationInfo",
    
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
    "NumberFontNormal",
    "LootFrame", "CharacterFrame", "MainMenuBar",
    "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
    "PlayerFrame", "TargetFrame", "FocusFrame",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
    "CastingBarFrame", "PossessBarFrame", "OverrideActionBar",
    
    -- Ace3 (embedded)
    "LibStub",
    
    -- Addon globals
    "ControllerCompanion", "ControllerCompanionDB", "ControllerCompanionLoaderDB",
    
    -- bit library
    "bit",
}

-- Ignore some common WoW addon patterns
ignore = {
    "212",  -- unused variable (common in WoW event handlers)
    "213",  -- unused loop variable
}

-- Per-file settings
files = {
    ["spec/**"] = {
        globals = { "_MockPlayer", "_SetCombatState", "_GetOverrideBindings", "_ResetBindings" }
    }
}
