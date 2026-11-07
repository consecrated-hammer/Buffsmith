local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local helpful, harmful, delayed = {}, {}, nil
GetTime = function() return 100 end
UnitIsDeadOrGhost, UnitOnTaxi, IsResting = function() return false end, function() return false end, function() return false end
C_Timer = { After = function(_, fn) delayed = fn end }
C_UnitAuras = {
    GetAuraDataByIndex = function(_, index, filter) return (filter == "HARMFUL" and harmful or helpful)[index] end,
    GetUnitAuraBySpellID = function(_, id)
        for _, aura in ipairs(helpful) do if aura.spellId == id then return aura end end
    end,
}
C_Item = { GetItemCooldown = function() return 0, 0, 1 end }
local ns = { TARGET = "Camelot", db = { consumableAuras = {}, categories = { food = true },
    excludedConsumables = {}, reminderPercent = { food = 10, buff = 10, item = {} } },
    Plain = function(v) return v end, IsSecret = function() return false end, IsCombatLocked = function() return false end }
assert(loadfile("Data/Consumables.lua"))("Buffsmith", ns)
assert(loadfile("Features/Inventory.lua"))("Buffsmith", ns)
assert(loadfile("Features/Actions.lua"))("Buffsmith", ns)
local food = { kind = "item", itemID = 9001, name = "Coyote Steak", category = "food", usable = true }
ns.Inventory.items.food = { food }
-- A synthetic shared icon cannot make a known camping effect count as food.
helpful = { { spellId = 1229741, name = "Camp Benefits", duration = 3600, expirationTime = 3700, icon = 136000 } }
eq(ns.Inventory:CategoryStatus("food"), nil, "Camp Benefits cannot cover Well Fed even with shared icon")
ns.db.consumableAuras[9001] = { spellID = 1229741, name = "Camp Benefits", duration = 3600 }
eq(#ns.Actions:VisibleChoices("food"), 1, "old camp mapping cannot hide owned food")
eq(ns.db.consumableAuras[9001].spellID, 1229741, "old mapping retained without being trusted")
helpful = {}
harmful = { { spellId = 1229451, name = "Boosted Rest", duration = 3600, expirationTime = 3700 } }
ns.db.consumableAuras[9001] = { spellID = 1229451, name = "Boosted Rest", duration = 3600 }
eq(ns.Inventory:LearnedAura(food), nil, "camp lockout cannot be a learned food effect")
eq(#ns.Actions:VisibleChoices("food"), 1, "Boosted Rest cannot suppress food")
-- Legitimate Well Fed still suppresses food normally.
ns.db.consumableAuras[9001] = { spellID = 12345, name = "Well Fed", duration = 900 }
helpful = { { spellId = 12345, name = "Well Fed", duration = 900, expirationTime = 1000, icon = 1 } }
eq(#ns.Actions:VisibleChoices("food"), 0, "real Well Fed still covers food")
-- A learned food effect still covers ready alternatives if its own item is unusable.
local alternative = { kind = "item", itemID = 9002, name = "Crocolisk Steak", category = "food", usable = true }
ns.Inventory.ownedItems = { food = { food, alternative } }
ns.Inventory.items.food = { alternative }
helpful = { { spellId = 12345, name = "Specific food effect", duration = 900, expirationTime = 1000, icon = 1 } }
eq(#ns.Actions:VisibleChoices("food"), 0, "owned learned mapping covers ready alternative even if source item is unusable")
ns.Inventory.items.food = { food }
-- A camp benefit arriving during food use cannot overwrite a valid food mapping.
helpful = {}
ns.Inventory:BeginConsumableUse(food)
helpful = { { spellId = 1229741, name = "Camp Benefits", duration = 3600, expirationTime = 3700 } }
ns.Inventory:FinishConsumableUse()
assert(delayed); delayed()
eq(ns.db.consumableAuras[9001].spellID, 12345, "new camping effect cannot be learned as food")
print("food and camping separation tests passed")

-- Other buffs arriving during eating also cannot become food's learned effect.
helpful = {}
ns.Inventory:BeginConsumableUse(food)
helpful = { { spellId = 21562, name = "Fortitude", duration = 3600, expirationTime = 3700, icon = 1 } }
ns.Inventory:FinishConsumableUse(); delayed()
eq(ns.db.consumableAuras[9001].spellID, 12345, "unrelated class buff cannot overwrite food mapping")
helpful = {}
ns.Inventory:BeginConsumableUse(food)
helpful = { { spellId = 54321, name = "Well Fed", duration = 900, expirationTime = 1000, icon = 136000 } }
ns.Inventory:FinishConsumableUse(); delayed()
eq(ns.db.consumableAuras[9001].spellID, 54321, "positive Well Fed observation still learns normally")
