-- CouchPotato/Core/Diagnostics.lua
-- In-game diagnostic suite and debug dump.
--
-- /cp test  — run assertions and print PASS/FAIL for each check
-- /cp debug — dump current binding, module, and DB state
--
-- Patch 12.0.1 (Interface 120001)

local CP = CouchPotato
local Diagnostics = CP:NewModule("Diagnostics")

-- Face-button → controller label
local FACE_NAMES = {
    PAD1 = "A/Cross",
    PAD2 = "B/Circle",
    PAD3 = "X/Square",
    PAD4 = "Y/Triangle",
}

-- All PAD keys to inspect in the debug dump
local ALL_PAD_KEYS = {
    "PAD1", "PAD2", "PAD3", "PAD4",
    "PADLSHOULDER", "PADRSHOULDER",
    "PADLTRIGGER",  "PADRTRIGGER",
    "PADLSTICK",    "PADRSTICK",
    "PADBACK",      "PADSTART",
    "PADDDUP",      "PADDDDOWN", "PADDDLEFT", "PADDDRIGHT",
}

function Diagnostics:OnEnable()
    -- Diagnostics are on-demand; nothing to initialise.
end

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function stripColors(s)
    return s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

-- (helpers are defined as local closures inside RunTests / DumpDebug below)

-- ── /cp test ─────────────────────────────────────────────────────────────────

