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

-- The optional Forever fallback is deliberately an untargeted emote.  It is
-- used only after both direct source reads fail, never as a guessed whisper.
ns.db.thanksChannel, ns.db.thanksUnknownEmote, ns.db.thanksEmote = "EMOTE", true, "THANK"
ns.Thanks.seen, ns.Thanks.seenAuras, ns.Thanks.eligibleAuras, ns.Thanks.attributedAuras = {}, {}, {}, {}
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return { spellId = 1244, auraInstanceID = 104, name = "Power Word: Fortitude" } end
end
C_UnitAuras.GetAuraDataByAuraInstanceID = function(_, instanceID)
    if instanceID == 104 then return { spellId = 1244, auraInstanceID = 104, name = "Power Word: Fortitude" } end
end
local firstRetry = #scheduled + 1
ns.Thanks:Observe(false)
scheduled[firstRetry].callback()
scheduled[firstRetry + 1].callback()
equal(#emotes, 4, "an opted-in unknown caster gets one untargeted Forever emote")
equal(emotes[4].target, "none", "the fallback never invents an emote target")
equal(ns.Thanks.lastStatus, "emoted without caster: THANK", "the fallback is visible in diagnostics")

-- Identified group casters can be skipped without changing unknown fallback.
do
    local units, timers, output, groupParty, groupRaid
    local function setup(target)
        units = { player = "self", target = "caster", party1 = "other-member" }
        timers, output, groupParty, groupRaid = {}, {}, {}, {}
        UnitExists = function(unit) return units[unit] ~= nil end
        UnitGUID = function(unit) return units[unit] end
        UnitIsPlayer, UnitCanAssist = function() return true end, function() return true end
        UnitName = function(unit) return units[unit] end
        UnitInParty = function(unit) return groupParty[units[unit]] == true end
        UnitInRaid = function(unit) return groupRaid[units[unit]] end
        IsInGroup = function() return true end
        C_Timer.After = function(delay, fn) timers[#timers + 1] = { delay = delay, callback = fn } end
        SendChatMessage = function(...) output[#output + 1] = { ... } end
        DoEmote = function(token, unit) output[#output + 1] = { token, unit } end
        C_ChatInfo = { PerformEmote = function(token, name) output[#output + 1] = { token, name }; return true end }
        C_UnitAuras = { GetAuraDataByIndex = function() return nil end }
        local current = { TARGET = target,
            db = { thanksEnabled = true, thanksSkipGroupMembers = true, thanksUnknownEmote = true,
                thanksChannel = "WHISPER", thanksDelay = 1, thanksEmote = "THANK", thanksMessage = "Thanks for {buff}!" },
            PARTY_BUFFS = { PRIEST = { { auraID = 1243, label = "Power Word: Fortitude" } } },
            Plain = function(v) return v end, IsSecret = function() return false end,
            IsCombatLocked = function() return false end }
        assert(loadfile("Features/Thanks.lua"))("Buffsmith", current)
        current.Thanks.initialized = true
        return current
    end
    for _, target in ipairs({ "Camelot", "Mainline" }) do
        for _, channel in ipairs({ "WHISPER", "SAY", "PARTY", "EMOTE" }) do
            for _, group in ipairs({ "party", "raid" }) do
                local current = setup(target)
                current.db.thanksChannel = channel
                local unit = group == "party" and "party2" or "raid17"
                units[unit] = "caster"
                if group == "party" then groupParty.caster = true else groupRaid.caster = 17 end
                equal(current.Thanks:Queue("Fortitude", "caster", "caster", unit), false,
                    target .. " " .. channel .. " skips identified " .. group .. " caster")
                equal(#timers, 0, "skipped caster never queues thanks")
                equal(#output, 0, "skipped caster sends nothing")
                current.db.thanksSkipGroupMembers = false
                current.Thanks:Queue("Fortitude", "caster", "caster", unit)
                timers[1].callback()
                equal(#output, 1, "turning skip off retains previous channel behaviour")
            end
            local current = setup(target)
            current.db.thanksChannel = channel
            current.Thanks:Queue("Fortitude", "caster", "caster", "target")
            timers[1].callback()
            equal(#output, 1, target .. " " .. channel .. " still thanks an outside caster")
        end
        local current = setup(target)
        current.Thanks:Queue("Fortitude", "caster", "caster", "target")
        -- The caster joins the raid, while the original target token changes.
        units.target, units.raid17 = "replacement", "caster"
        groupRaid.caster = 17
        timers[1].callback()
        equal(#output, 0, "send-time roster GUID check catches joined caster despite stale token")
        current = setup(target)
        current.db.thanksSkipGroupMembers = false
        current.Thanks:Queue("Fortitude", "caster", "caster", "target")
        current.db.thanksSkipGroupMembers, units.party2, groupParty.caster = true, "caster", true
        timers[1].callback()
        equal(#output, 0, "enabling skip cancels a pending group thank-you")
        current = setup(target)
        current.Thanks:Queue("Fortitude", "caster", "caster", "target")
        units.target, groupParty.replacement = "replacement", true
        timers[1].callback()
        equal(#output, 1, "changed target joining group does not misclassify original outside caster")
        current = setup(target)
        groupRaid.caster = 0
        UnitGUID = function(unit) if unit == "player" then return "self" end end
        equal(current.Thanks:Queue("Fortitude", "caster", "caster", "target"), false,
            "numeric raid membership, including zero, skips even without a readable caster GUID")
        equal(#timers, 0, "membership API result does not need GUID roster fallback")
    end
    local current = setup("Camelot")
    units.party2, groupParty.caster = "caster", true
    local buff = function(_, index)
        if index == 1 then return { spellId = 1243, sourceUnit = "party2" } end
    end
    C_UnitAuras.GetAuraDataByIndex = buff
    current.Thanks:Observe(false)
    equal(#timers, 0, "known group buff is skipped on observation")
    current.db.thanksSkipGroupMembers = false
    current.Thanks:Observe(false)
    equal(#timers, 0, "turning skip off does not retroactively thank an existing buff")
    C_UnitAuras.GetAuraDataByIndex = function() end
    current.Thanks:Observe(false)
    C_UnitAuras.GetAuraDataByIndex = buff
    current.Thanks:Observe(false)
    equal(#timers, 1, "a newly reapplied buff can be thanked after skip is disabled")
    current = setup("Camelot")
    current.db.thanksChannel = "EMOTE"
    groupParty["other-member"] = true
    C_UnitAuras.GetAuraDataByIndex = function(_, index)
        if index == 1 then return { spellId = 1243, name = "Power Word: Fortitude" } end
    end
    current.Thanks:Observe(false)
    equal(#output, 1, "unknown-caster fallback still fires while grouped with skip enabled")
    equal(output[1][2], "none", "unknown-caster fallback remains untargeted")
    current = setup("Camelot")
    current.db.thanksChannel = "EMOTE"
    units.party2, groupParty.caster = "caster", true
    C_UnitAuras.GetAuraDataByIndex = function(_, index)
        if index == 1 then return { spellId = 1243, auraInstanceID = 999, name = "Power Word: Fortitude" } end
    end
    C_UnitAuras.GetAuraDataByAuraInstanceID = function()
        return { spellId = 1243, auraInstanceID = 999, name = "Power Word: Fortitude", sourceUnit = "party2" }
    end
    current.Thanks:Observe(false)
    timers[1].callback()
    equal(#output, 0, "retry identifying a group caster skips thanks instead of using unknown fallback")
    equal(#timers, 1, "identified group caster schedules no thank-you or extra retry")
    equal(current.Thanks.lastStatus, "skipped: caster is in your party or raid", "group skip is reported")
    for _, target in ipairs({ "Camelot", "Mainline" }) do
        current = setup(target)
        current.db.thanksChannel = "EMOTE"
        local aura = { spellId = 1243, auraInstanceID = 701, sourceUnit = "target" }
        C_UnitAuras.GetAuraDataByIndex = function(_, index) if index == 1 then return aura end end
        current.Thanks:Observe(true)
        current.Thanks:Queue("Fortitude", "caster", "caster", "target")
        local oldSend = timers[#timers].callback
        current.Thanks:ZoneTransition(true)
        aura = nil
        current.Thanks:Observe(false)
        oldSend()
        equal(#output, 0, "loading cancels pending thanks")
        current.Thanks:ZoneTransition(false)
        local oldSettle = timers[#timers].callback
        current.Thanks:ZoneTransition(false)
        local settle = timers[#timers].callback
        oldSettle()
        equal(current.Thanks.zoneReady, false, "obsolete zone timer cannot end a newer transition")
        aura = { spellId = 1243, auraInstanceID = 702 }
        current.Thanks:Observe(false)
        equal(next(current.Thanks.retrying), nil, "rehydrated aura cannot start attribution retries")
        local combat = true
        current.IsCombatLocked = function() return combat end
        settle()
        equal(current.Thanks.zonePriming, true, "combat defers final zone baseline")
        combat = false
        current.Thanks:FinishZoneTransition()
        equal(current.Thanks.zonePriming, false, "combat ending finishes zone baseline")
        aura.sourceUnit = "target"
        current.Thanks:Observe(false)
        equal(#output, 0, "late caster for an existing zone buff is not thanked")
        aura = nil
        current.Thanks:Observe(false)
        aura = { spellId = 1243, sourceUnit = "target" }
        current.Thanks:Observe(false)
        local freshSend = timers[#timers].callback
        oldSend()
        equal(current.Thanks.pending.caster ~= nil, true, "cancelled callback cannot clear a new job for the same caster")
        current.Thanks:Observe(false, { isFullUpdate = true })
        equal(current.Thanks.pending.caster ~= nil, true, "ordinary full update preserves an already queued valid reply")
        freshSend()
        equal(#output, 1, "genuine new outside buff is thanked after settling")
        aura = { spellId = 1243, auraInstanceID = 703 }
        current.Thanks:Observe(false, { isFullUpdate = true })
        equal(next(current.Thanks.retrying), nil, "full aura snapshot primes without retrying old buffs")
        aura.sourceUnit = "target"
        current.Thanks:Observe(false)
        equal(next(current.Thanks.pending), nil, "late source after full snapshot stays baseline")
    end
    current = setup("Camelot")
    current.db.thanksChannel = "EMOTE"
    local aura = { spellId = 1243, auraInstanceID = 801 }
    C_UnitAuras.GetAuraDataByIndex = function(_, index) if index == 1 then return aura end end
    current.Thanks:Observe(false)
    local oldRetry = timers[#timers].callback
    current.Thanks:ZoneTransition(true)
    oldRetry()
    equal(#output, 0, "loading invalidates attribution retry fallback")
    aura = nil
    current.Thanks:ZoneTransition(false)
    timers[#timers].callback()
    aura = { spellId = 1243 }
    current.Thanks:Observe(false)
    equal(#output, 1, "unknown-caster fallback still fires after zone settling")
end

print("thanks tests passed")
