local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local SPELL_NAMES = {
    [465] = "Devotion Aura", [19740] = "Blessing of Might", [19838] = "Blessing of Might",
    [20217] = "Blessing of Kings", [19742] = "Blessing of Wisdom",
    [687] = "Demon Skin", [28176] = "Fel Armor", [324] = "Lightning Shield", [52127] = "Water Shield",
}

-- World state each scenario rewrites.
local playerClass, knownIDs, book, auras = "PALADIN", {}, nil, {}

local function install()
    C_Spell = { GetSpellInfo = function(spellID)
        local name = SPELL_NAMES[spellID]
        return name and { name = name, iconID = spellID } or nil
    end }
    C_SpellBook = { IsSpellKnown = function(spellID) return knownIDs[spellID] == true end }
    if book then
        C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
        C_SpellBook.GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book } end
        C_SpellBook.GetSpellBookItemInfo = function(index) return book[index] end
    end
    Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } }
    IsPlayerSpell, IsSpellKnown = nil, nil
    UnitClass = function() return playerClass, playerClass end
    C_UnitAuras = {
        GetUnitAuraBySpellID = function(unit, spellID)
            local aura = auras[unit] and auras[unit][spellID]
            return aura
        end,
        GetAuraDataByIndex = function() return nil end,
    }
end

local function load(target, db)
    install()
    local ns = { TARGET = target, Plain = function(value) return value end, IsSecret = function() return false end,
        IsCombatLocked = function() return false end, db = db }
    assert(loadfile("Data/SelfBuffs.lua"))("Buffsmith", ns)
    assert(loadfile("Data/PartyBuffs.lua"))("Buffsmith", ns)
    assert(loadfile("Data/RetailBuffs.lua"))("Buffsmith", ns)
    return ns
end

local function byLabel(entries)
    local result = {}
    for _, entry in ipairs(entries) do result[entry.name] = entry end
    return result
end

