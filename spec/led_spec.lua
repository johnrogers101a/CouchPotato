-- spec/led_spec.lua
-- Tests for LED module: spell school color mapping, DualSense LED

require("spec/wow_mock")
local helpers = require("spec/helpers")

describe("LED Module", function()
    local CP, LED
    
    before_each(function()
        helpers.resetMocks()
        C_GamePad._SimulateConnect(1)  -- controller needed for LED
        
        CP = LibStub("AceAddon-3.0"):NewAddon("CouchPotato", "AceConsole-3.0", "AceEvent-3.0")
        _G["CouchPotato"] = CP
        CP.db = LibStub("AceDB-3.0"):New("CouchPotatoDB", {
            profile = { ledEnabled = true }
        })
        
        dofile("CouchPotato/Core/LED.lua")
        LED = CP:GetModule("LED")
        LED:Enable()
    end)
    
    describe("school color mapping", function()
        it("maps Fire (school 4) to orange-red", function()
            LED:SetColorForSchool(4)
            local color = C_GamePad._ledColor
            assert.is_not_nil(color)
            -- Fire should be predominantly red/orange
            assert.is_true(color.r > 0.8, "Fire should have high red component")
            assert.is_true(color.g < 0.5, "Fire should have low green component")
            assert.is_true(color.b < 0.1, "Fire should have very low blue component")
        end)
        
        it("maps Frost (school 16) to ice blue", function()
            LED:SetColorForSchool(16)
            local color = C_GamePad._ledColor
            assert.is_not_nil(color)
            assert.is_true(color.b > 0.7, "Frost should have high blue component")
            assert.is_true(color.r < 0.5, "Frost should have lower red component")
        end)
        
        it("maps Shadow (school 32) to purple", function()
            LED:SetColorForSchool(32)
            local color = C_GamePad._ledColor
            assert.is_not_nil(color)
            assert.is_true(color.r > 0.3, "Shadow should have red component")
            assert.is_true(color.b > 0.5, "Shadow should have blue component")
            assert.is_true(color.g < 0.1, "Shadow should have very low green")
        end)
        
        it("maps Holy (school 2) to golden yellow", function()
            LED:SetColorForSchool(2)
            local color = C_GamePad._ledColor
            assert.is_not_nil(color)
            assert.is_true(color.r > 0.8, "Holy should have high red")
            assert.is_true(color.g > 0.7, "Holy should have high green (yellow)")
        end)
        
        it("maps Nature (school 8) to green", function()
            LED:SetColorForSchool(8)
            local color = C_GamePad._ledColor
            assert.is_not_nil(color)
            assert.is_true(color.g > 0.6, "Nature should have high green")
            assert.is_true(color.r < 0.3, "Nature should have low red")
        end)
        
        it("maps Arcane (school 64) to magenta", function()
            LED:SetColorForSchool(64)
            local color = C_GamePad._ledColor
            assert.is_not_nil(color)
            assert.is_true(color.r > 0.7, "Arcane should have high red")
            assert.is_true(color.b > 0.7, "Arcane should have high blue")
        end)
    end)
    
    describe("multi-school spells", function()
        it("uses lowest bit school for multi-school spells", function()
            -- School mask 6 = Holy(2) + Fire(4); lowest bit = Holy(2)
            LED:SetColorForSchool(6)
            local color = C_GamePad._ledColor
            assert.is_not_nil(color)
            -- Should be Holy (gold) not Fire (orange-red)
            assert.is_true(color.g > 0.7, "Should use Holy color (high green) not Fire")
        end)
        
        it("handles school mask 0 gracefully", function()
            assert.has_no.errors(function()
                LED:SetColorForSchool(0)
            end)
        end)
    end)
    
    describe("SetColorForSpell", function()
        it("sets Fire color for Fireball (spellID 133)", function()
            LED:SetColorForSpell(133)  -- Fireball = Fire school
            local color = C_GamePad._ledColor
            assert.is_not_nil(color)
            assert.is_true(color.r > 0.8, "Fireball should produce fire (high red) LED color")
        end)
        
        it("sets Frost color for Frostbolt (spellID 116)", function()
            LED:SetColorForSpell(116)  -- Frostbolt = Frost school
            local color = C_GamePad._ledColor
            assert.is_not_nil(color)
            assert.is_true(color.b > 0.7, "Frostbolt should produce frost (high blue) LED color")
        end)
        
        it("handles unknown spell ID gracefully", function()
            assert.has_no.errors(function()
                LED:SetColorForSpell(99999)  -- unknown spell
            end)
        end)
    end)
    
    describe("LED disabled", function()
        it("does not set LED color when ledEnabled is false", function()
            CP.db.profile.ledEnabled = false
            C_GamePad._ledColor = nil
            LED:SetColor(1.0, 0.0, 0.0)
            assert.is_nil(C_GamePad._ledColor)
        end)
    end)
    
    describe("ClearColor", function()
        it("clears LED color", function()
            LED:SetColor(1.0, 0.0, 0.0)
            assert.is_not_nil(C_GamePad._ledColor)
            LED:ClearColor()
            assert.is_nil(C_GamePad._ledColor)
        end)
    end)
end)
