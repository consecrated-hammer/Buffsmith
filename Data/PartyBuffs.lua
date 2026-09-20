local addonName, ns = ...

-- Class-level party coverage.  This is intentionally an availability model:
-- another player's spellbook is private, so Buffsmith identifies a party class
-- that normally provides the effect rather than claiming the spell is known.
ns.PARTY_BUFFS = {
    DRUID = {
        { spellID = 1126, auraID = 1126, auraIDs = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990, 48469 }, label = "Mark of the Wild", icon = 136078 },
    },
    MAGE = {
        { spellID = 1459, auraID = 1459, label = "Arcane Intellect", icon = 135932 },
    },
    PALADIN = {
        { spellID = 19740, auraID = 19740, label = "Blessing of Might", icon = 135906 },
        { spellID = 19742, auraID = 19742, label = "Blessing of Wisdom", icon = 135970 },
        { spellID = 20217, auraID = 20217, label = "Blessing of Kings", icon = 135995 },
    },
    PRIEST = {
        { spellID = 1243, auraID = 1243, label = "Power Word: Fortitude", icon = 135987 },
    },
    WARLOCK = {
        { spellID = 6307, auraID = 6307, label = "Blood Pact", icon = 136185 },
    },
}
