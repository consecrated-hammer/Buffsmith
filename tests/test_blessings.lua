local count = 0
local function eq(actual, expected, label)
    count = count + 1
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local M, K, W, F = 19740, 20217, 19742, 25780
local learned, auras, party, targetClass = { [M] = true }, {}, false, 'WARRIOR'
local names = { [M] = 'Blessing of Might', [K] = 'Blessing of Kings', [W] = 'Blessing of Wisdom', [F] = 'Righteous Fury' }
GetTime = function() return 100 end
UnitClass = function(unit) return '', unit == 'player' and 'PALADIN' or targetClass end
UnitGUID = function(unit) return unit == 'player' and 'Player-self' or 'Player-' .. unit end
UnitExists = function(unit) return unit == 'player' or unit == 'target' or (party and (unit == 'party1' or unit == 'party2')) end
UnitIsUnit = function(a, b) return a == b end
UnitIsPlayer, UnitCanAssist, UnitIsVisible, UnitIsConnected = function() return true end, function() return true end, function() return true end, function() return true end
UnitIsDeadOrGhost, UnitOnTaxi, IsResting = function() return false end, function() return false end, function() return false end
IsInGroup = function() return party end
GetSpecialization = function() return 0 end
C_SpellBook = { IsSpellKnown = function(id) return learned[id] end }
C_Spell = { GetSpellInfo = function(id) return { name = names[id], iconID = id } end }
C_UnitAuras = {
    GetUnitAuraBySpellID = function(unit, id) return auras[unit] and auras[unit][id] end,
    GetAuraDataByIndex = function() return nil end,
}
local ns = { TARGET = 'Camelot', Plain = function(v) return v end, IsSecret = function() return false end,
    IsCombatLocked = function() return false end, db = { excludedBuffs = {}, preferred = {}, buffDurations = {},
        reminderPercent = { buff = 10, buffBySpell = {} }, showTargetBuffs = true, showPartyBuffs = false } }
for _, path in ipairs({ 'Data/SelfBuffs.lua', 'Features/Actions.lua', 'Features/Blessings.lua' }) do assert(loadfile(path))('Buffsmith', ns) end
local B = ns.Blessings
local function order(key) return table.concat(B:Order(key, B:Known()), ',') end
local function action(unit)
    for _, entry in ipairs(ns.Actions:Entries()) do
        if (entry.unit or 'player') == unit and (entry.group == 'paladin-blessing' or names[entry.spellID]) then return entry.spellID end
    end
end
local function aura(source, remaining) return { sourceUnit = source, duration = 3600, expirationTime = 100 + (remaining or 3000) } end
local function reset()
    auras, targetClass, party = {}, 'WARRIOR', false
    ns.db.blessings = nil
    ns.db.showTargetBuffs, ns.db.showPartyBuffs = true, false
