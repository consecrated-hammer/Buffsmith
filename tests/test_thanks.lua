local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local sent = {}
local playerGUID = "Player-1-0001"
local scheduled = {}
local combatLocked = false
local providerGUID = "Player-1-priest"
local emotes = {}

C_Timer = { After = function(delay, callback) scheduled[#scheduled + 1] = { delay = delay, callback = callback } end }

SendChatMessage = function(message, channel, _, recipient)
    sent[#sent + 1] = { message = message, channel = channel, recipient = recipient }
end
UnitGUID = function(unit) return unit == "player" and playerGUID or providerGUID end
UnitExists = function(unit) return unit == "party1" end
UnitIsPlayer = function(unit) return unit == "party1" end
UnitCanAssist = function() return true end
UnitName = function() return "Helpfulpriest", "OtherRealm" end

local ns = {
    db = { thanksEnabled = true, thanksChannel = "WHISPER", thanksDelay = 3, thanksMessage = "Thanks for the {buff}!" },
    PARTY_BUFFS = {
        DRUID = { { auraID = 1126, label = "Mark of the Wild" } },
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
local twoBuffs = C_UnitAuras.GetAuraDataByIndex
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
equal(#scheduled, 1, "enabling Thank You does not re-thank an existing aura")
C_UnitAuras.GetAuraDataByIndex = function() end
ns.Thanks:Observe(false)
C_UnitAuras.GetAuraDataByIndex = twoBuffs
ns.Thanks:Observe(false)
equal(#scheduled, 2, "a removed and reapplied buff queues another reply")
combatLocked = true
scheduled[2].callback()
equal(#sent, 1, "a queued reply is cancelled when combat begins")
equal(ns.Thanks.lastStatus, "cancelled: combat", "combat cancellation is reported")

combatLocked = false
MAXEMOTEINDEX = 4
EMOTE1_TOKEN, EMOTE1_CMD1 = "BOW", "bow"
EMOTE2_TOKEN, EMOTE2_CMD1 = "THANK", "thank"
EMOTE3_TOKEN, EMOTE3_CMD1 = "DANCE", "/dance"
EMOTE4_TOKEN, EMOTE4_CMD1 = "BOW", "bow"
local choices = ns.Thanks:EmoteChoices()
equal(#choices, 4, "aliases do not duplicate emotes")
equal(choices[1].token, "RANDOM", "random leads the picker")
equal(choices[2].token, "THANK", "thank is the first featured emote")
equal(choices[2].label, "Thank", "featured emotes use plain names")
equal(choices[3].token, "BOW", "other featured emotes follow")
equal(choices[4].token, "DANCE", "the remaining catalogue follows featured emotes")
equal(choices[4].label, "Dance", "catalogue emotes use plain names")

ns.db.thanksChannel, ns.db.thanksEmote = "EMOTE", "THANK"
C_ChatInfo = { PerformEmote = function(token, target)
    emotes[#emotes + 1] = { token = token, target = target }
    return true
end }
ns.Thanks:Queue("Power Word: Fortitude", "Helpfulpriest-OtherRealm", providerGUID, "party1")
ns.Thanks:Queue("Arcane Intellect", "Helpfulpriest-OtherRealm", providerGUID, "party1")
scheduled[3].callback()
equal(#emotes, 1, "one targeted emote thanks a provider for two buffs")
equal(emotes[1].token, "THANK", "the configured emote is sent")
equal(emotes[1].target, "Helpfulpriest-OtherRealm", "emote is directed at the provider")
equal(#sent, 1, "emote mode sends no chat message")

ns.db.thanksEmote = "RANDOM"
ns.Thanks:Queue("Power Word: Fortitude", "Helpfulpriest-OtherRealm", providerGUID, "party1")
scheduled[4].callback()
equal(#emotes, 2, "random sends one emote")
assert(emotes[2].token == "THANK" or emotes[2].token == "BOW" or emotes[2].token == "DANCE")

ns.Thanks:Queue("Power Word: Fortitude", "Helpfulpriest-OtherRealm", providerGUID, "party1")
providerGUID = "Player-1-someone-else"
scheduled[5].callback()
equal(#emotes, 2, "a changed unit token is never thanked")
equal(ns.Thanks.lastStatus, "skipped: emote target unavailable", "lost target is reported")

providerGUID = "Player-1-priest"
ns.TARGET = "Camelot"
C_ChatInfo = { PerformEmote = function() error("Forever must use DoEmote") end }
DoEmote = function(token, unit) emotes[#emotes + 1] = { token = token, target = unit } end
ns.db.thanksEmote = "BOW"
ns.Thanks:Queue("Power Word: Fortitude", "Helpfulpriest-OtherRealm", providerGUID, "party1")
scheduled[6].callback()
equal(emotes[3].token, "BOW", "Forever uses its configured emote")
equal(emotes[3].target, "party1", "Forever uses the confirmed unit token")

ns.Thanks.tracked = nil
ns.Thanks.seen = {}
ns.db.thanksChannel = "WHISPER"
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1244, name = "Power Word: Fortitude", sourceUnit = "party1" } end
end
ns.Thanks:Observe(false)
equal(#scheduled, 7, "a ranked Forever buff is queued by its name")
assert(ns.Thanks.lastScan:find("1 name matches", 1, true), "rank match is visible in diagnostics")
scheduled[7].callback()
equal(#sent, 2, "the ranked buff sends a thank-you")

ns.Thanks.seen = {}
ns.Thanks.seenAuras = {}
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1244, name = "Power Word: Fortitude" } end
end
ns.Thanks:Observe(false)
equal(#scheduled, 7, "a buff without a caster does not queue a reply")
equal(ns.Thanks.lastStatus, "skipped: provider unavailable for Power Word: Fortitude (no caster token)", "missing Forever source is explained")
assert(ns.Thanks.lastScan:find("1 without provider", 1, true), "missing source is visible in diagnostics")
ns.Thanks.lastStatus = "sent"
ns.Thanks:Observe(false)
equal(ns.Thanks.lastStatus, "sent", "an existing unidentified buff does not repeatedly replace status")

ns.Thanks.lastStatus = "sent"
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1126, name = "Mark of the Wild", sourceUnit = "player" } end
end
ns.Thanks:Observe(false)
equal(ns.Thanks.lastStatus, "sent", "an existing self-buff does not overwrite thank-you status")
assert(ns.Thanks.lastScan:find("1 self; 0 without provider", 1, true), "self-casts are separated from unknown providers")

ns.Thanks.seen, ns.Thanks.seenAuras = {}, {}
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1244, auraInstanceID = 99, name = "Power Word: Fortitude" } end
end
ns.Thanks:Observe(false, { addedAuras = { { spellId = 1244, auraInstanceID = 99, sourceUnit = "party1" } } })
equal(#scheduled, 8, "matching UNIT_AURA entry supplies a direct caster")
equal(ns.Thanks.lastAttribution, "Power Word: Fortitude: UNIT_AURA added aura", "event attribution is reported")
scheduled[8].callback()
equal(#sent, 3, "a directly attributed event sends one thanks")

ns.Thanks.seen, ns.Thanks.seenAuras = {}, {}
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1244, auraInstanceID = 100, name = "Power Word: Fortitude" } end
end
C_UnitAuras.GetAuraDataByAuraInstanceID = function(_, instanceID)
    if instanceID == 100 then
        return { spellId = 1244, auraInstanceID = 100, name = "Power Word: Fortitude", sourceUnit = "party1" }
    end
end
ns.Thanks:Observe(false)
equal(#scheduled, 9, "a fresh uncredited aura gets one bounded retry")
equal(scheduled[9].delay, 0.2, "first retry waits briefly")
scheduled[9].callback()
equal(#scheduled, 10, "the same aura gaining a caster queues a thank-you")
equal(ns.Thanks.lastAttribution, "Power Word: Fortitude: indexed aura after retry 1", "retry attribution is reported")
scheduled[10].callback()
equal(#sent, 4, "late direct attribution sends a whisper")

ns.Thanks.seen, ns.Thanks.seenAuras = {}, {}
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1244, auraInstanceID = 101, name = "Power Word: Fortitude" } end
end
C_UnitAuras.GetAuraDataByAuraInstanceID = function(_, instanceID)
    if instanceID == 101 then return { spellId = 1244, auraInstanceID = 101, name = "Power Word: Fortitude" } end
end
ns.Thanks:Observe(false)
equal(#scheduled, 11, "an unattributed aura schedules a retry")
scheduled[11].callback()
equal(scheduled[12].delay, 0.5, "second retry remains bounded")
scheduled[12].callback()
equal(#sent, 4, "no whisper is sent without a direct caster")
assert(ns.Thanks.lastAttribution:find("no caster after 0.7 seconds", 1, true), "failed retry is reported")

ns.Thanks.seen, ns.Thanks.seenAuras, ns.Thanks.seenProviders, ns.Thanks.eligibleAuras = {}, {}, {}, {}
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1244, auraInstanceID = 102, name = "Power Word: Fortitude" } end
end
ns.Thanks:Observe(true)
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1244, auraInstanceID = 102, name = "Power Word: Fortitude", sourceUnit = "party1" } end
end
ns.Thanks:Observe(false)
equal(#scheduled, 12, "a pre-existing aura is not thanked when its caster appears later")

ns.Thanks.seen, ns.Thanks.seenAuras, ns.Thanks.seenProviders, ns.Thanks.eligibleAuras = {}, {}, {}, {}
providerGUID = "Player-1-priest"
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1244, auraInstanceID = 103, name = "Power Word: Fortitude", sourceUnit = "party1" } end
end
ns.Thanks:Observe(true)
providerGUID = "Player-1-other-priest"
ns.Thanks:Observe(false)
equal(#scheduled, 13, "a different caster refreshing the same aura instance is thanked")
scheduled[13].callback()
equal(#sent, 5, "the refreshed buff sends one whisper to its new caster")

print("thanks tests passed")
