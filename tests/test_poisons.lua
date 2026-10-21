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
print("poison item tests passed")
