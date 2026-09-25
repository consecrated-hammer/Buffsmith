local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local sent = {}
local playerGUID = "Player-1-0001"
local scheduled = {}
local combatLocked = false

C_Timer = { After = function(delay, callback) scheduled[#scheduled + 1] = { delay = delay, callback = callback } end }

SendChatMessage = function(message, channel, _, recipient)
    sent[#sent + 1] = { message = message, channel = channel, recipient = recipient }
end
UnitGUID = function(unit) return unit == "player" and playerGUID or "Player-1-priest" end
UnitExists = function(unit) return unit == "party1" end
UnitIsPlayer = function(unit) return unit == "party1" end
UnitCanAssist = function() return true end
UnitName = function() return "Helpfulpriest", "OtherRealm" end

local ns = {
    db = { thanksEnabled = true, thanksChannel = "WHISPER", thanksDelay = 3, thanksMessage = "Thanks for the {buff}!" },
    PARTY_BUFFS = {
        PRIEST = { { auraID = 1243, label = "Power Word: Fortitude" } },
        MAGE = { { auraID = 1459, label = "Arcane Intellect" } },
    },
    IsCombatLocked = function() return combatLocked end,
    IsSecret = function() return false end,
    Plain = function(value) return value end,
}
assert(loadfile("Features/Thanks.lua"))("Buffsmith", ns)
ns.Thanks.initialized = true

C_UnitAuras = { GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1243, sourceUnit = "party1" } end
    if index == 2 then return { spellId = 1459, sourceUnit = "party1" } end
end }
ns.Thanks:Observe(false)
equal(#sent, 0, "the thank-you is delayed")
equal(#scheduled, 1, "one delayed thank-you is queued")
equal(scheduled[1].delay, 3, "the configured delay is used")
equal(ns.Thanks.lastStatus, "queued: 3 seconds (2 buffs)", "multiple buffs from one provider share a reply")

ns.Thanks:Observe(false)
equal(#scheduled, 1, "the same active aura is not queued twice")

scheduled[1].callback()
equal(#sent, 1, "a recognised identifiable provider is thanked after the delay")
equal(sent[1].recipient, "Helpfulpriest-OtherRealm", "full cross-realm name is used for whisper")
equal(sent[1].message, "Thanks for the Power Word: Fortitude and Arcane Intellect!", "the combined message names both buffs")

ns.db.thanksEnabled = false
ns.Thanks.seen = {}
ns.Thanks:Observe(false)
equal(#scheduled, 1, "disabled Thank You does not queue a message")

ns.db.thanksEnabled = true
ns.Thanks.seen = {}
ns.Thanks:Observe(false)
equal(#scheduled, 2, "enabled Thank You queues another reply")
combatLocked = true
scheduled[2].callback()
equal(#sent, 1, "a queued reply is cancelled when combat begins")
equal(ns.Thanks.lastStatus, "cancelled: combat", "combat cancellation is reported")

print("thanks tests passed")
