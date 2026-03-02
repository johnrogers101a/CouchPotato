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

local function pass(label, detail)
    local msg = "|cff00ff00PASS|r " .. tostring(label)
    if detail ~= nil then msg = msg .. " (" .. tostring(detail) .. ")" end
    CP:Print(msg)
end

local function fail(label, detail)
    local msg = "|cffff4444FAIL|r " .. tostring(label)
    if detail ~= nil then msg = msg .. " — " .. tostring(detail) .. "" end
    CP:Print(msg)
end

-- Returns (passed, failed) incremented appropriately.
local function check(label, ok, detail)
    if ok then
        pass(label, detail)
        return 1, 0
    else
        fail(label, detail)
        return 0, 1
    end
end

-- ── /cp test ─────────────────────────────────────────────────────────────────

function Diagnostics:RunTests()
    local passed, failed = 0, 0
    local function tally(p, f) passed = passed + p; failed = failed + f end

    CP:Print("── In-Game Diagnostics ──")

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
    --      GetBindingByKey is the ground truth: if it's wrong, bindings won't fire.
    if layout then
        local faceMap = {
            { pad = "PAD4", field = "primary",   spell = layout.primary   },
            { pad = "PAD2", field = "secondary",  spell = layout.secondary },
            { pad = "PAD1", field = "tertiary",   spell = layout.tertiary  },
            { pad = "PAD3", field = "interrupt",  spell = layout.interrupt },
        }
        for _, entry in ipairs(faceMap) do
            local actual   = GetBindingByKey(entry.pad)
            local expected = entry.spell and ("SPELL " .. entry.spell)
            local detail   = string.format(
                "GetBindingByKey=%q  expected=%q",
                tostring(actual), tostring(expected))
            tally(check(
                string.format("%s (%s) → %q",
                    entry.pad, FACE_NAMES[entry.pad] or entry.pad,
                    entry.spell or "(nil)"),
                actual == expected, detail))
        end
    else
        CP:Print("|cffffff00SKIP|r  Face-button binding checks (no layout)")
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
        CP:Print("|cffffff00SKIP|r  SetOverrideBindingClick test (combat or no ownerFrame)")
    end

    -- Summary
    CP:Print(string.format("── %d passed, %d failed ──", passed, failed))
end

-- ── /cp debug ────────────────────────────────────────────────────────────────

function Diagnostics:DumpDebug()
    CP:Print("── Debug Dump ──")

    -- Gamepad state
    CP:Print(string.format("C_GamePad.IsEnabled()       = %s",
        tostring(C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled())))
    CP:Print(string.format("C_GamePad.GetActiveDeviceID = %s",
        tostring(C_GamePad and C_GamePad.GetActiveDeviceID and
                 C_GamePad.GetActiveDeviceID())))

    -- What WoW actually has bound for every PAD key
    CP:Print("PAD key bindings (GetBindingByKey):")
    for _, key in ipairs(ALL_PAD_KEYS) do
        local b = GetBindingByKey(key)
        if b then
            CP:Print(string.format("  %-18s = %s", key, b))
        end
    end

    -- Module enable states
    CP:Print("Module states:")
    for name, mod in CP:IterateModules() do
        CP:Print(string.format("  %-20s %s",
            name, mod:IsEnabled() and "|cff00ff00enabled|r" or "|cffaaaaaaaadisabled|r"))
    end

    -- Bindings internal state
    local Bindings = CP:GetModule("Bindings", true)
    if Bindings then
        CP:Print(string.format("Bindings.wheelOpen    = %s", tostring(Bindings.wheelOpen)))
        CP:Print(string.format("Bindings.pendingApply = %s", tostring(Bindings.pendingApply)))
        CP:Print(string.format("Bindings.pendingClear = %s", tostring(Bindings.pendingClear)))
        CP:Print(string.format("Bindings.ownerFrame   = %s",
            Bindings.ownerFrame and "exists" or "nil"))
    end

    -- DB snapshot
    if CP.db then
        CP:Print("CP.db.profile:")
        for k, v in pairs(CP.db.profile) do
            if type(v) ~= "function" then
                CP:Print(string.format("  %-24s = %s", k, tostring(v)))
            end
        end
        CP:Print(string.format("CP.db.char.currentWheel = %s",
            tostring(CP.db.char and CP.db.char.currentWheel)))
        CP:Print(string.format("CP.db.char.healerMode   = %s",
            tostring(CP.db.char and CP.db.char.healerMode)))
    else
        CP:Print("|cffff4444CP.db is nil — ADDON_LOADED never fired?|r")
    end

    CP:Print("── End Dump ──")
end
