-- InfoPanels/Core/APIValidation.lua
-- Validation command: /ipvalidate
-- Exercises every WoW UI API that the InfoPanels framework uses.
-- Outputs PASS/FAIL per test to the debug log window (not chat).
-- All test frames are created hidden and cleaned up after validation.

local addonName, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared

-- Build a logger that always writes to CouchPotatoDB.debugLog via CouchPotatoLog.
-- Prefer CouchPotatoShared.CreateLogger when available; fall back to the global
-- CouchPotatoLog directly (which is loaded by the CouchPotato core addon before
-- any dependent addon runs).
local function makeLogger(addonTag)
    local CL = _G.CouchPotatoLog
    if CP and CP.CreateLogger then
        return CP.CreateLogger(addonTag)
    elseif CL then
        -- Return a function matching the CreateLogger-produced signature:
        --   logger(level, message)  e.g. logger("Info", "text")
        return function(level, msg)
            local lv = tostring(level):lower()
            if lv == "debug" then
                CL:Debug(addonTag, msg)
            elseif lv == "warn" then
                CL:Warn(addonTag, msg)
            elseif lv == "error" then
                CL:Error(addonTag, msg)
            else
                CL:Info(addonTag, msg)
            end
        end
    else
        -- Last resort: write directly to CouchPotatoDB.debugLog if it exists,
        -- and also print to chat so output is never silently lost.
        return function(level, msg)
            local entry = "[InfoPanels/" .. tostring(level) .. "] " .. tostring(msg)
            if _G.CouchPotatoDB and type(_G.CouchPotatoDB.debugLog) == "table" then
                table.insert(_G.CouchPotatoDB.debugLog, {
                    timestamp = (GetTime and GetTime()) or 0,
                    level     = tostring(level):upper(),
                    addon     = addonTag,
                    message   = tostring(msg),
                })
            end
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage(entry)
            else
                print(entry)
            end
        end
    end
end

local iplog = makeLogger("IP")

local results = {}

local function out(msg)
    iplog("Info", msg)
end

local function record(testName, passed, detail)
    local status = passed and "PASS" or "FAIL"
    local msg = status .. "  " .. testName
    if detail then msg = msg .. " -- " .. detail end
    iplog("Info", msg)
    table.insert(results, { name = testName, passed = passed, detail = detail })
end

-------------------------------------------------------------------------------
-- Cleanup registry: frames created during validation
-------------------------------------------------------------------------------
local cleanupFrames = {}

local function safeCreate(frameType, name, parent, template)
    local ok, frame = pcall(CreateFrame, frameType, name, parent or UIParent, template)
    if ok and frame then
        frame:Hide()
        table.insert(cleanupFrames, frame)
        return frame
    end
    -- Retry without template
    if template then
        local ok2, frame2 = pcall(CreateFrame, frameType, name, parent or UIParent)
        if ok2 and frame2 then
            frame2:Hide()
            table.insert(cleanupFrames, frame2)
            return frame2
        end
    end
    return nil
end

local function cleanup()
    for _, f in ipairs(cleanupFrames) do
        pcall(function() f:Hide() end)
        pcall(function() f:SetParent(nil) end)
    end
    cleanupFrames = {}
end

-------------------------------------------------------------------------------
-- TEST GROUPS
-------------------------------------------------------------------------------

-- T1: Frame creation (Frame, Button, ScrollFrame, EditBox, with/without BackdropTemplate)
local function testFrameCreation()
    out("--- Frame Creation ---")

    -- Frame with BackdropTemplate
    local f1ok, f1 = pcall(CreateFrame, "Frame", "IPVal_Frame_BDT", UIParent, "BackdropTemplate")
    if f1ok and f1 then
        f1:Hide()
        table.insert(cleanupFrames, f1)
        record("CreateFrame(Frame + BackdropTemplate)", true)
    else
        record("CreateFrame(Frame + BackdropTemplate)", false, tostring(f1))
    end

    -- Frame without template
    local f2 = safeCreate("Frame", "IPVal_Frame_Plain")
    record("CreateFrame(Frame, no template)", f2 ~= nil)

    -- Button
    local btn = safeCreate("Button", "IPVal_Button")
    record("CreateFrame(Button)", btn ~= nil)

    -- ScrollFrame
    local sf = safeCreate("ScrollFrame", "IPVal_ScrollFrame")
    record("CreateFrame(ScrollFrame)", sf ~= nil)

    -- EditBox
    local eb = safeCreate("EditBox", "IPVal_EditBox")
    record("CreateFrame(EditBox)", eb ~= nil)

    -- Frame with UIPanelButtonTemplate
    local uipBtn = safeCreate("Button", "IPVal_UIPanelBtn", UIParent, "UIPanelButtonTemplate")
    record("CreateFrame(Button + UIPanelButtonTemplate)", uipBtn ~= nil)

    -- UIDropDownMenuTemplate
    local dd = safeCreate("Frame", "IPVal_Dropdown", UIParent, "UIDropDownMenuTemplate")
    record("CreateFrame(Frame + UIDropDownMenuTemplate)", dd ~= nil)
end

-- T2: Layout and anchoring APIs
local function testLayoutAPIs()
    out("--- Layout & Anchoring ---")

    local f = safeCreate("Frame", "IPVal_Layout")
    if not f then
        record("Layout test frame creation", false, "Could not create frame")
        return
    end

    -- SetSize
    local ok1 = pcall(function() f:SetSize(200, 100) end)
    record("SetSize(200, 100)", ok1)

    -- SetWidth / SetHeight
    local ok2 = pcall(function() f:SetWidth(250) end)
    record("SetWidth(250)", ok2)
    local ok3 = pcall(function() f:SetHeight(120) end)
    record("SetHeight(120)", ok3)

    -- GetSize (tolerance-based comparison for floating-point values)
    local ok4, w, h = pcall(function() return f:GetWidth(), f:GetHeight() end)
    local widthMatch = ok4 and type(w) == "number" and math.abs(w - 250) < 0.01
    local heightMatch = ok4 and type(h) == "number" and math.abs(h - 120) < 0.01
    record("GetWidth/GetHeight", ok4 and widthMatch and heightMatch,
        ok4 and ("w=" .. tostring(w) .. " h=" .. tostring(h)) or tostring(w))

    -- SetPoint / ClearAllPoints
    local ok5 = pcall(function() f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end)
    record("SetPoint(CENTER)", ok5)
    local ok6 = pcall(function() f:ClearAllPoints() end)
    record("ClearAllPoints()", ok6)
    pcall(function() f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end)

    -- GetPoint
    local ok7, pt = pcall(function() return f:GetPoint(1) end)
    record("GetPoint(1)", ok7 and pt == "CENTER", "point=" .. tostring(pt))

    -- SetMovable / EnableMouse
    local ok8 = pcall(function() f:SetMovable(true) end)
    record("SetMovable(true)", ok8)
    local ok9 = pcall(function() f:EnableMouse(true) end)
    record("EnableMouse(true)", ok9)

    -- StartMoving / StopMovingOrSizing (safe to call in sequence)
    local ok10 = pcall(function() f:StartMoving(); f:StopMovingOrSizing() end)
    record("StartMoving + StopMovingOrSizing", ok10)

    -- SetFrameStrata / SetFrameLevel
    local ok11 = pcall(function() f:SetFrameStrata("MEDIUM") end)
    record("SetFrameStrata(MEDIUM)", ok11)
    local ok12 = pcall(function() f:SetFrameLevel(5) end)
    record("SetFrameLevel(5)", ok12)

    -- Show / Hide / IsShown
    local ok13 = pcall(function() f:Show(); assert(f:IsShown()); f:Hide(); assert(not f:IsShown()) end)
    record("Show/Hide/IsShown", ok13)
