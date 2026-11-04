local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local roster, auras, grouped, hidden, dead = {}, {}, true, {}, {}
local secret = {}
UnitExists = function(unit) return roster[unit] ~= nil end
UnitIsPlayer = function(unit) return not unit:find("pet") end
UnitCanAssist = function() return true end
UnitIsDeadOrGhost = function(unit) return dead[unit] == true end
UnitIsVisible = function(unit) return not hidden[unit] end
UnitIsConnected = function() return true end
UnitClass = function(unit) return "Class", roster[unit].class end
UnitName = function(unit) return roster[unit].name or unit end
UnitGUID = function(unit) return roster[unit] and roster[unit].guid end
IsInGroup = function() return grouped end
GetTime = function() return 100 end
C_UnitAuras = {
    GetUnitAuraBySpellID = function(unit, id) return (auras[unit] or {})[id] end,
    GetAuraDataByIndex = function(unit, index)
        if index ~= 1 then return end
        for _, aura in pairs(auras[unit] or {}) do return aura end
    end,
}

local function load(target)
    roster = { player = { class = "WARRIOR", guid = "self" },
        party1 = { class = "MAGE", guid = "mage-1", name = "Newmage" } }
    auras, grouped, hidden, dead = {}, true, {}, {}
    local ns = { TARGET = target, db = { showPartyCoverage = true, reminderPercent = { buff = 10 } },
        Plain = function(value) if value ~= secret then return value end end,
        IsSecret = function(value) return value == secret end,
        IsCombatLocked = function() return false end }
    assert(loadfile("Data/PartyBuffs.lua"))("Buffsmith", ns)
    assert(loadfile("Data/RetailBuffs.lua"))("Buffsmith", ns)
    assert(loadfile("Features/Actions.lua"))("Buffsmith", ns)
    return ns.Actions, ns
end

local function aura(id, source, name)
    auras.player = { [id] = { duration = 3600, expirationTime = 3700,
        sourceUnit = source, name = name } }
end

-- Class and level never establish that a spell was actually learned.
local actions = load("Camelot")
equal(#actions:PartyCoverage(), 0, "level 1 mage without observed spell stays absent")
UnitLevel = function() return 60 end
equal(#actions:PartyCoverage(), 0, "high level alone is not evidence either")
aura(1459, nil)
equal(#actions:PartyCoverage(), 0, "missing attribution cannot prove provider")
aura(1459, secret)
equal(#actions:PartyCoverage(), 0, "secret attribution cannot prove provider")
aura(1459, "player")
equal(#actions:PartyCoverage(), 0, "someone else's buff cannot prove mage knows it")
aura(1459, "party1")
equal(actions:PartyCoverage()[1].providerText, "Newmage", "observed caster qualifies")
auras = {}
equal(#actions:PartyCoverage(), 1, "reminder remains after observed buff expires")
hidden.party1 = true
equal(#actions:PartyCoverage(), 0, "out of range caster is not offered")
hidden.party1 = nil
equal(#actions:PartyCoverage(), 1, "returning caster retains observed spell")
dead.party1 = true
equal(#actions:PartyCoverage(), 0, "dead caster is not offered")
dead.party1 = nil
equal(#actions:PartyCoverage(), 1, "resurrected caster retains observed spell")

roster.party2 = { class = "MAGE", guid = "mage-2", name = "Othermage" }
equal(actions:PartyCoverage()[1].providerText, "Newmage", "unconfirmed same-class member excluded")
roster.party1 = nil
equal(#actions:PartyCoverage(), 0, "departed caster is forgotten")
roster.party1 = { class = "MAGE", guid = "mage-3" }
equal(#actions:PartyCoverage(), 0, "replacement in same slot cannot inherit evidence")

-- Every Forever class entry uses the same evidence gate, including talents.
local _, catalogue = load("Camelot")
for class, buffs in pairs(catalogue.PARTY_BUFFS) do
    for _, buff in ipairs(buffs) do
        actions = load("Camelot")
        roster.party1.class = class
        roster.partypet1 = { guid = "pet-1" }
        equal(#actions:PartyCoverage(), 0, buff.label .. " starts unconfirmed")
        aura(buff.auraID, buff.pet and "partypet1" or "party1")
        equal(#actions:PartyCoverage(), 1, buff.label .. " qualifies after attribution")
        auras = {}
        equal(#actions:PartyCoverage(), 1, buff.label .. " remains known after expiration")
        grouped = false
        equal(#actions:PartyCoverage(), 0, "solo drops evidence")
        grouped = true
        equal(#actions:PartyCoverage(), 0, "rejoining does not restore old evidence")
    end
end

actions = load("Camelot")
roster.party1.class = "WARLOCK"
roster.partypet1 = { guid = "imp-1" }
aura(6307, "partypet1")
equal(#actions:PartyCoverage(), 1, "Blood Pact attributed to current pet qualifies")
auras = {}
roster.partypet1.guid = "different-pet"
equal(#actions:PartyCoverage(), 0, "pet swap invalidates Blood Pact")
roster.partypet1 = nil
equal(#actions:PartyCoverage(), 0, "missing pet cannot provide Blood Pact")

-- Rank IDs absent from the catalogue still match the buff's existing name path.
actions = load("Camelot")
aura(1460, "party1", "Arcane Intellect")
equal(#actions:PartyCoverage(), 1, "higher rank establishes availability by name")
auras = {}
actions:Dismiss(actions:PartyCoverage()[1])
equal(#actions:PartyCoverage(), 0, "dismissal still suppresses confirmed provider")

actions = load("Mainline")
equal(#actions:PartyCoverage(), 1, "Retail retains class-based coverage")

print("party coverage tests passed")
