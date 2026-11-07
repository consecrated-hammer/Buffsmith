local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
-- Fixture IDs: reproduce the reported cooked foods without an item-ID allowlist.
local bag = { 9001, 9002, 9001 }
local items = { [9001] = "Coyote Steak", [9002] = "Crocolisk Steak" }
local usable = false
GetTime = function() return 100 end
C_Container = {
    GetContainerNumSlots = function(id) return id == 0 and #bag or 0 end,
    GetContainerItemID = function(_, slot) return bag[slot] end,
    GetContainerItemInfo = function() return { stackCount = 2 } end,
}
C_Item = {
    GetItemInfo = function(id) return items[id], "item:" .. id, 1, 1, 5, "Consumable", "Food & Drink", 20, "", 1 end,
    IsUsableItem = function() return usable end,
}
C_TooltipInfo = { GetItemByID = function() return { lines = {
    { leftText = "Use: Restores health. If you spend at least 10 seconds eating you will become well fed." },
} } end }
local ns = { db = { consumableAuras = {} }, Plain = function(v) return v end,
    IsSecret = function() return false end, IsCombatLocked = function() return false end }
assert(loadfile("Data/Consumables.lua"))("Buffsmith", ns)
assert(loadfile("Features/Inventory.lua"))("Buffsmith", ns)
ns.Inventory:Refresh()
eq(ns.Inventory:ReminderSummary("food"), "2 in your bags; currently unavailable.", "temporary use restrictions cannot mean no food owned")
eq(#ns.Inventory:OwnedChoices("food"), 2, "both cooked food types discovered")
eq(#ns.Inventory:Choices("food"), 0, "unavailable food excluded from cast choices")
eq(ns.Inventory:OwnedChoices("food")[1].count + ns.Inventory:OwnedChoices("food")[2].count, 6, "owned stacks counted across slots")
assert(ns.Inventory:ReminderFor(ns.Inventory:OwnedChoices("food")[1]):find("Currently unavailable", 1, true), "row explains unavailability")
usable = true
ns.Inventory:Refresh()
eq(#ns.Inventory:Choices("food"), 2, "foods become actionable after temporary restriction ends")
eq(#ns.Inventory:OwnedChoices("food"), 2, "ownership does not change on landing")
print("inventory ownership tests passed")

-- A restricted item must not erase useful learned timing for another owned item.
ns.db.consumableAuras[9001] = { duration = 1000 }
ns.Actions = { Percent = function() return 10 end, Refresh = function() end }
C_Item.IsUsableItem = function(id) return id == 9001 end
ns.Inventory:Refresh()
local summary = ns.Inventory:ReminderSummary("food")
assert(summary:find("Coyote Steak: 1m left", 1, true), "mixed availability retains learned timer")
assert(summary:find("1 currently unavailable", 1, true), "mixed availability appends unavailable count")
eq(#ns.Inventory:Choices("food"), 1, "restricted item remains excluded from cast choices")
assert(ns.Inventory.lastStatus:find("eligible: 1 food", 1, true), "diagnostics label usability counts explicitly")
