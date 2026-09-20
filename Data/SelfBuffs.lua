local addonName, ns = ...

-- Reviewed self-maintenance actions, shown when present in the player spellbook.
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
        { spellID = 20154, auraID = 20154, label = "Seal of Righteousness" },
    },
    PRIEST = {
        { spellID = 1243, auraID = 1243, label = "Power Word: Fortitude", target = true },
        { spellID = 588, auraID = 588, label = "Inner Fire" },
        { spellID = 976, auraID = 976, label = "Shadow Protection", target = true },
    },
    SHAMAN = {
        { spellID = 324, auraID = 324, label = "Lightning Shield" },
        { spellID = 52127, auraID = 52127, label = "Water Shield" },
    },
    WARLOCK = {
        { spellID = 687, auraID = 687, label = "Demon Armor", permanent = true },
        { spellID = 28176, auraID = 28176, label = "Fel Armor", permanent = true },
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

function ns.KnownSelfBuffs()
    local _, class = UnitClass("player")
    local entries = {}
    ns.lastSelfBuffClass = class or "unknown"
    ns.lastSelfBuffProbe = {}
    for _, entry in ipairs(ns.SELF_BUFFS[class] or {}) do
        local isKnown, source = known(entry.spellID)
        if isKnown then
            local name, icon = spellInfo(entry.spellID, entry.label)
            entries[#entries + 1] = {
                kind = "spell", spellID = entry.spellID, auraID = entry.auraID,
                auraIDs = entry.auraIDs,
                permanent = entry.permanent == true,
                target = entry.target == true,
                name = name, icon = icon,
            }
        end
        ns.lastSelfBuffProbe[#ns.lastSelfBuffProbe + 1] = entry.label .. "=" .. source
    end
    return entries
end
