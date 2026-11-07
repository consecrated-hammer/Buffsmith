local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function fixture()
    local s = { time = 100, timers = {}, combat = false, usable = false, endTime = 101, reads = 0, refreshes = 0 }
    local secret = {}
    local ns = { db = { consumableAuras = {} }, IsCombatLocked = function() return s.combat end,
        Plain = function(v) if v ~= secret then return v end end, IsSecret = function(v) return v == secret end,
        RefreshAll = function() s.refreshes = s.refreshes + 1 end }
    C_Timer = { After = function(delay, fn) s.timers[#s.timers + 1] = { delay, fn } end }
    GetTime = function() return s.time end
    GetItemCooldown, IsUsableItem = nil, nil
    C_Container = { GetContainerNumSlots = function() error("no bag scans") end }
    C_TooltipInfo = { GetItemByID = function() error("no tooltip scans") end }
    C_Item = { GetItemInfo = function() error("no metadata scans") end,
        IsUsableItem = function()
            s.reads = s.reads + 1
            if s.error then error("restricted") end
            if s.secret then return secret end
            return s.usable, s.noMana
        end,
        GetItemCooldown = function()
            if s.secretCooldown then return secret end
            if s.endTime then return 100, s.endTime - 100, 1 end
            return 0, 0, 1
        end }
    assert(loadfile("Data/Consumables.lua"))("Buffsmith", ns)
    assert(loadfile("Features/Inventory.lua"))("Buffsmith", ns)
    local item = { itemID = 9001, kind = "item", category = "food", name = "Food", usable = false, usabilityKnown = true }
    ns.Inventory.ownedItems, ns.Inventory.items = { food = { item } }, { food = {} }
    return ns, s, item
end
local ns, s, item = fixture()
ns.Inventory:RefreshUsability()
eq(#s.timers, 1, "unavailable owned food schedules a readable expiry")
s.time, s.usable = 101.1, true
local wake = table.remove(s.timers, 1); wake[2]()
eq(#ns.Inventory:Choices("food"), 1, "expiry restores food without any bag or tooltip query")
eq(s.refreshes, 1, "only changed eligibility rebuilds the UI")
ns.Inventory:QueueUsabilityRefresh(); ns.Inventory:QueueUsabilityRefresh()
eq(#s.timers, 1, "event refreshes coalesce")
table.remove(s.timers, 1)[2]()
eq(s.refreshes, 1, "unchanged eligibility does not rebuild")

ns, s = fixture()
ns.Inventory:RefreshUsability()
local first = table.remove(s.timers, 1)
s.endTime, s.time = 105, 101.1
first[2]()
eq(#ns.Inventory:Choices("food"), 0, "extended cooldown does not falsely restore food")
eq(#s.timers, 1, "extended cooldown gets one replacement wakeup")
s.time, s.usable = 105.1, true
table.remove(s.timers, 1)[2]()
eq(#ns.Inventory:Choices("food"), 1, "extended cooldown eventually restores")

ns, s = fixture()
ns.Inventory:RefreshUsability()
s.combat = true
table.remove(s.timers, 1)[2]()
eq(s.refreshes, 0, "combat callback never rebuilds protected UI")
eq(ns.Inventory.usabilityDeferred, true, "combat marks deferred observation")
s.combat, s.time, s.usable = false, 102, true
ns.Inventory:QueueUsabilityRefresh(); table.remove(s.timers, 1)[2]()
eq(#ns.Inventory:Choices("food"), 1, "postcombat observation recovers")

ns, s, item = fixture()
s.endTime = nil
ns.Inventory:RefreshUsability()
eq(#s.timers, 0, "permanent restriction has no invented retry deadline")
s.secret, s.secretCooldown = true, true
ns.Inventory:RefreshUsability()
eq(item.usable, true, "unreadable usability preserves native input")
eq(item.usabilityKnown, false, "unknown is not labelled confirmed ready")
eq(#s.timers, 0, "secret cooldown has no invented deadline")
s.secret = false; s.error = true
ns.Inventory:RefreshUsability()
eq(item.usabilityKnown, false, "API error remains unknown")
s.error, s.noMana = false, true
ns.Inventory:RefreshUsability()
eq(item.usable, true, "no-mana result stays eligible")
eq(item.usabilityKnown, true, "readable no-mana result is known")
print("cached inventory readiness tests passed")

-- A cooldown can end without IsUsableItem changing at all.
ns, s, item = fixture()
s.usable, item.usable = true, true
ns.Inventory:RefreshUsability()
local cooldownWake = table.remove(s.timers, 1)
s.time = 101.1
cooldownWake[2]()
eq(s.refreshes, 1, "cooldown-only expiry rebuilds the grid even with usability unchanged")
eq(item.cooling, false, "ended cooldown is observed")
