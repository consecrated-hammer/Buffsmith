local addonName, ns = ...

-- Reviewed self-maintenance actions, shown when present in the player spellbook.
-- Entry fields:
--   spellID  stable logical identity for settings and exclusions (lowest rank).
--   ids      optional ascending rank family; the highest known member is the
--            resolved rank.  Defaults to { spellID }.
--   auraIDs  applied aura IDs; defaults to the rank family.  Ranked Forever
--            auras also match by the resolved spell name.
--   group    mutually exclusive family: one active member satisfies the whole
--            group, and only the first known, non-excluded member is offered.
--   target   the effect is safe to cast on friendly players and pets.
--   short    lasts under a minute, so it is listed but off by default.  A
--            duration observed on the player replaces this flag.
ns.SELF_BUFFS = {
    DRUID = {
        { spellID = 1126, auraID = 1126,
            auraIDs = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990, 48469 },
            label = "Mark of the Wild", target = true },
        { spellID = 467, auraID = 467, label = "Thorns", target = true },
    },
    HUNTER = {
        { spellID = 13165, auraID = 13165, label = "Aspect of the Hawk", permanent = true },
    },
    MAGE = {
        { spellID = 1459, auraID = 1459, label = "Arcane Intellect", target = true },
        { spellID = 7302, auraID = 7302, label = "Ice Armor", permanent = true },
    },
    PALADIN = {
        { spellID = 465, auraID = 465, label = "Devotion Aura", permanent = true },
        { spellID = 20154, auraID = 20154, label = "Seal of Righteousness", short = true },
        -- A paladin maintains one of their own blessings per target.  Rank
        -- IDs above rank 1 are unverified on Forever, so the spellbook name
        -- resolves the learned rank there instead of an assumed list.
        { spellID = 19740, auraID = 19740, label = "Blessing of Might", target = true, group = "paladin-blessing" },
        { spellID = 20217, auraID = 20217, label = "Blessing of Kings", target = true, group = "paladin-blessing" },
        { spellID = 19742, auraID = 19742, label = "Blessing of Wisdom", target = true, group = "paladin-blessing" },
    },
    PRIEST = {
        { spellID = 1243, auraID = 1243, label = "Power Word: Fortitude", target = true },
        { spellID = 588, auraID = 588, label = "Inner Fire" },
        { spellID = 976, auraID = 976, label = "Shadow Protection", target = true },
    },
    SHAMAN = {
        { spellID = 324, auraID = 324, label = "Lightning Shield", group = "shaman-shield" },
        { spellID = 52127, auraID = 52127, label = "Water Shield", group = "shaman-shield" },
    },
    WARLOCK = {
        { spellID = 687, auraID = 687, label = "Demon Armor", permanent = true, group = "warlock-armor" },
        { spellID = 28176, auraID = 28176, label = "Fel Armor", permanent = true, group = "warlock-armor" },
    },
    WARRIOR = {
        { spellID = 6673, auraID = 6673, label = "Battle Shout" },
        { spellID = 469, auraID = 469, label = "Commanding Shout" },
    },
}

local function known(spellID)
    -- The Mainline player spellbook is the preferred source for castable spells.
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local ok, result = pcall(C_SpellBook.IsSpellKnown, spellID, bank)
        if ok and ns.Plain(result) == true then return true, "spellbook" end
    end

    -- Legacy spell APIs support compatible clients.
    if type(IsPlayerSpell) == "function" then
        local ok, result = pcall(IsPlayerSpell, spellID)
        if ok and ns.Plain(result) == true then return true, "legacy player" end
    end
    if type(IsSpellKnown) == "function" then
        local ok, result = pcall(IsSpellKnown, spellID)
        if ok and ns.Plain(result) == true then return true, "legacy spell" end
    end
    return false, "not known"
end

local function spellInfo(spellID, fallbackName)
    local info
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, result = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(result) == "table" then info = result end
    end
    if info then
        return ns.Plain(info.name) or fallbackName, ns.Plain(info.iconID) or 134400
    end
    if GetSpellInfo then
        local ok, name, _, icon = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" then return name, icon or 134400 end
    end
    return fallbackName, 134400
end

-- The Mainline-shaped spellbook enumerates learned spells with their exact
-- rank IDs.  It is cached until SPELLS_CHANGED because the bar resolves its
-- catalogue several times per refresh.
local spellbookCache

function ns.ResetSpellbook()
    spellbookCache = nil
end

local function spellbook()
    if spellbookCache then return spellbookCache end
    local book = { byID = {}, byName = {}, offSpec = {}, available = false, count = 0 }
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo
        and C_SpellBook.GetSpellBookItemInfo and bank then
        local ok, lineCount = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        lineCount = ok and tonumber(ns.Plain(lineCount)) or 0
        local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        for lineIndex = 1, math.min(lineCount, 128) do
            local lineOK, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, lineIndex)
            local offset = lineOK and type(line) == "table" and tonumber(ns.Plain(line.itemIndexOffset))
            local count = lineOK and type(line) == "table" and tonumber(ns.Plain(line.numSpellBookItems))
            if offset and count then
                book.available = true
                for itemOffset = 1, math.min(count, 1024) do
                    local itemOK, item = pcall(C_SpellBook.GetSpellBookItemInfo, offset + itemOffset, bank)
                    local spellID = itemOK and type(item) == "table" and tonumber(ns.Plain(item.spellID))
                    local isSpell = spellID and (spellType == nil or item.itemType == spellType)
                    if isSpell and item.isOffSpec == true then
                        book.offSpec[spellID] = true
                    elseif isSpell then
                        book.byID[spellID] = true
                        book.count = book.count + 1
                        local name = ns.Plain(item.name) or spellInfo(spellID)
                        if type(name) == "string" and name ~= "" then
                            -- Keep the highest ID seen for a name: later ranks
                            -- carry larger IDs in every legacy rank family.
                            if not book.byName[name] or spellID > book.byName[name] then
                                book.byName[name] = spellID
                            end
                        end
                    end
                end
            end
        end
    end
    spellbookCache = book
    return book
