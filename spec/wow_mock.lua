-- spec/wow_mock.lua
-- Comprehensive WoW API mock layer for Busted tests
-- Simulates WoW's global environment outside the game client
-- Interface: 120001 (Patch 12.0.1 Midnight)

-- ChatFrame1 stub (used by DelveCompanionStats for position anchor)
_G.ChatFrame1 = {
    _type = "Frame",
    GetPoint = function() return "BOTTOMLEFT", nil, "BOTTOMLEFT", 0, 0 end,
}
setmetatable(_G.ChatFrame1, {__index = _G.UIParent})

-- IsInInstance mock (mutable for tests)
_G._isInInstanceType = "none"   -- default: not in any instance
_G.IsInInstance = function()
    return nil, _G._isInInstanceType
end

-- C_DelvesUI stub (used by DelveCompanionStats to fetch active companion)
_G.C_DelvesUI = {
    GetActiveCompanion = function() return nil end,
    GetFactionForCompanion = function() return 2744 end,
    GetCompanionInfoForActivePlayer = function() return nil end,
    HasActiveDelve = function() return C_DelvesUI._hasActiveDelve or false end,
    _hasActiveDelve = false,
    _SetHasActiveDelve = function(val) C_DelvesUI._hasActiveDelve = val end,
}

-- Core UI frames
_G.UIParent = {
    _type = "Frame",
    SetAllPoints = function() end,
    Show = function() end,
    Hide = function() end,
}

_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

-- WoW string utility globals
_G.strlower  = function(s) return (s or ""):lower() end
_G.strupper  = function(s) return (s or ""):upper() end
_G.strtrim   = function(s) return (s or ""):match("^%s*(.-)%s*$") end
_G.strfind   = string.find
_G.strsub    = string.sub
_G.strlen    = string.len

-- WoW table utility globals (aliases for standard Lua table functions)
_G.tinsert   = table.insert
_G.tremove   = table.remove
_G.tContains = function(t, value)
    for _, v in ipairs(t) do if v == value then return true end end
    return false
end
_G.wipe      = function(t) for k in pairs(t) do t[k] = nil end return t end

_G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(self, msg, r, g, b)
        print(msg)
    end
}

local _tooltipNumLines = 0

_G.GameTooltip = {
    SetOwner     = function() end,
    SetSpellByID = function() end,
    SetItemByID  = function() end,
    Show         = function() end,
    Hide         = function() end,
    NumLines     = function() return _tooltipNumLines end,
}

-- GameTooltipTextLeft1..8: FontString stubs read by GetBoonsDisplayText()
for i = 1, 8 do
    _G["GameTooltipTextLeft" .. i] = {
        _text = "",
        GetText = function(self)
            if self._text and self._text ~= "" then return self._text end
            return nil
        end,
    }
end

-- Test helper: populate mock tooltip lines (used for boon tests)
_G._SetMockBoonTooltip = function(lines)
    _tooltipNumLines = #lines
    for i = 1, 8 do
        _G["GameTooltipTextLeft" .. i]._text = lines[i] or ""
    end
end

-- Test helper: clear mock tooltip (called in before_each / after_each)
_G._ClearMockBoonTooltip = function()
    _tooltipNumLines = 0
    for i = 1, 8 do
        _G["GameTooltipTextLeft" .. i]._text = ""
    end
end