end
-- Only learned spells; new spells append after existing/custom order.
eq(order('MAGE'), tostring(M), 'level 11 only lists Might')
learned[W], learned[K] = true, true
ns.ResetSpellbook()
eq(order('MAGE'), W .. ',' .. K .. ',' .. M, 'uncustomised caster default includes learned Wisdom first')
B:Move('MAGE', K, -1)
eq(order('MAGE'), K .. ',' .. W .. ',' .. M, 'reorder')
learned[K] = nil; ns.ResetSpellbook()
eq(order('MAGE'), W .. ',' .. M, 'temporarily unavailable spell hidden')
learned[K] = true; ns.ResetSpellbook()
eq(order('MAGE'), K .. ',' .. W .. ',' .. M, 'returning spell retains order')
ns.db.blessings.orders.MAGE = { M, W }
eq(order('MAGE'), M .. ',' .. W .. ',' .. K, 'new spell appended after custom order')
reset()
eq(order('MAGE'), W .. ',' .. K .. ',' .. M, 'caster default')
eq(order('WARRIOR'), M .. ',' .. K, 'warrior has no Wisdom')
eq(order('ROGUE'), M .. ',' .. K, 'rogue has no Wisdom')
eq(action('target'), M, 'warrior starts with Might')
auras.target = { [M] = aura('party3') }
eq(action('target'), K, 'another paladin Might allows Kings')
auras.target[K] = aura('party4')
eq(action('target'), nil, 'warrior with Might and Kings covered')
targetClass = 'MAGE'
eq(action('target'), W, 'mage gets missing Wisdom')
auras.target[W] = aura('party5')
eq(action('target'), nil, 'all blessings covered')
reset(); targetClass = 'MAGE'
auras.target = { [M] = aura('player') }
eq(action('target'), nil, 'keep own active blessing')
auras.target[M] = aura('player', 50)
eq(action('target'), M, 'renew own blessing instead of replacing it')
ns.db.blessings.keepActive = false
eq(action('target'), W, 'opt out permits priority replacement')
auras.target = { [W] = aura('player') }
eq(action('target'), nil, 'own highest priority does not cycle')
reset(); auras.target = { [M] = aura(nil) }
eq(action('target'), nil, 'unknown caster safely waits')
auras.target[M].auraInstanceID = 9
C_UnitAuras.GetAuraCasterGUID = function(unit, instance) eq(unit, 'target', 'caster GUID uses recipient unit'); return 'Player-other' end
eq(action('target'), K, 'GUID fallback permits complementary blessing')
C_UnitAuras.GetAuraCasterGUID = nil
reset(); targetClass = 'MAGE'; B:Config().automatic = false; B:Config().manual = K
eq(action('target'), K, 'manual blessing')
auras.target = { [K] = aura('party3', 1) }
eq(action('target'), nil, 'manual does not renew another paladin blessing')
B:Config().manual = W; targetClass = 'ROGUE'; auras = {}
eq(action('target'), nil, 'manual still excludes rogue Wisdom')
reset(); party = true; ns.db.showTargetBuffs = false; ns.db.showPartyBuffs = true
auras.party1 = { [M] = aura('player') }; auras.party2 = { [M] = aura('party3') }
eq(action('party2'), K, 'party selection retains whole group after covered member')
-- Dismissals apply to the selected blessing and recipient.
local chosen
for _, entry in ipairs(ns.Actions:Entries()) do if entry.unit == 'party2' then chosen = entry end end
assert(chosen)
ns.Actions:Dismiss(chosen)
eq(action('party2'), nil, 'dismiss selected party Kings')
ns.Actions.suppressed = {}
ns.Actions:Dismiss({ kind = 'spell', spellID = M })
eq(action('party2'), K, 'self Might dismissal does not hide party Kings')
ns.Actions.suppressed = {}
reset(); targetClass = 'MAGE'
auras.target = { [M] = aura(nil), [K] = aura('player', 50) }
eq(action('target'), K, 'unknown foreign blessing does not block own renewal')
ns.db.excludedBuffs[K] = true
eq(action('target'), nil, 'ignored own blessing still protected from replacement')
ns.db.excludedBuffs[K] = nil
reset(); targetClass = nil
eq(action('target'), nil, 'unknown recipient class waits')
reset()
ns.db.blessings = { orders = { MAGE = { M } } }
B:LearnedSpellsChanged()
eq(table.concat(ns.db.blessings.orders.MAGE, ','), M .. ',' .. W .. ',' .. K, 'learn event appends to custom priority')
local savedOrder = ns.db.blessings.orders.MAGE
B:Order('MAGE', B:Known())
eq(ns.db.blessings.orders.MAGE, savedOrder, 'priority reads do not replace saved order')
reset(); learned[F] = true; ns.ResetSpellbook()
local fury
for _, entry in ipairs(ns.KnownSelfBuffCandidates()) do if entry.spellID == F then fury = entry end end
assert(fury)
eq(ns.IsBuffExcluded(fury), true, 'Fury off by default')
ns.db.excludedBuffs[F] = false
local found = false
for _, entry in ipairs(ns.Actions:Entries()) do if entry.spellID == F then found = true end end
eq(found, true, 'Fury enabled missing reminder')
auras.player = { [F] = aura('player') }
found = false
for _, entry in ipairs(ns.Actions:Entries()) do if entry.spellID == F then found = true end end
eq(found, false, 'active Fury suppresses reminder')
ns.TARGET = 'Retail'
eq(B:Enabled(), false, 'Retail untouched')
-- Automatic blessing priorities skip a missing blessing outside its display rule.
assert(loadfile('Features/DisplayRules.lua'))('Buffsmith', ns)
local R = ns.DisplayRules
R:Initialize(ns.db, true)
ns.TARGET = 'Camelot'
reset(); learned[F] = nil; ns.ResetSpellbook(); targetClass = 'MAGE'
IsInInstance = function() return false, 'none' end
R:Set({kind='spell',spellID=W}, 'INSTANCES')
eq(action('target'), K, 'automatic priority skips currently hidden Wisdom')
R:Set({kind='spell',spellID=K}, 'INSTANCES')
eq(action('target'), M, 'falls through to next allowed blessing')
R:Set({kind='spell',spellID=M}, 'INSTANCES')
eq(action('target'), nil, 'all blessing rules hidden means no action')
R:Set({kind='spell',spellID=K}, 'ALWAYS')
B:Config().automatic = false; B:Config().manual = W
eq(action('target'), nil, 'hidden manual blessing does not fall through')
B:Config().automatic = true
auras.target = { [M] = aura('player', 30) }
eq(action('target'), nil, 'hidden own renewal does not replace protected blessing')
print('blessings: ' .. count .. ' assertions passed')