function Diagnostics:RunTests()
    local lines = {}

    -- All helpers are local closures that capture `lines`.
    local function out(msg)
        CP:Print(msg)
        lines[#lines + 1] = stripColors(msg)
    end
    local function pass(label, detail)
        local msg = "|cff00ff00PASS|r " .. tostring(label)
        if detail ~= nil then msg = msg .. " (" .. tostring(detail) .. ")" end
        out(msg)
    end
    local function fail(label, detail)
        local msg = "|cffff4444FAIL|r " .. tostring(label)
        if detail ~= nil then msg = msg .. " — " .. tostring(detail) end
        out(msg)
    end
    local function check(label, ok, detail)
        if ok then pass(label, detail); return 1, 0
        else       fail(label, detail); return 0, 1 end
    end

    local passed, failed = 0, 0
    local function tally(p, f) passed = passed + p; failed = failed + f end

    out("── In-Game Diagnostics ──")

    -- ── API Compatibility ─────────────────────────────────────────────────────
    -- Verify every WoW global/namespace the addon actually calls still exists.
    -- After any patch, FAIL here = Blizzard removed or renamed that API.
    out("── API Compatibility ──")

    -- C_GamePad namespace (Bindings.lua, GamePad.lua, Specs.lua, CouchPotato.lua)
    tally(check("C_GamePad (namespace)",
        type(C_GamePad) == "table",
        type(C_GamePad)))
    tally(check("C_GamePad.IsEnabled",
        type(C_GamePad and C_GamePad.IsEnabled) == "function",
        type(C_GamePad and C_GamePad.IsEnabled)))
    tally(check("C_GamePad.GetActiveDeviceID",
        type(C_GamePad and C_GamePad.GetActiveDeviceID) == "function",
        type(C_GamePad and C_GamePad.GetActiveDeviceID)))
    tally(check("C_GamePad.GetDeviceMappedState",
        type(C_GamePad and C_GamePad.GetDeviceMappedState) == "function",
        type(C_GamePad and C_GamePad.GetDeviceMappedState)))
    tally(check("C_GamePad.SetLedColor",
        type(C_GamePad and C_GamePad.SetLedColor) == "function",
        type(C_GamePad and C_GamePad.SetLedColor)))
    tally(check("C_GamePad.ClearLedColor",
        type(C_GamePad and C_GamePad.ClearLedColor) == "function",
        type(C_GamePad and C_GamePad.ClearLedColor)))

    -- C_Spell namespace (Radial.lua)
    tally(check("C_Spell (namespace)",
        type(C_Spell) == "table",
        type(C_Spell)))
    tally(check("C_Spell.GetSpellInfo",
        type(C_Spell and C_Spell.GetSpellInfo) == "function",
        type(C_Spell and C_Spell.GetSpellInfo)))

    -- C_AddOns namespace (localized in CouchPotato.lua; used by Loader)
    tally(check("C_AddOns (namespace)",
        type(C_AddOns) == "table",
        type(C_AddOns)))
    tally(check("C_AddOns.IsAddOnLoaded",
        type(C_AddOns and C_AddOns.IsAddOnLoaded) == "function",
        type(C_AddOns and C_AddOns.IsAddOnLoaded)))

    -- C_Timer namespace (CouchPotato.lua ScheduleTimer / ScheduleRepeatingTimer, Radial.lua)
    tally(check("C_Timer (namespace)",
        type(C_Timer) == "table",
        type(C_Timer)))
    tally(check("C_Timer.After",
        type(C_Timer and C_Timer.After) == "function",
        type(C_Timer and C_Timer.After)))
    tally(check("C_Timer.NewTicker",
        type(C_Timer and C_Timer.NewTicker) == "function",
        type(C_Timer and C_Timer.NewTicker)))

    -- C_Item namespace (Radial.lua SetSlot item type)
    tally(check("C_Item (namespace)",
        type(C_Item) == "table",
        type(C_Item)))
    tally(check("C_Item.GetItemInfo",
        type(C_Item and C_Item.GetItemInfo) == "function",
        type(C_Item and C_Item.GetItemInfo)))

    -- Override-binding globals (Bindings.lua)
    tally(check("SetOverrideBinding",
        type(SetOverrideBinding) == "function",
        type(SetOverrideBinding)))
    tally(check("SetOverrideBindingSpell",
        type(SetOverrideBindingSpell) == "function",
        type(SetOverrideBindingSpell)))
    tally(check("SetOverrideBindingClick",
        type(SetOverrideBindingClick) == "function",
        type(SetOverrideBindingClick)))
    tally(check("ClearOverrideBindings",
        type(ClearOverrideBindings) == "function",
        type(ClearOverrideBindings)))
    tally(check("GetBindingAction",
        type(GetBindingAction) == "function",
        type(GetBindingAction)))

    -- Core WoW globals used throughout the addon
    tally(check("InCombatLockdown",
        type(InCombatLockdown) == "function",
        type(InCombatLockdown)))
    tally(check("CreateFrame",
        type(CreateFrame) == "function",
        type(CreateFrame)))
    tally(check("CreateColor",
        type(CreateColor) == "function",
        type(CreateColor)))
    tally(check("GetSpecialization",
        type(GetSpecialization) == "function",
        type(GetSpecialization)))
    tally(check("UnitClass",
        type(UnitClass) == "function",
        type(UnitClass)))
    tally(check("UIFrameFadeIn",
        type(UIFrameFadeIn) == "function",
        type(UIFrameFadeIn)))
    tally(check("ReloadUI",
        type(ReloadUI) == "function",
        type(ReloadUI)))

    -- 1. Gamepad CVar / C_GamePad state
    local gpEnabled = C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled()
    tally(check("Gamepad enabled",
        gpEnabled == true,
        tostring(gpEnabled)))

    -- 2. CP.db initialised
    tally(check("CP.db initialised",
        CP.db ~= nil and CP.db.profile ~= nil))

    -- 3. Bindings module enabled
    local Bindings = CP:GetModule("Bindings", true)
    tally(check("Bindings module enabled",
        Bindings ~= nil and Bindings:IsEnabled()))

    -- 4. ownerFrame is a valid frame
    local owner = Bindings and Bindings.ownerFrame
    tally(check("Bindings ownerFrame exists",
        owner ~= nil,
        owner and "CouchPotatoBindingOwner" or "nil"))

    -- 5. Specs layout found for current character
    local Specs = CP:GetModule("Specs", true)
    local layout = Specs and Specs:GetCurrentLayout()
    tally(check("Specs layout found",
        layout ~= nil,
        layout and layout.specName or "nil — no spec / layout undefined"))

    -- 6–9. What WoW ACTUALLY has bound after SetOverrideBindingSpell
    --      GetBindingAction is the ground truth: if it's wrong, bindings won't fire.
    if layout then
        local faceMap = {
            { pad = "PAD4", field = "primary",   spell = layout.primary   },
            { pad = "PAD2", field = "secondary",  spell = layout.secondary },
            { pad = "PAD1", field = "tertiary",   spell = layout.tertiary  },
            { pad = "PAD3", field = "interrupt",  spell = layout.interrupt },
        }
        for _, entry in ipairs(faceMap) do
            local actual   = GetBindingAction(entry.pad)
            local expected = entry.spell and ("SPELL " .. entry.spell)
            local detail   = string.format(
                "GetBindingAction=%q  expected=%q",
                tostring(actual), tostring(expected))
            tally(check(
                string.format("%s (%s) → %q",
                    entry.pad, FACE_NAMES[entry.pad] or entry.pad,
                    entry.spell or "(nil)"),
                actual == expected, detail))
        end
    else
        out("|cffffff00SKIP|r  Face-button binding checks (no layout)")
    end

    -- 10. Cardinal wheel-slot buttons exist (created by Radial at load time)
    local cardinalSlots = { PAD4 = 1, PAD2 = 4, PAD1 = 7, PAD3 = 10 }
    for pad, slotIdx in pairs(cardinalSlots) do
        local btnName = string.format("CouchPotatoWheel1Slot%d", slotIdx)
        local btn     = _G[btnName]
        tally(check(
            string.format("Wheel 1 Slot %d button exists (%s)", slotIdx, pad),
            btn ~= nil, btnName))
    end

    -- 11. Cardinal slots have a spell set (not still "empty")
    local slot1 = _G["CouchPotatoWheel1Slot1"]
    if slot1 then
        local spellAttr = slot1:GetAttribute("spell")
        tally(check("Wheel 1 Slot 1 spell attribute",
            spellAttr ~= nil,
            tostring(spellAttr)))
    else
        tally(0, 1)
        fail("Wheel 1 Slot 1 spell attribute", "button not found")
    end

    local slot10 = _G["CouchPotatoWheel1Slot10"]
    if slot10 then
        local spellAttr = slot10:GetAttribute("spell")
        tally(check("Wheel 1 Slot 10 spell attribute (PAD3/X fix)",
            spellAttr ~= nil,
            tostring(spellAttr)))
    else
        tally(0, 1)
        fail("Wheel 1 Slot 10 spell attribute", "button not found")
    end

    -- 12. SetOverrideBindingClick can be called without error
    if owner and not InCombatLockdown() then
        -- Create a temporary secure button for the click-binding probe
        local testName = "CouchPotatoDiagProbeBtn"
        local probe = CreateFrame("Button", testName, UIParent,
                                  "SecureActionButtonTemplate")
        probe:RegisterForClicks("AnyDown", "AnyUp")
        probe:SetAttribute("type", "spell")
        probe:SetAttribute("spell", layout and layout.primary or "Fireball")

        local ok, err = pcall(function()
            SetOverrideBindingClick(owner, true, "PAD4", testName, "LeftButton")
        end)
        -- Restore direct bindings so we don't leave the probe binding active
        if Bindings and Bindings:IsEnabled() and not Bindings.wheelOpen then
            Bindings:ApplyDirectBindings()
        end
        tally(check("SetOverrideBindingClick fires without error",
            ok, ok and "OK" or tostring(err)))
    else
        out("|cffffff00SKIP|r  SetOverrideBindingClick test (combat or no ownerFrame)")
    end

    -- ── Spell Validity ────────────────────────────────────────────────────────
    -- For each spell in the current spec layout, verify C_Spell.GetSpellInfo
    -- returns non-nil. A nil result means the spell was renamed or removed.
    out("── Spell Validity ──")
    do
        local specsModule = CP:GetModule("Specs", true)
        local spellLayout = specsModule and specsModule:GetCurrentLayout()
        if not spellLayout then
            out("|cffffff00SKIP|r  Spell validity (no layout for current spec)")
        elseif not (C_Spell and C_Spell.GetSpellInfo) then
            out("|cffffff00SKIP|r  Spell validity (C_Spell.GetSpellInfo unavailable)")
        else
            local spellFields = {
                "primary", "secondary", "tertiary", "interrupt",
                "majorCD", "defensiveCD", "movement", "dpadUp", "dpadDown",
            }
            for _, field in ipairs(spellFields) do
                local spellName = spellLayout[field]
                if spellName then
                    local info = C_Spell.GetSpellInfo(spellName)
                    tally(check(
                        string.format("C_Spell.GetSpellInfo(%q)", spellName),
                        info ~= nil,
                        info and "found" or "nil — spell renamed or removed?"))
                end
            end
        end
    end

    -- Summary
    out(string.format("── %d passed, %d failed ──", passed, failed))

    -- Persist to SavedVars (guard: global scope may not exist yet at load time)
    if CP.db and CP.db.global then
        CP.db.global.lastTestOutput = table.concat(lines, "\n")
        CP.db.global.lastTestTime   = time()
    end
    -- Open the scrollable output window
    if CP.DiagnosticsWindow then
        CP.DiagnosticsWindow.Show(lines)
    end
end

-- ── /cp debug ────────────────────────────────────────────────────────────────

function Diagnostics:DumpDebug()
    local lines = {}
    local function out(msg)
        CP:Print(msg)
        lines[#lines + 1] = stripColors(msg)
    end

    -- Gamepad state
    out(string.format("C_GamePad.IsEnabled()       = %s",
        tostring(C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled())))
    out(string.format("C_GamePad.GetActiveDeviceID = %s",
        tostring(C_GamePad and C_GamePad.GetActiveDeviceID and
                 C_GamePad.GetActiveDeviceID())))

    -- What WoW actually has bound for every PAD key
    out("PAD key bindings (GetBindingAction):")
    for _, key in ipairs(ALL_PAD_KEYS) do
        local b = GetBindingAction(key)
        if b then
            out(string.format("  %-18s = %s", key, b))
        end
    end

    -- Module enable states
    out("Module states:")
    for name, mod in CP:IterateModules() do
        out(string.format("  %-20s %s",
            name, mod:IsEnabled() and "|cff00ff00enabled|r" or "|cffaaaaaaadisabled|r"))
    end

    -- Bindings internal state
    local Bindings = CP:GetModule("Bindings", true)
    if Bindings then
        out(string.format("Bindings.wheelOpen    = %s", tostring(Bindings.wheelOpen)))
        out(string.format("Bindings.pendingApply = %s", tostring(Bindings.pendingApply)))
        out(string.format("Bindings.pendingClear = %s", tostring(Bindings.pendingClear)))
        out(string.format("Bindings.ownerFrame   = %s",
            Bindings.ownerFrame and "exists" or "nil"))
    end

    -- DB snapshot
    if CP.db then
        out("CP.db.profile:")
        for k, v in pairs(CP.db.profile) do
            if type(v) ~= "function" then
                out(string.format("  %-24s = %s", k, tostring(v)))
            end
        end
        out(string.format("CP.db.char.currentWheel = %s",
            tostring(CP.db.char and CP.db.char.currentWheel)))
        out(string.format("CP.db.char.healerMode   = %s",
            tostring(CP.db.char and CP.db.char.healerMode)))
    else
        out("|cffff4444CP.db is nil — ADDON_LOADED never fired?|r")
    end

    out("── End Dump ──")

    -- Persist to SavedVars (guard: global scope may not exist yet at load time)
    if CP.db and CP.db.global then
        CP.db.global.lastTestOutput = table.concat(lines, "\n")
        CP.db.global.lastTestTime   = time()
    end
    -- Open the scrollable output window
    if CP.DiagnosticsWindow then
        CP.DiagnosticsWindow.Show(lines)
    end
end