-- CreateFrame - returns a FUNCTIONAL frame mock
local function createMockFrame(frameType, name, parent, template)
    local frame = {
        _type = frameType or "Frame",
        _name = name,
        _parent = parent,
        _template = template,
        _scripts = {},
        _events = {},
        _attributes = {},
        _shown = true,
        _alpha = 1.0,
        _width = 0,
        _height = 0,
        _textures = {},
        _fontstrings = {},
    }
    
    function frame:SetSize(w, h) self._width = w; self._height = h end
    function frame:SetHeight(h) self._height = h end
    function frame:GetWidth() return self._width end
    function frame:GetHeight() return self._height end
    function frame:SetPoint(...) end
    function frame:ClearAllPoints() end
    function frame:SetAllPoints(other) end
    function frame:SetParent(p) self._parent = p end
    function frame:GetParent() return self._parent end
    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown end
    function frame:IsVisible() return self._shown end
    function frame:SetAlpha(a) self._alpha = a end
    function frame:GetAlpha() return self._alpha end
    function frame:SetScale(s) self._scale = s end
    function frame:GetScale() return self._scale or 1.0 end
    function frame:SetFrameStrata(s) self._strata = s end
    function frame:GetFrameStrata() return self._strata or "MEDIUM" end
    function frame:SetFrameLevel(l) self._level = l end
    function frame:GetFrameLevel() return self._level or 0 end
    function frame:GetSize() return self._width, self._height end
    function frame:EnableGamePadButton(e) self._gpEnabled = e end
    function frame:EnableGamePadStick(e) self._stickEnabled = e end
    function frame:SetPropagateKeyboardInput(p) self._propagateKeyboard = p end
    function frame:RegisterForClicks(...) end
    function frame:GetName() return self._name end
    function frame:SetBackdrop(backdrop) self._backdrop = backdrop end
    function frame:SetBackdropColor(r,g,b,a) self._backdropColor = {r,g,b,a} end
    function frame:SetBackdropBorderColor(r,g,b,a) self._backdropBorderColor = {r,g,b,a} end
    function frame:SetMovable(v) self._movable = v end
    function frame:EnableMouse(v) self._mouseEnabled = v end
    function frame:RegisterForDrag(...) end
    function frame:GetPoint(index)
        return "BOTTOMLEFT", nil, "BOTTOMLEFT", 0, 0
    end
    
    function frame:SetScript(event, fn)
        self._scripts[event] = fn
    end
    function frame:GetScript(event)
        return self._scripts[event]
    end
    
    function frame:SetAttribute(key, value)
        self._attributes[key] = value
    end
    function frame:GetAttribute(key)
        return self._attributes[key]
    end
    
    function frame:RegisterEvent(event)
        self._events[event] = true
        -- Track raw event listeners for helper.fireEvent
        _G._rawEventListeners = _G._rawEventListeners or {}
        _G._rawEventListeners[event] = _G._rawEventListeners[event] or {}
        _G._rawEventListeners[event][frame] = function(...)
            local handler = frame._scripts["OnEvent"]
            if handler then handler(frame, ...) end
        end
    end
    function frame:UnregisterEvent(event)
        self._events[event] = nil
        if _G._rawEventListeners and _G._rawEventListeners[event] then
            _G._rawEventListeners[event][frame] = nil
        end
    end
    function frame:UnregisterAllEvents()
        for event in pairs(self._events) do
            self:UnregisterEvent(event)
        end
        self._events = {}
    end
    function frame:IsEventRegistered(event)
        return self._events[event] == true
    end
    
    function frame:CreateTexture(name, layer)
        local tex = {
            _shown = true,
            _texture = nil,
            _color = {1,1,1,1},
        }
        function tex:SetAllPoints(anchor) end
        function tex:SetPoint(...) end
        function tex:SetSize(w, h) self._width = w; self._height = h end
        function tex:SetHeight(h) self._height = h end
        function tex:GetWidth() return self._width or 0 end
        function tex:SetTexture(t) self._texture = t; return t ~= nil end
        function tex:GetTexture() return self._texture end
        function tex:SetColorTexture(r,g,b,a) self._color = {r,g,b,a} end
        function tex:SetVertexColor(r,g,b,a) end
        function tex:SetBlendMode(m) end
        function tex:SetAlpha(a) end
        function tex:Show() self._shown = true end
        function tex:Hide() self._shown = false end
        function tex:IsShown() return self._shown end
        table.insert(frame._textures, tex)
        return tex
    end
    
    function frame:CreateFontString(name, layer, font)
        local fs = {
            _text = "",
            _shown = true,
        }
        function fs:SetPoint(...) end
        function fs:SetText(t) self._text = t end
        function fs:GetText() return self._text end
        function fs:SetTextColor(r,g,b,a) self._r = r; self._g = g; self._b = b; self._a = a end
        function fs:GetTextColor() return self._r or 1, self._g or 1, self._b or 1, self._a or 1 end
        function fs:SetFont(font, size, flags) self._fontPath = font; self._fontSize = size; self._fontFlags = flags end
        function fs:GetFont() return self._fontPath or "GameFontNormal", self._fontSize or 12, self._fontFlags or "" end
        function fs:SetWidth(w) self._width = w end
        function fs:SetJustifyH(j) end
        function fs:Show() self._shown = true end
        function fs:Hide() self._shown = false end
        function fs:IsShown() return self._shown end
        function fs:SetShadowOffset(x, y) end
        function fs:SetShadowColor(r, g, b, a) end
        table.insert(frame._fontstrings, fs)
        return fs
    end

    -- Base frame keyboard support
    function frame:EnableKeyboard(v) self._keyboardEnabled = v end

    -- Cooldown frame support
    if template and template:find("CooldownFrameTemplate") then
        function frame:SetDrawEdge(v) end
        function frame:SetCooldown(start, duration) end
    end

    -- UIPanelButtonTemplate support (SetText on button labels)
    if template and template:find("UIPanelButtonTemplate") then
        frame._text = ""
        function frame:SetText(t) self._text = t end
        function frame:GetText() return self._text end
    end
    
    -- StatusBar support
    if frameType == "StatusBar" then
        frame._value = 0
        frame._min = 0
        frame._max = 100
        function frame:SetMinMaxValues(min, max) self._min = min; self._max = max end
        function frame:SetValue(v) self._value = v end
        function frame:GetValue() return self._value end
        function frame:SetStatusBarColor(r,g,b,a) end
        function frame:SetStatusBarTexture(t) end
    end

    -- EditBox support
    if frameType == "EditBox" then
        frame._text = ""
        function frame:SetText(t) self._text = t end
        function frame:GetText() return self._text end
        function frame:SetMultiLine(v) end
        function frame:SetAutoFocus(v) end
        function frame:SetFontObject(f) end
        function frame:SetFont(font, size, flags) end
        function frame:EnableMouse(v) self._mouseEnabled = v end
    end

    -- ScrollFrame support
    if frameType == "ScrollFrame" then
        function frame:SetScrollChild(child) self._scrollChild = child end
        function frame:GetScrollChild() return self._scrollChild end
    end

    return frame
