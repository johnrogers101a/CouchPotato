-- CouchPotato_Loader/Loader.lua
-- Minimal always-on addon that detects gamepad input and dynamically loads CouchPotato
-- Patch 12.0.1 (Interface 120001)
-- Created: 2026-03-01

local ADDON_NAME = "CouchPotato_Loader"
local MAIN_ADDON = "CouchPotato"

-- Frame for event handling
local frame = CreateFrame("Frame")

-- State tracking
local isLoaded = false

-- SavedVariables (initialized in ADDON_LOADED)
CouchPotatoLoaderDB = CouchPotatoLoaderDB or {
    lastKnownState = false,
    autoLoad = true,
}

-- Load the main CouchPotato addon
local function LoadCouchPotato()
    -- Check if auto-load is disabled
    if not CouchPotatoLoaderDB.autoLoad then
        return
    end
    
    -- Already loaded?
    if C_AddOns.IsAddOnLoaded(MAIN_ADDON) then
        if CouchPotato then
            -- Signal it to activate
            CouchPotato:OnControllerActivated()
        end
        isLoaded = true
        return
    end
    
    -- Try to load
    local loaded, reason = C_AddOns.LoadAddOn(MAIN_ADDON)
    if not loaded then
        if reason == "DISABLED" then
            -- Enable it and try again
            C_AddOns.EnableAddOn(MAIN_ADDON)
            loaded, reason = C_AddOns.LoadAddOn(MAIN_ADDON)
        end
        
        if not loaded then
            print(string.format("|cffff6600CouchPotato:|r Failed to load: %s", reason or "Unknown"))
            return
        end
    end
    
    isLoaded = true
    print("|cffff6600CouchPotato:|r Controller detected - addon loaded.")
    CouchPotatoLoaderDB.lastKnownState = true

    -- Activate modules now that the addon is freshly loaded.
    -- OnControllerActivated enables all modules and applies bindings.
    -- (When the addon was already loaded we call this in the early-return branch above;
    --  here we mirror that call so both paths are identical.)
    if CouchPotato then
        CouchPotato:OnControllerActivated()
    end
end

-- Signal CouchPotato to restore keyboard UI
local function RestoreKeyboardMode()
    if C_AddOns.IsAddOnLoaded(MAIN_ADDON) and CouchPotato then
        CouchPotato:OnControllerDeactivated()
    end
    CouchPotatoLoaderDB.lastKnownState = false
end

-- Event: GAME_PAD_ACTIVE_CHANGED (Patch 9.1.5+)
-- Fires whenever WoW switches between gamepad/mouse/keyboard input modes —
-- including on every mouse move or keypress.  Only use it to *load* the addon;
-- never call RestoreKeyboardMode() here.  Real deactivation is handled by
-- GAME_PAD_DISCONNECTED (physical unplug) and CVAR_UPDATE (user disables it).
local function OnGamePadActiveChanged(isActive)
    if isActive then
        LoadCouchPotato()
    end
end

-- Event: GAME_PAD_CONNECTED
-- Physical connection detected
local function OnGamePadConnected(deviceID)
    -- Only load if GamePad is also enabled in settings
    if C_GamePad.IsEnabled() then
        LoadCouchPotato()
    end
end

-- Event: GAME_PAD_DISCONNECTED
-- Physical disconnection
local function OnGamePadDisconnected(deviceID)
    RestoreKeyboardMode()
end

-- Event: CVAR_UPDATE
-- Fallback for older clients or manual cvar changes
local function OnCVarUpdate(cvarName, cvarValue)
    if cvarName ~= "GamePadEnable" then return end
    
    if cvarValue == "1" then
        -- GamePad enabled
        LoadCouchPotato()
    elseif cvarValue == "0" then
        -- GamePad disabled
        RestoreKeyboardMode()
    end
end

-- Event: PLAYER_LOGIN
-- Check initial state on login
local function OnPlayerLogin()
    if C_GamePad.IsEnabled() then
        LoadCouchPotato()
    end
