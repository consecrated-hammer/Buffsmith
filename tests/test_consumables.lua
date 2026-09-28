local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

-- Bag items and the tooltip text the client would show for each.
local items = {
    [1262] = { "Keg of Thunderbrew", "Food & Drink", "Use: Increases Stamina by 3 for 4 min.  Gets you pretty drunk." },
    [2288] = { "Conjured Fresh Water", "Food & Drink", "Use: Restores 436 mana over 21 sec." },
    [4599] = { "Cured Ham Steak", "Food & Drink", "Use: Restores 1392 health over 30 sec.  If you spend at least 10 seconds eating you will become well fed." },
    [8949] = { "Elixir of Agility", "Elixir", "Use: Increases Agility by 15 for 1 hour." },
    [4623] = { "Lesser Stoneshield Potion", "Potion", "Use: Increases armor by 1000 for 1.5 min." },
    [13461] = { "Greater Arcane Protection Potion", "Potion", "Use: Absorbs 1950 to 3250 arcane damage." },
    [13445] = { "Elixir of Superior Defense", "Elixir", "Use: Increases armor by 450 for 1 hour." },
    [13510] = { "Flask of the Titans", "Flask", "Use: Increases the player's maximum health by 1200 for 2 hours." },
}
local bag = { 1262, 2288, 4599, 8949, 4623, 13461, 13445, 13510 }

C_Container = {
    GetContainerNumSlots = function(id) return id == 0 and #bag or 0 end,
    GetContainerItemID = function(_, slot) return bag[slot] end,
    GetContainerItemInfo = function(_, slot) return bag[slot] and { stackCount = 1 } or nil end,
}
C_Item = {
    GetItemInfo = function(itemID)
        local item = items[itemID]
        return { itemName = item[1], itemLink = "item:" .. itemID, itemType = "Consumable", itemSubType = item[2], iconFileID = 1 }
    end,
    IsUsableItem = function() return true end,
}
C_TooltipInfo = { GetItemByID = function(itemID) return { lines = { { leftText = items[itemID][1] }, { leftText = items[itemID][3] } } } end }

local ns = { db = { consumableAuras = {} }, Plain = function(value) return value end,
    IsSecret = function() return false end, IsCombatLocked = function() return false end }
assert(loadfile("Data/Consumables.lua"))("Buffsmith", ns)
assert(loadfile("Features/Inventory.lua"))("Buffsmith", ns)
equal(ns.Inventory:Refresh(), true, "the bags are scanned")

local function names(category)
    local out = {}
    for _, item in ipairs(ns.Inventory:Choices(category)) do out[#out + 1] = item.name end
    return table.concat(out, ",")
end
equal(names("food"), "Cured Ham Steak", "Well Fed food stays food")
equal(names("other"), "Elixir of Agility,Elixir of Superior Defense,Keg of Thunderbrew", "elixirs and timed-buff drinks are other buffs")
equal(names("flask"), "Flask of the Titans", "flasks keep their own category")
equal(ns.Inventory:CategoryStatus("other"), nil, "other buffs are judged one item at a time")

print("consumable tests passed")