end

-- CreateFrame - returns a FUNCTIONAL frame mock and registers named frames in _G,
-- mirroring WoW's behaviour where CreateFrame("Button", "MyFrame", ...) makes
-- _G["MyFrame"] available immediately.
_G.CreateFrame = function(frameType, name, parent, template)
    local frame = createMockFrame(frameType, name, parent, template)
    if name then _G[name] = frame end   -- register globally by name, just like WoW
    return frame
end

-- C_GamePad API
_G.C_GamePad = {
    _enabled = false,
    _activeDeviceID = nil,
    _ledColor = nil,
    _vibrating = false,
    _devices = {},
    
    IsEnabled = function() return _G.C_GamePad._enabled end,
    GetActiveDeviceID = function() return _G.C_GamePad._activeDeviceID end,
    GetAllDeviceIDs = function()
        local ids = {}
        for id in pairs(_G.C_GamePad._devices) do table.insert(ids, id) end
        return ids
    end,
    SetLedColor = function(color) _G.C_GamePad._ledColor = color end,
    GetLedColor = function() return _G.C_GamePad._ledColor end,
    ClearLedColor = function() _G.C_GamePad._ledColor = nil end,
    SetVibration = function(vibeType, intensity)
        _G.C_GamePad._vibrating = true
        _G.C_GamePad._lastVibration = { type = vibeType, intensity = intensity }
    end,
    StopVibration = function() _G.C_GamePad._vibrating = false end,
    GetDeviceMappedState = function(deviceID)
        return _G.C_GamePad._devices[deviceID]
    end,
    GetDeviceRawState = function(deviceID)
        return _G.C_GamePad._devices[deviceID]
    end,
    
    -- Test helpers
    _SimulateConnect = function(deviceID)
        deviceID = deviceID or 1
        _G.C_GamePad._devices[deviceID] = { leftTrigger = 0, rightTrigger = 0 }
        _G.C_GamePad._activeDeviceID = deviceID
        _G.C_GamePad._enabled = true
    end,
    _SimulateDisconnect = function()
        _G.C_GamePad._enabled = false
        _G.C_GamePad._activeDeviceID = nil
        _G.C_GamePad._devices = {}
    end,
    _SetTriggerAxis = function(lt, rt)
        local deviceID = _G.C_GamePad._activeDeviceID or 1
        if _G.C_GamePad._devices[deviceID] then
            _G.C_GamePad._devices[deviceID].leftTrigger = lt or 0
            _G.C_GamePad._devices[deviceID].rightTrigger = rt or 0
        end
    end,
}

