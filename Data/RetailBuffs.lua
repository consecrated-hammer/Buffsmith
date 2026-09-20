local addonName, ns = ...

-- Forever loads the Camelot TOC and keeps its Classic-era spell catalogue.
-- Retail shares the Mainline API family, not those retired spells or ranks.
if ns.TARGET == "Camelot" then return end

ns.SELF_BUFFS = {
    DRUID = { { spellID = 1126, auraID = 1126, label = "Mark of the Wild", target = true } },
    MAGE = { { spellID = 1459, auraID = 1459, label = "Arcane Intellect", target = true } },
    PALADIN = { { spellID = 465, auraID = 465, label = "Devotion Aura", permanent = true } },
    PRIEST = { { spellID = 21562, auraID = 21562, label = "Power Word: Fortitude", target = true } },
    SHAMAN = { { spellID = 192106, auraID = 192106, label = "Lightning Shield" } },
    WARRIOR = { { spellID = 6673, auraID = 6673, label = "Battle Shout", target = true } },
}

ns.PARTY_BUFFS = {
    DRUID = { { spellID = 1126, auraID = 1126, label = "Mark of the Wild", icon = 136078 } },
    MAGE = { { spellID = 1459, auraID = 1459, label = "Arcane Intellect", icon = 135932 } },
    PRIEST = { { spellID = 21562, auraID = 21562, label = "Power Word: Fortitude", icon = 135987 } },
    WARRIOR = { { spellID = 6673, auraID = 6673, label = "Battle Shout", icon = 132333 } },
}
