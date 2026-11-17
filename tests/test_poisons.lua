local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local items = {
    { "Instant Poison II", "Poison" },
    { "Crippling Poison", "Other" },
    { "Brilliant Wizard Oil", "Item Enhancement" },
    { "Anti-Poison Potion", "Potion" },
    { "Elixir of Poison Resistance", "Elixir" },
    { "Poisoned Bread", "Food & Drink" },
}
local main, off, hasMain, hasOff, usable = false, false, true, true, true
GetTime = function() return 100 end
GetSpecialization = function() return 1 end
GetInventoryItemID = function(_, slot) return slot == 16 and hasMain and 99 or nil end
OffhandHasWeapon = function() return hasOff end
GetWeaponEnchantInfo = function() return main, 0, 10, 1, off, 0, 10, 2 end
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #items or 0 end,
    GetContainerItemID = function(_, slot) return slot end,
    GetContainerItemInfo = function() return { stackCount = 3 } end,
}
C_Item = {
    GetItemInfo = function(id) return { itemName = items[id][1], itemSubType = items[id][2], itemType = "Consumable" } end,
    IsUsableItem = function(id) return id == 3 or usable end,
}
local ns = { Plain = function(value) return value end, IsSecret = function() return false end,
    IsCombatLocked = function() return false end, db = {
        categories = { weapon = true }, preferred = {}, excludedConsumables = {},
        consumableAuras = {}, reminderPercent = { item = {} },
    } }
