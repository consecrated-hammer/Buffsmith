local addonName, ns = ...

-- Forever loads the Camelot TOC and keeps its Classic-era spell catalogue.
-- Retail shares the Mainline API family, not those retired spells or ranks.
-- Blessing of the Bronze applies a per-class aura ID; its shared name is the
-- reliable match, so no applied ID is guessed here.
if ns.TARGET == "Camelot" then return end

ns.SELF_BUFFS = {
    DRUID = { { spellID = 1126, auraID = 1126, label = "Mark of the Wild", target = true } },
    MAGE = { { spellID = 1459, auraID = 1459, label = "Arcane Intellect", target = true } },
    PALADIN = { { spellID = 465, auraID = 465, label = "Devotion Aura", permanent = true } },
    PRIEST = { { spellID = 21562, auraID = 21562, label = "Power Word: Fortitude", target = true } },
    ROGUE = {
        { spellID = 2823, auraID = 2823, label = "Deadly Poison", group = "rogue-lethal" },
        { spellID = 315584, auraID = 315584, label = "Instant Poison", group = "rogue-lethal" },
        { spellID = 8679, auraID = 8679, label = "Wound Poison", group = "rogue-lethal" },
        { spellID = 381664, auraID = 381664, label = "Amplifying Poison", group = "rogue-lethal" },
        { spellID = 3408, auraID = 3408, label = "Crippling Poison", group = "rogue-nonlethal" },
        { spellID = 5761, auraID = 5761, label = "Numbing Poison", group = "rogue-nonlethal" },
        { spellID = 381637, auraID = 381637, label = "Atrophic Poison", group = "rogue-nonlethal" },
    },
    SHAMAN = {
        { spellID = 192106, auraID = 192106, label = "Lightning Shield", group = "shaman-shield" },
        { spellID = 52127, auraID = 52127, label = "Water Shield", group = "shaman-shield" },
        { spellID = 462854, auraID = 462854, label = "Skyfury" },
    },
    EVOKER = { { spellID = 364342, auraID = 364342, label = "Blessing of the Bronze" } },
    WARRIOR = { { spellID = 6673, auraID = 6673, label = "Battle Shout", target = true } },
}

ns.PARTY_BUFFS = {
    DRUID = { { spellID = 1126, auraID = 1126, label = "Mark of the Wild", icon = 136078 } },
    MAGE = { { spellID = 1459, auraID = 1459, label = "Arcane Intellect", icon = 135932 } },
    PRIEST = { { spellID = 21562, auraID = 21562, label = "Power Word: Fortitude", icon = 135987 } },
    WARRIOR = { { spellID = 6673, auraID = 6673, label = "Battle Shout", icon = 132333 } },
}
