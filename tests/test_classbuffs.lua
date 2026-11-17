local count = 0
local function eq(actual, expected, label)
    count = count + 1
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local class, learned, auras, roles, targetUnit, inGroup = 'DRUID', { [1126] = true, [467] = true }, {}, {}, 'party1', true
local names = { [1126] = 'Mark of the Wild', [467] = 'Thorns', [324] = 'Lightning Shield', [52127] = 'Water Shield' }
UnitClass = function() return class, class end
UnitExists = function(unit) return unit == 'player' or unit == 'target' or unit == 'party1' or unit == 'party2' or unit == 'pet' end
UnitIsPlayer = function(unit) return unit ~= 'pet' end
UnitIsUnit = function(a,b) return a == b or (a == 'target' and b == targetUnit) end
UnitGUID = function(unit) return unit == 'target' and targetUnit or unit end
UnitCanAssist, UnitIsVisible, UnitIsConnected = function() return true end, function() return true end, function() return true end
UnitIsDeadOrGhost, UnitOnTaxi, IsResting = function() return false end, function() return false end, function() return false end
UnitGroupRolesAssigned = function(unit) return roles[unit] or 'NONE' end
IsInGroup = function() return inGroup end
GetSpecialization, GetTime = function() return 1 end, function() return 100 end
C_SpellBook = { IsSpellKnown = function(id) return learned[id] end }
C_Spell = { GetSpellInfo = function(id) return { name = names[id], iconID = id } end }
C_UnitAuras = { GetUnitAuraBySpellID = function(unit,id) return auras[unit] and auras[unit][id] end,
    GetAuraDataByIndex = function() return nil end }
local ns = { TARGET = 'Camelot', Plain = function(v) return v end, IsSecret = function() return false end,
    IsCombatLocked = function() return false end, db = { preferred = {}, excludedBuffs = {}, buffDurations = {},
        showTargetBuffs = true, showPartyBuffs = true, showPetBuffs = true,
        reminderPercent = { buff = 10, buffBySpell = {} } } }
for _, file in ipairs({ 'Data/SelfBuffs.lua', 'Features/Actions.lua', 'Features/ClassBuffs.lua' }) do assert(loadfile(file))('Buffsmith', ns) end
local C = ns.ClassBuffs
local mark, thorns = { spellID = 1126 }, { spellID = 467 }
local function action(id, unit)
    for _, entry in ipairs(ns.Actions:Entries()) do if entry.spellID == id and (entry.unit or 'player') == unit then return entry end end
