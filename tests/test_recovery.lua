local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end
local ID, secret = 1259705, {}
local state
local function load(target)
    state = { health = 100, maxHealth = 100, mana = 100, maxMana = 100, known = true,
        cooldown = { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }, now = 100 }
    UnitClass = function() return "Hunter", "HUNTER" end
    UnitHealth, UnitHealthMax = function() return state.health end, function() return state.maxHealth end
    UnitPower = function(unit, power) equal(unit, "player", "mana owner"); equal(power, 0, "checks mana explicitly"); return state.mana end
    UnitPowerMax = function(_, power) equal(power, 0, "mana maximum uses same type"); return state.maxMana end
    UnitExists = function(unit) return unit == "player" end
    UnitIsDeadOrGhost = function() return state.dead end
    UnitOnTaxi = function() return state.taxi end
    IsInGroup, IsResting = function() return false end, function() return state.resting end
    GetTime = function() return state.now end
    Enum = { SpellBookSpellBank = { Player = 0 }, PowerType = { Mana = 0 } }
    C_SpellBook = { IsSpellKnown = function(id) return id == ID and state.known end }
    IsPlayerSpell, IsSpellKnown, GetSpellCooldown, GetSpellInfo = nil, nil, nil, nil
    C_Spell = { GetSpellInfo = function(id) return { name = id == ID and "Read Leyline" or "Other", iconID = id } end,
        GetSpellCooldown = function(id) equal(id, ID, "reads resolved cooldown ID"); return state.cooldown end }
    C_UnitAuras = { GetAuraDataByIndex = function() return nil end }
    local ns = { TARGET = target, Plain = function(v) if v ~= secret then return v end end,
        IsSecret = function(v) return v == secret end, IsCombatLocked = function() return state.combat end }
    assert(loadfile("Core/Config.lua"))("Buffsmith", ns)
    BuffsmithDB = nil; ns.InitConfig()
    assert(loadfile("Data/SelfBuffs.lua"))("Buffsmith", ns)
    assert(loadfile("Data/PartyBuffs.lua"))("Buffsmith", ns)
    assert(loadfile("Data/RetailBuffs.lua"))("Buffsmith", ns)
    assert(loadfile("Features/Actions.lua"))("Buffsmith", ns)
    return ns
