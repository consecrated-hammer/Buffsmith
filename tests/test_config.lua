local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local ns = { RefreshAll = function() end }
BuffsmithDB = { scale = "broken", palettePoint = "broken", categories = false, maxAlternatives = 99 }
assert(loadfile("Core/Config.lua"))("Buffsmith", ns)
ns.InitConfig()
equal(ns.db.scale, 1, "invalid scale is repaired")
equal(ns.db.maxAlternatives, 3, "alternatives are capped")
equal(type(ns.db.categories), "table", "categories are repaired")
equal(ns.db.palettePoint[1], "CENTER", "palette point is repaired")

-- A missing IsPlayerSpell global must not prevent the remaining compatible
-- spell probe from finding a castable self-buff.
local spellNS = { Plain = function(value) return value end }
C_SpellBook, C_Spell, IsPlayerSpell = nil, nil, nil
IsSpellKnown = function(spellID) return spellID == 1126 end
UnitClass = function() return "Druid", "DRUID" end
assert(loadfile("Data/SelfBuffs.lua"))("Buffsmith", spellNS)
local buffs = spellNS.KnownSelfBuffs()
equal(#buffs, 1, "legacy IsSpellKnown fallback is reached")
equal(buffs[1].spellID, 1126, "known self-buff is retained")
print("config tests passed")