end
local function aura(left) return { duration = 600, expirationTime = 100 + (left or 500) } end
-- Per-spell independence and global ceilings.
eq(C:Druid(thorns).party, 'ALL', 'inherit party setting')
eq(action(467, 'player') ~= nil, true, 'self Thorns unchanged')
eq(action(1126, 'player') ~= nil, true, 'Mark independent from Thorns')
C:Druid(thorns).self = false
eq(action(467, 'player'), nil, 'Thorns self off')
eq(action(1126, 'player') ~= nil, true, 'Mark self still on')
C:Druid(thorns).party = 'TANK'; roles.party2 = 'TANK'
eq(action(467, 'party2') ~= nil, true, 'only assigned party tank')
roles.party2 = nil
eq(action(467, 'party2'), nil, 'no role never inferred')
GetPartyAssignment = function(_, unit) return unit == 'party2' end
eq(action(467, 'party2') ~= nil, true, 'explicit main-tank assignment supported')
GetPartyAssignment = nil
C:Druid(thorns).target = false; C:Druid(thorns).party = 'ALL'
eq(action(467, 'target'), nil, 'selected target disabled')
eq(action(467, 'party1') ~= nil, true, 'target off does not suppress party recipient')
C:Druid(thorns).target = true
eq(action(467, 'target') ~= nil, true, 'selected target independent of roles')
eq(action(467, 'party1'), nil, 'target party deduplicated')
ns.db.showPartyBuffs = false
eq(action(467, 'party2'), nil, 'global party ceiling')
C:Druid(thorns).pets = false
eq(action(467, 'pet'), nil, 'pets off')
C:Druid(thorns).pets = true
eq(action(467, 'pet') ~= nil, true, 'pet allowed')
ns.db.showPetBuffs = false
eq(action(467, 'pet'), nil, 'global pet ceiling')
auras.target = { [467] = aura() }
eq(action(467, 'target'), nil, 'active Thorns from anyone covers recipient')
auras.target[467] = aura(30)
eq(action(467, 'target') ~= nil, true, 'existing renewal threshold retained')
ns.db.excludedBuffs[467] = true
eq(action(467, 'target'), nil, 'ignored Thorns stays off')
ns.db.excludedBuffs[467] = nil
-- Initial recipient values inherit disabled global switches.
ns.db.classBuffs = nil; ns.db.showTargetBuffs = false
eq(C:Druid(thorns).target, false, 'migration inherits target off')
eq(C:Druid(thorns).party, 'NONE', 'migration inherits party off')
eq(C:Druid(thorns).pets, false, 'migration inherits pets off')
-- Shaman preference and keep-active behaviour.
class, learned, auras, inGroup = 'SHAMAN', { [324] = true, [52127] = true }, {}, false
ns.ResetSpellbook(); ns.db.excludedBuffs = {}; ns.db.preferred['1'] = { ['shaman-shield'] = 52127 }
eq(action(52127, 'player') ~= nil, true, 'preferred learned Water Shield')
auras.player = { [324] = aura() }
eq(action(52127, 'player'), nil, 'keep active Lightning Shield')
auras.player[324] = aura(30)
eq(action(324, 'player') ~= nil, true, 'renew active shield rather than replace')
C:Config().keepShield = false
eq(action(52127, 'player') ~= nil, true, 'opt out permits preferred replacement')
learned[52127] = nil; ns.ResetSpellbook()
eq(action(52127, 'player'), nil, 'unlearned shield never offered')
ns.TARGET = 'Retail'
eq(C:Allows(thorns, 'self', 'player'), true, 'Retail scope unchanged')
-- Actual reminder and key/configure paths honour per-buff display rules.
assert(loadfile('Features/DisplayRules.lua'))('Buffsmith', ns)
local R = ns.DisplayRules
R:Initialize(ns.db, true)
local place = 'none'
IsInInstance = function() return place ~= 'none', place end
class, learned, auras, inGroup = 'DRUID', { [1126] = true, [467] = true }, {}, true
ns.db.classBuffs, ns.db.excludedBuffs = nil, {}
ns.db.showTargetBuffs, ns.db.showPartyBuffs, ns.db.showPetBuffs = true, true, true
ns.ResetSpellbook()
R:Set(thorns, 'INSTANCES')
eq(action(467, 'player'), nil, 'outdoor Thorns self reminder hidden')
eq(action(467, 'target'), nil, 'outdoor Thorns target reminder hidden')
eq(action(467, 'party2'), nil, 'outdoor Thorns party reminder hidden')
eq(action(467, 'pet'), nil, 'outdoor Thorns pet reminder hidden')
eq(action(1126, 'player') ~= nil, true, 'independent Mark rule remains available')
ns.CONSUMABLE_ORDER = {}
for _, entry in ipairs(ns.Actions:BindingEntries()) do assert(entry.spellID ~= 467, 'key cannot select hidden Thorns') end
local attrs = {}
local button = { SetAttribute = function(_,key,value) attrs[key] = value end }
ns.Actions:Configure(button, { kind = 'spell', spellID = 467, name = 'Thorns' })
eq(attrs.type1, nil, 'stale prepared entry disarmed outside its display rule')
place = 'party'
eq(action(467, 'player') ~= nil, true, 'dungeon restores Thorns')
ns.Actions:Configure(button, { kind = 'spell', spellID = 467, name = 'Thorns' })
eq(attrs.type1, 'spell', 'allowed rule prepares secure action')
C_Minimap = { GetNumTrackingTypes = function() return 1 end,
    GetTrackingInfo = function() return { type = 'spell', spellID = 2383, name = 'Find Herbs', active = false } end }
UnitGUID = function(unit) return unit == 'player' and 'Player-self' or unit end
assert(loadfile('Features/Tracking.lua'))('Buffsmith', ns)
R:Set({kind='spell',spellID=2383}, 'READY')
local hasTracking = false
for _, entry in ipairs(ns.Actions:Entries()) do if entry.tracking then hasTracking = true end end
eq(hasTracking, false, 'tracking respects own rule')
R:Set({kind='spell',spellID=2383}, 'ALWAYS')
for _, entry in ipairs(ns.Actions:Entries()) do if entry.tracking then hasTracking = true end end
eq(hasTracking, true, 'default tracking remains available')
-- A hidden preferred shield is not permission to select a different shield.
class, learned, auras, inGroup = 'SHAMAN', { [324] = true, [52127] = true }, {}, false
ns.ResetSpellbook(); ns.db.preferred['1'] = { ['shaman-shield'] = 324 }
R:Set({kind='spell',spellID=324}, 'READY')
eq(action(324, 'player'), nil, 'hidden preferred shield not offered')
eq(action(52127, 'player'), nil, 'display rule never chooses another shield implicitly')
print('class buffs: ' .. count .. ' assertions passed')
