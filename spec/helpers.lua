-- spec/helpers.lua
-- Test helper utilities for CouchPotato test suite

local helpers = {}

-- Fire a WoW event to all registered CP module handlers.
-- Uses CouchPotato._FireEvent — works after dofile("CouchPotato/CouchPotato.lua").
function helpers.fireEvent(event, ...)
    if _G.CouchPotato and _G.CouchPotato._FireEvent then
        _G.CouchPotato._FireEvent(event, ...)
    end
end

-- Reset all mock state between tests
function helpers.resetMocks()
    C_GamePad._enabled        = false
    C_GamePad._activeDeviceID = nil
    C_GamePad._ledColor       = nil
    C_GamePad._vibrating      = false
    C_GamePad._lastVibration  = nil
    C_GamePad._devices        = {}

    C_AddOns._Reset()
    C_Timer._Reset()
    _G._SetCombatState(false)
    _G._ResetBindings()
    _G._rawEventListeners = {}
end

-- Simulate controller connect
function helpers.connectController(deviceID)
    C_GamePad._SimulateConnect(deviceID or 1)
    helpers.fireEvent("GAME_PAD_CONNECTED", deviceID or 1)
    helpers.fireEvent("GAME_PAD_ACTIVE_CHANGED", true)
end

-- Simulate controller disconnect
function helpers.disconnectController()
    C_GamePad._SimulateDisconnect()
    helpers.fireEvent("GAME_PAD_DISCONNECTED")
    helpers.fireEvent("GAME_PAD_ACTIVE_CHANGED", false)
end

-- Assert a color is approximately equal (float comparison)
function helpers.assertColorEqual(actual, expected, tolerance)
    tolerance = tolerance or 0.01
    assert.is_not_nil(actual, "Color is nil")
    assert.near(actual.r, expected.r, tolerance)
    assert.near(actual.g, expected.g, tolerance)
    assert.near(actual.b, expected.b, tolerance)
end

-- Assert override binding exists for a key
function helpers.assertBinding(owner, key, expectedAction)
    local bindings = _G._GetOverrideBindings(owner)
    assert.is_not_nil(bindings[key],
        string.format("Expected binding for key %s, but none found", key))
    if expectedAction then
        assert.equals(bindings[key], expectedAction)
    end
end

-- Assert no override bindings exist for an owner
function helpers.assertNoBindings(owner)
    local bindings = _G._GetOverrideBindings(owner)
    local count = 0
    for _ in pairs(bindings) do count = count + 1 end
    if count ~= 0 then
        error("Expected no bindings but found " .. count, 2)
    end
end

return helpers
