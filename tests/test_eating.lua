local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

-- While the player is eating or drinking, the bar keeps its icons but no
-- icon or the trigger casts, because casting would stand the player up.
local auras = {}
C_UnitAuras = { GetAuraDataByIndex = function(_, index) return auras[index] end }
C_Spell = { GetSpellName = function(spellID) return spellID == 433 and "Nourriture" or nil end }
GetSpellInfo = nil

local ns = { db = {}, Plain = function(value) return value end,
    IsSecret = function() return false end, IsCombatLocked = function() return false end }
assert(loadfile("Features/Actions.lua"))("Buffsmith", ns)

local function fakeButton()
    local attributes = {}
    return { attributes = attributes,
        SetAttribute = function(_, key, value) attributes[key] = value end }
end
local spell = { kind = "spell", name = "Arcane Intellect", unit = "player" }

equal(ns.Actions:IsEating(), false, "no aura, not eating")
ns.Actions.eatingPaused = ns.Actions:IsEating()
local button = fakeButton()
equal(ns.Actions:Configure(button, spell), true, "a buff is actionable normally")
equal(button.attributes.type1, "spell", "and casts on left-click")

auras[1] = { name = "Well Fed" }
auras[2] = { name = "Food & Drink" }
equal(ns.Actions:IsEating(), true, "Food & Drink counts as eating")
ns.Actions.eatingPaused = ns.Actions:IsEating()
equal(ns.Actions:Configure(button, spell), false, "nothing is actionable while eating")
equal(button.attributes.type1, nil, "the previous cast is cleared")
equal(button.buffsmithEntry, spell, "the icon keeps its entry for the tooltip")

auras[2] = { name = "Nourriture" }
equal(ns.Actions:IsEating(), true, "the client's localised Food name counts")

auras[2] = nil
equal(ns.Actions:IsEating(), false, "eating ends with the aura")

print("eating tests passed")