end

function ns.SpellbookSummary()
    local book = spellbook()
    return book.available and (tostring(book.count) .. " spells enumerated") or "unavailable"
end

local function rankIDs(entry)
    return entry.ids or { entry.spellID }
end

-- Resolve the highest known rank.  The secure action still casts by name, so
-- the client picks its own rank; this ID keeps cast matching, range checks
-- and diagnostics honest.  The name fallback is limited to Forever, where
-- rank IDs are not yet verified.  Retail keeps its exact-ID gate so a renamed
-- or off-spec ability never arms a secure button.
local function resolve(entry, book)
    local found, source
    -- An off-spec item is never armed.  On Retail an enumerated spellbook is
    -- authoritative; Forever's can list only part of a legacy class book, so
    -- a legacy positive is merged there, as in Salve.
    local legacy = not book.available or ns.TARGET == "Camelot"
    for _, spellID in ipairs(rankIDs(entry)) do
        if book.byID[spellID] then
            found, source = spellID, "spellbook"
        elseif legacy and not book.offSpec[spellID] then
            local isKnown, how = known(spellID)
            if isKnown then found, source = spellID, how end
        end
    end
    if ns.TARGET == "Camelot" then
        -- A legacy spellbook can report rank 1 as known while the client
        -- casts a later rank; the named spellbook entry is that later rank.
        local name = spellInfo(entry.spellID, entry.label)
        local byName = book.byName[name] or book.byName[entry.label]
        if byName and (not found or byName > found) then return byName, "spellbook name" end
    end
    if found then return found, source end
    return nil, "not known"
end

local function auraList(entry, castID)
    local ids, seen = {}, {}
    local function add(id)
        if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    for _, id in ipairs(entry.auraIDs or {}) do add(id) end
    add(entry.auraID)
    for _, id in ipairs(rankIDs(entry)) do add(id) end
    add(castID)
    return ids
end

-- Anything under a minute is too short-lived to be worth a standing prompt.
ns.SHORT_BUFF_SECONDS = 60

function ns.IsShortBuff(entry)
    local learned = ns.db and ns.db.buffDurations and ns.db.buffDurations[entry.spellID]
    if type(learned) == "number" and learned > 0 then return learned < ns.SHORT_BUFF_SECONDS end
    return entry.short == true
end

-- excludedBuffs holds the player's explicit choice: true is off, false is on.
-- With no choice recorded, a short buff is off and anything else is on.
function ns.IsBuffExcluded(entry)
    local choice = ns.db and ns.db.excludedBuffs and ns.db.excludedBuffs[entry.spellID]
    if choice ~= nil then return choice == true end
    return ns.IsShortBuff(entry)
end

local excluded = ns.IsBuffExcluded

-- Every catalogue entry the player knows, one per spell.  The settings page
-- lists these so an excluded group member can be ticked back on.
function ns.KnownSelfBuffCandidates()
    local _, class = UnitClass("player")
    local book, entries = spellbook(), {}
    ns.lastSelfBuffClass = class or "unknown"
    ns.lastSelfBuffProbe = {}
    for _, entry in ipairs(ns.SELF_BUFFS[class] or {}) do
        local castID, source = resolve(entry, book)
        if castID then
            local name, icon = spellInfo(castID, entry.label)
            entries[#entries + 1] = {
                kind = "spell", spellID = entry.spellID, castID = castID,
                auraID = entry.auraID, auraIDs = auraList(entry, castID),
                permanent = entry.permanent == true,
                target = entry.target == true,
                group = entry.group, short = entry.short == true,
                name = name, icon = icon,
            }
            if castID ~= entry.spellID then source = source .. " " .. castID end
        end
        ns.lastSelfBuffProbe[#ns.lastSelfBuffProbe + 1] = entry.label .. "=" .. source
    end
    return entries
end

-- The actions the bar offers.  A group collapses to its first known,
-- non-excluded member, carrying every known member so any one of them
-- satisfies the group on a unit.  Excluded ungrouped entries remain here;
-- Actions:IsSuppressed hides them at each call site.
function ns.KnownSelfBuffs()
    local entries, groups = {}, {}
    for _, entry in ipairs(ns.KnownSelfBuffCandidates()) do
        if not entry.group then
            entries[#entries + 1] = entry
        else
            local group = groups[entry.group]
            if not group then
                group = { members = {} }
                groups[entry.group] = group
                entries[#entries + 1] = group
            end
            group.members[#group.members + 1] = entry
            if not group.offered and not excluded(entry) then group.offered = entry end
        end
    end
    for index = #entries, 1, -1 do
        local group = entries[index]
        if group.members then
            if group.offered then
                group.offered.members = group.members
                entries[index] = group.offered
            else
                table.remove(entries, index)
            end
        end
    end
    return entries
end
