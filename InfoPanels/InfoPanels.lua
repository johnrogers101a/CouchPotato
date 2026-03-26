-- InfoPanels.lua
-- Main entry point for the InfoPanels addon.
-- Initializes the registry-based engine, registers built-in functions,
-- sets up slash commands, and integrates with CouchPotatoDB.addonStates.

local addonName, ns = ...
if not ns then
    addonName = "InfoPanels"
    ns = {}
end

_G.InfoPanelsNS = ns
ns.version = "2.0.0"

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local function ipprint(msg)
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Print("IP", msg)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff44ccffIP:|r " .. tostring(msg))
    else
        print("|cff44ccffIP:|r " .. tostring(msg))
    end
end

-------------------------------------------------------------------------------
-- Slash commands: /infopanels and /ip
-------------------------------------------------------------------------------
SLASH_INFOPANELS1 = "/infopanels"
SLASH_INFOPANELS2 = "/ip"
SlashCmdList["INFOPANELS"] = function(msg)
    local cmd = msg and msg:lower():match("^%s*(%S+)") or ""
    local rest = msg and msg:match("^%s*%S+%s+(.+)$") or ""
    iplog("Info", "Slash received, cmd='" .. cmd .. "' rest='" .. rest .. "'")

    if cmd == "editor" or cmd == "edit" then
        if ns.Editor then ns.Editor.Toggle() end
    elseif cmd == "show" then
        if rest ~= "" then
            if ns.PanelEngine then ns.PanelEngine.ShowPanel(rest) end
        else
            if ns.PanelEngine then
                for id in pairs(ns.PanelEngine.GetAllPanels()) do
                    ns.PanelEngine.ShowPanel(id)
                end
            end
        end
        ipprint("Panels shown")
    elseif cmd == "hide" then
        if rest ~= "" then
            if ns.PanelEngine then ns.PanelEngine.HidePanel(rest) end
        else
            if ns.PanelEngine then
                for id in pairs(ns.PanelEngine.GetAllPanels()) do
                    ns.PanelEngine.HidePanel(id)
                end
            end
        end
        ipprint("Panels hidden")
    elseif cmd == "toggle" then
        if rest ~= "" then
            if ns.PanelEngine then ns.PanelEngine.TogglePanel(rest) end
        else
            if ns.PanelEngine then
                for id in pairs(ns.PanelEngine.GetAllPanels()) do
                    ns.PanelEngine.TogglePanel(id)
                end
            end
        end
    elseif cmd == "reset" then
        if rest ~= "" then
            if ns.PanelEngine then ns.PanelEngine.ResetPanel(rest) end
        else
            if ns.PanelEngine then
                for id in pairs(ns.PanelEngine.GetAllPanels()) do
                    ns.PanelEngine.ResetPanel(id)
                end
            end
        end
        ipprint("Panel position(s) reset")
    elseif cmd == "export" then
        if rest ~= "" and ns.PanelEngine and ns.ProfileCodec then
            local panel = ns.PanelEngine.GetPanel(rest)
            if panel and panel.definition then
                local str, err = ns.ProfileCodec.Export(panel.definition)
                if str then
                    ns.Editor.ShowExportDialog(str)
                else
                    ipprint("Export failed: " .. tostring(err))
                end
            else
                ipprint("Panel not found: " .. rest)
            end
        else
            ipprint("Usage: /ip export <panel_id>")
        end
    elseif cmd == "import" then
        if ns.Editor then ns.Editor.ShowImportDialog() end
    elseif cmd == "list" then
        if ns.PanelEngine then
            ipprint("Active panels:")
            for id, panel in pairs(ns.PanelEngine.GetAllPanels()) do
                local title = panel.definition and panel.definition.title or id
                local shown = panel.frame and panel.frame:IsShown() and "visible" or "hidden"
                ipprint("  " .. id .. " (" .. title .. ") - " .. shown)
            end
        end
    elseif cmd == "functions" or cmd == "func" then
        if ns.Functions then
            ipprint("Registered functions:")
            local sorted = ns.Functions.GetAllSorted()
            for _, item in ipairs(sorted) do
                local cat = item.info.category or ""
                local bi = item.info.builtin and " [built-in]" or ""
                ipprint("  " .. item.name .. " (" .. cat .. ")" .. bi)
            end
        end
    elseif cmd == "test" or cmd == "validate" then
        if ns.InGameTests and ns.InGameTests.RunAll then
            ns.InGameTests.RunAll()
        elseif ns.APIValidation and ns.APIValidation.RunAll then
            ns.APIValidation.RunAll()
        else
            ipprint("Test module not loaded")
        end
    else
        ipprint("Info Panels v" .. ns.version)
        ipprint("Usage: /ip [editor|show|hide|toggle|reset|export|import|list|functions|test]")
        ipprint("  /ip editor - Open the panel editor")
        ipprint("  /ip show [id] - Show panel(s)")
        ipprint("  /ip hide [id] - Hide panel(s)")
        ipprint("  /ip toggle [id] - Toggle panel(s)")
        ipprint("  /ip reset [id] - Reset panel position(s)")
        ipprint("  /ip export <id> - Export panel as string")
        ipprint("  /ip import - Import panel from string")
        ipprint("  /ip list - List all panels")
        ipprint("  /ip functions - List all functions")
        ipprint("  /ip test - Run in-game tests")
    end