-- Every declared Forever class resolves each of its entries when known, and
-- classes without a catalogue are intentionally empty rather than erroring.
do
    local ns = load("Camelot")
    for class, entries in pairs(ns.SELF_BUFFS) do
        playerClass, knownIDs, book = class, {}, nil
        for _, entry in ipairs(entries) do knownIDs[entry.spellID] = true end
        ns.ResetSpellbook()
        equal(#ns.KnownSelfBuffCandidates(), #entries, class .. " resolves every known entry")
    end
    for _, class in ipairs({ "DEATHKNIGHT", "MONK", "ROGUE", "DEMONHUNTER", "EVOKER" }) do
        playerClass, knownIDs = class, {}
        equal(#ns.KnownSelfBuffs(), 0, class .. " has no Forever self catalogue")
    end
end

-- The reported Forever Paladin: Devotion Aura and Blessing of Might known.
do
    playerClass, knownIDs, book = "PALADIN", { [465] = true, [19740] = true }, nil
    local ns = load("Camelot")
    local buffs = byLabel(ns.KnownSelfBuffs())
    local might = buffs["Blessing of Might"]
    assert(might, "Blessing of Might is offered to a Forever Paladin")
    equal(might.target, true, "Blessing of Might supports friendly targets")
    equal(might.castID, 19740, "rank 1 resolves by exact ID")
    equal(buffs["Seal of Righteousness"], nil, "an unknown seal stays absent")
end

-- A later rank found only by spellbook name is selected on Forever, while the
-- stable settings identity stays the rank 1 ID.
do
    playerClass, knownIDs = "PALADIN", { [19740] = true }
    book = { { itemType = 1, spellID = 19838, name = "Blessing of Might" } }
    local ns = load("Camelot")
    local might = byLabel(ns.KnownSelfBuffs())["Blessing of Might"]
    equal(might.castID, 19838, "the highest named rank is the cast ID")
    equal(might.spellID, 19740, "the logical ID is unchanged")
    local hasRank = false
    for _, id in ipairs(might.auraIDs) do if id == 19838 then hasRank = true end end
    equal(hasRank, true, "the resolved rank's aura is matched")
    equal(ns.SpellbookSummary(), "1 spells enumerated", "spellbook enumeration is reported")
end

-- Off-spec spellbook entries are never armed, and Retail never uses the name
-- fallback for a spell whose exact ID is unknown.
do
    SPELL_NAMES[99999] = "Devotion Aura"
    playerClass, knownIDs = "PALADIN", { [19740] = true }
    book = { { itemType = 1, spellID = 99999 },
        { itemType = 1, spellID = 19740, name = "Blessing of Might", isOffSpec = true } }
    local ns = load("Camelot")
    local buffs = byLabel(ns.KnownSelfBuffs())
    equal(buffs["Blessing of Might"], nil, "an off-spec entry is not re-admitted by IsSpellKnown")
    assert(buffs["Devotion Aura"], "Forever resolves by a spellbook name derived from the spell ID")
    ns = load("Mainline")
    equal(#ns.KnownSelfBuffs(), 0, "Retail requires the exact spell ID")
    SPELL_NAMES[99999] = nil
end

-- On Retail an enumerated spellbook is authoritative; the legacy probe is
-- used only when enumeration is unavailable.
do
    playerClass, knownIDs = "DRUID", { [1126] = true }
    book = { { itemType = 1, spellID = 5185, name = "Healing Touch" } }
    equal(#load("Mainline").KnownSelfBuffs(), 0, "Retail ignores a legacy positive absent from the spellbook")
    book = nil
    equal(#load("Mainline").KnownSelfBuffs(), 1, "Retail uses the legacy probe without enumeration")
end

-- Groups offer one member; exclusions fall through to the next known member.
do
    playerClass, book = "PALADIN", nil
    knownIDs = { [19740] = true, [20217] = true, [19742] = true }
    local db = { excludedBuffs = {} }
    local ns = load("Camelot", db)
    local offered = ns.KnownSelfBuffs()
    equal(#offered, 1, "three blessings collapse to one action")
    equal(offered[1].spellID, 19740, "the first known member is offered")
    equal(#offered[1].members, 3, "every known member is carried")
    db.excludedBuffs[19740] = true
    equal(ns.KnownSelfBuffs()[1].spellID, 20217, "an excluded member yields to the next")
    db.excludedBuffs[20217], db.excludedBuffs[19742] = true, true
    equal(#ns.KnownSelfBuffs(), 0, "a fully excluded group is not offered")
    equal(#ns.KnownSelfBuffCandidates(), 3, "settings still list every member")
end

-- Retail replaces both catalogues; Forever keeps its own.
do
    local forever, retail = load("Camelot"), load("Mainline")
    equal(forever.SELF_BUFFS.PALADIN[3].label, "Blessing of Might", "Forever keeps the Camelot Paladin table")
    equal(#retail.SELF_BUFFS.PALADIN, 1, "Retail replaces the Paladin table")
    equal(retail.SELF_BUFFS.EVOKER[1].label, "Blessing of the Bronze", "Retail adds Evoker")
    equal(retail.PARTY_BUFFS.PALADIN, nil, "Retail replaces party coverage")
    equal(forever.PARTY_BUFFS.PALADIN[1].label, "Blessing of Might", "Forever keeps Paladin coverage")
end

-- Actions: an active group member satisfies the group on self, target, party
-- and pet, and a missing group creates targeted copies of the offered member.
do
    playerClass, book = "PALADIN", nil
    knownIDs = { [19740] = true, [20217] = true }
    local db = { excludedBuffs = {}, reminderPercent = { buff = 10 }, showTargetBuffs = true,
        showPartyBuffs = true, showPetBuffs = true, showPartyCoverage = false }
    local ns = load("Camelot", db)
    GetTime = function() return 100 end
    IsResting, IsInGroup = function() return false end, function() return true end
    local exists = { player = true, target = true, party1 = true, pet = true }
    UnitExists = function(unit) return exists[unit] == true end
    UnitIsPlayer = function(unit) return unit ~= "pet" end
    UnitCanAssist = function() return true end
    UnitIsDeadOrGhost = function() return false end
    UnitIsUnit = function(a, b) return a == b end
    UnitGUID = function(unit) return "guid-" .. unit end
    UnitName = function(unit) return unit end
    assert(loadfile("Features/Actions.lua"))("Buffsmith", ns)
    local function missingUnits()
        local units = {}
        for _, entry in ipairs(ns.Actions:Entries()) do
            units[#units + 1] = (entry.unit or "player") .. ":" .. entry.spellID
        end
        table.sort(units)
        return table.concat(units, ",")
    end
    auras = {}
    equal(missingUnits(), "party1:19740,pet:19740,player:19740,target:19740", "a missing group is offered on every unit")
    UnitIsConnected = function(unit) return unit ~= "party1" end
    equal(missingUnits(), "pet:19740,player:19740,target:19740", "an offline party member is not offered")
    UnitIsConnected = nil
    auras = { player = { [20217] = { duration = 0 } }, target = { [20217] = { duration = 0 } },
        party1 = { [19740] = { duration = 0 } }, pet = { [20217] = { duration = 0 } } }
    equal(missingUnits(), "", "any active member satisfies the group")
    db.excludedBuffs[19740] = true
    auras = {}
    equal(missingUnits(), "party1:20217,pet:20217,player:20217,target:20217", "the next member is offered after an exclusion")
end

-- Buffs under a minute are listed but off until the player ticks them.  An
-- observed duration replaces the catalogue flag in either direction.
do
    playerClass, book = "PALADIN", nil
    knownIDs = { [20154] = true, [19740] = true }
    SPELL_NAMES[20154] = "Seal of Righteousness"
    local db = { excludedBuffs = {}, buffDurations = {}, reminderPercent = { buff = 10 },
        showTargetBuffs = false, showPartyBuffs = false, showPetBuffs = false, showPartyCoverage = false }
    local ns = load("Camelot", db)
    local seal = byLabel(ns.KnownSelfBuffCandidates())["Seal of Righteousness"]
    assert(seal, "a short buff is still listed in settings")
    equal(ns.IsBuffExcluded(seal), true, "a short buff is off by default")
    db.excludedBuffs[20154] = false
    equal(ns.IsBuffExcluded(seal), false, "an explicit tick turns a short buff on")
    db.excludedBuffs[20154] = nil
    db.buffDurations[20154] = 1800
    equal(ns.IsBuffExcluded(seal), false, "an observed long duration overrides the catalogue flag")

    IsInGroup = function() return false end
    UnitExists = function(unit) return unit == "player" end
    assert(loadfile("Features/Actions.lua"))("Buffsmith", ns)
    auras = { player = { [19740] = { duration = 30, expirationTime = 120 } } }
    ns.Actions:Entries()
    equal(db.buffDurations[19740], 30, "the player's aura duration is learned")
    equal(ns.IsBuffExcluded(byLabel(ns.KnownSelfBuffCandidates())["Blessing of Might"]), true,
        "a buff observed under a minute becomes off by default")
    db.buffDurations[20154] = nil
    equal(ns.Actions:ReminderFor(seal), "Short duration", "settings explain the default")
    SPELL_NAMES[20154] = nil
end

print("self-buff tests passed")
