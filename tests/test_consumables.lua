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

-- Camping uses its real effect, not the duration in the placement tooltip or
-- an aura learned incidentally while placing a world object.
do
    items[279979] = { "Camp Chair", "Other", "Use: Assembles a camp chair that allows nearby players to gain 2% increased critical strike chance. Requires a Campfire nearby. All camping features share a cooldown of 1 hour." }
    items[279978] = { "Camp Tent", "Other", "Use: Builds a tent that allows nearby players to increase Rested experience to 5% of a level. Requires a Campfire nearby. All camping features share a cooldown of 1 hour." }
    bag[#bag + 1], bag[#bag + 2] = 279979, 279978
    local clock, active, lockout, unknown, locked = 100, false, false, false, false
    GetTime = function() return clock end
    local filters = {}
    C_UnitAuras = { GetAuraDataByIndex = function(_, index, filter)
        filters[filter] = true
        if unknown then error("unavailable") end
        if index ~= 1 then return end
        if filter == "HELPFUL" and active then
            return { spellId = 1229741, name = "Camp Benefits", duration = 3600, expirationTime = 3700 }
        elseif filter == "HARMFUL" and lockout then
            return { spellId = 1229451, name = "Boosted Rest", duration = 3600, expirationTime = 3700 }
        end
    end }
    ns.TARGET = "Camelot"
    ns.IsCombatLocked = function() return locked end
    ns.db.categories, ns.db.excludedConsumables = { other = true }, {}
    ns.db.reminderPercent = { other = 50, buff = 10 }
    -- A stale learned aura must not override either camp rule.
    ns.db.consumableAuras[279979] = { spellID = 9999, name = "Wrong effect", duration = 60 }
    ns.db.consumableAuras[279978] = { spellID = 1229741, name = "Camp Benefits", duration = 3600 }
    ns.Inventory:Refresh()
    assert(loadfile("Features/Actions.lua"))("Buffsmith", ns)
    local function offered()
        local out = {}
        for _, entry in ipairs(ns.Actions:VisibleChoices("other")) do out[entry.itemID] = entry end
        return out
    end
    equal(offered()[279979] ~= nil, true, "chair offered without camping buff")
    equal(offered()[279978] ~= nil, true, "tent offered without rested lockout")
    active = true
    equal(offered()[279979], nil, "Camp Benefits hides chair without prior item use")
    equal(offered()[279978] ~= nil, true, "Camp Benefits does not substitute for rested lockout")
    ns.Actions.nextReminderDelay = nil
    clock = 3699
    equal(offered()[279979], nil, "chair stays hidden right up to buff expiry")
    equal(ns.Actions.nextReminderDelay, 1, "refresh scheduled at expiry, not generic reminder threshold")
    clock = 3700
    equal(offered()[279979] ~= nil, true, "expired aura returns chair before removal event")
    clock, active, lockout = 100, false, true
    equal(offered()[279979] ~= nil, true, "Boosted Rest does not hide chair")
    equal(offered()[279978], nil, "harmful Boosted Rest hides tent")
    active = true
    equal(offered()[279979], nil, "both effects hide chair")
    equal(offered()[279978], nil, "both effects hide tent")
    equal(filters.HELPFUL and filters.HARMFUL, true, "correct helpful and harmful filters used")
    active, lockout, unknown = false, false, true
    ns.Actions.nextReminderDelay = nil
    equal(offered()[279979], nil, "unavailable aura read is not treated as missing")
    equal(ns.Actions.nextReminderDelay, 5, "unavailable aura read schedules a retry")
    unknown, locked = false, true
    equal(ns.Inventory:CampingStatus({ itemID = 279979 }).state, "unknown", "no camping scan during combat")
    locked = false
    ns.db.excludedConsumables[279979] = true
    equal(offered()[279979], nil, "ignored chair stays ignored")
    ns.db.excludedConsumables[279979] = nil
    C_Item.GetItemCooldown = function(id) return id == 279979 and 50 or 0, 3600, 1 end
    equal(offered()[279979], nil, "chair cooldown still respected")
    C_Item.GetItemCooldown = nil
    ns.Inventory.pendingConsumable = { itemID = 1262 }
    ns.Inventory:BeginConsumableUse({ kind = "item", itemID = 279979 })
    equal(ns.Inventory.pendingConsumable, nil, "camp placement never learns unrelated buffs")
    equal(ns.db.consumableAuras[279979].spellID, 9999, "saved mappings preserved but ignored for camping")
    ns.TARGET = "Mainline"
    equal(ns.Inventory:CampingStatus({ itemID = 279979 }), nil, "Retail does not use Forever rules")
end

print("consumable tests passed")