end
local ns = load("Camelot")
equal(ns.KnowsResourceRecovery(), true, "known racial is detected")
local entry = ns.KnownSelfBuffCandidates()[1]
equal(entry.spellID, ID, "racial appears independently of class catalogue")
equal(entry.resourceRecovery, true, "resource condition survives resolution")
equal(ns.Actions:Percent(entry), 50, "threshold defaults to requested fifty percent")
equal(ns.Actions:ReminderFor(entry), "Health or mana below 50%", "settings describe resource threshold")
equal(#ns.Actions:Entries(), 0, "full resources suppress reminder")
state.health = 49
equal(#ns.Actions:Entries(), 1, "low health is sufficient")
state.health = 50
equal(#ns.Actions:Entries(), 0, "exactly threshold is not below")
state.health, state.mana = 100, 49
equal(#ns.Actions:Entries(), 1, "low mana is sufficient")
state.mana = 50
equal(#ns.Actions:Entries(), 0, "mana threshold is strict")
state.maxMana, state.mana = 0, 0
equal(#ns.Actions:Entries(), 0, "characters without mana do not trigger for zero mana")
state.health = 49
equal(#ns.Actions:Entries(), 1, "no-mana character can still have low health")
ns.db.buffDurations[ID] = 15
equal(ns.IsBuffExcluded(entry), false, "short racial effect never disables recovery default")
ns.db.excludedBuffs[ID] = true
equal(#ns.Actions:Entries(), 0, "normal exclusion is honoured")
ns.Actions:Restore("spell", ID)
equal(#ns.Actions:Entries(), 1, "ignored racial can be restored")
ns.db.reminderPercent.buffBySpell[ID] = 30
state.health = 40
equal(#ns.Actions:Entries(), 0, "per-ability slider threshold is honoured")
ns.db.reminderPercent.buffBySpell[ID] = nil

for _, flag in ipairs({ "combat", "dead", "taxi" }) do
    state[flag] = true
    equal(#ns.Actions:Entries(), 0, flag .. " suppresses reminder")
    state[flag] = false
end
ns.db.ignoreBuffsInRestedAreas, state.resting = true, true
equal(#ns.Actions:Entries(), 0, "existing rested pause still applies")
ns.db.ignoreBuffsInRestedAreas, state.resting = false, false
state.cooldown = { startTime = 90, duration = 120, isEnabled = true, modRate = 1 }
equal(#ns.Actions:Entries(), 0, "cooldown hides ability")
equal(ns.Actions.nextReminderDelay, 110, "cooldown expiry schedules a bar refresh")
state.now = 210
equal(#ns.Actions:Entries(), 1, "ready at expiry")
state.now, state.cooldown.modRate = 100, 2
equal(#ns.Actions:Entries(), 0, "rate-adjusted cooldown still active")
equal(ns.Actions.nextReminderDelay, 110, "UI rate never advances the API cooldown end time")
state.now = 160
equal(#ns.Actions:Entries(), 0, "non-unit UI rate cannot make a still-active cooldown ready")
state.now = 100
for _, field in ipairs({ "startTime", "duration", "isEnabled", "modRate" }) do
    state.cooldown = { startTime = 90, duration = 120, isEnabled = true, modRate = 1 }
    state.cooldown[field] = secret
    equal(#ns.Actions:Entries(), 0, "secret " .. field .. " never establishes readiness")
end
for _, invalid in ipairs({ false, 0, secret }) do
    state.cooldown = { startTime = 0, duration = 0, isEnabled = invalid }
    equal(#ns.Actions:Entries(), 0, "disabled or unreadable cooldown stays hidden")
end
-- WoW Forever leaves isEnabled out; that isn't "disabled".
state.cooldown = { startTime = 0, duration = 0 }
equal(#ns.Actions:Entries(), 1, "a ready cooldown without isEnabled shows")
-- The client's own flags win, as in Salve's cooldown icons.
state.cooldown = { isActive = false }
equal(#ns.Actions:Entries(), 1, "isActive false is ready even without times")
state.cooldown = { startTime = 99, duration = 1.5, isActive = true, isOnGCD = true }
equal(#ns.Actions:Entries(), 1, "the global cooldown alone doesn't hide it")
state.cooldown = { isActive = true, isOnGCD = false }
equal(#ns.Actions:Entries(), 0, "active with unknown times stays hidden")
equal(ns.Actions.nextReminderDelay, 5, "and looks again shortly")
state.cooldown = { startTime = 90, duration = 120, isActive = true, isOnGCD = false }
equal(#ns.Actions:Entries(), 0, "a real cooldown stays hidden")
C_Spell.GetSpellCooldown = function() error("unreadable") end
equal(#ns.Actions:Entries(), 0, "cooldown errors hide conservatively")
C_Spell.GetSpellCooldown = nil
GetSpellCooldown = function() return 0, 0, 1 end
equal(#ns.Actions:Entries(), 1, "legacy ready cooldown is supported")
GetSpellCooldown = function() return 90, 120, 1 end
equal(#ns.Actions:Entries(), 0, "legacy cooldown hides ability")
GetSpellCooldown = nil
equal(#ns.Actions:Entries(), 0, "missing cooldown API never assumes ready")

ns = load("Camelot")
state.health, state.maxMana = secret, 0
equal(#ns.Actions:Entries(), 0, "unreadable health and no mana provide no trigger")
state.health, state.mana, state.maxMana = secret, 10, 100
equal(#ns.Actions:Entries(), 1, "readable low mana can independently trigger")
state.known = false
ns.ResetSpellbook()
equal(#ns.KnownSelfBuffCandidates(), 0, "unknown racial is never offered")
ns = load("Mainline")
state.health = 10
equal(ns.KnowsResourceRecovery(), false, "Retail never enables Forever recovery events")
equal(#ns.KnownSelfBuffCandidates(), 0, "Forever racial remains absent on Retail even with misleading known result")

ns = load("Camelot")
state.health = 10
C_Spell.GetSpellCooldown = nil
GetSpellCooldown = function() return 0, 1, 1, secret end
equal(#ns.Actions:Entries(), 0, "secret legacy cooldown rate never establishes readiness")

ns = load("Camelot")
local probes = 0
local originalKnown = C_SpellBook.IsSpellKnown
C_SpellBook.IsSpellKnown = function(id) probes = probes + 1; return originalKnown(id) end
for index = 1, 30 do equal(ns.KnowsResourceRecovery(), true, "known racial cache") end
equal(probes, 1, "repeated resource events do not re-probe spellbook")
state.known = false
ns.ResetSpellbook()
equal(ns.KnowsResourceRecovery(), false, "spellbook change invalidates racial cache")
local previousProbes = probes
for index = 1, 30 do equal(ns.KnowsResourceRecovery(), false, "unknown racial cache") end
equal(probes, previousProbes, "unknown racial is cached too")

ns = load("Camelot")
local timers, refreshed = {}, 0
C_Timer = { After = function(delay, fn) timers[#timers + 1] = fn end }
ns.Palette = { Refresh = function() refreshed = refreshed + 1 end }
for index = 1, 100 do
    state.now = 100 + index / 100
    ns.Actions:ArmReminder(210 - state.now)
end
equal(#timers, 1, "repeated cooldown observations share one pending wakeup")
state.now = 211
timers[1]()
equal(refreshed, 1, "the shared timer refreshes once")
equal(ns.Actions.reminderWakeAt, nil, "completed wakeup clears its deadline")

-- Grouped on Forever: current health and mana are secret.
ns = load("Camelot")
ns.CONSUMABLE_ORDER = {}
state.health, state.mana = secret, secret
equal(#ns.Actions:Entries(), 0, "secret resources without curve support stay hidden")
C_CurveUtil = { CreateCurve = function() return {} end }
Enum.LuaCurveType = { Step = 1 }
UnitHealthPercent, UnitPowerPercent = function() return secret end, function() return secret end
local faded = ns.Actions:Entries()
equal(#faded, 1, "secret resources carry a faded reminder")
equal(faded[1].secretRecovery, true, "reminder is marked for client-side fading")
equal(#ns.Actions:BindingEntries(), 0, "the key never casts a faded reminder")
state.cooldown = { startTime = 90, duration = 120, isEnabled = true, modRate = 1 }
equal(#ns.Actions:Entries(), 0, "faded reminder still waits for the cooldown")
state.cooldown = { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
state.health, state.mana = 40, 100
local plain = ns.Actions:Entries()
equal(plain[1] and plain[1].secretRecovery, nil, "readable resources use the normal reminder")
equal(#ns.Actions:BindingEntries(), 1, "normal reminder stays on the key")
C_CurveUtil, UnitHealthPercent, UnitPowerPercent = nil, nil, nil

print("resource recovery tests passed")
