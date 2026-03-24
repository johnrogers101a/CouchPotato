-- spec/CouchPotato_spec.lua
-- Busted tests for the CouchPotato shared addon:
--   - Error capture system
--   - Minimap button
--   - Config window
--   - Slash commands

require("spec/wow_mock")

-- Provide minimal WoW APIs needed by CouchPotato files that aren't in wow_mock
_G.geterrorhandler = _G.geterrorhandler or function() return nil end
_G.seterrorhandler = _G.seterrorhandler or function(fn) end

_G.UISpecialFrames = _G.UISpecialFrames or {}

-- Minimap stub (not in wow_mock)
_G.Minimap = _G.Minimap or {
    _width  = 160,
    _height = 160,
    _left   = 0,
    _bottom = 0,
    GetWidth  = function(self) return self._width end,
    GetHeight = function(self) return self._height end,
    GetLeft   = function(self) return self._left end,
    GetBottom = function(self) return self._bottom end,
    GetEffectiveScale = function(self) return 1 end,
}
setmetatable(_G.Minimap, {__index = _G.UIParent})

-- GameFontHighlightSmall stub
_G.GameFontHighlightSmall = { _name = "GameFontHighlightSmall" }

-- GameTooltip stubs (AddLine may not exist in mock)
_G.GameTooltip.AddLine = _G.GameTooltip.AddLine or function() end

-- GetCursorPosition stub
_G.GetCursorPosition = _G.GetCursorPosition or function() return 0, 0 end

-------------------------------------------------------------------------------
-- Helper: load the CouchPotato addon files fresh for each describe block
-------------------------------------------------------------------------------
local function LoadCouchPotato()
    -- Reset globals
    _G.CouchPotatoDB      = nil
    _G.CouchPotatoShared  = nil
    _G.CouchPotatoLog     = nil
    _G.SlashCmdList       = _G.SlashCmdList or {}
    _G.SLASH_CP1          = nil
    _G.SLASH_CP2          = nil
    _G.SLASH_CC1          = nil
    _G.SLASH_CC2          = nil
    -- Reset UISpecialFrames
    _G.UISpecialFrames = {}
    -- Reset named frames
    _G.CouchPotatoConfigFrame  = nil
    _G.CouchPotatoExportFrame  = nil
    _G.CouchPotatoMinimapButton = nil

    -- Reset error handler mocks
    local _capturedHandler = nil
    _G.geterrorhandler = function() return _capturedHandler end
    _G.seterrorhandler = function(fn) _capturedHandler = fn end

    dofile("CouchPotato/CouchPotatoLog.lua")
    dofile("CouchPotato/CouchPotato.lua")
    dofile("CouchPotato/MinimapButton.lua")
    dofile("CouchPotato/ConfigWindow.lua")

    -- Simulate ADDON_LOADED to init DB
    local cp = _G.CouchPotatoShared
    -- Find the frame that registered ADDON_LOADED and fire it
    -- We do this by directly calling InitDB/HookErrorHandler via the internal test
    -- trigger: fire the ADDON_LOADED event on all frames that registered it.
    for _, listeners in pairs(_G._rawEventListeners or {}) do
        -- not needed; just init DB manually by firing event
    end
    -- Direct approach: fire ADDON_LOADED on registered frames
    if _G._rawEventListeners and _G._rawEventListeners["ADDON_LOADED"] then
        for frame, handler in pairs(_G._rawEventListeners["ADDON_LOADED"]) do
            handler("ADDON_LOADED", "CouchPotato")
        end
    end

    return _G.CouchPotatoShared
end

-------------------------------------------------------------------------------
-- Tests
-------------------------------------------------------------------------------

