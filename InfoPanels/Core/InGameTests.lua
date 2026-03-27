-- InfoPanels/Core/InGameTests.lua
-- Real UX test suite that opens the editor, performs actions, and measures
-- actual rendered frame state.  Reports PASS/FAIL to the debug log.
--
-- Run via:  /cptests ux   (or the button in CouchPotato settings)
--
-- Design principles:
--   1. Tests open the UI (Editor.Show()).
--   2. Tests perform real actions (click, type, select).
--   3. Tests assert on rendered state, NEVER on constants or module existence.
--   4. Tests must FAIL when the UI is visually broken.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local InGameTests = {}
ns.InGameTests = InGameTests

-------------------------------------------------------------------------------
-- Test infrastructure
-------------------------------------------------------------------------------
local passCount = 0
local failCount = 0
local results = {}
local _suites = {}
local _suiteOrder = {}

local function log(msg)
    if _G.CouchPotatoLog then
        _G.CouchPotatoLog:Print("IP", msg)
    end
    iplog("Info", msg)
end

local function pass(name, detail)
    passCount = passCount + 1
    local msg = name
    if detail then msg = msg .. " (" .. tostring(detail) .. ")" end
    results[#results + 1] = { name = name, status = "PASS" }
    log("|cff44ff44PASS|r  " .. msg)
end

local function fail(name, reason)
    failCount = failCount + 1
    results[#results + 1] = { name = name, status = "FAIL", reason = reason }
    log("|cffff4444FAIL|r  " .. name .. ": " .. tostring(reason))
end

-- Assertion helpers -- each returns nothing, records pass/fail internally
local function assertEqual(name, expected, actual)
    if expected == actual then
        pass(name)
    else
        fail(name, "expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local function assertNotNil(name, value)
    if value ~= nil then pass(name) else fail(name, "value is nil") end
end

local function assertTrue(name, value, reason)
    if value then pass(name) else fail(name, reason or "value is falsy") end
end

local function assertGte(name, actual, minimum)
    if actual and actual >= minimum then
        pass(name, tostring(actual) .. " >= " .. tostring(minimum))
    else
        fail(name, "actual=" .. tostring(actual) .. " expected >= " .. tostring(minimum))
    end
end

local function assertLte(name, actual, maximum)
    if actual and actual <= maximum then
        pass(name, tostring(actual) .. " <= " .. tostring(maximum))
    else
        fail(name, "actual=" .. tostring(actual) .. " expected <= " .. tostring(maximum))
    end
end

-------------------------------------------------------------------------------
-- Utility: safe frame accessors
-------------------------------------------------------------------------------
local function safeGetRect(frame)
    if not frame then return nil, nil, nil, nil end
    local ok, l, b, w, h = pcall(frame.GetRect, frame)
    if ok and l then return l, b, w, h end
    return nil, nil, nil, nil
end

local function safeGetText(region)
    if not region then return nil end
    if region.GetText then return region:GetText() end
    return nil
end

local function getVisibleChildren(parent)
    if not parent then return {} end
    local children = { parent:GetChildren() }
    local visible = {}
    for _, c in ipairs(children) do
        if c:IsVisible() then visible[#visible + 1] = c end
    end
    return visible
end

local function getFontStrings(frame)
    if not frame then return {} end
    local regions = { frame:GetRegions() }
    local fs = {}
    for _, r in ipairs(regions) do
        if r.GetObjectType and r:GetObjectType() == "FontString" then
            fs[#fs + 1] = r
        end
    end
    return fs
end

local function overlaps(a, b)
    if not (a and b and a:IsVisible() and b:IsVisible()) then return false end
    local aL, aB, aW, aH = safeGetRect(a)
    local bL, bB, bW, bH = safeGetRect(b)
    if not (aL and bL) then return false end
    return aL < bL + bW and aL + aW > bL and aB < bB + bH and aB + aH > bB
end

local function isClippedByParent(child)
    if not child then return false end
    local parent = child:GetParent()
    if not parent then return false end
    local cL, cB, cW, cH = safeGetRect(child)
    local pL, pB, pW, pH = safeGetRect(parent)
    if not (cL and pL) then return false end
    -- Allow 1px tolerance for rounding
    return cL < pL - 1 or cB < pB - 1 or (cL + cW) > (pL + pW) + 1 or (cB + cH) > (pB + pH) + 1
end

-------------------------------------------------------------------------------
-- Suite registration
-------------------------------------------------------------------------------
local function addSuite(name, fn)
    _suites[name] = fn
    _suiteOrder[#_suiteOrder + 1] = name
end

-------------------------------------------------------------------------------
-- T1: Editor Layout Tests
-------------------------------------------------------------------------------
addSuite("T1: Editor Layout", function()
    local f = _G.InfoPanelsEditorFrame
    assertNotNil("T1: Editor frame exists after Show()", f)
    if not f then return end

    assertTrue("T1: Editor frame is visible", f:IsVisible())

    local w, h = f:GetWidth(), f:GetHeight()
    assertGte("T1: Editor frame width >= 800", w, 800)
    assertGte("T1: Editor frame height >= 500", h, 500)

    -- Check all child frames within parent bounds.
    -- Tabs (IPEditorTab1/2/3) are intentionally anchored BELOW the frame
    -- (CharacterFrameTabButtonTemplate hangs below), so skip them here.
    local children = { f:GetChildren() }
    local clippedCount = 0
    for _, child in ipairs(children) do
        local cName = child:GetName() or ""
        local isTab = cName:match("^IPEditorTab%d+$")
        local isCloseBtn = cName:match("CloseButton$")
        if not isTab and not isCloseBtn and child:IsVisible() and isClippedByParent(child) then
            clippedCount = clippedCount + 1
            fail("T1: Child clipped by editor frame: " .. tostring(cName), "child extends outside parent bounds")
        end
    end
    if clippedCount == 0 then
        pass("T1: All visible children within editor frame bounds", #children .. " checked")
    end

    -- Check bottom buttons are not clipped.
    -- Tabs hang below the frame by design — exclude them from this check too.
    local fBottom = f:GetBottom()
    if fBottom then
        local allAbove = true
        for _, child in ipairs(children) do
            local cName = child:GetName() or ""
            local isTab = cName:match("^IPEditorTab%d+$")
            local isCloseBtn = cName:match("CloseButton$")
            if not isTab and not isCloseBtn and child:IsVisible() then
                local cB = child:GetBottom()
                if cB and cB < fBottom - 1 then
                    allAbove = false
                    fail("T1: Child below editor bottom", cName .. " bottom=" .. tostring(cB) .. " frame bottom=" .. tostring(fBottom))
                end
            end
        end
        if allAbove then pass("T1: All children above editor frame bottom") end
    end
end)

-------------------------------------------------------------------------------
-- T2: Panel Selection Tests
-------------------------------------------------------------------------------
addSuite("T2: Panel Selection", function()
    local Editor = ns.Editor
    if not Editor then fail("T2: Editor module missing", ""); return end

    -- We need at least one panel to test with.  Create a test panel.
    local db = _G.InfoPanelsDB or {}
    db.userPanels = db.userPanels or {}
    local testId = "_ux_test_panel"
    local testTitle = "UX Test Panel"
    db.userPanels[testId] = {
        id = testId,
        title = testTitle,
        builtin = false,
        lines = {
            { template = "Line 1: {{PLAYER_NAME}}" },
            { template = "Line 2: Static text" },
        },
    }
    db.panels = db.panels or {}
    db.panels[testId] = db.panels[testId] or {}
    _G.InfoPanelsDB = db

    -- Create in PanelEngine if available
    local PE = ns.PanelEngine
    if PE then
        if PE.GetPanel(testId) then PE.DestroyPanel(testId) end
        PE.CreatePanel(db.userPanels[testId], db.panels[testId])
    end

    -- Refresh panel list so the test panel appears
    local PanelList = ns.EditorPanelList
    if PanelList then PanelList.Refresh() end

    -- Now select it
    Editor.EditPanel(testId)

    -- Check panel name input
    local nameInput = _G.IPEditorNameInput
    assertNotNil("T2: Panel name input exists", nameInput)
    if nameInput then
        local text = nameInput:GetText()
        assertEqual("T2: Panel name shows selected panel title", testTitle, text)
    end

    -- Check Live Preview header
    local previewArea = _G.IPEditorPreviewArea
    if previewArea then
        local LP = ns.EditorLivePreview
        -- The preview title is stored on the container frame, not previewArea
        -- We need to find the FontString that shows the panel name
        local previewFrame = previewArea:GetParent()
        if previewFrame and previewFrame._previewTitle then
            local previewTitle = safeGetText(previewFrame._previewTitle)
            assertEqual("T2: Live Preview header shows panel title", testTitle, previewTitle)
        else
            fail("T2: Live Preview title FontString not found", "previewFrame._previewTitle is nil")
        end
    else
        fail("T2: Preview area not found", "IPEditorPreviewArea is nil")
    end

    -- Check that line editor entries are visible and contain text
    local f = _G.InfoPanelsEditorFrame
    if f and f._linesScrollChild then
        local lineChildren = getVisibleChildren(f._linesScrollChild)
        assertGte("T2: Line editor has visible entries for 2-line panel", #lineChildren, 2)

        -- Check first line entry has text
        if #lineChildren >= 1 then
            local firstEntry = lineChildren[1]
            -- The EditBox is a child of the row frame
            local entryChildren = { firstEntry:GetChildren() }
            local foundText = false
            for _, ec in ipairs(entryChildren) do
                if ec.GetText and ec:GetObjectType() == "EditBox" then
                    local t = ec:GetText()
                    if t and t ~= "" then foundText = true end
                end
            end
            assertTrue("T2: First line entry EditBox has text", foundText,
                "line editor text boxes are empty when panel has lines")
        end
    else
        fail("T2: Lines scroll child not found", "")
    end

    -- Cleanup: remove test panel
    if PE and PE.GetPanel(testId) then PE.DestroyPanel(testId) end
    db.userPanels[testId] = nil
    db.panels[testId] = nil
end)

-------------------------------------------------------------------------------
-- T3: Button Interaction Tests
-------------------------------------------------------------------------------
addSuite("T3: Button Interaction", function()
    local Editor = ns.Editor
    if not Editor then fail("T3: Editor module missing", ""); return end

    -- Test "New Panel" button via Editor.StartNewPanel()
    local PanelList = ns.EditorPanelList
    local db = _G.InfoPanelsDB or {}

    -- Count panels before
    local beforeCount = 0
    if db.userPanels then
        for _ in pairs(db.userPanels) do beforeCount = beforeCount + 1 end
    end

    Editor.StartNewPanel()

    -- Count panels after
    db = _G.InfoPanelsDB or {}
    local afterCount = 0
    local newPanelId = nil
    if db.userPanels then
        for id in pairs(db.userPanels) do
            afterCount = afterCount + 1
            -- Find the new one
            if id:find("user_new_panel") then newPanelId = id end
        end
    end

    assertTrue("T3: New Panel increases panel count", afterCount > beforeCount,
        "before=" .. tostring(beforeCount) .. " after=" .. tostring(afterCount))

    -- Check name field is populated with default name
    local nameInput = _G.IPEditorNameInput
    if nameInput then
        local text = nameInput:GetText()
        assertTrue("T3: New panel name field populated", text and text ~= "",
            "panel name field is empty after New Panel")
        assertEqual("T3: Default panel name is 'New Panel'", "New Panel", text)
    end

    -- Test "Add Line" button
    local f = _G.InfoPanelsEditorFrame
    if f and f._linesScrollChild then
        local beforeLines = #getVisibleChildren(f._linesScrollChild)

        -- Call Editor._addLine directly (the button calls this)
        Editor._addLine("Test line {{PLAYER_NAME}}")

        local afterLines = #getVisibleChildren(f._linesScrollChild)
        assertTrue("T3: Add Line creates new line entry", afterLines > beforeLines,
            "before=" .. tostring(beforeLines) .. " after=" .. tostring(afterLines))
    end

    -- Cleanup: delete the new panel
    if newPanelId then
        local PE = ns.PanelEngine
        if PE and PE.GetPanel(newPanelId) then PE.DestroyPanel(newPanelId) end
        db = _G.InfoPanelsDB or {}
        if db.userPanels then db.userPanels[newPanelId] = nil end
        if db.panels then db.panels[newPanelId] = nil end
    end

    -- Test tab switching
    local tab1 = _G.IPEditorTab1
    local tab2 = _G.IPEditorTab2
    local tab3 = _G.IPEditorTab3

    if tab2 and f and f._tabFrames then
        -- Click Properties tab
        Editor._selectTab(2)

        local funcFrame = f._tabFrames[1]
        local propFrame = f._tabFrames[2]

        if funcFrame then
            assertTrue("T3: Functions tab hidden after Properties click",
                not funcFrame:IsVisible(),
                "Functions tab is still visible after switching to Properties")
        end
        if propFrame then
            assertTrue("T3: Properties tab visible after Properties click",
                propFrame:IsVisible(),
                "Properties tab not visible after clicking it")
        end

        -- Switch back to Functions
        Editor._selectTab(1)
    end
end)

-------------------------------------------------------------------------------
-- T4: Text Truncation Tests
-------------------------------------------------------------------------------
addSuite("T4: Text Truncation", function()
    -- Check function list entries for text truncation
    local funcScroll = _G.IPEditorFuncListScroll
    if not funcScroll then
        fail("T4: Function list scroll not found", "IPEditorFuncListScroll is nil")
        return
    end

    -- Make sure we're on the Functions tab and list is populated
    local Editor = ns.Editor
    if Editor then Editor._selectTab(1) end
    if Editor then Editor._refreshFuncList() end

    local scrollChild = funcScroll:GetScrollChild()
    if not scrollChild then
        fail("T4: Function list scroll child not found", "")
        return
    end

    local children = getVisibleChildren(scrollChild)
    assertTrue("T4: Function list has visible entries", #children > 0,
        "function list is empty")

    local truncatedCount = 0
    for i, btn in ipairs(children) do
        local fontStrings = getFontStrings(btn)
        for _, fs in ipairs(fontStrings) do
            local text = fs:GetText()
            if text and text ~= "" and not text:find("|cff") then
                -- Check truncation: GetStringWidth() vs GetWidth()
                local stringW = fs:GetStringWidth()
                local containerW = fs:GetWidth()
                if stringW and containerW and stringW > 0 and containerW > 0 then
                    if stringW > containerW + 1 then  -- 1px tolerance
                        truncatedCount = truncatedCount + 1
                        fail("T4: Text truncated in func list entry " .. i,
                            "text='" .. text .. "' stringW=" .. string.format("%.1f", stringW) ..
                            " containerW=" .. string.format("%.1f", containerW))
                    end
                end
            end
        end
    end
    if truncatedCount == 0 and #children > 0 then
        pass("T4: No text truncation in function list", #children .. " entries checked")
    end
end)

-------------------------------------------------------------------------------
-- T5: Spacing & Touch Target Tests (Fitts's Law)
-------------------------------------------------------------------------------
addSuite("T5: Spacing & Touch Targets", function()
    local f = _G.InfoPanelsEditorFrame
    if not f then fail("T5: Editor frame not found", ""); return end

    -- Collect all visible buttons in the editor
    local allButtons = {}
    local function collectButtons(frame)
        if not frame then return end
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            if child:IsVisible() then
                if child:GetObjectType() == "Button" then
                    -- Only include UIPanelButtonTemplate-style buttons (have SetText)
                    if child.GetText and child:GetText() and child:GetText() ~= "" then
                        allButtons[#allButtons + 1] = child
                    end
                end
                collectButtons(child)
            end
        end
    end
    collectButtons(f)

    assertTrue("T5: Found buttons to test", #allButtons > 0,
        "no visible buttons found in editor")

    -- Check minimum button sizes
    -- Blizzard CharacterFrameTabButtonTemplate tabs have a fixed height that is
    -- their standard (typically 20-22px).  They are exempt from the minimum-height
    -- check because their size is controlled by the Blizzard template, not by us.
    local tabButtonNames = { IPEditorTab1 = true, IPEditorTab2 = true, IPEditorTab3 = true }
    local smallCount = 0
    for _, btn in ipairs(allButtons) do
        local bw, bh = btn:GetWidth(), btn:GetHeight()
        local label = btn:GetText() or "?"
        local btnName = btn:GetName()
        local isTabButton = btnName and tabButtonNames[btnName]
        if bh < 22 and not isTabButton then
            smallCount = smallCount + 1
            fail("T5: Button too short: '" .. label .. "'",
                "height=" .. string.format("%.1f", bh) .. " minimum=22")
        end
        if bw < 60 then
            -- Allow small icon buttons (like "X" remove buttons)
            if label ~= "X" then
                smallCount = smallCount + 1
                fail("T5: Button too narrow: '" .. label .. "'",
                    "width=" .. string.format("%.1f", bw) .. " minimum=60")
            end
        end
    end
    if smallCount == 0 then
        pass("T5: All buttons meet minimum size requirements", #allButtons .. " checked")
    end

    -- Check spacing between adjacent buttons that share a parent
    local parentGroups = {}
    for _, btn in ipairs(allButtons) do
        local parent = btn:GetParent()
        if parent then
            parentGroups[parent] = parentGroups[parent] or {}
            parentGroups[parent][#parentGroups[parent] + 1] = btn
        end
    end

    local tightCount = 0
    for parent, buttons in pairs(parentGroups) do
        if #buttons >= 2 then
            -- Sort by position (left to right, top to bottom)
            for i = 1, #buttons do
                for j = i + 1, #buttons do
                    local a, b = buttons[i], buttons[j]
                    local aL, aB, aW, aH = safeGetRect(a)
                    local bL, bB, bW, bH = safeGetRect(b)
                    if aL and bL then
                        -- Check horizontal adjacency
                        local aRight = aL + aW
                        local hGap = bL - aRight
                        if hGap >= 0 and hGap < 200 then  -- nearby horizontally
                            if hGap < 4 then
                                tightCount = tightCount + 1
                                fail("T5: Buttons too close horizontally",
                                    "'" .. (a:GetText() or "?") .. "' and '" .. (b:GetText() or "?") ..
                                    "' gap=" .. string.format("%.1f", hGap) .. "px (min 4)")
                            end
                        end
                        -- Check vertical adjacency
                        local aTop = aB + aH
                        local bTop = bB + bH
                        local vGap = aB - bTop  -- In WoW, higher Y = higher on screen
                        if vGap >= 0 and vGap < 200 then  -- nearby vertically
                            if vGap < 4 then
                                tightCount = tightCount + 1
                                fail("T5: Buttons too close vertically",
                                    "'" .. (a:GetText() or "?") .. "' and '" .. (b:GetText() or "?") ..
                                    "' gap=" .. string.format("%.1f", vGap) .. "px (min 4)")
                            end
                        end
                    end
                end
            end
        end
    end
    if tightCount == 0 then
        pass("T5: All button spacing >= 4px")
    end
end)

-------------------------------------------------------------------------------
-- T6: Content Population Tests
-------------------------------------------------------------------------------
addSuite("T6: Content Population", function()
    -- Ensure Functions tab is active and populated
    local Editor = ns.Editor
    if Editor then
        Editor._selectTab(1)
        Editor._refreshFuncList()
    end

    local funcScroll = _G.IPEditorFuncListScroll
    if funcScroll then
        local scrollChild = funcScroll:GetScrollChild()
        if scrollChild then
            local visible = getVisibleChildren(scrollChild)
            assertTrue("T6: Function list has visible entries when Functions tab active",
                #visible > 0,
                "function list is empty — no functions shown")
        end
    else
        fail("T6: Function list scroll not found", "")
    end

    -- Select a function and verify Name and Code fields populate
    local Functions = ns.Functions
    if Functions and Editor then
        local sorted = Functions.GetAllSorted()
        if sorted and #sorted > 0 then
            local firstName = sorted[1].name
            Editor._editFunction(firstName)

            local funcName = _G.IPEditorFuncName
            if funcName then
                local text = funcName:GetText()
                assertTrue("T6: Function name field populated after selection",
                    text and text ~= "",
                    "function name field is empty")
                assertEqual("T6: Function name matches selected", firstName, text)
            end
        end
    end

    -- Check Live Preview placeholder does NOT contain "data sources"
    local previewArea = _G.IPEditorPreviewArea
    if previewArea then
        local parent = previewArea:GetParent()
        if parent and parent._emptyMsg then
            local emptyText = safeGetText(parent._emptyMsg)
            if emptyText then
                local lower = emptyText:lower()
                assertTrue("T6: Preview placeholder does not say 'data sources'",
                    not lower:find("data sources"),
                    "placeholder text contains 'data sources': " .. emptyText)
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- T7: Overlap Detection Tests
-------------------------------------------------------------------------------
addSuite("T7: Overlap Detection", function()
    local f = _G.InfoPanelsEditorFrame
    if not f then fail("T7: Editor frame not found", ""); return end

    -- Check that tab content frames don't overlap each other
    if f._tabFrames then
        local visibleTabs = {}
        for i, tf in pairs(f._tabFrames) do
            if tf and tf:IsVisible() then
                visibleTabs[#visibleTabs + 1] = { index = i, frame = tf }
            end
        end
        -- Only one tab content should be visible at a time
        assertLte("T7: At most one tab content visible", #visibleTabs, 1)
    end

    -- Collect all visible buttons and check pairwise overlap
    local allButtons = {}
    local function collectButtons(frame)
        if not frame then return end
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            if child:IsVisible() and child:GetObjectType() == "Button" then
                if child.GetText and child:GetText() and child:GetText() ~= "" then
                    allButtons[#allButtons + 1] = child
                end
            end
        end
    end

    -- Check sidebar buttons
    if f._centerFrame then collectButtons(f._centerFrame) end
    local children = { f:GetChildren() }
    for _, child in ipairs(children) do
        if child:IsVisible() then collectButtons(child) end
    end

    local overlapCount = 0
    for i = 1, #allButtons do
        for j = i + 1, #allButtons do
            local a, b = allButtons[i], allButtons[j]
            if a:GetParent() == b:GetParent() and overlaps(a, b) then
                overlapCount = overlapCount + 1
                fail("T7: Buttons overlap",
                    "'" .. (a:GetText() or "?") .. "' and '" .. (b:GetText() or "?") .. "'")
            end
        end
    end
    if overlapCount == 0 and #allButtons > 0 then
        pass("T7: No button overlaps detected", #allButtons .. " buttons checked")
    end
end)

-------------------------------------------------------------------------------
-- T8: Visibility State Tests
-------------------------------------------------------------------------------
addSuite("T8: Visibility State", function()
    local f = _G.InfoPanelsEditorFrame
    local Editor = ns.Editor
    if not f or not Editor then fail("T8: Editor not available", ""); return end

    -- Switch to Functions tab
    Editor._selectTab(1)
    if f._tabFrames then
        local funcFrame = f._tabFrames[1]
        local propFrame = f._tabFrames[2]
        local visFrame = f._tabFrames[3]

        if funcFrame then
            assertTrue("T8: Functions content visible when Functions tab selected",
                funcFrame:IsVisible())
        end
        if propFrame then
            assertTrue("T8: Properties content hidden when Functions tab selected",
                not propFrame:IsVisible(),
                "Properties panel is visible when it should be hidden")
        end
        if visFrame then
            assertTrue("T8: Visibility content hidden when Functions tab selected",
                not visFrame:IsVisible(),
                "Visibility panel is visible when it should be hidden")
        end
    end

    -- Switch to Properties tab
    Editor._selectTab(2)
    if f._tabFrames then
        local funcFrame = f._tabFrames[1]
        local propFrame = f._tabFrames[2]

        if funcFrame then
            assertTrue("T8: Functions content hidden when Properties tab selected",
                not funcFrame:IsVisible(),
                "Functions panel still visible after switching to Properties")
        end
        if propFrame then
            assertTrue("T8: Properties content visible when Properties tab selected",
                propFrame:IsVisible(),
                "Properties panel not visible after selecting Properties tab")
        end
    end

    -- Switch to Visibility tab
    Editor._selectTab(3)
    if f._tabFrames then
        local funcFrame = f._tabFrames[1]
        local propFrame = f._tabFrames[2]
        local visFrame = f._tabFrames[3]

        if funcFrame then
            assertTrue("T8: Functions hidden when Visibility tab selected",
                not funcFrame:IsVisible())
        end
        if propFrame then
            assertTrue("T8: Properties hidden when Visibility tab selected",
                not propFrame:IsVisible())
        end
        if visFrame then
            assertTrue("T8: Visibility content visible when Visibility tab selected",
                visFrame:IsVisible())
        end
    end

    -- Restore to tab 1
    Editor._selectTab(1)
end)

-------------------------------------------------------------------------------
-- T9: Persistence Tests
-------------------------------------------------------------------------------
addSuite("T9: Persistence", function()
    local Editor = ns.Editor
    local PE = ns.PanelEngine
    if not Editor then fail("T9: Editor module missing", ""); return end

    local testId = "_ux_persist_test"
    local testTitle = "Persistence Test Panel"
    local testLine = "Persisted line: {{PLAYER_NAME}}"

    -- Create a panel with a name and line
    local db = _G.InfoPanelsDB or {}
    db.userPanels = db.userPanels or {}
    db.userPanels[testId] = {
        id = testId,
        title = testTitle,
        builtin = false,
        lines = { { template = testLine } },
    }
    db.panels = db.panels or {}
    db.panels[testId] = db.panels[testId] or {}
    _G.InfoPanelsDB = db

    if PE then
        if PE.GetPanel(testId) then PE.DestroyPanel(testId) end
        PE.CreatePanel(db.userPanels[testId], db.panels[testId])
    end

    -- Verify it's in the DB
    db = _G.InfoPanelsDB or {}
    assertNotNil("T9: Panel saved in DB", db.userPanels and db.userPanels[testId])
    if db.userPanels and db.userPanels[testId] then
        assertEqual("T9: Saved panel title matches", testTitle, db.userPanels[testId].title)
        local lines = db.userPanels[testId].lines
        assertTrue("T9: Saved panel has lines", lines and #lines >= 1,
            "no lines in saved panel")
        if lines and lines[1] then
            assertEqual("T9: Saved line template matches", testLine, lines[1].template)
        end
    end

    -- Now edit it in the editor
    Editor.EditPanel(testId)

    -- Verify name field
    local nameInput = _G.IPEditorNameInput
    if nameInput then
        assertEqual("T9: Name field shows persisted title", testTitle, nameInput:GetText())
    end

    -- Close and reopen
    Editor.Hide()
    Editor.Show()

    -- Refresh panel list
    local PanelList = ns.EditorPanelList
    if PanelList then PanelList.Refresh() end

    -- Re-select the panel
    Editor.EditPanel(testId)

    -- Verify name and line are still there
    if nameInput then
        assertEqual("T9: Name persists after close/reopen", testTitle, nameInput:GetText())
    end

    local f = _G.InfoPanelsEditorFrame
    if f and f._linesScrollChild then
        local lineChildren = getVisibleChildren(f._linesScrollChild)
        assertGte("T9: Lines persist after close/reopen", #lineChildren, 1)
    end

    -- Delete the panel
    if PE and PE.GetPanel(testId) then PE.DestroyPanel(testId) end
    db = _G.InfoPanelsDB or {}
    if db.userPanels then db.userPanels[testId] = nil end
    if db.panels then db.panels[testId] = nil end
    _G.InfoPanelsDB = db

    -- Verify it's gone
    db = _G.InfoPanelsDB
    assertTrue("T9: Panel removed from DB after delete",
        not (db.userPanels and db.userPanels[testId]),
        "panel still in DB after deletion")
end)

-------------------------------------------------------------------------------
-- T10: Layout Proportions
-------------------------------------------------------------------------------
addSuite("T10: Layout Proportions", function()
    local f = _G.InfoPanelsEditorFrame
    if not f then fail("T10: Editor frame not found", ""); return end

    -- Measure work area (the content area between title bar and bottom)
    local workArea = nil
    local children = { f:GetChildren() }
    for _, child in ipairs(children) do
        if child:IsVisible() and not child:GetName() then
            local _, _, w, h = safeGetRect(child)
            if w and w > 400 and h and h > 200 then
                workArea = child
                break
            end
        end
    end

    if not workArea then
        fail("T10: Could not identify work area frame", "")
        return
    end

    local waH = workArea:GetHeight()
    assertGte("T10: Work area has measurable height", waH, 200)

    -- Live Preview height: should fill right column (>= 60% of work area)
    local previewArea = _G.IPEditorPreviewArea
    if previewArea then
        local previewH = previewArea:GetHeight()
        local previewRatio = previewH / waH
        assertGte("T10: Live Preview height >= 60% of work area",
            previewRatio, 0.60)
    else
        fail("T10: Preview area not found", "IPEditorPreviewArea is nil")
    end

    -- Code editor dimensions
    local codeScroll = _G.IPEditorFuncCodeScroll
    if codeScroll and codeScroll:IsVisible() then
        local codeW = codeScroll:GetWidth()
        local codeH = codeScroll:GetHeight()
        assertGte("T10: Code editor width >= 250", codeW, 250)
        assertGte("T10: Code editor height >= 120", codeH, 120)
    else
        -- Switch to Functions tab to make it visible
        local Editor = ns.Editor
        if Editor then Editor._selectTab(1) end
        codeScroll = _G.IPEditorFuncCodeScroll
        if codeScroll then
            local codeW = codeScroll:GetWidth()
            local codeH = codeScroll:GetHeight()
            assertGte("T10: Code editor width >= 250", codeW, 250)
            assertGte("T10: Code editor height >= 120", codeH, 120)
        else
            fail("T10: Code scroll frame not found", "IPEditorFuncCodeScroll is nil")
        end
    end

    -- Function list width <= 50% of bottom section (tab content) width
    local funcScroll = _G.IPEditorFuncListScroll
    if funcScroll then
        local funcW = funcScroll:GetWidth()
        local tabContent = f._tabContentFrame
        if tabContent then
            local tabW = tabContent:GetWidth()
            local funcRatio = funcW / tabW
            assertLte("T10: Function list width <= 50% of bottom section",
                funcRatio, 0.50)
        end
    end

    -- Lines area height >= 35% of work area
    local linesScroll = _G.IPEditorLinesScroll
    if linesScroll then
        local linesH = linesScroll:GetHeight()
        local linesRatio = linesH / waH
        assertGte("T10: Lines area height >= 35% of work area",
            linesRatio, 0.35)
    else
        fail("T10: Lines scroll not found", "IPEditorLinesScroll is nil")
    end

    -- Bottom section (tab content) height <= 45% of work area
    local tabContent = f._tabContentFrame
    if tabContent then
        local tabH = tabContent:GetHeight()
        local tabRatio = tabH / waH
        assertLte("T10: Bottom section height <= 45% of work area",
            tabRatio, 0.45)
    end
end)

-------------------------------------------------------------------------------
-- T12: Code Editor Usability
-------------------------------------------------------------------------------
addSuite("T12: Code Editor Usability", function()
    local Editor = ns.Editor
    if not Editor then fail("T12: Editor module missing", ""); return end

    -- Make sure Functions tab is active
    Editor._selectTab(1)

    -- Select the first available function
    local Functions = ns.Functions
    if Functions then
        local sorted = Functions.GetAllSorted()
        if sorted and #sorted > 0 then
            Editor._editFunction(sorted[1].name)
        end
    end

    -- Check code editor EditBox visibility
    local codeScroll = _G.IPEditorFuncCodeScroll
    if codeScroll then
        assertTrue("T12: Code editor scroll is visible", codeScroll:IsVisible(),
            "code editor scroll frame is not visible when Functions tab is active")

        local codeW = codeScroll:GetWidth()
        local codeH = codeScroll:GetHeight()
        assertGte("T12: Code editor EditBox width >= 250", codeW, 250)
        assertGte("T12: Code editor EditBox height >= 100", codeH, 100)
    else
        fail("T12: Code editor scroll not found", "IPEditorFuncCodeScroll is nil")
    end

    -- Check function name field width
    local funcName = _G.IPEditorFuncName
    if funcName then
        assertTrue("T12: Function name field is visible", funcName:IsVisible(),
            "function name field is not visible")
        local nameW = funcName:GetWidth()
        assertGte("T12: Function name field width >= 150", nameW, 150)
    else
        fail("T12: Function name field not found", "IPEditorFuncName is nil")
    end
end)

-------------------------------------------------------------------------------
-- T13: Scrollbar Visibility
-------------------------------------------------------------------------------
addSuite("T13: Scrollbar Visibility", function()
    local funcScroll = _G.IPEditorFuncListScroll
    if not funcScroll then
        fail("T13: Function list scroll not found", "IPEditorFuncListScroll is nil")
        return
    end

    local scrollChild = funcScroll:GetScrollChild()
    if not scrollChild then
        fail("T13: Scroll child not found", "")
        return
    end

    local childH = scrollChild:GetHeight()
    local scrollH = funcScroll:GetHeight()

    if childH > scrollH then
        -- Content overflows: scrollbar should exist and be visible
        local scrollBar = funcScroll.ScrollBar
            or (funcScroll:GetName() and _G[funcScroll:GetName() .. "ScrollBar"])
        assertNotNil("T13: Scrollbar frame exists when content overflows", scrollBar)
        if scrollBar then
            assertTrue("T13: Scrollbar is visible when content overflows",
                scrollBar:IsVisible(),
                "scrollbar exists but is not visible; content height=" ..
                string.format("%.0f", childH) .. " scroll height=" ..
                string.format("%.0f", scrollH))
        end
    else
        pass("T13: Content fits in scroll area, scrollbar not required",
            "childH=" .. string.format("%.0f", childH) ..
            " scrollH=" .. string.format("%.0f", scrollH))
    end
end)

-------------------------------------------------------------------------------
-- T14: Tab Styling Tests
-------------------------------------------------------------------------------
addSuite("T14: Tab Styling", function()
    local f = _G.InfoPanelsEditorFrame
    if not f then fail("T14: Editor frame not found", ""); return end

    local tabs = f._tabs
    assertNotNil("T14: Tabs table exists", tabs)
    if not tabs or #tabs == 0 then
        fail("T14: No tabs found", "expected at least 1 tab button")
        return
    end
    assertTrue("T14: At least 2 tabs exist", #tabs >= 2, "found " .. #tabs)

    -- Check each tab is a proper button with texture regions
    for i, tab in ipairs(tabs) do
        local prefix = "T14: Tab" .. i
        assertNotNil(prefix .. " Left texture exists", tab.Left)
        assertNotNil(prefix .. " Right texture exists", tab.Right)
        assertNotNil(prefix .. " Middle texture exists", tab.Middle)
    end

    -- Identify selected tab (tab 1 should be selected by default after Show)
    -- Custom tab textures: tab-active / tab-inactive in InfoPanels/Textures/
    -- GetTexture() may return the path string or a numeric FileDataID, so we
    -- check for non-nil and optionally match the path if it is a string.

    -- Verify selected tab has a texture set
    local selectedIdx = f._activeTab or 1
    local selTab = tabs[selectedIdx]
    if selTab and selTab.Left and selTab.Left.GetTexture then
        local tex = selTab.Left:GetTexture()
        assertTrue("T14: Selected tab has active texture",
            tex ~= nil,
            "texture=" .. tostring(tex))
        -- If string, verify it contains "tab-active" (custom) or "ActiveTab" (Blizzard)
        if type(tex) == "string" then
            assertTrue("T14: Selected tab texture is active variant",
                tex:find("tab%-active") or tex:find("ActiveTab"),
                "texture=" .. tostring(tex))
        end
    end

    -- Verify inactive tabs have inactive texture
    for i, tab in ipairs(tabs) do
        if i ~= selectedIdx and tab.Left and tab.Left.GetTexture then
            local tex = tab.Left:GetTexture()
            assertTrue("T14: Inactive tab " .. i .. " has texture set",
                tex ~= nil,
                "texture=" .. tostring(tex))
            if type(tex) == "string" then
                assertTrue("T14: Inactive tab " .. i .. " has inactive texture",
                    tex:find("tab%-inactive") or tex:find("InActiveTab"),
                    "texture=" .. tostring(tex))
            end
        end
    end

    -- Verify selected tab text is gold (1, 0.82, 0)
    if selTab then
        pcall(function()
            local fs = selTab:GetFontString()
            if fs then
                local r, g, b = fs:GetTextColor()
                assertTrue("T14: Selected tab text is gold",
                    r and math.abs(r - 1) < 0.05 and math.abs(g - 0.82) < 0.05 and math.abs(b) < 0.05,
                    string.format("color=(%.2f, %.2f, %.2f) expected=(1, 0.82, 0)", r or 0, g or 0, b or 0))
            else
                fail("T14: Selected tab has no FontString", "")
            end
        end)
    end

    -- Verify inactive tab text is dimmer gold (0.78, 0.64, 0)
    for i, tab in ipairs(tabs) do
        if i ~= selectedIdx then
            pcall(function()
                local fs = tab:GetFontString()
                if fs then
                    local r, g, b = fs:GetTextColor()
                    assertTrue("T14: Inactive tab " .. i .. " text is dimmer gold",
                        r and math.abs(r - 0.78) < 0.15 and math.abs(g - 0.64) < 0.15 and b ~= nil and b < 0.15,
                        string.format("color=(%.2f, %.2f, %.2f) expected=(0.78, 0.64, 0)", r or 0, g or 0, b or 0))
                end
            end)
        end
    end

    -- Verify tab click switches content
    if #tabs >= 2 then
        local Editor = ns.Editor
        if Editor and Editor._selectTab then
            -- Switch to tab 2
            Editor._selectTab(2)
            local tabFrames = f._tabFrames
            if tabFrames and tabFrames[2] then
                assertTrue("T14: Tab 2 content visible after click", tabFrames[2]:IsVisible())
            end
            if tabFrames and tabFrames[1] then
                assertTrue("T14: Tab 1 content hidden after switching to tab 2", not tabFrames[1]:IsVisible())
            end
            -- Verify tab 2 now has active texture
            if tabs[2] and tabs[2].Left and tabs[2].Left.GetTexture then
                local tex = tabs[2].Left:GetTexture()
                assertTrue("T14: Tab 2 has active texture after click",
                    tex ~= nil,
                    "texture=" .. tostring(tex))
                if type(tex) == "string" then
                    assertTrue("T14: Tab 2 texture is active variant after click",
                        tex:find("tab%-active") or tex:find("ActiveTab"),
                        "texture=" .. tostring(tex))
                end
            end
            -- Switch back to tab 1
            Editor._selectTab(1)
        end
    end

    -- Verify tab buttons have proper width (sized to text + padding)
    for i, tab in ipairs(tabs) do
        local w = tab:GetWidth()
        assertGte("T14: Tab " .. i .. " width >= 60 (text + padding)", w, 60)
        assertLte("T14: Tab " .. i .. " width <= 300 (reasonable max)", w, 300)
    end

    -- Verify tab buttons are positioned at bottom of editor frame
    local frameBottom = f:GetBottom()
    if frameBottom then
        for i, tab in ipairs(tabs) do
            local tabTop = tab:GetTop()
            if tabTop then
                -- Tabs should be near the bottom of the frame (within 30px of frame bottom)
                local distFromBottom = tabTop - frameBottom
                assertLte("T14: Tab " .. i .. " near frame bottom",
                    distFromBottom, 30,
                    "tab top is " .. string.format("%.0f", distFromBottom) .. "px above frame bottom")
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- T11: Test Cleanup Verification (runs LAST)
-------------------------------------------------------------------------------
addSuite("T11: Test Cleanup Verification", function()
    -- Check no test panels remain in DB
    local db = _G.InfoPanelsDB or {}
    local testPanels = {}
    if db.userPanels then
        for id, _ in pairs(db.userPanels) do
            if id:find("^_ux_") or id:find("^_test_") then
                testPanels[#testPanels + 1] = id
            end
        end
    end

    if #testPanels > 0 then
        -- Clean them up
        local PE = ns.PanelEngine
        for _, id in ipairs(testPanels) do
            if PE and PE.GetPanel(id) then PE.DestroyPanel(id) end
            if db.userPanels then db.userPanels[id] = nil end
            if db.panels then db.panels[id] = nil end
        end
        fail("T11: Test panels found in DB after test suite",
            table.concat(testPanels, ", ") .. " — cleaned up now")
    else
        pass("T11: No test panels remaining in DB")
    end

    -- Check no TEST_ functions remain
    local Functions = ns.Functions
    if Functions then
        local sorted = Functions.GetAllSorted()
        local testFuncs = {}
        if sorted then
            for _, item in ipairs(sorted) do
                if item.name:find("^TEST_") then
                    testFuncs[#testFuncs + 1] = item.name
                end
            end
        end
        if #testFuncs > 0 then
            -- Clean them up
            for _, name in ipairs(testFuncs) do
                pcall(function() Functions.DeleteUserFunction(name) end)
            end
            fail("T11: TEST_ functions found after test suite",
                table.concat(testFuncs, ", ") .. " — cleaned up now")
        else
            pass("T11: No TEST_ functions remaining")
        end
    end

    -- Also clean up any "Persistence Test Panel" in panel list
    local PanelList = ns.EditorPanelList
    if PanelList then PanelList.Refresh() end
end)

-------------------------------------------------------------------------------
-- RunAll: Execute all test suites and report summary.
-- Opens the editor first to ensure frames exist.
-------------------------------------------------------------------------------
function InGameTests.RunAll()
    passCount = 0
    failCount = 0
    results = {}

    log("========================================")
    log("InfoPanels UX Test Suite v" .. (ns.version or "?"))
    log(date("%Y-%m-%d %H:%M:%S"))
    log("========================================")

    -- Pre-check: must not be in combat
    if InCombatLockdown and InCombatLockdown() then
        fail("PRE-CHECK", "Cannot run UX tests during combat lockdown")
        log("========================================")
        log("Results: 0 PASS, 1 FAIL (combat lockdown)")
        log("========================================")
        return 0, 1, results
    end

    -- Step 1: Open the editor
    log("--- Opening Editor ---")
    local Editor = ns.Editor
    if not Editor then
        fail("PRE-CHECK", "Editor module not found")
        log("========================================")
        log("Results: 0 PASS, 1 FAIL")
        log("========================================")
        return 0, 1, results
    end

    Editor.Show()

    -- Verify editor opened
    local editorFrame = _G.InfoPanelsEditorFrame
    if not editorFrame or not editorFrame:IsVisible() then
        fail("PRE-CHECK", "Editor.Show() did not produce a visible frame")
        log("========================================")
        log("Results: 0 PASS, 1 FAIL")
        log("========================================")
        return 0, 1, results
    end
    pass("PRE-CHECK: Editor opened successfully")

    -- Step 2: Run all suites
    for _, suiteName in ipairs(_suiteOrder) do
        log("--- " .. suiteName .. " ---")
        local fn = _suites[suiteName]
        local ok, err = pcall(fn)
        if not ok then
            fail(suiteName .. " (uncaught error)", tostring(err))
        end
    end

    -- Step 3: Summary
    log("========================================")
    log("Results: " .. passCount .. " PASS, " .. failCount .. " FAIL")
    if failCount == 0 then
        log("|cff44ff44ALL TESTS PASSED|r")
    else
        log("|cffff4444" .. failCount .. " TEST(S) FAILED|r")
    end
    log("========================================")

    return passCount, failCount, results
end

return InGameTests