end

-- Event: ADDON_LOADED
-- Initialize SavedVariables
local function OnAddonLoaded(addonName)
    if addonName ~= ADDON_NAME then return end
    
    -- Ensure DB structure
    CouchPotatoLoaderDB = CouchPotatoLoaderDB or {}
    if CouchPotatoLoaderDB.autoLoad == nil then
        CouchPotatoLoaderDB.autoLoad = true
    end
    if CouchPotatoLoaderDB.lastKnownState == nil then
        CouchPotatoLoaderDB.lastKnownState = false
    end
    
    -- Check if controller is active at load time
    if C_GamePad.IsEnabled() then
        LoadCouchPotato()
    end
end

-- Event dispatcher
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "GAME_PAD_ACTIVE_CHANGED" then
        local isActive = ...
        OnGamePadActiveChanged(isActive)
    elseif event == "GAME_PAD_CONNECTED" then
        local deviceID = ...
        OnGamePadConnected(deviceID)
    elseif event == "GAME_PAD_DISCONNECTED" then
        local deviceID = ...
        OnGamePadDisconnected(deviceID)
    elseif event == "CVAR_UPDATE" then
        local cvarName, cvarValue = ...
        OnCVarUpdate(cvarName, cvarValue)
    elseif event == "PLAYER_LOGIN" then
        OnPlayerLogin()
    elseif event == "ADDON_LOADED" then
        local addonName = ...
        OnAddonLoaded(addonName)
    end
end)

-- Register events
frame:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
frame:RegisterEvent("GAME_PAD_CONNECTED")
frame:RegisterEvent("GAME_PAD_DISCONNECTED")
frame:RegisterEvent("CVAR_UPDATE")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")

-- Slash command: /cp  (always available — force-loads main addon if needed)
SLASH_CP1 = "/cp"
SLASH_CP2 = "/couchpotato"
SlashCmdList["CP"] = function(msg)
    msg = strtrim(strlower(msg or ""))

    -- Force-load the main addon regardless of controller state
    if not C_AddOns.IsAddOnLoaded(MAIN_ADDON) then
        C_AddOns.EnableAddOn(MAIN_ADDON)
        C_AddOns.LoadAddOn(MAIN_ADDON)
    end

    -- Delegate everything to the main addon's handler if it loaded
    if CouchPotato and CouchPotato.ChatCommand then
        -- Default: open config window
        if msg == "" then msg = "config" end
        CouchPotato:ChatCommand(msg)
    else
        print("|cffff6600CouchPotato:|r Failed to load main addon.")
    end
end

-- Slash command: /cpload
SLASH_CPLOAD1 = "/cpload"
SlashCmdList["CPLOAD"] = function(msg)
    msg = strtrim(strlower(msg or ""))
    
    if msg == "" then
        -- Manual load
        LoadCouchPotato()
    elseif msg == "auto" then
        -- Toggle auto-load
        CouchPotatoLoaderDB.autoLoad = not CouchPotatoLoaderDB.autoLoad
        print(string.format("|cffff6600CouchPotato:|r Auto-load %s", 
            CouchPotatoLoaderDB.autoLoad and "enabled" or "disabled"))
    elseif msg == "status" then
        -- Show status
        print("|cffff6600CouchPotato Loader:|r")
        print(string.format("  Controller active: %s", C_GamePad.IsEnabled() and "Yes" or "No"))
        print(string.format("  Main addon loaded: %s", C_AddOns.IsAddOnLoaded(MAIN_ADDON) and "Yes" or "No"))
        print(string.format("  Auto-load: %s", CouchPotatoLoaderDB.autoLoad and "Enabled" or "Disabled"))
    else
        print("|cffff6600CouchPotato Loader:|r Commands:")
        print("  /cpload - Manually load CouchPotato")
        print("  /cpload auto - Toggle auto-load on controller detection")
        print("  /cpload status - Show current status")
    end
end