-- C_AddOns API
_G.C_AddOns = {
    _addons = {
        ControllerCompanion = { loaded = false, enabled = true },
    },
    
    IsAddOnLoaded = function(name)
        local addon = _G.C_AddOns._addons[name]
        return addon and addon.loaded or false
    end,
    LoadAddOn = function(name)
        local addon = _G.C_AddOns._addons[name]
        if not addon then return false, "MISSING" end
        if not addon.enabled then return false, "DISABLED" end
        addon.loaded = true
        return true, nil
    end,
    EnableAddOn = function(name, character)
        if _G.C_AddOns._addons[name] then
            _G.C_AddOns._addons[name].enabled = true
        end
    end,
    DisableAddOn = function(name, character)
        if _G.C_AddOns._addons[name] then
            _G.C_AddOns._addons[name].enabled = false
        end
    end,
    
    -- Test helpers
    _Reset = function()
        _G.C_AddOns._addons = {
            ControllerCompanion = { loaded = false, enabled = true },
        }
    end,
}

-- C_Spell API
_G.C_Spell = {
    _spells = {
        -- Mock some common spells with school masks
        [133]  = { name = "Fireball",    icon = "Interface\\Icons\\Spell_Fire_Flamebolt",    schoolMask = 4  },  -- Fire
        [116]  = { name = "Frostbolt",   icon = "Interface\\Icons\\Spell_Frost_FrostBolt02", schoolMask = 16 },  -- Frost
        [30449] = { name = "Spellsteal", icon = "Interface\\Icons\\Spell_Arcane_Arcane03",   schoolMask = 64 },  -- Arcane
        [589]  = { name = "Shadow Word: Pain", icon = "Interface\\Icons\\Spell_Shadow_WordPain", schoolMask = 32 }, -- Shadow
        [1064] = { name = "Chain Heal", icon = "Interface\\Icons\\Spell_Nature_HealingWave", schoolMask = 8  },  -- Nature
        [85673] = { name = "Word of Glory", icon = "Interface\\Icons\\Spell_Holy_WordOfGlory", schoolMask = 2 }, -- Holy
    },
    
    GetSpellInfo = function(spellID)
        local spell = _G.C_Spell._spells[spellID]
        if spell then
            return { name = spell.name, iconID = spell.icon, schoolMask = spell.schoolMask }
        end
        return nil
    end,
}

-- C_Timer
local _timers = {}
local _tickers = {}
local _timerID = 0

