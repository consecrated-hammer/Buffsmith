local count = 0
local function eq(actual, expected, label)
    count = count + 1
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local now, instance, grouped, timers, refreshes = 100, 'none', true, {}, 0
GetTime = function() return now end
IsInGroup = function() return grouped end
IsInInstance = function() return instance ~= 'none', instance end
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { at = now + delay, run = callback } end }
local ns = { Plain = function(v) return v end, RefreshAll = function() refreshes = refreshes + 1 end }
assert(loadfile('Core/Config.lua'))('Buffsmith', ns)
assert(loadfile('Features/DisplayRules.lua'))('Buffsmith', ns)
local R = ns.DisplayRules
local food = { kind = 'category', category = 'food' }
local item = { kind = 'item', itemID = 9001, category = 'food' }
local buff = { kind = 'spell', spellID = 467 }
BuffsmithDB = nil
ns.InitConfig()
eq(R:Effective(food), 'INSTANCES', 'new install recommended food default')
eq(R:Effective({kind='category',category='weapon'}), 'ALWAYS', 'new weapons always')
eq(R:Effective(buff), 'ALWAYS', 'buff default always')
eq(R:Allows(item), false, 'new food hidden outdoors')
instance = 'party'; eq(R:Allows(item), true, 'food in dungeon')
instance = 'raid'; eq(R:Allows(item), true, 'food in raid')
instance = 'scenario'; eq(R:Allows(item), true, 'scenario counts as dungeon')
instance = 'pvp'; eq(R:Allows(item), false, 'instance preset excludes battlegrounds')
BuffsmithDB = { categories = { food = false }, excludedBuffs = { [467] = true }, preferred = { ['1'] = { food = 9001 } } }
ns.InitConfig()
instance = 'none'
eq(R:Effective(food), 'ALWAYS', 'existing install retains availability')
eq(ns.db.categories.food, false, 'migration preserves enable flag')
eq(ns.db.excludedBuffs[467], true, 'migration preserves ignored buff')
eq(ns.db.preferred['1'].food, 9001, 'migration preserves preference')
R:Set(food, 'INSTANCES')
eq(R:Allows(item), false, 'item inherits category')
eq(R:Describe(item), 'Using Food settings: Dungeons and raids', 'inheritance explained')
R:Set(item, 'ALWAYS'); eq(R:Allows(item), true, 'item overrides category timing')
R:Set(item, 'INHERIT'); eq(R:Own(item), nil, 'inherit removes override')
R:Set(food, 'ALWAYS'); eq(R:Allows(item), true, 'inherited value follows later category edits')
R:Set(item, 'CUSTOM')
eq(R:Own(item).world, true, 'custom starts from effective rule')
R:Set(item, { world = false, dungeon = true, raid = false, pvp = false, ready = true })
eq(R:Allows(item), false, 'custom waits for ready check')
R:ReadyCheck()
eq(R:Allows(item), false, 'ready check cannot bypass location')
instance = 'party'; eq(R:Allows(item), true, 'location and ready conditions both match')
now = 114.9; eq(R:Allows(item), true, 'ready window before 15 seconds')
now = 115; eq(R:Allows(item), false, 'ready window expires at 15 seconds')
local before = refreshes; timers[1].run(); eq(refreshes, before + 1, 'expiry refreshes actions')
R:Set(buff, 'READY'); now = 120; R:ReadyCheck(); now = 125; R:ReadyCheck()
now = 135; timers[2].run()
eq(R:Allows(buff), true, 'old timer cannot clear newer ready check')
grouped = false; R:GroupChanged(); grouped = true
eq(R:Allows(buff), false, 'leaving group clears ready window')
R:Set(buff, { pvp = true })
instance = 'arena'; eq(R:Allows(buff), true, 'arena maps to PvP')
instance = 'none'; eq(R:Allows(buff), false, 'PvP-only excludes open world')
R:Set(buff, {})
eq(R:Allows(buff), false, 'no selected locations never matches')
local api = IsInInstance; IsInInstance = function() error('unavailable') end
R:Set(buff, 'INSTANCES'); eq(R:Allows(buff), false, 'unknown context cannot match restricted rule')
R:Set(buff, 'ALWAYS'); eq(R:Allows(buff), true, 'always does not need location API')
IsInInstance = api
R:Set(item, 'READY'); R:Set(buff, 'INSTANCES')
R:Recommended()
eq(R:Own(item), nil, 'recommended clears item overrides')
eq(R:Own(buff), nil, 'recommended clears buff overrides')
eq(R:Effective(food), 'INSTANCES', 'recommended applies category defaults')
eq(ns.db.categories.food, false, 'recommended does not enable reminders')
eq(ns.db.excludedBuffs[467], true, 'recommended preserves ignored spells')
eq(ns.db.preferred['1'].food, 9001, 'recommended preserves choices')
R:Set(food, 'READY'); ns.InitConfig()
eq(R:Effective(food), 'READY', 'reinitializing preserves custom rules')
ns.db.displayRules.buffs = 'malformed'
eq(R:Effective(buff), 'ALWAYS', 'malformed bucket repaired safely')
ns.TARGET = 'Camelot'; ns.CAMPING_ITEMS = { [9002] = { label = 'Camp Chair' } }
BuffsmithDB = nil; ns.InitConfig(); instance = 'none'
eq(R:Allows({kind='item',itemID=9002,category='other'}), true, 'new camping item remains available outdoors')
R:Set({kind='item',itemID=9002,category='other'}, 'INSTANCES'); R:Recommended()
eq(R:Allows({kind='item',itemID=9002,category='other'}), true, 'recommended keeps camping available outdoors')
print('display rules: ' .. count .. ' assertions passed')
