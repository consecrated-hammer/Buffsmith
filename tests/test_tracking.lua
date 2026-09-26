local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

-- The minimap's tracking list: three spells and one static type.
local tracking
local function resetTracking()
    tracking = {
        { name = "Find Herbs", texture = 1, active = false, type = "spell", spellID = 2383 },
        { name = "Flight Master", texture = 2, active = true, type = "other" },
        { name = "Find Minerals", texture = 3, active = false, type = "spell", spellID = 2580 },
        { name = "Find Treasure", texture = 4, active = false, type = "spell", spellID = 2481 },
    }
end
local function install()
    C_Minimap = {
        GetNumTrackingTypes = function() return #tracking end,
        GetTrackingInfo = function(index) return tracking[index] end,
    }
    GetNumTrackingTypes, GetTrackingInfo = nil, nil
end

local function load(target)
    resetTracking()
    install()
    local db = { excludedBuffs = {}, buffDurations = {} }
    local ns = { TARGET = target, db = db, Plain = function(value) return value end }
    UnitClass = function() return "Dwarf", "WARRIOR" end
    assert(loadfile("Data/SelfBuffs.lua"))("Buffsmith", ns)
    assert(loadfile("Features/Tracking.lua"))("Buffsmith", ns)
    return ns, db
end

local function names(list)
    local out = {}
    for _, entry in ipairs(list) do out[#out + 1] = entry.name end
    return table.concat(out, ",")
end

-- Only spell-based tracking is offered, with gathering ticked by default.
do
    local ns = load("Camelot")
    local available = ns.Tracking:Available()
    equal(names(available), "Find Herbs,Find Minerals,Find Treasure", "static tracking types are skipped")
    equal(ns.IsBuffExcluded(available[1]), false, "Find Herbs starts ticked")
    equal(ns.IsBuffExcluded(available[2]), false, "Find Minerals starts ticked")
    equal(ns.IsBuffExcluded(available[3]), true, "Find Treasure starts unticked")
    equal(available[1].castID, 2383, "the tracking spell is what the bar casts")
    equal(available[1].permanent, true, "tracking has no expiry reminder")
end

-- WoW Forever: one slot, satisfied by any ticked tracking.
do
    local ns, db = load("Camelot")
    equal(ns.Tracking.Exclusive(), true, "Forever is assumed to track one thing at a time")
    equal(names(ns.Tracking:Entries()), "Find Herbs", "with nothing on, the first ticked tracking is offered")
    tracking[3].active = true
    equal(names(ns.Tracking:Entries()), "", "any ticked tracking being on satisfies the slot")
    tracking[3].active = false
    db.excludedBuffs[2383] = true
    equal(names(ns.Tracking:Entries()), "Find Minerals", "unticking Find Herbs offers the next")
    db.excludedBuffs[2481] = false
    tracking[4].active = true
    equal(names(ns.Tracking:Entries()), "", "a ticked Find Treasure satisfies it too")
    tracking[4].active = false
    ns.Actions = { IsSuppressed = function(_, entry) return entry.spellID == 2580 end }
    equal(names(ns.Tracking:Entries()), "Find Treasure", "a dismissed tracking yields to the next ticked one")
end

-- A client seen running two tracking types at once is remembered as allowing it.
do
    local ns, db = load("Camelot")
    tracking[1].active, tracking[3].active = true, true
    ns.Tracking:Available()
    equal(db.trackingConcurrent, true, "two active tracking types are noticed")
    equal(ns.Tracking.Exclusive(), false, "and one slot is no longer assumed")
    tracking[3].active = false
    equal(names(ns.Tracking:Entries()), "Find Minerals", "each ticked tracking that is off is then offered")
end

-- Retail: several tracking types at once, so each missing one shows.
do
    local ns = load("Mainline")
    equal(ns.Tracking.Exclusive(), false, "Retail tracks several at once")
    equal(names(ns.Tracking:Entries()), "Find Herbs,Find Minerals", "every ticked tracking that is off shows")
end

-- Older clients return the fields in order rather than as a table.
do
    local ns = load("Camelot")
    C_Minimap = nil
    GetNumTrackingTypes = function() return 1 end
    GetTrackingInfo = function() return "Find Herbs", 1, false, "spell", nil, 2383 end
    equal(names(ns.Tracking:Available()), "Find Herbs", "the legacy tracking API is read")
    GetNumTrackingTypes, GetTrackingInfo = nil, nil
    equal(#ns.Tracking:Available(), 0, "no tracking API means no tracking entries")
end

-- The bar shows tracking alongside self-buffs.
do
    local ns, db = load("Camelot")
    db.reminderPercent, db.showTargetBuffs, db.showPartyBuffs, db.showPetBuffs = { buff = 10 }, false, false, false
    db.showPartyCoverage = false
    ns.IsSecret, ns.IsCombatLocked = function() return false end, function() return false end
    C_SpellBook, IsPlayerSpell, IsSpellKnown = nil, nil, nil
    C_UnitAuras = { GetUnitAuraBySpellID = function() return nil end, GetAuraDataByIndex = function() return nil end }
    GetTime, IsResting, IsInGroup = function() return 1 end, function() return false end, function() return false end
    UnitExists = function(unit) return unit == "player" end
    UnitIsPlayer, UnitCanAssist, UnitIsDeadOrGhost = function() return true end, function() return true end, function() return false end
    UnitIsUnit, UnitGUID = function(a, b) return a == b end, function(unit) return "guid-" .. unit end
    assert(loadfile("Features/Actions.lua"))("Buffsmith", ns)
    local entries = ns.Actions:Entries()
    equal(#entries, 1, "one bar entry")
    equal(entries[1].name, "Find Herbs", "the bar offers Find Herbs")
    equal(entries[1].kind, "spell", "as a castable spell")
    equal(ns.lastTrackingProbe[1], "Find Herbs", "diagnostics record it")
    tracking[1].active = true
    equal(#ns.Actions:Entries(), 0, "it disappears once tracking is on")
end

print("tracking tests passed")