_G.C_Timer = {
    After = function(delay, callback)
        _timerID = _timerID + 1
        local id = _timerID
        _timers[id] = { callback = callback, delay = delay, fired = false }
        return id
    end,
    NewTicker = function(interval, callback, iterations)
        _timerID = _timerID + 1
        local id = _timerID
        _tickers[id] = { callback = callback, interval = interval, count = 0, cancelled = false }
        return {
            Cancel = function(self)
                if _tickers[id] then _tickers[id].cancelled = true end
            end,
            IsCancelled = function(self)
                return _tickers[id] and _tickers[id].cancelled or true
            end,
        }
    end,
    -- Test helper: fire all pending timers
    _FireAll = function()
        for id, timer in pairs(_timers) do
            if not timer.fired then
                timer.fired = true
                timer.callback()
            end
        end
    end,
    _Reset = function()
        _timers = {}
        _tickers = {}
        _timerID = 0
    end,
}

-- Unit info functions
local _mockPlayer = {
    name = "TestPlayer",
    class = "MAGE",
    classID = 8,
    level = 80,
    health = 100000,
    healthMax = 100000,
    power = 100000,
    powerMax = 100000,
    powerType = 0,  -- Mana
    spec = 2,       -- Fire Mage
    inCombat = false,
}

_G.UnitName = function(unit)
    if unit == "player" then return _mockPlayer.name, "TestRealm" end
    return nil
end

_G.UnitClass = function(unit)
    if unit == "player" then
        return "Mage", _mockPlayer.class, _mockPlayer.classID
    end
    return nil
end

_G.UnitLevel = function(unit)
    if unit == "player" then return _mockPlayer.level end
    return 0
end

_G.UnitHealth = function(unit)
    if unit == "player" then return _mockPlayer.health end
    return 0
end

_G.UnitHealthMax = function(unit)
    if unit == "player" then return _mockPlayer.healthMax end
    return 0
end

_G.UnitPower = function(unit, powerType)
    if unit == "player" then return _mockPlayer.power end
    return 0
end

_G.UnitPowerMax = function(unit, powerType)
    if unit == "player" then return _mockPlayer.powerMax end
    return 0
end

_G.UnitPowerType = function(unit)
    if unit == "player" then return _mockPlayer.powerType, "MANA" end
    return 0, "MANA"
end

_G.UnitExists = function(unit)
    return unit == "player"
end

_G.UnitIsEnemy = function(unit1, unit2) return false end
_G.UnitIsFriend = function(unit1, unit2) return true end
_G.UnitIsDead = function(unit) return false end

_G.GetSpecialization = function()
    return _mockPlayer.spec
end

_G.GetSpecializationInfo = function(specIndex)
    if specIndex == 2 then
        return 2, "Fire", "Fire Mage specialization", "Interface\\Icons\\Spell_Fire_Firebolt02", "DAMAGER"
    end
    return specIndex, "Unknown", "", "", "DAMAGER"
end

_G.GetNumGroupMembers = function() return 0 end

-- Test helper to change mock state
_G._MockPlayer = _mockPlayer

-- Combat state
local _inCombat = false
_G.InCombatLockdown = function() return _inCombat end
_G._SetCombatState = function(state) _inCombat = state end

-- Binding functions
local _overrideBindings  = {}  -- [owner][key] = action   (SetOverrideBinding* layer)
local _permanentBindings = {}  -- [key] = action           (SetBinding layer — persists)
local _saveBindingsCalls = 0   -- count of SaveBindings() calls (test assertion helper)

_G.SetOverrideBinding = function(owner, isPriority, key, action)
    if _inCombat then error("SetOverrideBinding called during combat lockdown!") end
    if not _overrideBindings[owner] then _overrideBindings[owner] = {} end
    _overrideBindings[owner][key] = action
end

_G.SetOverrideBindingSpell = function(owner, isPriority, key, spellName)
    SetOverrideBinding(owner, isPriority, key, "SPELL " .. tostring(spellName))
