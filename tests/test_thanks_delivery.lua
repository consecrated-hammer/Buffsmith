local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local SELF, CASTER, OTHER = "Player-1-self", "Player-2-caster", "Player-3-other"
local secret = {}
local function fixture(target, channel)
    local state = { units = { player = SELF }, timers = {}, output = {}, guid = CASTER,
        names = { [CASTER] = { "Helpful", "Other Realm" } }, combat = false,
        aura = { spellId = 1243, auraInstanceID = 401 }, group = false }
    local ns = { TARGET = target,
        db = { thanksEnabled = true, thanksChannel = channel or "WHISPER", thanksDelay = 1,
            thanksSkipGroupMembers = true, thanksUnknownEmote = true, thanksEmote = "THANK", thanksMessage = "Thanks for {buff}!" },
        PARTY_BUFFS = { PRIEST = { { auraID = 1243, label = "Fortitude" } } },
        Plain = function(v) if v ~= secret then return v end end,
        IsSecret = function(v) return v == secret end,
        IsCombatLocked = function() return state.combat end }
    UnitExists = function(unit) return state.units[unit] ~= nil end
    UnitGUID = function(unit) return state.units[unit] end
    UnitIsPlayer, UnitCanAssist = function() return true end, function() return true end
    UnitName = function(unit)
        local name = state.names[state.units[unit]]
        if name then return name[1], name[2] end
    end
    UnitInParty, UnitInRaid = function() return false end, function() end
    UnitTokenFromGUID = function() return state.token end
    UnitNameFromGUID = function(guid)
        local name = state.names[guid]
        if name then return name[1], name[2] end
    end
    GetPlayerInfoByGUID = nil
    IsInGroup = function() return true end
    C_UnitAuras = {
        GetAuraDataByIndex = function(_, index) if index == 1 then return state.aura end end,
        GetAuraDataByAuraInstanceID = function() return state.aura end,
        GetAuraCasterGUID = function(unit, id)
            equal(unit, "player", "GUID lookup receives aura owner")
            equal(id, 401, "GUID lookup receives instance ID")
            return state.guid
        end }
    C_Timer = { After = function(delay, callback) state.timers[#state.timers + 1] = callback end }
    SendChatMessage = function(text, channel, _, recipient)
        state.output[#state.output + 1] = { channel = channel, recipient = recipient }
    end
    DoEmote = function(token, recipient) state.output[#state.output + 1] = { channel = "EMOTE", recipient = recipient } end
    C_ChatInfo = { PerformEmote = function(token, recipient) DoEmote(token, recipient); return true end }
    assert(loadfile("Features/Thanks.lua"))("Buffsmith", ns)
    ns.Thanks.initialized = true
    function state:drain()
        local index = 1
        while index <= #self.timers do
            assert(index <= 10, "timer loop")
            self.timers[index](); index = index + 1
        end
        self.timers = {}
    end
    return ns, state
end


-- Exercise delivery policy through actual aura observations and timer callbacks.
for _, target in ipairs({ "Camelot", "Mainline" }) do
    local ns, state = fixture(target, "EMOTE")
    DoEmote = function() return false end
    C_ChatInfo.PerformEmote = DoEmote
    ns.Thanks:Observe(false)
    state:drain()
    equal(ns.Thanks.lastStatus, "skipped: emote rejected", target .. " API false is not a success")

    for _, failure in ipairs({ "error", "secret", "partial" }) do
        ns, state = fixture(target, "EMOTE")
        ns.Thanks:Observe(true)
        local original = C_UnitAuras.GetAuraDataByIndex
        C_UnitAuras.GetAuraDataByIndex = function(_, index)
            if failure == "partial" and index == 1 then return { spellId = 1243, auraInstanceID = 402 } end
            if failure == "secret" then return secret end
            error("unavailable")
        end
        ns.Thanks:Observe(false)
        equal(#state.timers, 0, "incomplete snapshot cannot queue partial observations")
        C_UnitAuras.GetAuraDataByIndex = original
        ns.Thanks:Observe(false)
        state:drain()
        equal(#state.output, 0, target .. " " .. failure .. " scan preserves baseline")
    end

    for _, cancellation in ipairs({ "disabled", "combat", "zone" }) do
        ns, state = fixture(target, "EMOTE")
        ns.Thanks:Observe(false)
        if cancellation == "disabled" then ns.Thanks:SetEnabled(false); ns.Thanks:SetEnabled(true)
        elseif cancellation == "combat" then
            state.combat = true; ns.Thanks:CombatStarted()
            state.combat = false; ns.Thanks:CombatEnded()
        else ns.Thanks:ZoneTransition(true) end
        state:drain()
        equal(#state.output, 0, target .. " pending reply cancelled by " .. cancellation)
    end
end

local ns, state = fixture("Camelot", "EMOTE")
state.guid = nil
ns.db.thanksDelay = 2
ns.Thanks:Observe(false)
state.timers[1]() -- 0.2s retry
state.timers[2]() -- 0.7s retry
local fallback = state.timers[3]
equal(type(fallback), "function", "unknown reply queues after bounded attribution retries")
equal(#state.output, 0, "unknown reply waits instead of sending during retry")
fallback()
equal(#state.output, 1, "one general emote after delay")
state.guid = CASTER
ns.Thanks:Observe(false)
state:drain()
equal(#state.output, 1, "late attribution cannot thank the same buff twice")
state.guid = OTHER
state.names[OTHER] = { "Another", "Realm" }
ns.Thanks:Observe(false)
state:drain()
equal(#state.output, 2, "genuinely different caster refreshing aura can be thanked")

for _, recovery in ipairs({ "known", "group", "self", "removed", "full snapshot" }) do
    ns, state = fixture("Camelot", "EMOTE")
    state.guid = nil
    ns.Thanks:Observe(false)
    state.timers[1](); state.timers[2]()
    if recovery == "removed" then state.aura = nil
    elseif recovery == "self" then state.guid = SELF
    else state.guid = CASTER end
    if recovery == "group" then state.units.party1 = CASTER end
    ns.Thanks:Observe(false, recovery == "full snapshot" and { isFullUpdate = true } or nil)
    state:drain()
    equal(#state.output, recovery == "known" and 1 or 0, "pending general reply handles " .. recovery)
end

for _, cancellation in ipairs({ "disabled", "combat", "zone", "fallback off", "channel changed" }) do
    ns, state = fixture("Camelot", "EMOTE")
    state.guid = nil
    ns.Thanks:Observe(false)
    state.timers[1](); state.timers[2]()
    if cancellation == "disabled" then ns.Thanks:SetEnabled(false); ns.Thanks:SetEnabled(true)
    elseif cancellation == "combat" then ns.Thanks:CombatStarted(); ns.Thanks:CombatEnded()
    elseif cancellation == "zone" then ns.Thanks:ZoneTransition(true)
    elseif cancellation == "fallback off" then ns.db.thanksUnknownEmote = false
    else ns.db.thanksChannel = "WHISPER" end
    state:drain()
    equal(#state.output, 0, "pending general reply cancelled by " .. cancellation)
end

ns, state = fixture("Camelot", "EMOTE")
state.guid = nil
local first = state.aura
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return first end
    if index == 2 then return { spellId = 1243, auraInstanceID = 402 } end
end
C_UnitAuras.GetAuraDataByAuraInstanceID = function(_, id)
    return { spellId = 1243, auraInstanceID = id }
end
ns.Thanks:Observe(false)
state:drain()
equal(#state.output, 1, "multiple unknown buffs batch into one general emote")

-- A missing name must not discard a known group GUID.
ns, state = fixture("Camelot", "EMOTE")
state.aura.sourceUnit = "party1"
state.units.party1 = CASTER
state.names[CASTER] = nil
C_UnitAuras.GetAuraCasterGUID = nil
ns.Thanks:Observe(false)
state:drain()
equal(#state.output, 0, "known group token without readable name never falls through")

-- Self/NPC evidence invalidates outstanding attribution work permanently.
for _, exclusion in ipairs({ "self", "npc" }) do
    ns, state = fixture("Camelot", "EMOTE")
    state.guid = nil
    ns.Thanks:Observe(false)
    local retry = state.timers[1]
    if exclusion == "self" then state.guid = SELF else state.guid = "Creature-1-npc" end
    ns.Thanks:Observe(false)
    state.guid = nil
    retry()
    state:drain()
    equal(#state.output, 0, "known " .. exclusion .. " exclusion survives subsequent missing identity")
end

for _, baseline in ipairs({ true, false }) do
    ns, state = fixture("Camelot", "EMOTE")
    state.units.target = CASTER
    state.aura.sourceUnit = "target"
    local originalGUID = UnitGUID
    local hidden = true
    UnitGUID = function(unit) if unit == "target" and hidden then return nil end; return originalGUID(unit) end
    ns.Thanks:Observe(baseline)
    hidden = false
    ns.Thanks:Observe(false)
    state:drain()
    equal(#state.output, baseline and 0 or 1, "name-to-GUID enrichment is not a new application")
end

ns, state = fixture("Camelot", "WHISPER")
SendChatMessage = function() error("blocked") end
ns.Thanks:Observe(false)
state:drain()
equal(ns.Thanks.lastStatus, "skipped: chat rejected", "chat exceptions become diagnostics")

ns, state = fixture("Camelot", "EMOTE")
GetTime = function() return state.now or 0 end
state.guid = nil
ns.db.thanksUnknownEmote = false
ns.Thanks:Observe(false)
state:drain()
state.now, state.guid = 6, CASTER
ns.Thanks:Observe(false)
state:drain()
equal(#state.output, 0, "late identity cannot create a stale reply after five seconds")
GetTime = nil

ns, state = fixture("Camelot", "EMOTE")
for index = 1, 20 do ns.Thanks.lastStatus = "decision " .. index; ns.Thanks:SaveDiagnostics() end
equal(#ns.db.thanksDiagnostics, 12, "saved diagnostics stay bounded")
equal(ns.db.thanksDiagnostics[12].status, "decision 20", "newest decision survives")
local saved = ns.db.thanksDiagnostics
assert(loadfile("Features/Thanks.lua"))("Buffsmith", ns)
equal(ns.db.thanksDiagnostics, saved, "runtime reload preserves saved decisions")


-- Identity enrichment can arrive before the display name recovers.
for _, baseline in ipairs({ true, false }) do
    ns, state = fixture("Camelot", "EMOTE")
    state.units.target = CASTER
    state.aura.sourceUnit = "target"
    C_UnitAuras.GetAuraCasterGUID = nil
    local originalGUID, hidden = UnitGUID, true
    UnitGUID = function(unit) if unit == "target" and hidden then return nil end; return originalGUID(unit) end
    ns.Thanks:Observe(baseline)
    state:drain()
    hidden, state.names[CASTER] = false, nil
    ns.Thanks:Observe(false)
    state.names[CASTER] = { "Helpful", "Other Realm" }
    ns.Thanks:Observe(false)
    state:drain()
    equal(#state.output, baseline and 0 or 1, "temporarily missing name during enrichment never re-arms aura")
end

ns, state = fixture("Camelot", "EMOTE")
state.units.target = CASTER
state.aura.sourceUnit = "target"
C_UnitAuras.GetAuraCasterGUID = nil
ns.PARTY_BUFFS.MAGE = { { auraID = 1459, label = "Intellect" } }
local originalGUID, hidden = UnitGUID, true
UnitGUID = function(unit) if unit == "target" and hidden then return nil end; return originalGUID(unit) end
local aura2
C_UnitAuras.GetAuraDataByIndex = function(_, index)
    if index == 1 then return state.aura elseif index == 2 then return aura2 end
end
ns.Thanks:Observe(false)
hidden = false
aura2 = { spellId = 1459, auraInstanceID = 402, sourceUnit = "target" }
ns.Thanks:Observe(false)
state:drain()
equal(#state.output, 1, "one caster batches across name-to-GUID pending job migration")

ns, state = fixture("Camelot", "EMOTE")
state.guid = nil
ns.Thanks:Observe(false)
state.timers[1](); state.timers[2]()
local oldFallback = state.timers[3]
ns.Thanks:Observe(false, { isFullUpdate = true })
state.aura = { spellId = 1243, auraInstanceID = 402 }
C_UnitAuras.GetAuraCasterGUID = nil
ns.Thanks:Observe(false)
state.timers[4](); state.timers[5]()
local newFallback = state.timers[6]
equal(type(newFallback), "function", "new unknown application gets its own delay after full baseline")
oldFallback()
equal(#state.output, 0, "preserved old fallback timer cannot deliver a new application early")
newFallback()
equal(#state.output, 1, "new timer delivers once")

ns, state = fixture("Camelot", "EMOTE")
state.guid = nil
ns.Thanks:Observe(false)
DoEmote = function() return false end
state:drain()
equal(ns.Thanks.attributedAuras["401"], "rejected", "rejected fallback has a terminal outcome")
equal(ns.Thanks.lastStatus, "skipped: untargeted emote rejected", "rejected general emote is visible")

ns, state = fixture("Camelot", "EMOTE")
ns.Thanks.lastStatus = "sent"
ns.Thanks:SaveDiagnostics()
for index = 1, 20 do ns.Thanks.lastScan = "scan " .. index; ns.Thanks:SaveDiagnostics() end
equal(#ns.db.thanksDiagnostics, 1, "scan noise cannot evict actual decisions")

ns, state = fixture("Camelot", "EMOTE")
local originalGUID = UnitGUID
local ownHidden = true
UnitGUID = function(unit) if unit == "player" and ownHidden then return nil end; return originalGUID(unit) end
ns.Thanks:Observe(false)
ownHidden = false
state:drain()
equal(#state.output, 1, "bounded retry recovers transient unreadable own identity")


for _, unavailable in ipairs({ "nil", "error", "secret" }) do
    ns, state = fixture("Camelot", "EMOTE")
    state.units.target = CASTER
    state.aura.sourceUnit = "target"
    UnitCanAssist = function()
        if unavailable == "error" then error("not readable") end
        if unavailable == "secret" then return secret end
    end
    ns.Thanks:Observe(false)
    equal(ns.Thanks.attributedAuras["401"], nil, "unreadable friendliness is recoverable: " .. unavailable)
    UnitCanAssist = function() return true end
    state:drain()
    equal(#state.output, 1, "friendly caster recovers through retry: " .. unavailable)
end
ns, state = fixture("Camelot", "EMOTE")
state.units.target = CASTER
state.aura.sourceUnit = "target"
UnitCanAssist = function() return false end
ns.Thanks:Observe(false)
state:drain()
equal(#state.output, 0, "explicit unfriendly source remains excluded")

print("Thank You delivery lifecycle tests passed")