end

-- T3: Texture and font APIs
local function testTextureFont()
    out("--- Texture & Font ---")

    local f = safeCreate("Frame", "IPVal_TexFont")
    if not f then
        record("Texture/Font test frame creation", false)
        return
    end
    f:SetSize(200, 100)
    f:SetPoint("CENTER")

    -- CreateTexture + SetColorTexture
    local okTex, tex
    okTex = pcall(function()
        tex = f:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(f)
        tex:SetColorTexture(0, 0, 0, 0.5)
    end)
    record("CreateTexture + SetColorTexture", okTex)

    -- Texture with SetTexture (built-in asset)
    local okTex2 = pcall(function()
        local t2 = f:CreateTexture(nil, "ARTWORK")
        t2:SetSize(16, 16)
        t2:SetPoint("CENTER")
        t2:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
    end)
    record("SetTexture (built-in asset)", okTex2)

    -- CreateFontString
    local okFS, fs
    okFS = pcall(function()
        fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    end)
    record("CreateFontString(GameFontNormalLarge)", okFS)

    if fs then
        -- SetText
        local ok1 = pcall(function() fs:SetText("Validation Test") end)
        record("FontString:SetText()", ok1)

        -- SetTextColor
        local ok2 = pcall(function() fs:SetTextColor(1, 0.82, 0, 1) end)
        record("FontString:SetTextColor()", ok2)

        -- SetJustifyH / SetJustifyV
        local ok3 = pcall(function() fs:SetJustifyH("LEFT") end)
        record("FontString:SetJustifyH(LEFT)", ok3)
        local ok4 = pcall(function() fs:SetJustifyV("MIDDLE") end)
        record("FontString:SetJustifyV(MIDDLE)", ok4)

        -- SetShadowOffset / SetShadowColor
        local ok5 = pcall(function() fs:SetShadowOffset(1, -1) end)
        record("FontString:SetShadowOffset()", ok5)
        local ok6 = pcall(function() fs:SetShadowColor(0, 0, 0, 1) end)
        record("FontString:SetShadowColor()", ok6)

        -- SetFont (direct path)
        local ok7 = pcall(function() fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE") end)
        record("FontString:SetFont(path, size, flags)", ok7)

        -- SetFontObject
        local ok8 = pcall(function() fs:SetFontObject(GameFontHighlightSmall) end)
        record("FontString:SetFontObject(GameFontHighlightSmall)", ok8)

        -- SetFontObject with ObjectiveTitleFont (used in headers)
        local ok9 = pcall(function() fs:SetFontObject(ObjectiveTitleFont) end)
        record("FontString:SetFontObject(ObjectiveTitleFont)", ok9,
            not ok9 and "ObjectiveTitleFont may not exist" or nil)

        -- SetFontObject with ObjectiveFont (used in labels)
        local ok10 = pcall(function() fs:SetFontObject(ObjectiveFont) end)
        record("FontString:SetFontObject(ObjectiveFont)", ok10,
            not ok10 and "ObjectiveFont may not exist" or nil)

        -- GetStringWidth (needed for dynamic sizing)
        local ok11, sw = pcall(function() return fs:GetStringWidth() end)
        record("FontString:GetStringWidth()", ok11, "width=" .. tostring(sw))
    end
end

-- T4: ScrollFrame + EditBox combo (import/export, editor text areas)
local function testScrollEditBox()
    out("--- ScrollFrame + EditBox ---")

    local parent = safeCreate("Frame", "IPVal_ScrollParent")
    if not parent then
        record("ScrollEditBox parent creation", false)
        return
    end
    parent:SetSize(300, 200)
    parent:SetPoint("CENTER")

    -- ScrollFrame
    local sf = safeCreate("ScrollFrame", "IPVal_ScrollF", parent)
    if not sf then
        record("ScrollFrame creation (child)", false)
        return
    end
    local okSF = pcall(function()
        sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -28)
        sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 30)
    end)
    record("ScrollFrame anchoring", okSF)

    -- EditBox as scroll child
    local eb = safeCreate("EditBox", "IPVal_ScrollEB", sf)
    if not eb then
        record("EditBox creation (scroll child)", false)
        return
    end

    local okEB = pcall(function()
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(sf:GetWidth() or 250)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end)
    record("EditBox:SetMultiLine + SetAutoFocus + SetFontObject", okEB)

    -- SetScrollChild
    local okSC = pcall(function() sf:SetScrollChild(eb) end)
    record("ScrollFrame:SetScrollChild(EditBox)", okSC)

    -- SetText / GetText
    local testStr = "Hello from IPValidate!\nLine 2\nLine 3"
    local okSet = pcall(function() eb:SetText(testStr) end)
    record("EditBox:SetText(multiline)", okSet)

    local okGet, got = pcall(function() return eb:GetText() end)
    record("EditBox:GetText()", okGet and got == testStr,
        okGet and ("len=" .. tostring(#(got or ""))) or tostring(got))

    -- HighlightText
    local okHL = pcall(function() eb:HighlightText() end)
    record("EditBox:HighlightText()", okHL)

    -- SetFocus (only valid when shown, so may fail hidden — that's OK)
    local okFocus = pcall(function() eb:SetFocus() end)
    record("EditBox:SetFocus() (may fail hidden)", okFocus, not okFocus and "expected when hidden" or nil)

    -- ClearFocus
    local okCF = pcall(function() eb:ClearFocus() end)
    record("EditBox:ClearFocus()", okCF)

    -- ScrollFrame scroll APIs
    local okScroll = pcall(function()
        sf:SetVerticalScroll(0)
        local vs = sf:GetVerticalScroll()
    end)
    record("ScrollFrame:Set/GetVerticalScroll()", okScroll)
end

-- T5: Dropdown / Menu APIs
local function testDropdownAPIs()
    out("--- Dropdown / Menu APIs ---")

    -- UIDropDownMenu (legacy API, still used in 12.0.x)
    local dd = safeCreate("Frame", "IPVal_DD", UIParent, "UIDropDownMenuTemplate")
    if dd then
        record("UIDropDownMenuTemplate frame", true)

        -- UIDropDownMenu_Initialize
        local okInit = pcall(function()
            UIDropDownMenu_Initialize(dd, function(self, level, menuList)
                local info = UIDropDownMenu_CreateInfo()
                info.text = "Test Item 1"
                info.value = "test1"
                info.func = function() end
                UIDropDownMenu_AddButton(info, level)

                info = UIDropDownMenu_CreateInfo()
                info.text = "Test Item 2"
                info.value = "test2"
                info.func = function() end
                UIDropDownMenu_AddButton(info, level)
            end)
        end)
        record("UIDropDownMenu_Initialize + AddButton", okInit)

        -- UIDropDownMenu_SetSelectedValue
        local okSel = pcall(function()
            UIDropDownMenu_SetSelectedValue(dd, "test1")
        end)
        record("UIDropDownMenu_SetSelectedValue", okSel)

        -- UIDropDownMenu_SetWidth
        local okW = pcall(function()
            UIDropDownMenu_SetWidth(dd, 150)
        end)
        record("UIDropDownMenu_SetWidth", okW)
    else
        record("UIDropDownMenuTemplate frame", false, "Template not available")
    end

    -- Check if MenuUtil exists (newer API in TWW/Midnight)
    local hasMenuUtil = type(_G.MenuUtil) == "table"
    record("MenuUtil global exists", hasMenuUtil,
        hasMenuUtil and "Modern menu API available" or "Not available — use UIDropDownMenu")
end

-- T6: Compression/encoding (LibDeflate or fallback)
local function testCompression()
    out("--- Compression / Encoding ---")

    -- Check if LibDeflate is loaded (global or via LibStub if another addon registered it)
    local LibDeflate = _G.LibDeflate or (LibStub and LibStub("LibDeflate", true))
    if LibDeflate then
        record("LibDeflate global exists", true)

        -- Compress
        local testData = "This is a test string for compression. Repeated data repeated data repeated data."
        local okComp, compressed = pcall(function()
            return LibDeflate:CompressDeflate(testData)
        end)
        record("LibDeflate:CompressDeflate()", okComp and compressed ~= nil,
            okComp and ("compressed len=" .. tostring(#(compressed or ""))) or tostring(compressed))

        if okComp and compressed then
            -- Encode for transmission (base64-like)
            local okEnc, encoded = pcall(function()
                return LibDeflate:EncodeForPrint(compressed)
            end)
            record("LibDeflate:EncodeForPrint()", okEnc and encoded ~= nil,
                okEnc and ("encoded len=" .. tostring(#(encoded or ""))) or tostring(encoded))

            if okEnc and encoded then
                -- Decode
                local okDec, decoded = pcall(function()
                    return LibDeflate:DecodeForPrint(encoded)
                end)
                record("LibDeflate:DecodeForPrint()", okDec and decoded ~= nil)

                if okDec and decoded then
                    -- Decompress
                    local okDecomp, decompressed = pcall(function()
                        return LibDeflate:DecompressDeflate(decoded)
                    end)
                    record("LibDeflate:DecompressDeflate()", okDecomp and decompressed == testData,
                        okDecomp and ("roundtrip match=" .. tostring(decompressed == testData)) or tostring(decompressed))
                end
            end

            -- EncodeForWoWAddonChannel (chat-safe encoding)
            local okWow, wowEncoded = pcall(function()
                return LibDeflate:EncodeForWoWAddonChannel(compressed)
            end)
            record("LibDeflate:EncodeForWoWAddonChannel()", okWow and wowEncoded ~= nil,
                okWow and ("len=" .. tostring(#(wowEncoded or ""))) or tostring(wowEncoded))
        end
    else
        record("LibDeflate global exists", false,
            "LibDeflate not loaded — must be vendored in Libs/LibDeflate.lua")

        -- Test basic Lua string compression fallback
        out("  (Testing basic base64 encode/decode as fallback)")

        -- WoW has no built-in base64; test that string.byte/char work for manual encoding
        local okB = pcall(function()
            local s = "test"
            local bytes = {string.byte(s, 1, #s)}
            local rebuilt = string.char(unpack(bytes))
            assert(rebuilt == s)
        end)
        record("string.byte/char roundtrip (encoding building block)", okB)
    end
end

-- T7: Drag handling
local function testDragHandling()
    out("--- Drag Handling ---")

    local f = safeCreate("Frame", "IPVal_Drag")
    if not f then
        record("Drag test frame creation", false)
        return
    end
    f:SetSize(100, 50)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)

    -- RegisterForDrag
    local ok1 = pcall(function() f:RegisterForDrag("LeftButton") end)
    record("RegisterForDrag(LeftButton)", ok1)

    -- SetScript OnDragStart / OnDragStop
    local dragStartCalled = false
    local dragStopCalled = false
    local ok2 = pcall(function()
        f:SetScript("OnDragStart", function(self)
            dragStartCalled = true
            self:StartMoving()
        end)
        f:SetScript("OnDragStop", function(self)
            dragStopCalled = true
            self:StopMovingOrSizing()
        end)
    end)
    record("SetScript(OnDragStart/OnDragStop)", ok2)

    -- Verify scripts are set
    local ok3, hasDragStart = pcall(function() return f:GetScript("OnDragStart") ~= nil end)
    record("GetScript(OnDragStart) returns handler", ok3 and hasDragStart)

    -- RegisterForClicks (needed for buttons)
    local btn = safeCreate("Button", "IPVal_DragBtn")
    if btn then
        local ok4 = pcall(function() btn:RegisterForClicks("AnyUp") end)
        record("Button:RegisterForClicks(AnyUp)", ok4)
    end

    -- SetClampedToScreen (prevents dragging off screen)
    local ok5 = pcall(function() f:SetClampedToScreen(true) end)
    record("SetClampedToScreen(true)", ok5)
end

-- T8: WoW game API calls (pcall-wrapped)
local function testGameAPIs()
    out("--- WoW Game APIs (pcall) ---")

    -- GetHaste
    local ok1, val1 = pcall(GetHaste)
    record("GetHaste()", ok1, "value=" .. tostring(val1))

    -- GetCritChance
    local ok2, val2 = pcall(GetCritChance)
    record("GetCritChance()", ok2, "value=" .. tostring(val2))

    -- GetMasteryEffect
    local ok3, val3 = pcall(GetMasteryEffect)
    record("GetMasteryEffect()", ok3, "value=" .. tostring(val3))

    -- UnitStat
    local ok4, val4 = pcall(UnitStat, "player", 1)
    record("UnitStat(player, 1) [Strength]", ok4, "value=" .. tostring(val4))

    -- GetSpecialization
    local ok5, val5 = pcall(GetSpecialization)
    record("GetSpecialization()", ok5, "specIndex=" .. tostring(val5))

    -- GetSpecializationInfo
    if ok5 and val5 then
        local ok6, id, name = pcall(GetSpecializationInfo, val5)
        record("GetSpecializationInfo()", ok6, "id=" .. tostring(id) .. " name=" .. tostring(name))
    end

    -- UnitLevel
    local ok7, lvl = pcall(UnitLevel, "player")
    record("UnitLevel(player)", ok7, "level=" .. tostring(lvl))

    -- UnitClass
    local ok8, cls, clsEn = pcall(UnitClass, "player")
    record("UnitClass(player)", ok8, "class=" .. tostring(cls))

    -- C_Timer.After
    local ok9 = pcall(function()
        C_Timer.After(0, function() end)
    end)
    record("C_Timer.After(0, fn)", ok9)

    -- GetCombatRating (versatility etc)
    local ok10, cr = pcall(function()
        return GetCombatRating(CR_VERSATILITY_DAMAGE_DONE or 29)
    end)
    record("GetCombatRating(Versatility)", ok10, "value=" .. tostring(cr))

    -- C_CurrencyInfo.GetCurrencyInfo (common data source)
    local ok11, cInfo = pcall(function()
        return C_CurrencyInfo.GetCurrencyInfo(1792) -- Honor
    end)
    record("C_CurrencyInfo.GetCurrencyInfo(1792)", ok11,
        ok11 and cInfo and ("name=" .. tostring(cInfo.name)) or tostring(cInfo))

    -- Nonexistent API (verifies error handling works)
    local ok12, err12 = pcall(function()
        return _G["ThisAPIDoesNotExist_12345"]()
    end)
    record("Nonexistent API error handling", not ok12,
        "Correctly caught error: " .. tostring(err12):sub(1, 60))
end

-- T9: ObjectiveTracker docking
local function testTrackerDocking()
    out("--- ObjectiveTracker Docking ---")

    -- Check ObjectiveTrackerFrame exists
    local hasOT = ObjectiveTrackerFrame ~= nil
    record("ObjectiveTrackerFrame exists", hasOT)

    if hasOT then
        -- GetWidth
        local ok1, w = pcall(function() return ObjectiveTrackerFrame:GetWidth() end)
        record("ObjectiveTrackerFrame:GetWidth()", ok1, "width=" .. tostring(w))

        -- Anchor a test frame to tracker
        local f = safeCreate("Frame", "IPVal_TrackerDock")
        if f then
            f:SetSize(200, 30)
            local ok2 = pcall(function()
                f:SetPoint("TOPRIGHT", ObjectiveTrackerFrame, "BOTTOMRIGHT", 0, -14)
            end)
            record("Anchor to ObjectiveTracker BOTTOMRIGHT", ok2)

            -- Chain anchor: second frame below first
            local f2 = safeCreate("Frame", "IPVal_TrackerDock2")
            if f2 then
                f2:SetSize(200, 30)
                local ok3 = pcall(function()
                    f2:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -14)
                end)
                record("Chain anchor (panel below panel)", ok3)
            end
        end
    end

    -- CouchPotatoShared.GetBaseTrackerAnchor
    if CP and CP.GetBaseTrackerAnchor then
        local ok4, anchor = pcall(CP.GetBaseTrackerAnchor)
        record("CouchPotatoShared.GetBaseTrackerAnchor()", ok4,
            "anchor=" .. tostring(anchor))
    else
        record("CouchPotatoShared.GetBaseTrackerAnchor()", false,
            "Not available — CP shared not loaded or function missing")
    end
end

-- T10: Misc APIs needed by editor/engine
local function testMiscAPIs()
    out("--- Misc Editor/Engine APIs ---")

    -- SetScript variants
    local f = safeCreate("Frame", "IPVal_Misc")
    if f then
        local ok1 = pcall(function()
            f:SetScript("OnShow", function() end)
            f:SetScript("OnHide", function() end)
            f:SetScript("OnUpdate", function() end)
            f:SetScript("OnEvent", function() end)
        end)
        record("SetScript(OnShow/OnHide/OnUpdate/OnEvent)", ok1)

        -- RegisterEvent / UnregisterEvent
        local ok2 = pcall(function()
            f:RegisterEvent("PLAYER_ENTERING_WORLD")
            f:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end)
        record("RegisterEvent/UnregisterEvent", ok2)

        -- Clear the OnUpdate so we don't waste cycles
        pcall(function() f:SetScript("OnUpdate", nil) end)
    end

    -- Tooltip APIs (for data display)
    local hasTooltip = GameTooltip ~= nil
    record("GameTooltip exists", hasTooltip)
    if hasTooltip then
        local ok3 = pcall(function()
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("IPValidate Test", 1, 1, 1)
            GameTooltip:AddDoubleLine("Left", "Right", 1, 1, 1, 0.5, 0.5, 0.5)
            GameTooltip:Hide()
        end)
        record("GameTooltip:AddLine/AddDoubleLine", ok3)
    end

    -- Slider (for editor numeric inputs)
    local slider = safeCreate("Slider", "IPVal_Slider", UIParent, "OptionsSliderTemplate")
    if slider then
        record("CreateFrame(Slider + OptionsSliderTemplate)", true)
        local ok4 = pcall(function()
            slider:SetMinMaxValues(0, 100)
            slider:SetValue(50)
            slider:SetValueStep(1)
        end)
        record("Slider:SetMinMaxValues/SetValue/SetValueStep", ok4)
    else
        -- Try without template
        local slider2 = safeCreate("Slider", "IPVal_Slider2")
        record("CreateFrame(Slider, no template)", slider2 ~= nil,
            "OptionsSliderTemplate not available")
    end

    -- CheckButton (for editor toggles)
    local cb = safeCreate("CheckButton", "IPVal_Check", UIParent, "UICheckButtonTemplate")
    if cb then
        record("CreateFrame(CheckButton + UICheckButtonTemplate)", true)
        local ok5 = pcall(function()
            cb:SetChecked(true)
            assert(cb:GetChecked() == true)
            cb:SetChecked(false)
        end)
        record("CheckButton:SetChecked/GetChecked", ok5)
    else
        record("CreateFrame(CheckButton + UICheckButtonTemplate)", false)
    end

    -- StatusBar (for progress display in panels)
    local sb = safeCreate("StatusBar", "IPVal_StatusBar")
    if sb then
        record("CreateFrame(StatusBar)", true)
        local ok6 = pcall(function()
            sb:SetMinMaxValues(0, 100)
            sb:SetValue(75)
            sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            sb:SetStatusBarColor(0.2, 0.8, 0.2, 1)
        end)
        record("StatusBar:SetMinMaxValues/SetValue/SetStatusBarTexture", ok6)
    end

    -- tinsert / tremove / wipe (Lua table APIs used heavily)
    local ok7 = pcall(function()
        local t = {}
        tinsert(t, "a")
        tinsert(t, "b")
        tremove(t, 1)
        assert(t[1] == "b")
        wipe(t)
        assert(#t == 0)
    end)
    record("tinsert/tremove/wipe", ok7)

    -- strsplit / strjoin (WoW string utilities)
    local ok8 = pcall(function()
        local a, b, c = strsplit(",", "hello,world,test")
        assert(a == "hello" and b == "world" and c == "test")
        local joined = strjoin(",", a, b, c)
        assert(joined == "hello,world,test")
    end)
    record("strsplit/strjoin", ok8)

    -- date/time (for versioning)
    local ok9, ts = pcall(function() return time() end)
    record("time()", ok9, "timestamp=" .. tostring(ts))

    local ok10, d = pcall(function() return date("%Y-%m-%d %H:%M:%S") end)
    record("date()", ok10, "date=" .. tostring(d))
end

-------------------------------------------------------------------------------
-- PHASE 2: Engine Core Validation Tests
-------------------------------------------------------------------------------

-- T11: Panel creation from a definition table
local function testPanelCreation()
    out("--- Panel Creation from Definition ---")

    local PanelEngine = ns.PanelEngine
    if not PanelEngine then
        record("PanelEngine available", false, "ns.PanelEngine is nil")
        return
    end
    record("PanelEngine available", true)

    -- Create a simple panel from definition
    local testDef = {
        id = "_ipv_test_panel",
        title = "Validation Test Panel",
        layout = "vertical",
        bindings = {
            { sourceId = "player.name", label = "Name" },
            { sourceId = "player.level", label = "Level" },
        },
        events = { "PLAYER_ENTERING_WORLD" },
    }

    local panel, err = PanelEngine.CreatePanel(testDef, {})
    record("CreatePanel from definition", panel ~= nil,
        panel and "created" or ("failed: " .. tostring(err)))

    if panel then
        -- Verify panel has expected fields
        record("Panel has .frame", panel.frame ~= nil)
        record("Panel has .contentFrame", panel.contentFrame ~= nil)
        record("Panel has .definition", panel.definition ~= nil)
        record("Panel has .id", panel.id == "_ipv_test_panel")

        -- Clean up
        PanelEngine.DestroyPanel("_ipv_test_panel")
        record("DestroyPanel cleanup", PanelEngine.GetPanel("_ipv_test_panel") == nil)
    end

    -- Test bad definition
    local badPanel, badErr = PanelEngine.CreatePanel({ title = "No ID" }, {})
    record("Reject definition with no id", badPanel == nil and badErr ~= nil,
        "err=" .. tostring(badErr))

    local badPanel2, badErr2 = PanelEngine.CreatePanel({ id = "", title = "" }, {})
    record("Reject definition with empty id", badPanel2 == nil,
        "err=" .. tostring(badErr2))
end

-- T12: Data source binding and refresh
local function testDataBinding()
    out("--- Data Source Binding & Refresh ---")

    local DataSources = ns.DataSources
    if not DataSources then
        record("DataSources available", false)
        return
    end
    record("DataSources available", true)

    -- Fetch a registered source
    local val, err = DataSources.Fetch("player.name")
    record("Fetch player.name", val ~= nil or err ~= nil,
        "val=" .. tostring(val) .. " err=" .. tostring(err))

    -- Fetch unknown source
    local val2, err2 = DataSources.Fetch("nonexistent.source.xyz")
    record("Fetch unknown source returns error", err2 ~= nil,
        "err=" .. tostring(err2))

    -- Register and fetch a dynamic source
    DataSources.RegisterDynamic("_ipv_dynamic_test", "UnitLevel", { "player" }, {
        name = "Test Dynamic Level",
        category = "Validation",
    })
    local dynVal, dynErr = DataSources.Fetch("_ipv_dynamic_test")
    record("Dynamic source registration + fetch", dynVal ~= nil or dynErr ~= nil,
        "val=" .. tostring(dynVal) .. " err=" .. tostring(dynErr))

    -- FetchDynamic for arbitrary API
    local dVal, dErr = DataSources.FetchDynamic("UnitLevel", "player")
    record("FetchDynamic(UnitLevel, player)", dVal ~= nil or dErr ~= nil,
        "val=" .. tostring(dVal) .. " err=" .. tostring(dErr))

    -- FetchDynamic for missing API
    local mVal, mErr = DataSources.FetchDynamic("NonExistentAPI_12345")
    record("FetchDynamic missing API", mErr ~= nil and mErr:find("unavailable"),
        "err=" .. tostring(mErr))

    -- FetchDynamic for nil-returning API
    local nVal, nErr = DataSources.FetchDynamic("C_DelvesUI.GetActiveCompanion")
    record("FetchDynamic nil return shows No data", nErr == nil or nErr:find("No data") or nVal ~= nil,
        "val=" .. tostring(nVal) .. " err=" .. tostring(nErr))
end

-- T13: API discovery/search
local function testAPIDiscovery()
    out("--- API Discovery & Search ---")

    local DataSources = ns.DataSources
    if not DataSources then
        record("DataSources available for discovery", false)
        return
    end

    -- Search registered sources
    local results = DataSources.Search("haste")
    record("Search('haste') finds results", #results > 0,
        "found " .. #results .. " sources")

    -- Search with empty string
    local empty = DataSources.Search("")
    record("Search('') returns empty", #empty == 0)

    -- GetCategories
    local cats = DataSources.GetCategories()
    record("GetCategories returns list", #cats > 0,
        "categories: " .. #cats)

    -- GetSourcesInCategory
    local statSources = DataSources.GetSourcesInCategory("Player Stats")
    record("GetSourcesInCategory('Player Stats')", #statSources > 0,
        "found " .. #statSources .. " sources")

    -- DiscoverAPIs (namespace search)
    local discovered = DataSources.DiscoverAPIs("UnitLevel")
    record("DiscoverAPIs('UnitLevel')", #discovered > 0,
        "found " .. #discovered .. " API matches")

    -- DiscoverAPIs for C_ namespace
    local cDiscovered = DataSources.DiscoverAPIs("GetCurrencyInfo")
    record("DiscoverAPIs('GetCurrencyInfo') C_ namespace", #cDiscovered > 0,
        "found " .. #cDiscovered .. " matches")
end

-- T14: Event subscription
local function testEventSubscription()
    out("--- Event Subscription ---")

    local PanelEngine = ns.PanelEngine
    if not PanelEngine then
        record("PanelEngine for events", false)
        return
    end

    local testDef = {
        id = "_ipv_event_panel",
        title = "Event Test",
        layout = "vertical",
        bindings = { { sourceId = "player.level", label = "Level" } },
        events = { "PLAYER_ENTERING_WORLD", "UNIT_STATS" },
    }

    local panel = PanelEngine.CreatePanel(testDef, {})
    if panel then
        record("Event panel created", true)
        record("Event frame exists", panel._eventFrame ~= nil)
        if panel._eventFrame then
            local hasEvent = panel._eventFrame.IsEventRegistered
                and panel._eventFrame:IsEventRegistered("PLAYER_ENTERING_WORLD")
            record("PLAYER_ENTERING_WORLD registered", hasEvent)
        end
        PanelEngine.DestroyPanel("_ipv_event_panel")
    else
        record("Event panel created", false)
    end
end

-- T15: Visibility conditions
local function testVisibilityConditions()
    out("--- Visibility Conditions ---")

    local PanelEngine = ns.PanelEngine
    if not PanelEngine then
        record("PanelEngine for visibility", false)
        return
    end

    -- Always visible (no conditions)
    local vis1 = PanelEngine.CheckVisibility({ visibility = nil })
    record("No visibility = always visible", vis1 == true)

    -- Empty conditions = visible
    local vis2 = PanelEngine.CheckVisibility({ visibility = { conditions = {} } })
    record("Empty conditions = visible", vis2 == true)

    -- Type = "always"
    local vis3 = PanelEngine.CheckVisibility({
        visibility = { conditions = { { type = "always" } } }
    })
    record("type=always => visible", vis3 == true)

    -- Type = "never"
    local vis4 = PanelEngine.CheckVisibility({
        visibility = { conditions = { { type = "never" } } }
    })
    record("type=never => hidden", vis4 == false)

    -- Source-based truthy (player.name should be truthy in game)
    local vis5 = PanelEngine.CheckVisibility({
        visibility = { conditions = { { sourceId = "player.name", operator = "truthy" } } }
    })
    record("sourceId truthy condition", type(vis5) == "boolean",
        "result=" .. tostring(vis5))
end

-- T16: Panel show/hide/collapse/pin/unpin/drag
local function testPanelUIOperations()
    out("--- Panel Show/Hide/Collapse/Pin/Unpin/Drag ---")

    local PanelEngine = ns.PanelEngine
    if not PanelEngine then
        record("PanelEngine for UI ops", false)
        return
    end

    local testDef = {
        id = "_ipv_ui_panel",
        title = "UI Ops Test",
        layout = "vertical",
        bindings = { { sourceId = "player.level", label = "Level" } },
    }

    local panel = PanelEngine.CreatePanel(testDef, {})
    if not panel then
        record("UI ops panel creation", false)
        return
    end

    -- Show
    PanelEngine.ShowPanel("_ipv_ui_panel")
    record("ShowPanel", panel.frame and panel.frame:IsShown())

    -- Hide
    PanelEngine.HidePanel("_ipv_ui_panel")
    record("HidePanel", panel.frame and not panel.frame:IsShown())

    -- Toggle (should show)
    PanelEngine.TogglePanel("_ipv_ui_panel")
    record("TogglePanel (show)", panel.frame and panel.frame:IsShown())

    -- Collapse
    if panel.SetCollapsed then
        panel.SetCollapsed(true)
        record("SetCollapsed(true)", panel._db.collapsed or not panel.contentFrame:IsShown())

        panel.SetCollapsed(false)
        record("SetCollapsed(false)", panel.contentFrame:IsShown())
    else
        record("SetCollapsed function", false, "not available")
    end

    -- Pin (dock to tracker)
    if panel.ApplyPinnedState then
        local okPin = pcall(panel.ApplyPinnedState)
        record("ApplyPinnedState", okPin)
        record("Pinned state stored", panel._db.pinned == true)
    end

    -- Unpin (make draggable)
    if panel.ApplyUnpinnedState then
        local okUnpin = pcall(panel.ApplyUnpinnedState)
        record("ApplyUnpinnedState", okUnpin)
        record("Unpinned state stored", panel._db.pinned == false)
    end

    -- Drag support (verify frame is movable when unpinned)
    record("Frame movable when unpinned", panel.frame and panel.frame:IsMovable())

    PanelEngine.DestroyPanel("_ipv_ui_panel")
end

-- T17: Position persistence
local function testPositionPersistence()
    out("--- Position Persistence ---")

    local PanelEngine = ns.PanelEngine
    if not PanelEngine then
        record("PanelEngine for position", false)
        return
    end

    local db = { pinned = false, position = { point = "CENTER", relativePoint = "CENTER", x = 100, y = -50 } }
    local testDef = {
        id = "_ipv_pos_panel",
        title = "Position Test",
        layout = "vertical",
        bindings = {},
    }

    local panel = PanelEngine.CreatePanel(testDef, db)
    if not panel then
        record("Position panel creation", false)
        return
    end

    -- Restore should apply saved position
    record("DB position preserved", db.position ~= nil and db.position.x == 100)

    -- Reset should clear position
    PanelEngine.ResetPanel("_ipv_pos_panel")
    record("ResetPanel clears position", db.position == nil)

    PanelEngine.DestroyPanel("_ipv_pos_panel")
end

-- T18: Schema validation
local function testSchemaValidation()
    out("--- Schema Validation ---")

    local PanelEngine = ns.PanelEngine
    if not PanelEngine or not PanelEngine.ValidateDefinition then
        record("ValidateDefinition available", false)
        return
    end
    record("ValidateDefinition available", true)

    -- Valid definition
    local ok1, err1 = PanelEngine.ValidateDefinition({
        id = "test", title = "Test", layout = "vertical",
        bindings = { { sourceId = "player.name", label = "Name" } },
    })
    record("Valid definition passes", ok1 == true and err1 == nil)

    -- Missing id
    local ok2, err2 = PanelEngine.ValidateDefinition({ title = "No ID" })
    record("Missing id fails", ok2 == false and err2 ~= nil)

    -- Invalid layout
    local ok3, err3 = PanelEngine.ValidateDefinition({
        id = "test", title = "Test", layout = "invalid_layout"
    })
    record("Invalid layout fails", ok3 == false)

    -- Invalid binding (no sourceId)
    local ok4, err4 = PanelEngine.ValidateDefinition({
        id = "test", title = "Test",
        bindings = { { label = "No Source" } },
    })
    record("Binding without sourceId fails", ok4 == false)

    -- Too many bindings
    local manyBindings = {}
    for i = 1, 51 do manyBindings[i] = { sourceId = "s" .. i } end
    local ok5, err5 = PanelEngine.ValidateDefinition({
        id = "test", title = "Test", bindings = manyBindings,
    })
    record("Excess bindings fails", ok5 == false)

    -- Non-table definition
    local ok6, err6 = PanelEngine.ValidateDefinition("not a table")
    record("Non-table definition fails", ok6 == false)

    -- Valid visibility conditions
    local ok7, err7 = PanelEngine.ValidateDefinition({
        id = "test", title = "Test",
        visibility = { conditions = { { type = "always" } } },
    })
    record("Valid visibility passes", ok7 == true)

    -- Invalid visibility condition
    local ok8, err8 = PanelEngine.ValidateDefinition({
        id = "test", title = "Test",
        visibility = { conditions = { { } } },
    })
    record("Empty visibility condition fails", ok8 == false)
end

-- T19: Error handling for bad definitions, nil API returns, missing APIs
local function testErrorHandling()
    out("--- Error Handling ---")

    local PanelEngine = ns.PanelEngine
    local DataSources = ns.DataSources

    -- CreatePanel with nil
    local p1, e1 = PanelEngine.CreatePanel(nil, {})
    record("CreatePanel(nil) returns nil + error", p1 == nil and e1 ~= nil)

    -- CreatePanel with non-table
    local p2, e2 = PanelEngine.CreatePanel("string", {})
    record("CreatePanel(string) returns nil + error", p2 == nil and e2 ~= nil)

    -- DataSources.Fetch with unknown source
    if DataSources then
        local v1, err1 = DataSources.Fetch("completely.unknown.source")
        record("Fetch unknown returns error", err1 ~= nil,
            "err=" .. tostring(err1))

        -- FetchDynamic with empty path
        local v2, err2 = DataSources.FetchDynamic("")
        record("FetchDynamic empty path", err2 ~= nil)

        -- FetchDynamic with non-function
        local v3, err3 = DataSources.FetchDynamic("math")
        record("FetchDynamic non-function", err3 ~= nil and err3:find("not a function"),
            "err=" .. tostring(err3))
    end
end

-- T20: Registry Pattern Validation
local function testRegistryPattern()
    out("--- Registry Pattern ---")

    local Registry = ns.Registry
    if not Registry then
        record("Registry module available", false)
        return
    end
    record("Registry module available", true)

    -- Panel type registration
    record("Registry.HasPanelType exists", type(Registry.HasPanelType) == "function")
    record("vertical_list panel type registered", Registry.HasPanelType("vertical_list"))
    record("circle_row panel type registered", Registry.HasPanelType("circle_row"))
    record("multi_section panel type registered", Registry.HasPanelType("multi_section"))
    record("simple_info panel type registered", Registry.HasPanelType("simple_info"))

    -- Layout type registration
    record("Registry.HasLayoutType exists", type(Registry.HasLayoutType) == "function")
    record("vertical_list layout type registered", Registry.HasLayoutType("vertical_list"))
    record("circle_row layout type registered", Registry.HasLayoutType("circle_row"))
    record("multi_section layout type registered", Registry.HasLayoutType("multi_section"))

    -- Data source registration
    record("Registry.HasDataSourceType exists", type(Registry.HasDataSourceType) == "function")

    -- Panel type structure
    local vtType = Registry.GetPanelType("vertical_list")
    record("vertical_list has create function", vtType and type(vtType.create) == "function")
    record("vertical_list has modify function", vtType and type(vtType.modify) == "function")
    record("vertical_list has default table", vtType and type(vtType.default) == "table")
    record("vertical_list has properties table", vtType and type(vtType.properties) == "table")

    local crType = Registry.GetPanelType("circle_row")
    record("circle_row has create function", crType and type(crType.create) == "function")
    record("circle_row has modify function", crType and type(crType.modify) == "function")
end

-- T20b: Built-In Panel Registration Validation
local function testBuiltInPanelRegistration()
    out("--- Built-In Panel Type Registration ---")

    local PanelEngine = ns.PanelEngine
    if not PanelEngine then
        record("PanelEngine available for builtin test", false)
        return
    end

    -- StatPriority
    local SPPanel = ns.StatPriorityPanel
    record("StatPriorityPanel module loaded", SPPanel ~= nil)
    if SPPanel then
        local def = SPPanel.GetDefinition()
        record("SP definition is table", type(def) == "table")
        record("SP id='stat_priority'", def.id == "stat_priority")
        record("SP is builtin", def.builtin == true)
        record("SP panelType='circle_row'", def.panelType == "circle_row")
        record("SP has NO customRender (pure data)", def.customRender == nil)
        record("SP has NO customUpdate (pure data)", def.customUpdate == nil)
        record("SP has stats array", type(def.stats) == "table")
        record("SP has events", type(def.events) == "table" and #def.events > 0)
        record("SP has marketplace description", type(def.description) == "string")
        record("SP has marketplace author", type(def.author) == "string")
        record("SP has marketplace tags", type(def.tags) == "table" and #def.tags > 0)
        record("SP has uid", type(def.uid) == "string")
        record("SP has dataEntry", type(def.dataEntry) == "table")
        if type(def.dataEntry) == "table" then
            record("SP dataEntry has paste_box", def.dataEntry[1] and def.dataEntry[1].type == "paste_box")
            record("SP dataEntry has drag_reorder", def.dataEntry[2] and def.dataEntry[2].type == "drag_reorder")
        end

        local valid, vErrors = PanelEngine.ValidateDefinition(def)
        record("SP passes schema validation", valid,
            not valid and vErrors and table.concat(vErrors, "; ") or nil)

        -- Create and test panel lifecycle
        local db = {}
        local panel, err = PanelEngine.CreatePanel(def, db)
        record("SP panel creation succeeds", panel ~= nil,
            not panel and ("err=" .. tostring(err)) or nil)
        if panel then
            record("SP panel has frame", panel.frame ~= nil)
            record("SP panel has contentFrame", panel.contentFrame ~= nil)
            record("SP panel has _region (registry-created)", panel._region ~= nil)

            local okUpdate = pcall(PanelEngine.UpdatePanel, "stat_priority")
            record("SP UpdatePanel succeeds", okUpdate)

            PanelEngine.ShowPanel("stat_priority")
            record("SP ShowPanel works", panel.frame:IsShown())
            PanelEngine.HidePanel("stat_priority")
            record("SP HidePanel works", not panel.frame:IsShown())

            PanelEngine.DestroyPanel("stat_priority")
            record("SP destroy works", PanelEngine.GetPanel("stat_priority") == nil)
        end
    end

    -- DelveCompanionStats
    local DCSPanel = ns.DelveCompanionStatsPanel
    record("DelveCompanionStatsPanel module loaded", DCSPanel ~= nil)
    if DCSPanel then
        local def = DCSPanel.GetDefinition()
        record("DCS panelType='multi_section'", def.panelType == "multi_section")
        record("DCS has sections", type(def.sections) == "table" and #def.sections > 0)
        record("DCS has NO customRender", def.customRender == nil)
        record("DCS has visibility conditions", def.visibility and def.visibility.conditions ~= nil)
        record("DCS has marketplace metadata", def.description ~= nil and def.author ~= nil)

        local valid = PanelEngine.ValidateDefinition(def)
        record("DCS passes schema validation", valid)
    end

    -- DelversJourney
    local DJPanel = ns.DelversJourneyPanel
    record("DelversJourneyPanel module loaded", DJPanel ~= nil)
    if DJPanel then
        local def = DJPanel.GetDefinition()
        record("DJ panelType='simple_info'", def.panelType == "simple_info")
        record("DJ has rows", type(def.rows) == "table" and #def.rows > 0)
        record("DJ has NO customRender", def.customRender == nil)
        record("DJ has marketplace metadata", def.description ~= nil and def.author ~= nil)

        local valid = PanelEngine.ValidateDefinition(def)
        record("DJ passes schema validation", valid)
    end

    -- Verify StatPriorityData is loaded
    record("StatPriorityData global loaded", _G.StatPriorityData ~= nil)
    if _G.StatPriorityData then
        local specCount = 0
        for _ in pairs(_G.StatPriorityData) do specCount = specCount + 1 end
        record("SP data has all specs", specCount >= 36, "specCount=" .. tostring(specCount))
    end
end

-- T20c: Built-In Panel Export/Import Roundtrip
local function testBuiltInExportImport()
    out("--- Built-In Panel Export/Import Roundtrip ---")

    local ProfileCodec = ns.ProfileCodec
    local PanelEngine = ns.PanelEngine
    if not ProfileCodec or not PanelEngine then
        record("ProfileCodec + PanelEngine available", false)
        return
    end

    local panels = {
        { name = "StatPriority", getter = ns.StatPriorityPanel },
        { name = "DelveCompanionStats", getter = ns.DelveCompanionStatsPanel },
        { name = "DelversJourney", getter = ns.DelversJourneyPanel },
    }

    for _, p in ipairs(panels) do
        if p.getter then
            local def = p.getter.GetDefinition()
            local str, err = ProfileCodec.Export(def)
            record(p.name .. " export succeeds", str ~= nil, err)
            if str then
                record(p.name .. " string starts with !IP:", str:sub(1, 4) == "!IP:")
                local imported, err2 = ProfileCodec.Import(str)
                record(p.name .. " import succeeds", imported ~= nil, err2)
                if imported then
                    record(p.name .. " roundtrip id matches", imported.id == def.id)
                    record(p.name .. " roundtrip title matches", imported.title == def.title)
                    record(p.name .. " roundtrip panelType matches", imported.panelType == def.panelType)
                    -- Marketplace metadata preserved
                    record(p.name .. " roundtrip description preserved", imported.description == def.description)
                    record(p.name .. " roundtrip author preserved", imported.author == def.author)
                    record(p.name .. " roundtrip tags preserved",
                        type(imported.tags) == "table" and #imported.tags == #(def.tags or {}))
                    record(p.name .. " roundtrip uid preserved", imported.uid == def.uid)
                end
            end
        end
    end
end

-- T20d: Built-In Panel Deletion and Re-Import
local function testBuiltInDeletion()
    out("--- Built-In Panel Deletion + Re-Import ---")

    local PanelEngine = ns.PanelEngine
    local ProfileCodec = ns.ProfileCodec
    if not PanelEngine or not ProfileCodec then
        record("PanelEngine + ProfileCodec available for deletion test", false)
        return
    end

    -- Create a built-in panel
    local def = ns.DelversJourneyPanel and ns.DelversJourneyPanel.GetDefinition()
    if not def then
        record("DJ definition available for deletion test", false)
        return
    end

    _G.InfoPanelsDB = _G.InfoPanelsDB or {}
    _G.InfoPanelsDB.deletedBuiltins = _G.InfoPanelsDB.deletedBuiltins or {}

    local db = {}
    PanelEngine.CreatePanel(def, db)
    record("DJ panel created for deletion test", PanelEngine.GetPanel("delvers_journey") ~= nil)

    -- Delete it
    PanelEngine.DestroyPanel("delvers_journey")
    _G.InfoPanelsDB.deletedBuiltins["delvers_journey"] = true
    record("DJ deleted", PanelEngine.GetPanel("delvers_journey") == nil)
    record("DJ tracked in deletedBuiltins", _G.InfoPanelsDB.deletedBuiltins["delvers_journey"] == true)

    -- Simulate reload: skip deleted builtins
    local shouldSkip = _G.InfoPanelsDB.deletedBuiltins[def.id] == true
    record("DJ would be skipped on reload", shouldSkip)

    -- Re-import via string
    local str = ProfileCodec.Export(def)
    if str then
        local imported = ProfileCodec.Import(str)
        if imported then
            imported.builtin = false  -- imported panels are not builtin
            local reimportDb = {}
            PanelEngine.CreatePanel(imported, reimportDb)
            record("DJ re-imported successfully", PanelEngine.GetPanel(imported.id) ~= nil)

            -- Clean up
            PanelEngine.DestroyPanel(imported.id)

            -- Remove from deletedBuiltins to allow re-creation
            _G.InfoPanelsDB.deletedBuiltins["delvers_journey"] = nil
        else
            record("DJ re-import from string", false, "import failed")
        end
    else
        record("DJ export for re-import", false, "export failed")
    end
end

-- T20e: Docking Chain Validation
local function testDockingChain()
    out("--- Docking Chain with Multiple Panels ---")

    local PanelEngine = ns.PanelEngine
    if not PanelEngine then
        record("PanelEngine available for docking test", false)
        return
    end

    -- Create multiple panels with different heights
    local panels = {}
    for i = 1, 3 do
        local def = {
            id = "_ipv_dock_" .. i,
            title = "Dock Test " .. i,
            bindings = { { sourceId = "player.name", label = "Name" } },
        }
        local db = { pinned = true }
        local p = PanelEngine.CreatePanel(def, db)
        record("Dock panel " .. i .. " created", p ~= nil)
        if p then
            PanelEngine.ShowPanel(def.id)
            panels[i] = p
        end
    end

    -- Trigger chain rebuild
    PanelEngine.RebuildChain()

    -- Verify TOPRIGHT->BOTTOMRIGHT anchoring (panels are positioned)
    for i, p in ipairs(panels) do
        if p.frame then
            local point = p.frame:GetPoint(1)
            record("Dock panel " .. i .. " uses TOPRIGHT anchor", point == "TOPRIGHT")
        end
    end

    -- Cleanup
    for i = 1, 3 do
        PanelEngine.DestroyPanel("_ipv_dock_" .. i)
    end
end

-- T21: External Data Source Validation
local function testExternalDataSources()
    out("--- External Data Sources ---")

    local DataSources = ns.DataSources
    if not DataSources or not DataSources.RegisterExternal then
        record("DataSources.RegisterExternal available", false)
        return
    end
    record("DataSources.RegisterExternal available", true)

    -- Register an external source
    local storage = {}
    DataSources.RegisterExternal("_ipv_ext_test", {
        name = "Test External Data",
        category = "Validation",
        description = "Test external data source",
        dataEntry = { type = "paste_box", format = "text" },
        storage = storage,
        storageKey = "testVal",
    })

    local source = DataSources.Get("_ipv_ext_test")
    record("External source registered", source ~= nil)
    record("External source marked external", source and source.external == true)
    record("External source has dataEntry", source and source.dataEntry ~= nil)
    record("External source has store function", source and type(source.store) == "function")

    -- Fetch before storing (should return "No data entered")
    local val1, err1 = DataSources.Fetch("_ipv_ext_test")
    record("External fetch before store returns nil", val1 == nil and err1 ~= nil,
        "err=" .. tostring(err1))

    -- Store a value
    local storeOk, storeErr = DataSources.StoreExternal("_ipv_ext_test", "test data from archon")
    record("StoreExternal succeeds", storeOk == true)

    -- Fetch after storing
    local val2, err2 = DataSources.Fetch("_ipv_ext_test")
    record("External fetch after store returns value", val2 == "test data from archon",
        "val=" .. tostring(val2))

    -- StoreExternal on non-external source should fail
    local badOk, badErr = DataSources.StoreExternal("player.name", "override")
    record("StoreExternal on non-external fails", badOk == false,
        "err=" .. tostring(badErr))

    -- StoreExternal on unknown source should fail
    local unkOk, unkErr = DataSources.StoreExternal("nonexistent.xyz", "data")
    record("StoreExternal on unknown fails", unkOk == false)
end

-------------------------------------------------------------------------------
-- MAIN RUNNER
-------------------------------------------------------------------------------
local function runAllValidation()
    wipe(results)
    wipe(cleanupFrames)

    out("========================================")
    out("InfoPanels API Validation -- Phase 1 + Phase 2 + Phase 3A (Registry)")
    out("========================================")

    -- Phase 1 tests
    testFrameCreation()
    testLayoutAPIs()
    testTextureFont()
    testScrollEditBox()
    testDropdownAPIs()
    testCompression()
    testDragHandling()
    testGameAPIs()
    testTrackerDocking()
    testMiscAPIs()

    -- Phase 2: Engine Core tests
    out("")
    out("========================================")
    out("Phase 2: Engine Core Validation")
    out("========================================")
    testPanelCreation()
    testDataBinding()
    testAPIDiscovery()
    testEventSubscription()
    testVisibilityConditions()
    testPanelUIOperations()
    testPositionPersistence()
    testSchemaValidation()
    testErrorHandling()

    -- Phase 3A: Registry + Built-In Panel tests
    out("")
    out("========================================")
    out("Phase 3A: Registry + Built-In Panel Validation")
    out("========================================")
    testRegistryPattern()
    testBuiltInPanelRegistration()
    testBuiltInExportImport()
    testBuiltInDeletion()
    testDockingChain()
    testExternalDataSources()

    -- Summary
    local passed = 0
    local failed = 0
    for _, r in ipairs(results) do
        if r.passed then passed = passed + 1 else failed = failed + 1 end
    end

    out("========================================")
    out("SUMMARY: " .. passed .. " PASS / " .. failed .. " FAIL (total " .. #results .. ")")
    if failed == 0 then
        out("All API validations passed! Safe to build framework.")
    else
        out("Some validations failed. Review before proceeding.")
        out("Failed tests:")
        for _, r in ipairs(results) do
            if not r.passed then
                out("  FAIL: " .. r.name .. (r.detail and (" -- " .. r.detail) or ""))
            end
        end
    end
    out("========================================")

    -- Cleanup all test frames
    cleanup()
    out("Test frames cleaned up.")
end

-------------------------------------------------------------------------------
-- SLASH COMMAND
-------------------------------------------------------------------------------
SLASH_IPVALIDATE1 = "/ipvalidate"
SLASH_IPVALIDATE2 = "/ipv"
SlashCmdList["IPVALIDATE"] = function(msg)
    runAllValidation()
end

-- Register so addon load is visible
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == addonName or loadedAddon == "InfoPanels" then
        out("Loaded. Type /ipvalidate or /ipv to run API validation (output goes to debug log).")
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