end

_G.SetOverrideBindingItem = function(owner, isPriority, key, itemName)
    SetOverrideBinding(owner, isPriority, key, "ITEM " .. tostring(itemName))
end

_G.SetOverrideBindingMacro = function(owner, isPriority, key, macroName)
    SetOverrideBinding(owner, isPriority, key, "MACRO " .. tostring(macroName))
end

_G.SetOverrideBindingClick = function(owner, isPriority, key, buttonName, mouseButton)
    if _inCombat then error("SetOverrideBindingClick called during combat lockdown!") end
    if not _overrideBindings[owner] then _overrideBindings[owner] = {} end
    _overrideBindings[owner][key] = "CLICK " .. tostring(buttonName) .. ":" .. tostring(mouseButton or "LeftButton")
end

_G.ClearOverrideBindings = function(owner)
    if _inCombat then error("ClearOverrideBindings called during combat lockdown!") end
    _overrideBindings[owner] = nil
end

-- Permanent binding layer (SetBinding — survives /reload when followed by SaveBindings)
_G.SetBinding = function(key, command)
    if _inCombat then error("SetBinding called during combat lockdown!") end
    if command and command ~= "" then
        _permanentBindings[key] = command
    else
        _permanentBindings[key] = nil
    end
    return true
end

_G.SetBindingClick = function(key, frameName, mouseButton)
    if _inCombat then error("SetBindingClick called during combat lockdown!") end
    _permanentBindings[key] = "CLICK " .. (frameName or "") .. ":" .. (mouseButton or "LeftButton")
    return true
end

_G.SaveBindings = function(setID)
    _saveBindingsCalls = _saveBindingsCalls + 1
end

_G.GetCurrentBindingSet = function()
    return 1  -- 1 = account-wide bindings
end

-- Test helpers
_G._GetOverrideBindings  = function(owner) return _overrideBindings[owner] or {} end
_G._GetPermanentBindings = function() return _permanentBindings end
_G._GetSaveBindingsCalls = function() return _saveBindingsCalls end
_G._ResetBindings = function()
    _overrideBindings  = {}
    _permanentBindings = {}
    _saveBindingsCalls = 0
end

-- GetBindingAction: returns the currently active binding action for a key.
-- checkOverride: if true, override bindings are checked first (mirrors the real WoW API).
-- Without checkOverride only the permanent (SetBinding) layer is consulted.
-- This mirrors WoW: GetBindingAction("PAD4") returns the permanent binding;
-- GetBindingAction("PAD4", true) returns the override if one exists, else permanent.
_G.GetBindingAction = function(key, checkOverride)
    if checkOverride then
        for _, bindings in pairs(_overrideBindings) do
            if bindings[key] then return bindings[key] end
        end
    end
    return _permanentBindings[key]
end

-- Spell/item info
_G.GetSpellInfo = function(spellIDOrName)
    -- Check C_Spell mock first
    local info = nil
    if type(spellIDOrName) == "number" then
        info = C_Spell._spells[spellIDOrName]
    else
        -- search by name
        for id, s in pairs(C_Spell._spells) do
            if s.name == spellIDOrName then info = s; break end
        end
    end
    if info then
        return info.name, "", info.icon, 0, 0, 0, spellIDOrName, info.schoolMask
    end
    return nil
end

_G.GetSpellTexture = function(spellID)
    local spell = C_Spell._spells[spellID]
    if spell then return spell.icon end
    return nil
end

_G.GetItemInfo = function(itemID)
    return nil  -- most tests don't need item info
end

_G.C_Item = {
    GetItemInfo = function(itemID)
        return nil  -- most tests don't need item info
    end,
}

_G.IsSpellKnown = function(spellID) return true end  -- assume player knows all spells in tests

-- Other WoW globals
_G.ReloadUI = function() end
_G.SlashCmdList = _G.SlashCmdList or {}

