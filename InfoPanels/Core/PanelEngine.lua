-- InfoPanels/Core/PanelEngine.lua
-- Registry-based panel rendering engine. The engine ONLY talks to registries,
-- never special-cases specific panel types.
--
-- Following WeakAuras pattern: panels are pure data tables with string keys
-- that resolve to registered types via Registry.GetPanelType(name).
--
-- Single Responsibility: Panel lifecycle management + rendering via registries.
-- Open/Closed: New panel types = RegisterPanelType() call, zero engine changes.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local PanelEngine = {}
ns.PanelEngine = PanelEngine

-- Active panel instances: keyed by panel ID
local activePanels = {}

-- Ordered list of panel IDs (registration order = chain order)
local panelOrder = {}

-- Performance guard
local MAX_BINDINGS_PER_PANEL = 50
local MAX_LINES_PER_PANEL = 50

-------------------------------------------------------------------------------
-- ValidateDefinition: Validate a panel definition against the schema.
-- Returns true, nil on success or false, { "error1", "error2", ... } on failure.
-------------------------------------------------------------------------------
function PanelEngine.ValidateDefinition(definition)
    local errors = {}

    if type(definition) ~= "table" then
        return false, { "Definition must be a table" }
    end

    -- Required fields
    if type(definition.id) ~= "string" or definition.id == "" then
        errors[#errors + 1] = "id: must be a non-empty string"
    end
    if type(definition.title) ~= "string" or definition.title == "" then
        errors[#errors + 1] = "title: must be a non-empty string"
    end

    -- Panel type (optional, defaults to "vertical_list")
    if definition.panelType ~= nil then
        if type(definition.panelType) ~= "string" then
            errors[#errors + 1] = "panelType: must be a string"
        end
    end

    -- Lines (new architecture: ordered list of template strings)
    if definition.lines ~= nil then
        if type(definition.lines) ~= "table" then
            errors[#errors + 1] = "lines: must be a table"
        else
            if #definition.lines > MAX_LINES_PER_PANEL then
                errors[#errors + 1] = "lines: exceeds maximum of " .. MAX_LINES_PER_PANEL
            end
            for i, line in ipairs(definition.lines) do
                if type(line) ~= "table" then
                    errors[#errors + 1] = "lines[" .. i .. "]: must be a table"
                elseif type(line.template) ~= "string" then
                    errors[#errors + 1] = "lines[" .. i .. "].template: must be a string"
                end
            end
        end
    end

    -- Bindings (legacy, optional array)
    if definition.bindings ~= nil then
        if type(definition.bindings) ~= "table" then
            errors[#errors + 1] = "bindings: must be a table"
        else
            if #definition.bindings > MAX_BINDINGS_PER_PANEL then
                errors[#errors + 1] = "bindings: exceeds maximum of " .. MAX_BINDINGS_PER_PANEL
            end
            for i, binding in ipairs(definition.bindings) do
                if type(binding) ~= "table" then
                    errors[#errors + 1] = "bindings[" .. i .. "]: must be a table"
                elseif type(binding.sourceId) ~= "string" or binding.sourceId == "" then
                    errors[#errors + 1] = "bindings[" .. i .. "].sourceId: must be a non-empty string"
                end
            end
        end
    end

    -- Events (optional array of strings)
    if definition.events ~= nil then
        if type(definition.events) ~= "table" then
            errors[#errors + 1] = "events: must be a table"
        else
            for i, evt in ipairs(definition.events) do
                if type(evt) ~= "string" then
                    errors[#errors + 1] = "events[" .. i .. "]: must be a string"
                end
            end
        end
    end

    -- Visibility (optional table with conditions array)
    if definition.visibility ~= nil then
        if type(definition.visibility) ~= "table" then
            errors[#errors + 1] = "visibility: must be a table"
        elseif definition.visibility.conditions ~= nil then
            if type(definition.visibility.conditions) ~= "table" then
                errors[#errors + 1] = "visibility.conditions: must be a table"
            else
                for i, cond in ipairs(definition.visibility.conditions) do
                    if type(cond) ~= "table" then
                        errors[#errors + 1] = "visibility.conditions[" .. i .. "]: must be a table"
                    elseif not cond.sourceId and not cond.type then
                        errors[#errors + 1] = "visibility.conditions[" .. i .. "]: must have sourceId or type"
                    end
                end
            end
        end
    end

    -- Gap (optional number)
    if definition.gap ~= nil and type(definition.gap) ~= "number" then
        errors[#errors + 1] = "gap: must be a number"
    end

    -- DataEntry (optional table or array of tables)
    if definition.dataEntry ~= nil then
        if type(definition.dataEntry) ~= "table" then
            errors[#errors + 1] = "dataEntry: must be a table"
        end
    end

    if #errors > 0 then
        return false, errors
    end
    return true, nil
end

-------------------------------------------------------------------------------
-- CheckVisibility: Evaluate visibility conditions for a panel.
-- Returns true if panel should be visible, false otherwise.
-------------------------------------------------------------------------------
function PanelEngine.CheckVisibility(definition)
    if not definition or not definition.visibility then return true end
    local conditions = definition.visibility.conditions
    if not conditions or #conditions == 0 then return true end

    local DataSources = ns.DataSources
    local Utils = ns.Utils

    for _, cond in ipairs(conditions) do
        local visible = true

        if cond.type == "always" then
            visible = true
        elseif cond.type == "never" then
            visible = false
        elseif cond.type == "delve_only" then
            visible = Utils and Utils.IsInDelve() or false
        elseif cond.type == "instance_check" then
            local inInstance, instanceType = false, "none"
            if _G.IsInInstance then
                inInstance, instanceType = _G.IsInInstance()
            end
            visible = (instanceType == cond.instanceType)
            if cond.instanceType == "none" then
                visible = not inInstance or instanceType == "none"
            end
        elseif cond.type == "group_check" then
            local inGroup = _G.IsInGroup and _G.IsInGroup() or false
            if cond.inGroup then
                visible = inGroup and true or false
            else
                visible = not inGroup
            end
        elseif cond.type == "combat_check" then
            local inCombat = _G.UnitAffectingCombat and _G.UnitAffectingCombat("player") or false
            if cond.inCombat then
                visible = inCombat and true or false
            else
                visible = not inCombat
            end
        elseif cond.sourceId then
            if DataSources then
                local val, err = DataSources.Fetch(cond.sourceId)
                if err then
                    visible = false
                else
                    if cond.operator == "equals" then
                        visible = val == cond.value
                    elseif cond.operator == "not_equals" then
                        visible = val ~= cond.value
                    elseif cond.operator == "greater_than" then
                        visible = type(val) == "number" and val > (cond.value or 0)
                    elseif cond.operator == "less_than" then
                        visible = type(val) == "number" and val < (cond.value or 0)
                    elseif cond.operator == "truthy" or cond.operator == nil then
                        visible = val and val ~= false and val ~= 0
                    elseif cond.operator == "falsy" then
                        visible = not val or val == false or val == 0
                    end
                end
            else
                visible = false
            end
        end

        if not visible then return false end
    end

    return true
end

-- Debounce state for RebuildChain
local _rebuildPending = false

local function _doRebuildChain()
    _rebuildPending = false

    local baseAnchor
    if CP and CP.GetBaseTrackerAnchor then
        baseAnchor = CP.GetBaseTrackerAnchor()
    end
    if not baseAnchor then baseAnchor = _G.ObjectiveTrackerFrame end

    local prevFrame = nil
    local chainCount = 0

    for _, id in ipairs(panelOrder) do
        local panel = activePanels[id]
        if panel and panel.frame then
            local isPinned = panel._db.pinned ~= false
            local isVisible = panel.frame:IsShown()
            if isPinned and isVisible then
                panel.frame:SetMovable(false)
                panel.frame:ClearAllPoints()
                if prevFrame == nil then
                    panel.frame:SetPoint("TOPRIGHT", baseAnchor, "BOTTOMRIGHT", 0, -14)
                else
                    panel.frame:SetPoint("TOPRIGHT", prevFrame, "BOTTOMRIGHT", 0, -4)
                end
                prevFrame = panel.frame
                chainCount = chainCount + 1
            end
        end
    end

    iplog("Debug", "RebuildChain: chained " .. chainCount .. " of " .. #panelOrder .. " panels")
end

-------------------------------------------------------------------------------
-- RebuildChain: Debounced dock chain rebuild using actual panel heights.
-------------------------------------------------------------------------------
function PanelEngine.RebuildChain()
    if _rebuildPending then return end
    _rebuildPending = true
    if _G.C_Timer then
        _G.C_Timer.After(0, _doRebuildChain)
    else
        _doRebuildChain()
    end
end

-------------------------------------------------------------------------------
-- CreatePanel: Instantiate a panel from a definition.
-- The engine resolves panelType via Registry. No special-casing.
-------------------------------------------------------------------------------
function PanelEngine.CreatePanel(definition, db)
    if not definition or not definition.id then
        iplog("Error", "CreatePanel: invalid definition")
        return nil, "invalid definition: missing or nil"
    end

    local valid, errors = PanelEngine.ValidateDefinition(definition)
    if not valid then
        local errStr = table.concat(errors, "; ")
        iplog("Error", "CreatePanel: schema validation failed for " ..
            tostring(definition.id) .. ": " .. errStr)
        return nil, "schema validation failed: " .. errStr
    end

    local id = definition.id
    if activePanels[id] then
        iplog("Warn", "CreatePanel: panel " .. id .. " already exists, destroying first")
        PanelEngine.DestroyPanel(id)
    end

    -- Track registration order
    local alreadyInOrder = false
    for _, oid in ipairs(panelOrder) do
        if oid == id then alreadyInOrder = true; break end
    end
    if not alreadyInOrder then
        panelOrder[#panelOrder + 1] = id
    end

    db = db or {}

    local UIFramework = ns.UIFramework
    if not UIFramework then
        iplog("Error", "CreatePanel: UIFramework not available")
        return nil
    end

    local frameName = "InfoPanels_" .. id:gsub("[^%w]", "_")
    local panelFrame = UIFramework.CreatePanelFrame(frameName, db, {
        title = definition.title or id,
        gap = definition.gap or -14,
        chainAnchor = definition.chainAnchor,
    })

    if not panelFrame then
        iplog("Error", "CreatePanel: UIFramework.CreatePanelFrame returned nil for " .. id)
        return nil
    end

    panelFrame.definition = definition
    panelFrame.id = id
    panelFrame._db = db
    panelFrame._labels = {}
    panelFrame._eventFrame = nil
    panelFrame._region = nil

    -- New architecture: Lines-based panels
    if definition.lines and #definition.lines > 0 then
        PanelEngine._renderLinesLayout(panelFrame, definition)
    else
        -- Resolve panel type from registry (Tier 1: string key -> registry lookup)
        local panelTypeName = definition.panelType or "vertical_list"
        local Registry = ns.Registry
        local panelType = Registry and Registry.GetPanelType(panelTypeName)

        if panelType and panelType.create then
            local ok, region = pcall(panelType.create, panelFrame.contentFrame, definition)
            if ok and region then
                panelFrame._region = region
                panelFrame._labels = region._labels or {}
            else
                iplog("Error", "CreatePanel: panelType.create failed for " .. id .. ": " .. tostring(region))
            end
        elseif definition.bindings and #definition.bindings > 0 then
            -- Fallback: use vertical_list for legacy definitions without panelType
            local vtType = Registry and Registry.GetPanelType("vertical_list")
            if vtType and vtType.create then
                local ok, region = pcall(vtType.create, panelFrame.contentFrame, definition)
                if ok and region then
                    panelFrame._region = region
                    panelFrame._labels = region._labels or {}
                end
            else
                PanelEngine._renderStandardLayout(panelFrame, definition)
            end
        end
    end

    PanelEngine._setupEvents(panelFrame, definition)

    activePanels[id] = panelFrame

    panelFrame.OnPinChanged = function()
        PanelEngine.RebuildChain()
    end
    panelFrame.OnCollapseChanged = function()
        PanelEngine.RebuildChain()
    end

    panelFrame.RestoreState()
    PanelEngine.RebuildChain()

    iplog("Info", "CreatePanel: " .. id .. " created successfully")
    return panelFrame
end

-------------------------------------------------------------------------------
-- _renderLinesLayout: Render lines-based panels using {{FUNCTION}} templates.
-------------------------------------------------------------------------------
function PanelEngine._renderLinesLayout(panel, definition)
    local contentFrame = panel.contentFrame
    local contentWidth = panel._contentWidth
    local lines = definition.lines or {}

    local prevLabel = nil
    for i, line in ipairs(lines) do
        local label = ns.UIFramework.CreateLabel(
            contentFrame, contentWidth,
            prevLabel, prevLabel and -4 or -8
        )
        label:SetText(line.template or "")
        panel._labels[i] = { label = label, line = line }
        prevLabel = label
    end
end

-------------------------------------------------------------------------------
-- _renderStandardLayout: Fallback for legacy definitions without panelType.
-------------------------------------------------------------------------------
function PanelEngine._renderStandardLayout(panel, definition)
    local layout = definition.layout or "vertical"
    local bindings = definition.bindings or {}
    local contentFrame = panel.contentFrame
    local contentWidth = panel._contentWidth

    if layout == "vertical" or layout == "vertical_list" then
        local prevLabel = nil
        for i, binding in ipairs(bindings) do
            local label = ns.UIFramework.CreateLabel(
                contentFrame, contentWidth,
                prevLabel, prevLabel and -4 or -8
            )
            label:SetText((binding.label or binding.sourceId or "") .. ": ...")
            panel._labels[i] = { label = label, binding = binding }
            prevLabel = label
        end
    elseif layout == "horizontal" then
        local x = 8
        for i, binding in ipairs(bindings) do
            local label = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", x, -8)
            pcall(function() label:SetFontObject(_G.ObjectiveFont) end)
            label:SetTextColor(1, 1, 1, 1)
            label:SetText((binding.label or "") .. ": ...")
            panel._labels[i] = { label = label, binding = binding }
            x = x + 80
        end
    end
end

-------------------------------------------------------------------------------
-- UpdatePanel: Refresh all data for a panel via its registered type.
-------------------------------------------------------------------------------
function PanelEngine.UpdatePanel(id)
    local panel = activePanels[id]
    if not panel then return end

    local definition = panel.definition
    if not definition then return end

    -- Check visibility — only rebuild chain when state ACTUALLY CHANGES
    local shouldShow = PanelEngine.CheckVisibility(definition)
    if panel.frame then
        local wasShown = panel.frame:IsShown()
        if not shouldShow then
            if wasShown then
                panel.frame:Hide()
                PanelEngine.RebuildChain()
            end
            return
        elseif not panel._db.hidden then
            if not wasShown then
                panel.frame:Show()
                PanelEngine.RebuildChain()
            end
        end
    end

    -- Allow panels with a _refreshDefinition hook to update their data before rendering
    -- (e.g. StatPriority updates stats array when spec changes)
    if panel._refreshDefinition then
        local rok, rerr = pcall(panel._refreshDefinition, definition)
        if not rok then
            iplog("Error", "UpdatePanel: _refreshDefinition failed for " .. id .. ": " .. tostring(rerr))
        end
        -- Update header title if definition.title changed
        if panel.headerTitle and definition.title then
            pcall(function() panel.headerTitle:SetText(definition.title) end)
        end
    end

    -- Lines-based panels: resolve {{FUNCTION_NAME}} templates
    if definition.lines and #definition.lines > 0 then
        local Functions = ns.Functions
        if Functions then
            Functions.InvalidateCache()  -- Force refresh all
        end

        for i, entry in ipairs(panel._labels or {}) do
            local line = entry.line
            local label = entry.label
            if line and label then
                if Functions then
                    local resolved = Functions.ResolveTemplate(line.template or "")
                    label:SetText(resolved)
                else
                    label:SetText(line.template or "")
                end
            end
        end

        local numLabels = #(panel._labels or {})
        local contentH = math.max(numLabels * 20 + 16, 36)
        panel.UpdateFrameHeight(contentH)
        return
    end

    -- Resolve panel type from registry and call modify
    local panelTypeName = definition.panelType or "vertical_list"
    local Registry = ns.Registry
    local panelType = Registry and Registry.GetPanelType(panelTypeName)

    if panelType and panelType.modify and panel._region then
        local ok, contentH = pcall(panelType.modify, panel.contentFrame, panel._region, definition)
        if ok and contentH then
            panel.UpdateFrameHeight(contentH)
        else
            iplog("Error", "UpdatePanel: modify failed for " .. id .. ": " .. tostring(contentH))
        end
        return
    end

    -- Fallback: standard label-based update for legacy definitions
    local DataSources = ns.DataSources
    if not DataSources then return end

    local Utils = ns.Utils
    for i, entry in ipairs(panel._labels or {}) do
        local binding = entry.binding
        local label = entry.label
        if binding and label then
            local displayVal, isErr = Utils and Utils.FetchAndFormatBinding(DataSources, binding)
            if isErr or not displayVal then
                label:SetText((binding.label or "") .. ": |cff888888No data|r")
            else
                label:SetText((binding.label or "") .. ": " .. displayVal)
            end
        end
    end

    local numLabels = #(panel._labels or {})
    local contentH = math.max(numLabels * 20 + 16, 36)
    panel.UpdateFrameHeight(contentH)
end

-------------------------------------------------------------------------------
-- _setupEvents: Register WoW events to trigger panel refresh.
-------------------------------------------------------------------------------
function PanelEngine._setupEvents(panel, definition)
    local events = {}
    local eventSet = {}

    local function addEvent(evt)
        if not eventSet[evt] then
            eventSet[evt] = true
            events[#events + 1] = evt
        end
    end

    -- Copy explicit events
    if definition.events then
        for _, evt in ipairs(definition.events) do
            addEvent(evt)
        end
    end

    -- Collect events from functions referenced in lines
    if definition.lines then
        local Functions = ns.Functions
        if Functions then
            for _, line in ipairs(definition.lines) do
                if line.template then
                    for funcName in line.template:gmatch("{{(.-)}}") do
                        local trimmed = funcName:match("^%s*(.-)%s*$")
                        if trimmed and trimmed ~= "" then
                            local funcEvents = Functions.GetEventsForFunction(trimmed)
                            for _, evt in ipairs(funcEvents) do
                                addEvent(evt)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Collect events from bindings (legacy)
    if definition.bindings then
        local DataSources = ns.DataSources
        if DataSources then
            for _, binding in ipairs(definition.bindings) do
                local source = DataSources.Get(binding.sourceId)
                if source and source.events then
                    for _, evt in ipairs(source.events) do
                        addEvent(evt)
                    end
                end
            end
        end
    end

    if #events == 0 then return end

    local eventFrame = CreateFrame("Frame")
    for _, evt in ipairs(events) do
        pcall(eventFrame.RegisterEvent, eventFrame, evt)
    end
    eventFrame:SetScript("OnEvent", function()
        PanelEngine.UpdatePanel(panel.id)
    end)
    panel._eventFrame = eventFrame
end

-------------------------------------------------------------------------------
-- DestroyPanel: Remove and clean up a panel.
-------------------------------------------------------------------------------
function PanelEngine.DestroyPanel(id)
    local panel = activePanels[id]
    if not panel then return end

    if panel._eventFrame then
        panel._eventFrame:UnregisterAllEvents()
        panel._eventFrame:SetScript("OnEvent", nil)
    end
    if panel.frame then
        panel.frame:Hide()
        panel.frame:SetParent(nil)
    end

    activePanels[id] = nil

    for i, oid in ipairs(panelOrder) do
        if oid == id then
            table.remove(panelOrder, i)
            break
        end
    end

    PanelEngine.RebuildChain()
    iplog("Info", "DestroyPanel: " .. id .. " destroyed")
end

-------------------------------------------------------------------------------
-- Accessors
-------------------------------------------------------------------------------
function PanelEngine.GetPanel(id)
    return activePanels[id]
end

function PanelEngine.GetAllPanels()
    return activePanels
end

function PanelEngine.ShowPanel(id)
    local panel = activePanels[id]
    if panel and panel.frame then
        panel.frame:Show()
        PanelEngine.UpdatePanel(id)
        PanelEngine.RebuildChain()
    end
end

function PanelEngine.HidePanel(id)
    local panel = activePanels[id]
    if panel and panel.frame then
        panel.frame:Hide()
        PanelEngine.RebuildChain()
    end
end

function PanelEngine.TogglePanel(id)
    local panel = activePanels[id]
    if not panel or not panel.frame then return end
    if panel.frame:IsShown() then
        panel.frame:Hide()
    else
        panel.frame:Show()
        PanelEngine.UpdatePanel(id)
    end
end

function PanelEngine.ResetPanel(id)
    local panel = activePanels[id]
    if not panel then return end
    panel._db.position = nil
    panel._db.pinned = nil
    panel.ApplyPinnedState()
end

return PanelEngine
