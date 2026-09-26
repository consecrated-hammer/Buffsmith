local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local ns = { RefreshAll = function() end }
BuffsmithDB = { palettePoint = "broken", categories = false, maxAlternatives = 99 }
assert(loadfile("Core/Config.lua"))("Buffsmith", ns)
ns.InitConfig()
equal(ns.db.maxAlternatives, 3, "alternatives are capped")
equal(type(ns.db.categories), "table", "categories are repaired")
equal(ns.db.palettePoint[1], "CENTER", "palette point is repaired")
equal(type(ns.db.excludedBuffs), "table", "buff exclusions are created")
-- Settings-window position, startup message and minimap now live in
-- HammerCore's state and are tested there.
BuffsmithDB = { showStartupMessage = false, showMinimap = false, minimapAngle = 12 }
ns.InitConfig()
equal(ns.db.showStartupMessage, false, "legacy keys survive for HammerCore to adopt")
BuffsmithDB = { palettePoint = "broken", categories = false, maxAlternatives = 99 }
ns.InitConfig()
equal(ns.db.visibilityMode, "ALWAYS", "an unset visibility mode defaults to always")

BuffsmithDB = { flyoutVerticalDirection = "UP", flyoutHorizontalDirection = "LEFT" }
ns.InitConfig()
equal(ns.db.flyoutVerticalDirection, "AUTO", "an invalid vertical flyout direction is repaired")
equal(ns.db.flyoutHorizontalDirection, "AUTO", "an invalid horizontal flyout direction is repaired")

BuffsmithDB = { thanksDelay = 99 }
ns.InitConfig()
equal(ns.db.thanksDelay, 5, "thank-you delay is capped")
BuffsmithDB = { thanksDelay = "broken" }
ns.InitConfig()
equal(ns.db.thanksDelay, 1, "an invalid thank-you delay defaults to one second")
equal(ns.db.thanksEmote, "THANK", "the default emote is Thank")
BuffsmithDB = { thanksChannel = "EMOTE", thanksEmote = "RANDOM" }
ns.InitConfig()
equal(ns.db.thanksChannel, "EMOTE", "emote delivery persists")
equal(ns.db.thanksEmote, "RANDOM", "random emote selection persists")
BuffsmithDB = { thanksChannel = "EMOTE", thanksEmote = "bad token" }
ns.InitConfig()
equal(ns.db.thanksEmote, "THANK", "invalid emote selection resets to Thank")

-- showPalette folded into the visibility mode, so a saved "off" has to land on
-- Never rather than silently switching the bar back on.
BuffsmithDB = { showPalette = false }
ns.InitConfig()
equal(ns.db.visibilityMode, "NEVER", "a hidden bar migrates to Never")
equal(ns.db.showPalette, nil, "the retired key is dropped")

BuffsmithDB = { showPalette = true, visibilityMode = "ALWAYS" }
ns.InitConfig()
equal(ns.db.visibilityMode, "ALWAYS", "a shown bar keeps its mode")
equal(ns.db.showPalette, nil, "the retired key is dropped when it was true")

-- A missing IsPlayerSpell global must not prevent the remaining compatible
-- spell probe from finding a castable self-buff.
local spellNS = { Plain = function(value) return value end }
C_SpellBook, C_Spell, IsPlayerSpell = nil, nil, nil
IsSpellKnown = function(spellID) return spellID == 1126 end
UnitClass = function() return "Druid", "DRUID" end
assert(loadfile("Data/SelfBuffs.lua"))("Buffsmith", spellNS)
local buffs = spellNS.KnownSelfBuffs()
equal(#buffs, 1, "legacy IsSpellKnown fallback is reached")
equal(buffs[1].spellID, 1126, "known self-buff is retained")

local secret = {}
issecretvalue = function(value) return value == secret end
local coreNS = { HammerCore = { Print = function() end } }
assert(loadfile("Core.lua"))("Buffsmith", coreNS)
equal(coreNS.Plain(secret), nil, "secret values are never returned as plain")
equal(coreNS.Plain("safe"), "safe", "plain values pass through")
print("config tests passed")