assert(loadfile("Data/Consumables.lua"))("Buffsmith", ns)
assert(loadfile("Features/Inventory.lua"))("Buffsmith", ns)
assert(loadfile("Features/Actions.lua"))("Buffsmith", ns)
ns.Inventory:Refresh()
equal(#ns.Inventory:Choices("weapon"), 3, "poison subtype and poison names classified; potion excluded")
local function poisons()
    local choices = ns.Actions:VisibleChoices("weapon")
    local found = {}
    for _, choice in ipairs(choices) do if choice.poison then found[#found + 1] = choice end end
    return found, choices
end
local found, choices = poisons()
equal(#found, 2, "both poison choices visible")
equal(found[1].targetSlot, 16, "bare main hand first")
ns.Actions:RememberItem(found[2])
local mainChoice = found[2].itemID
local configuredMain = found[2]
main = true
found, choices = poisons()
equal(#choices, 2, "oil stays hidden while main hand enchanted")
equal(found[1].targetSlot, 17, "bare off-hand still offered")
equal(configuredMain.targetSlot, 16, "later query cannot mutate configured action target")
ns.Actions:RememberItem(found[1])
local offChoice = found[1].itemID
off = true
equal(#ns.Actions:VisibleChoices("weapon"), 0, "both coated means no prompt, even for charge-only coatings")
main, off = false, true
found, choices = poisons()
equal(choices[ns.Actions:Preferred("weapon", choices)].itemID, mainChoice, "main-hand choice retained")
main, off = true, false
found, choices = poisons()
equal(choices[ns.Actions:Preferred("weapon", choices)].itemID, offChoice, "off-hand choice retained")
hasOff = false
equal(#ns.Actions:VisibleChoices("weapon"), 0, "shield or empty off-hand never targeted")
hasMain, main = false, false
found = poisons()
equal(#found, 0, "no equipped weapons means no poison prompt")
hasMain, usable = true, false
ns.Inventory:Refresh()
equal(#ns.Inventory:Choices("weapon"), 1, "unusable class-restricted poisons omitted")
usable = true
ns.Inventory:Refresh()
found = poisons()
local attrs = {}
RegisterStateDriver = function() end
local button = { SetAttribute = function(_, key, value) attrs[key] = value end,
    GetAttribute = function(_, key) return attrs[key] end }
ns.Actions:Configure(button, found[1])
equal(attrs["type1"], "item", "secure item action")
equal(attrs["target-slot1"], 16, "secure action targets selected weapon")
equal(attrs["target-slot2"], nil, "right-click cannot coat a weapon")
local guard = assert(loadstring("return function(self, newstate) " .. attrs["_onstate-poisoncombat"] .. " end"))()
guard(button, "combat")
equal(attrs["type1"], nil, "combat entry disarms stale weapon targeting")
ns.Actions:Configure(button, found[1])
equal(attrs["type1"], "item", "out-of-combat refresh restores the item action")
ns.Actions:Configure(button, { kind = "spell", name = "Test" })
equal(attrs["target-slot1"], nil, "reused button clears weapon target")
ns.Actions.eatingPaused = true
ns.Actions:Configure(button, found[1])
equal(attrs["type1"], nil, "poison clicks disabled while eating")
ns.db.preferred["1"] = false
ns.Actions:Preferred("weapon", found)
ns.Actions:RememberItem(found[1])
equal(type(ns.db.preferred["1"]), "table", "invalid spec preferences are repaired")
-- Forever rogue settings resolve both preference and hand before preparing actions.
ns.TARGET = "Camelot"
UnitClass = function() return "Rogue", "ROGUE" end
assert(loadfile("Features/ClassBuffs.lua"))("Buffsmith", ns)
local C = ns.ClassBuffs
main, off, hasMain, hasOff, usable = false, false, true, true, true
ns.Actions.eatingPaused = false
ns.db.preferred["1"] = { ["poison:16"] = 1, ["poison:17"] = 2, weapon = 3 }
ns.Inventory:Refresh()
local slot, selected = C:PoisonSelection()
equal(slot, 16, "configured main hand first")
equal(selected.itemID, 1, "main-hand preference")
found, choices = poisons()
equal(choices[ns.Actions:Preferred("weapon", choices)].itemID, 1, "poison preferred over unrelated oil")
local prepared = found[1]
main = true
slot, selected = C:PoisonSelection()
equal(slot, 17, "existing main coating kept")
equal(selected.itemID, 2, "independent off-hand preference")
equal(prepared.targetSlot, 16, "prepared action slot stays stable")
main = false
C:SetPoisonPreference(16, 0)
slot = C:PoisonSelection()
equal(slot, 17, "main hand Off does not block off hand")
C:SetPoisonPreference(16, 999)
slot = C:PoisonSelection()
equal(slot, 17, "unavailable main poison does not block off hand")
local values, labels = C:PoisonOptions(16)
equal(values[#values], 999, "unavailable saved choice remains visible")
assert(labels[#labels]:find("not in bags", 1, true))
C:Config().poisonFallback = true
slot, selected = C:PoisonSelection()
equal(slot, 16, "fallback permits bare main hand")
found, choices = poisons()
local fallback = choices[ns.Actions:Preferred("weapon", choices)]
equal(fallback.poisonFallback, true, "fallback action marked")
ns.Actions:RememberItem(fallback)
equal(C:PoisonPreference(16), 999, "fallback never overwrites saved poison")
equal(ns.db.preferred["1"].weapon, 3, "poison casting preserves oil preference")
C:Config().poisonFallback = false
C:SetPoisonPreference(16, 1)
ns.db.excludedConsumables[1] = true
slot = C:PoisonSelection()
equal(slot, 17, "ignored preferred poison advances to other hand")
ns.db.excludedConsumables[1] = nil
C:SetPoisonPreference(16, 0); C:SetPoisonPreference(17, 0)
equal(C:PoisonSelection(), nil, "both hands Off")
C:SetPoisonPreference(16, -1); C:SetPoisonPreference(17, -1)
ns.db.preferred["1"]["poison:16"] = nil
ns.db.preferred["1"]["poison:17"] = nil
equal(C:PoisonPreference(16), nil, "legacy oil is not imported as a poison")
ns.db.preferred["1"].weapon = 2
equal(C:PoisonPreference(16), 2, "legacy poison preference inherited")
C:SetPoisonPreference(16, 1); C:SetPoisonPreference(17, 2)
main, off = true, true
equal(C:PoisonSelection(), nil, "both active coatings preserved")
main, off, hasMain, hasOff = true, false, true, false
equal(C:PoisonSelection(), nil, "shield or empty off hand not targeted")
C:Config().poisons = false
main, hasOff = false, true
equal(C:PoisonSelection(), nil, "poison reminder off")
C:Config().poisons = true
usable = false; ns.Inventory:Refresh()
equal(C:PoisonSelection(), nil, "unusable poison not offered")
usable = true; ns.Inventory:Refresh()
ns.db.categories.weapon = false
equal(#poisons(), 0, "global weapon category remains a ceiling")
ns.db.categories.weapon = true
-- Casting an automatically selected poison must not pin the automatic setting.
C:SetPoisonPreference(16, -1); C:SetPoisonPreference(17, -1)
found, choices = poisons()
local automatic = choices[ns.Actions:Preferred("weapon", choices)]
equal(automatic.poisonAutomatic, true, "automatic action marked")
ns.Actions:RememberItem(automatic)
equal(ns.db.preferred["1"]["poison:16"], -1, "Automatic survives casting")
local calls, originalSelection = 0, C.PoisonSelection
C.PoisonSelection = function(self) calls = calls + 1; return originalSelection(self) end
found, choices = poisons()
ns.Actions:Preferred("weapon", choices)
equal(calls, 1, "one poison selection per category query")
C.PoisonSelection = originalSelection
ns.TARGET = "Mainline"
equal(C:IsClass("ROGUE"), false, "Retail poison spell model unaffected")
print("poison item tests passed")