end

-------------------------------------------------------------------------------
-- Built-in panel definitions (pure data — no functions)
-------------------------------------------------------------------------------
local BUILTIN_PANELS = {}

local function collectBuiltinDefs()
    if ns.DelversJourneyPanel then
        BUILTIN_PANELS[#BUILTIN_PANELS + 1] = ns.DelversJourneyPanel.GetDefinition()
    end
    if ns.DelveCompanionStatsPanel then
        if ns.DelveCompanionStatsPanel.RegisterDataSources then
            ns.DelveCompanionStatsPanel.RegisterDataSources()
        end
        BUILTIN_PANELS[#BUILTIN_PANELS + 1] = ns.DelveCompanionStatsPanel.GetDefinition()
    end
    if ns.StatPriorityPanel then
        BUILTIN_PANELS[#BUILTIN_PANELS + 1] = ns.StatPriorityPanel.GetDefinition()
    end
end

-------------------------------------------------------------------------------
-- OnLoad: Initialize everything
-------------------------------------------------------------------------------
local function OnLoad()
    iplog("Info", "OnLoad: starting initialization")

    -- Initialize SavedVariables
    InfoPanelsDB = InfoPanelsDB or {}
    local db = InfoPanelsDB
    db.panels = db.panels or {}
    db.userPanels = db.userPanels or {}
    db.deletedBuiltins = db.deletedBuiltins or {}
    db.functions = db.functions or {}

    -- Migrate from legacy StatPriorityDB if present
    if _G.StatPriorityDB and not db.panels.stat_priority then
        db.panels.stat_priority = {
            pinned = _G.StatPriorityDB.pinned,
            position = _G.StatPriorityDB.position,
            collapsed = _G.StatPriorityDB.collapsed,
            specOverride = _G.StatPriorityDB.specOverride,
        }
    end

    if _G.DelversJourneyDB and not db.panels.delvers_journey then
        db.panels.delvers_journey = {
            pinned = _G.DelversJourneyDB.pinned,
            position = _G.DelversJourneyDB.position,
            collapsed = _G.DelversJourneyDB.collapsed,
        }
    end

    if _G.DelveCompanionStatsDB and not db.panels.delve_companion_stats then
        db.panels.delve_companion_stats = {
            pinned = _G.DelveCompanionStatsDB.pinned,
            position = _G.DelveCompanionStatsDB.position,
            collapsed = _G.DelveCompanionStatsDB.collapsed,
        }
    end

    -- Register built-in functions (replaces old DataSources)
    if ns.Functions then
        ns.Functions.RegisterBuiltInFunctions()
        ns.Functions.LoadUserFunctions()
    end

    -- Also register old DataSources for backward compat with built-in panels
    if ns.DataSources then
        ns.DataSources.RegisterBuiltInSources()
    end

    -- Collect built-in panel definitions
    collectBuiltinDefs()

    -- Create panels via the registry-based engine
    local PanelEngine = ns.PanelEngine
    if PanelEngine then
        -- Create built-in panels (skip deleted ones)
        for _, def in ipairs(BUILTIN_PANELS) do
            if not db.deletedBuiltins[def.id] then
                local panelDb = db.panels[def.id] or {}
                db.panels[def.id] = panelDb
                PanelEngine.CreatePanel(def, panelDb)

                if ns.StatPriorityPanel and def.id == "stat_priority" then
                    ns.StatPriorityPanel.RefreshDefinition(def)
                    local panel = PanelEngine.GetPanel(def.id)
                    if panel then
                        panel._refreshDefinition = ns.StatPriorityPanel.RefreshDefinition
                    end
                end

                PanelEngine.UpdatePanel(def.id)
            else
                iplog("Info", "OnLoad: skipping deleted built-in '" .. def.id .. "'")
            end
        end

        -- Restore user-defined panels
        for id, definition in pairs(db.userPanels) do
            local panelDb = db.panels[id] or {}
            db.panels[id] = panelDb
            PanelEngine.CreatePanel(definition, panelDb)
            PanelEngine.UpdatePanel(id)
        end

        PanelEngine.RebuildChain()
        iplog("Info", "OnLoad: final RebuildChain complete")
    end

    iplog("Info", "OnLoad complete — InfoPanels v" .. ns.version .. " ready")
    ipprint("Loaded v" .. ns.version)
end

-------------------------------------------------------------------------------
-- ADDON_LOADED handler
-------------------------------------------------------------------------------
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        iplog("Info", "ADDON_LOADED fired for: " .. tostring(arg1))
        self:UnregisterEvent("ADDON_LOADED")

        if _G.CouchPotatoDB and _G.CouchPotatoDB.addonStates and
           _G.CouchPotatoDB.addonStates.InfoPanels == false then
            iplog("Info", "InfoPanels disabled via /cp disable — skipping init")
            ns._cpDisabled = true
            return
        end

        OnLoad()
    end
end)