_G.CreateColor = function(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1.0,
             GetRGB = function(self) return self.r, self.g, self.b end }
end

_G.RAID_CLASS_COLORS = {
    MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE = { r = 1.0, g = 0.96, b = 0.41 },
    PRIEST = { r = 1.0, g = 1.0, b = 1.0 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    SHAMAN = { r = 0.0, g = 0.44, b = 0.87 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    MONK = { r = 0.0, g = 1.0, b = 0.59 },
    DRUID = { r = 1.0, g = 0.49, b = 0.04 },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    EVOKER = { r = 0.2, g = 0.58, b = 0.5 },
}

_G.PowerBarColor = {}

_G.UIFrameFadeIn = function(frame, time, startAlpha, endAlpha)
    frame:SetAlpha(endAlpha)  -- instant in tests
end

_G.UIFrameFadeOut = function(frame, time, startAlpha, endAlpha)
    frame:SetAlpha(endAlpha)  -- instant in tests
end

_G.SetGamePadCursorControl = function(enabled) end
_G.SetGamePadFreeLook = function(enabled) end
_G.IsGamePadCursorControlEnabled = function() return false end
_G.IsGamePadFreelookEnabled = function() return false end

-- Interface panel toggle stubs (real protected APIs, not MicroButton clicks)
_G.CloseAllWindows         = function() end
_G.ToggleCharacter         = function(tab) end
_G.ToggleSpellBook         = function(bookType) end
_G.ToggleTalentFrame       = function() end
_G.ToggleQuestLog          = function() end
_G.ToggleAchievementFrame  = function() end
_G.ToggleAllBags           = function() end
_G.ToggleCollectionsJournal= function(tab) end
_G.ToggleFriendsFrame      = function() end
_G.ToggleEncounterJournal  = function() end
_G.ToggleGuildFrame        = function() end
_G.PVEFrame_ToggleFrame    = function() end  -- replaces removed ToggleLFDParentFrame
_G.TogglePVPUI             = function() end
_G.ToggleStoreUI           = function() end
_G.ToggleHelpFrame         = function() end
_G.ToggleGameMenu          = function() end
_G.GameTimeCalendar_Toggle = function() end
_G.ToggleProfessionsBook   = function() end
_G.Screenshot              = function() end

_G.ShowUIPanel = function(frame) if frame and frame.Show then frame:Show() end end
_G.HideUIPanel = function(frame) if frame and frame.Hide then frame:Hide() end end

-- WorldMapFrame: direct frame used for map toggle (ToggleWorldMap removed in TWW)
_G.WorldMapFrame = {
    _shown = false,
    IsShown  = function(self) return self._shown end,
    SetShown = function(self, v) self._shown = v end,
    Show     = function(self) self._shown = true end,
    Hide     = function(self) self._shown = false end,
}

_G.GetTime = function() return os.time() end

_G._stateDrivers = {}  -- {[frame] = {[state] = macro}} — inspectable in tests
_G.RegisterStateDriver = function(frame, state, macro)
    if not _G._stateDrivers[frame] then _G._stateDrivers[frame] = {} end
    _G._stateDrivers[frame][state] = macro
end
_G.UnregisterStateDriver = function(frame, state)
    if _G._stateDrivers[frame] then _G._stateDrivers[frame][state] = nil end
end

_G.print = print  -- already exists in Lua

-- Lua 5.1 compat: WoW uses unpack(), Lua 5.3+ has it as table.unpack()
if not _G.unpack then
    _G.unpack = table.unpack
end

-- C_GossipInfo stub (used by DelveCompanionStats for friendship reputation)
_G.C_GossipInfo = _G.C_GossipInfo or {
    GetFriendshipReputation = function(factionID)
        if factionID == 2744 then
            return {
                standing           = 491930,
                reactionThreshold  = 460435,
                nextThreshold      = 499810,
                reaction           = "Level 24",
                friendshipFactionID = 2744,
                name               = "Valeera Sanguinar",
                friendshipRank     = 3,
            }
        end
        return nil
    end,
    GetFriendshipReputationRanks = function(factionID) return nil end,
}

-- C_Reputation stub (used by DelveCompanionStats for dynamic companion name lookup)
_G.C_Reputation = {
    GetFactionDataByID = function(factionID)
        if factionID == 2744 then return { name = "Valeera Sanguinar" } end
        return nil
    end,
}

-- bit library (available in WoW's Lua 5.1 environment)
if not _G.bit then
    -- Try to load luabitop (installed in CI via luarocks install luabitop)
    local success, bitop = pcall(require, "bit")
    if success then
        _G.bit = bitop
    else
        -- Pure Lua 5.1 fallback — no Lua 5.3 syntax used here
        local function _bits(n, w)
            local t = {}
            for i = 1, w do t[i] = n % 2; n = math.floor(n / 2) end
            return t
        end
        local function _num(t)
            local n = 0
            for i = #t, 1, -1 do n = n * 2 + t[i] end
            return n
        end
        local function _op(a, b, fn)
            local ta, tb, tc = _bits(a, 32), _bits(b, 32), {}
            for i = 1, 32 do tc[i] = fn(ta[i], tb[i]) end
            return _num(tc)
        end
        _G.bit = {
            band   = function(a, b) return _op(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end) end,
            bor    = function(a, b) return _op(a, b, function(x, y) return (x == 1 or  y == 1) and 1 or 0 end) end,
            bxor   = function(a, b) return _op(a, b, function(x, y) return (x ~= y)            and 1 or 0 end) end,
            lshift = function(a, b) return math.floor(a * (2 ^ b)) end,
            rshift = function(a, b) return math.floor(a / (2 ^ b)) end,
            bnot   = function(a)    return -(a + 1) end,
        }
    end
end

-- C_UnitAuras stub (used by DelveCompanionStats for boon detection)
-- _auras[spellID] = table (truthy) or nil
_G.C_UnitAuras = {
    _auras = {},

    GetPlayerAuraBySpellID = function(spellID, filter)
        return _G.C_UnitAuras._auras[spellID]
    end,
}

_G.UnitAura = function(unit, index, filter)
    return nil  -- legacy fallback; not used in primary code path
end

-- C_ScenarioInfo stub (TWW API — used by DelveCompanionStats for nemesis progress)
-- _criteria is a list of {description, quantity, totalQuantity}
_G.C_ScenarioInfo = {
    _criteria = {},

    GetInfo = function()
        return nil, nil, false  -- name, description, isInScenario
    end,

    GetScenarioStepInfo = function()
        return { numCriteria = #(_G.C_ScenarioInfo._criteria) }
    end,

    GetCriteriaInfo = function(i)
        local c = _G.C_ScenarioInfo._criteria[i]
        if not c then return nil end
        return c
    end,
}

-- Test helper: set a single boon aura by spell ID (value1 optional; presence is enough)
_G._SetMockAura = function(spellID, value1)
    _G.C_UnitAuras._auras[spellID] = { value1 = value1 }
end

-- Test helper: clear all mock auras
_G._ClearMockAuras = function()
    _G.C_UnitAuras._auras = {}
end

-- Test helper: set nemesis progress.
-- Two calling forms:
--   _SetMockNemesis(current, total)           -- single criterion (legacy)
--   _SetMockNemesis({ {desc, qty, total}, … }) -- explicit criteria table
_G._SetMockNemesis = function(criteriaOrCurrent, total)
    if type(criteriaOrCurrent) == "table" then
        _G.C_ScenarioInfo._criteria = criteriaOrCurrent
    else
        -- Legacy single-criterion form
        _G.C_ScenarioInfo._criteria = {
            { description = "Enemy group kills", quantity = criteriaOrCurrent, totalQuantity = total }
        }
    end
end