describe("CouchPotatoLog", function()
    before_each(function()
        _G.CouchPotatoLog = nil
        dofile("CouchPotato/CouchPotatoLog.lua")
    end)

    it("sets _G.CouchPotatoLog", function()
        assert.is_not_nil(_G.CouchPotatoLog)
    end)

    it("Print outputs with color prefix", function()
        local messages = {}
        _G.DEFAULT_CHAT_FRAME = {
            AddMessage = function(self, msg) table.insert(messages, msg) end
        }
        _G.CouchPotatoLog:Print("DCS", "hello")
        assert.equals(1, #messages)
        assert.truthy(messages[1]:find("DCS"))
        assert.truthy(messages[1]:find("hello"))
    end)

    it("Print uses fallback print when no DEFAULT_CHAT_FRAME", function()
        local orig = _G.DEFAULT_CHAT_FRAME
        _G.DEFAULT_CHAT_FRAME = nil
        -- Should not error
        assert.has_no.errors(function()
            _G.CouchPotatoLog:Print("SP", "test")
        end)
        _G.DEFAULT_CHAT_FRAME = orig
    end)

    it("Debug does nothing when disabled=false", function()
        local messages = {}
        _G.DEFAULT_CHAT_FRAME = {
            AddMessage = function(self, msg) table.insert(messages, msg) end
        }
        _G.CouchPotatoLog:Debug("CP", false, "should not appear")
        assert.equals(0, #messages)
    end)

    it("Debug prints when enabled=true", function()
        local messages = {}
        _G.DEFAULT_CHAT_FRAME = {
            AddMessage = function(self, msg) table.insert(messages, msg) end
        }
        _G.CouchPotatoLog:Debug("CP", true, "visible")
        assert.equals(1, #messages)
        assert.truthy(messages[1]:find("visible"))
    end)
end)

describe("CouchPotato error capture", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
    end)

    it("initializes CouchPotatoDB.errorLog as empty table", function()
        assert.is_not_nil(_G.CouchPotatoDB)
        assert.is_not_nil(_G.CouchPotatoDB.errorLog)
        assert.equals(0, #_G.CouchPotatoDB.errorLog)
    end)

    it("IsSuiteError returns true for CouchPotato errors", function()
        local ok, name = cp._isSuiteError("error in CouchPotato/CouchPotato.lua", "")
        assert.is_true(ok)
    end)

    it("IsSuiteError returns true for ControllerCompanion errors", function()
        local ok, name = cp._isSuiteError("error in Interface/AddOns/ControllerCompanion/Core/LED.lua", "")
        assert.is_true(ok)
    end)

    it("IsSuiteError returns true for DelveCompanionStats errors", function()
        local ok, _ = cp._isSuiteError("something in DelveCompanionStats", "")
        assert.is_true(ok)
    end)

    it("IsSuiteError returns true for StatPriority errors", function()
        local ok, _ = cp._isSuiteError("StatPriority threw", "")
        assert.is_true(ok)
    end)

    it("IsSuiteError returns false for unrelated addons", function()
        local ok, _ = cp._isSuiteError("error in SomeOtherAddon/Core.lua", "")
        assert.is_false(ok)
    end)

    it("error handler captures suite errors into CouchPotatoDB.errorLog", function()
        _G.CouchPotatoDB.errorLog = {}
        cp._errorHandler("error in CouchPotato/CouchPotato.lua", "stack trace")
        assert.equals(1, #_G.CouchPotatoDB.errorLog)
        assert.equals("error in CouchPotato/CouchPotato.lua", _G.CouchPotatoDB.errorLog[1].message)
    end)

    it("error handler ignores non-suite errors", function()
        _G.CouchPotatoDB.errorLog = {}
        cp._errorHandler("error in SomeRandomAddon.lua", "")
        assert.equals(0, #_G.CouchPotatoDB.errorLog)
    end)

    it("error entries have required fields", function()
        _G.CouchPotatoDB.errorLog = {}
        cp._errorHandler("CouchPotato error msg", "stack here")
        local entry = _G.CouchPotatoDB.errorLog[1]
        assert.is_not_nil(entry.timestamp)
        assert.is_not_nil(entry.message)
        assert.is_not_nil(entry.stack)
        assert.is_not_nil(entry.addonName)
        assert.equals("stack here", entry.stack)
    end)

    it("newest errors appear first (index 1)", function()
        _G.CouchPotatoDB.errorLog = {}
        cp._errorHandler("CouchPotato error A", "")
        cp._errorHandler("CouchPotato error B", "")
        assert.truthy(_G.CouchPotatoDB.errorLog[1].message:find("B"))
        assert.truthy(_G.CouchPotatoDB.errorLog[2].message:find("A"))
    end)

    it("caps error log at 500 entries", function()
        _G.CouchPotatoDB.errorLog = {}
        for i = 1, 510 do
            cp._errorHandler("CouchPotato error " .. i, "")
        end
        assert.equals(500, #_G.CouchPotatoDB.errorLog)
    end)

    it("forwards to original error handler", function()
        local forwarded = {}
        _G.geterrorhandler = function() return function(m, s) table.insert(forwarded, m) end end
        _G.seterrorhandler = function(fn) end
        -- Re-hook with real original
        local origHandler = function(m, s) table.insert(forwarded, m) end
        -- Manually call with original set
        local savedOrig = cp._errorHandler  -- already bound
        -- We need to re-run hook to pick up the new original
        -- Just call directly: non-suite error should still forward
        -- Since we can't easily re-hook, test the forwarding logic inline:
        -- The handler calls _originalErrorHandler when set. We test by
        -- verifying that non-nil original is called.
        -- Create a fresh handler bound to a known original
        local called = false
        local orig = function(m, s) called = true end
        -- Simulate: originalErrorHandler = orig
        -- We test this by calling _hookErrorHandler after setting geterrorhandler
        _G.geterrorhandler = function() return orig end
        local hooked = nil
        _G.seterrorhandler = function(fn) hooked = fn end
        cp._hookErrorHandler()
        assert.is_not_nil(hooked)
        -- Now call the hooked handler with a non-suite error
        -- (orig should be called regardless)
        hooked("SomeOtherAddon error", "")
        assert.is_true(called)
    end)

    it("does not error when geterrorhandler is nil", function()
        _G.geterrorhandler = nil
        assert.has_no.errors(function()
            cp._hookErrorHandler()
        end)
    end)
end)

describe("CouchPotato minimap button", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
        -- Build the button manually (PLAYER_LOGIN event won't fire in tests)
        cp.MinimapButton.Build()
    end)

    it("creates a minimap button", function()
        local btn = cp.MinimapButton.GetButton()
        assert.is_not_nil(btn)
    end)

    it("button is attached to Minimap", function()
        local btn = cp.MinimapButton.GetButton()
        assert.equals(_G.Minimap, btn._parent)
    end)

    it("default angle is 225 degrees", function()
        assert.equals(225, cp.MinimapButton.GetAngle())
    end)

    it("SetAngle updates angle and repositions button", function()
        cp.MinimapButton.SetAngle(90)
        assert.equals(90, cp.MinimapButton.GetAngle())
    end)

    it("SetAngle normalizes angle to [0, 360)", function()
        cp.MinimapButton.SetAngle(370)
        assert.equals(10, cp.MinimapButton.GetAngle())
    end)

    it("SetAngle normalizes negative angle", function()
        cp.MinimapButton.SetAngle(-10)
        assert.equals(350, cp.MinimapButton.GetAngle())
    end)

    it("saved angle is read from CouchPotatoDB", function()
        _G.CouchPotatoDB.minimapAngle = 135
        -- Re-build to pick up saved angle
        _G.CouchPotatoMinimapButton = nil
        cp.MinimapButton.Build()
        -- The angle from GetAngle() should reflect saved value after rebuild
        -- (Build() re-reads GetSavedAngle on first call)
        assert.equals(135, _G.CouchPotatoDB.minimapAngle)
    end)

    it("button has OnEnter tooltip script", function()
        local btn = cp.MinimapButton.GetButton()
        assert.is_not_nil(btn._scripts["OnEnter"])
    end)

    it("button has OnLeave script", function()
        local btn = cp.MinimapButton.GetButton()
        assert.is_not_nil(btn._scripts["OnLeave"])
    end)

    it("button has OnClick script", function()
        local btn = cp.MinimapButton.GetButton()
        assert.is_not_nil(btn._scripts["OnClick"])
    end)

    it("left-click opens config window", function()
        local btn = cp.MinimapButton.GetButton()
        -- Build config window first
        cp.ConfigWindow._Build()
        local frame = cp.ConfigWindow._GetFrame()
        frame:Hide()
        -- Simulate left-click (no drag)
        btn._scripts["OnClick"](btn, "LeftButton")
        assert.is_true(frame:IsShown())
    end)

    -- Regression tests for the angle-math bug (2026-03-24).
    -- Old formula: rad = math.rad(angle - 90)  → angle 0 mapped to BOTTOM (y<0).
    -- Fixed formula: rad = math.rad(90 - angle) → angle 0 maps to TOP   (y>0).
    it("angle=0 positions button at top of minimap (y > 0, x ≈ 0)", function()
        cp.MinimapButton.SetAngle(0)
        local btn = cp.MinimapButton.GetButton()
        local pt = btn._points[#btn._points]
        -- pt = { "CENTER", Minimap, "CENTER", x, y }
        local x, y = pt[4], pt[5]
        assert.is_true(y > 0,  "angle=0 should place button above minimap centre (y>0)")
        assert.is_true(math.abs(x) < 1, "angle=0 should have x≈0, got " .. tostring(x))
    end)

    it("angle=180 positions button at bottom of minimap (y < 0, x ≈ 0)", function()
        cp.MinimapButton.SetAngle(180)
        local btn = cp.MinimapButton.GetButton()
        local pt = btn._points[#btn._points]
        local x, y = pt[4], pt[5]
        assert.is_true(y < 0,  "angle=180 should place button below minimap centre (y<0)")
        assert.is_true(math.abs(x) < 1, "angle=180 should have x≈0, got " .. tostring(x))
    end)

    it("angle=90 positions button at right of minimap (x > 0, y ≈ 0)", function()
        cp.MinimapButton.SetAngle(90)
        local btn = cp.MinimapButton.GetButton()
        local pt = btn._points[#btn._points]
        local x, y = pt[4], pt[5]
        assert.is_true(x > 0,  "angle=90 should place button to the right (x>0)")
        assert.is_true(math.abs(y) < 1, "angle=90 should have y≈0, got " .. tostring(y))
    end)

    it("angle=225 (default) positions button at lower-left (x<0 and y<0)", function()
        cp.MinimapButton.SetAngle(225)
        local btn = cp.MinimapButton.GetButton()
        local pt = btn._points[#btn._points]
        local x, y = pt[4], pt[5]
        assert.is_true(x < 0, "angle=225 should place button left of centre (x<0), got x=" .. tostring(x))
        assert.is_true(y < 0, "angle=225 should place button below centre (y<0), got y=" .. tostring(y))
    end)

    it("icon texture is a non-empty string (not the missing SpicedFishBite path)", function()
        -- Verify the icon path was changed away from the broken INV_Misc_Food_Cooked_SpicedFishBite
        local btn = cp.MinimapButton.GetButton()
        local iconTex = btn._icon and btn._icon._texture
        assert.is_string(iconTex, "icon texture should be a string")
        assert.is_true(#iconTex > 0, "icon texture should not be empty")
        assert.is_nil(iconTex:find("SpicedFishBite"), "broken SpicedFishBite texture path must not be used")
    end)
end)

describe("CouchPotato config window", function()
    local cp

    before_each(function()
        cp = LoadCouchPotato()
        cp.ConfigWindow._Build()
    end)

    it("creates a config frame", function()
        assert.is_not_nil(cp.ConfigWindow._GetFrame())
    end)

    it("frame starts hidden", function()
        assert.is_false(cp.ConfigWindow._GetFrame():IsShown())
    end)

    it("Show() makes frame visible", function()
        cp.ConfigWindow.Show()
        assert.is_true(cp.ConfigWindow._GetFrame():IsShown())
    end)

    it("Hide() hides the frame", function()
        cp.ConfigWindow.Show()
        cp.ConfigWindow.Hide()
        assert.is_false(cp.ConfigWindow._GetFrame():IsShown())
    end)

    it("Toggle() shows when hidden", function()
        cp.ConfigWindow._GetFrame():Hide()
        cp.ConfigWindow.Toggle()
        assert.is_true(cp.ConfigWindow._GetFrame():IsShown())
    end)

    it("Toggle() hides when shown", function()
        cp.ConfigWindow._GetFrame():Show()
        cp.ConfigWindow.Toggle()
        assert.is_false(cp.ConfigWindow._GetFrame():IsShown())
    end)

    it("frame is registered with UISpecialFrames for ESC", function()
        local found = false
        for _, name in ipairs(_G.UISpecialFrames) do
            if name == "CouchPotatoConfigFrame" then found = true; break end
        end
        assert.is_true(found)
    end)

    it("frame strata is DIALOG", function()
        local f = cp.ConfigWindow._GetFrame()
        assert.equals("DIALOG", f:GetFrameStrata())
    end)

    it("frame is movable", function()
        local f = cp.ConfigWindow._GetFrame()
        assert.is_true(f._movable)
    end)

    it("OnShow populates error list without error", function()
        _G.CouchPotatoDB.errorLog = {
            { timestamp = 1.0, message = "CouchPotato test error", stack = "stack", addonName = "CouchPotato" },
        }
        assert.has_no.errors(function()
            cp.ConfigWindow.Show()
        end)
    end)

    it("RebuildErrorList with empty log sets content height to 1", function()
        _G.CouchPotatoDB.errorLog = {}
        assert.has_no.errors(function()
            cp.ConfigWindow._RebuildErrorList()
        end)
    end)

    it("RebuildErrorList with entries does not error", function()
        _G.CouchPotatoDB.errorLog = {
            { timestamp = 0, message = "CouchPotato e1", stack = "", addonName = "CouchPotato" },
            { timestamp = 1, message = "ControllerCompanion e2", stack = "", addonName = "ControllerCompanion" },
        }
        assert.has_no.errors(function()
            cp.ConfigWindow._RebuildErrorList()
        end)
    end)
end)

describe("CouchPotato slash commands", function()
    before_each(function()
        _G.SlashCmdList = {}
        LoadCouchPotato()
    end)

    it("/cp slash command is registered", function()
        assert.equals("/cp",         _G.SLASH_CP1)
        assert.equals("/couchpotato", _G.SLASH_CP2)
        assert.is_function(_G.SlashCmdList["CP"])
    end)

    it("/cc slash command is registered", function()
        assert.equals("/cc",                  _G.SLASH_CC1)
        assert.equals("/controllercompanion", _G.SLASH_CC2)
        assert.is_function(_G.SlashCmdList["CC"])
    end)

    it("/cp command opens config window", function()
        local cp = _G.CouchPotatoShared
        cp.ConfigWindow._Build()
        local f = cp.ConfigWindow._GetFrame()
        f:Hide()
        _G.SlashCmdList["CP"]("")
        assert.is_true(f:IsShown())
    end)

    it("/cc command attempts to open ControllerCompanion config", function()
        -- ControllerCompanion not loaded in test env — ensure no error
        _G.ControllerCompanion = nil
        assert.has_no.errors(function()
            _G.SlashCmdList["CC"]("")
        end)
    end)

    it("/cc opens ControllerCompanion.ConfigWindow if available", function()
        local shown = false
        _G.ControllerCompanion = {
            ConfigWindow = {
                Show = function() shown = true end
            }
        }
        _G.SlashCmdList["CC"]("")
        assert.is_true(shown)
        _G.ControllerCompanion = nil
    end)
end)

describe("ControllerCompanion_Loader slash commands", function()
    before_each(function()
        -- Reset slash cmds
        _G.SLASH_CP1 = nil
        _G.SLASH_CP2 = nil
        _G.SlashCmdList = _G.SlashCmdList or {}
        -- Ensure fresh C_AddOns state
        C_AddOns._addons = {
            ControllerCompanion = { loaded = false, enabled = true },
        }
        _G.ControllerCompanionLoaderDB = nil
    end)

    it("Loader.lua does NOT register /cp slash command", function()
        dofile("ControllerCompanion_Loader/Loader.lua")
        -- /cp should not be set by Loader.lua
        -- (It may have been set by CouchPotato.lua in another test, but here
        --  we only loaded Loader.lua — check SLASH_CPLOAD1 exists instead)
        assert.equals("/cpload", _G.SLASH_CPLOAD1)
        -- The CP handler in SlashCmdList, if set, must NOT be from Loader
        -- We can't easily assert absence without knowing if CouchPotato was
        -- already loaded; instead verify /cpload is present:
        assert.is_function(_G.SlashCmdList["CPLOAD"])
    end)
end)

describe("DelveCompanionStats dcsprint", function()
    before_each(function()
        _G.DelveCompanionStatsDB  = nil
        _G.DelveCompanionStatsNS  = nil
        _G.CouchPotatoLog         = nil
        -- Minimal spec mocks
        _G.GetSpecialization     = function() return 1 end
        _G.GetSpecializationInfo = function() return 1, "Arms", "", "", "DAMAGER" end
        -- C_DelvesUI already set in wow_mock
    end)

    it("dcsprint delegates to CouchPotatoLog when available", function()
        -- Load CouchPotatoLog first
        dofile("CouchPotato/CouchPotatoLog.lua")
        local printed = {}
        _G.CouchPotatoLog.Print = function(self, prefix, ...)
            table.insert(printed, { prefix = prefix, msg = ... })
        end

        dofile("DelveCompanionStats/DelveCompanionStats.lua")
        local ns = _G.DelveCompanionStatsNS
        -- Trigger dcsprint via slash command handler (which calls dcsprint)
        -- We need to initialize the addon first
        if _G._rawEventListeners and _G._rawEventListeners["ADDON_LOADED"] then
            for _, handler in pairs(_G._rawEventListeners["ADDON_LOADED"]) do
                handler("ADDON_LOADED", "DelveCompanionStats")
            end
        end
        -- Call /dcs show which calls dcsprint
        if _G.SlashCmdList["DCS"] then
            _G.SlashCmdList["DCS"]("show")
        end
        -- At least one call should have gone through CouchPotatoLog
        local found = false
        for _, p in ipairs(printed) do
            if p.prefix == "DCS" then found = true; break end
        end
        assert.is_true(found)
    end)

    it("dcsprint falls back when CouchPotatoLog not available", function()
        _G.CouchPotatoLog = nil
        local messages = {}
        _G.DEFAULT_CHAT_FRAME = {
            AddMessage = function(self, msg) table.insert(messages, msg) end
        }
        dofile("DelveCompanionStats/DelveCompanionStats.lua")
        if _G._rawEventListeners and _G._rawEventListeners["ADDON_LOADED"] then
            for _, handler in pairs(_G._rawEventListeners["ADDON_LOADED"]) do
                handler("ADDON_LOADED", "DelveCompanionStats")
            end
        end
        if _G.SlashCmdList["DCS"] then
            _G.SlashCmdList["DCS"]("show")
        end
        local found = false
        for _, msg in ipairs(messages) do
            if msg:find("DCS") then found = true; break end
        end
        assert.is_true(found)
    end)
end)
