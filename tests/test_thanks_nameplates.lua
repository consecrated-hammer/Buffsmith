local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local SELF, CASTER, OTHER = "Player-1-self", "Player-2-caster", "Player-3-other"
local secret = {}
local function fixture(target, channel)
    local state = { now = 100, units = { player = SELF }, timers = {}, output = {}, guid = CASTER,
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
    GetTime = function() return state.now end
    C_Timer = { After = function(delay, callback)
        state.timers[#state.timers + 1] = { at = state.now + delay, callback = callback }
    end }
    SendChatMessage = function(text, channel, _, recipient)
        state.output[#state.output + 1] = { channel = channel, recipient = recipient }
    end
    DoEmote = function(token, recipient) state.output[#state.output + 1] = { channel = "EMOTE", recipient = recipient } end
    C_ChatInfo = { PerformEmote = function(token, recipient) DoEmote(token, recipient); return true end }
    assert(loadfile("Features/Thanks.lua"))("Buffsmith", ns)
    ns.Thanks.initialized = true
    function state:advance(seconds)
        local untilTime = self.now + seconds
        local count = 0
        while true do
            table.sort(self.timers, function(a, b) return a.at < b.at end)
            if not self.timers[1] or self.timers[1].at > untilTime then break end
            local timer = table.remove(self.timers, 1)
            self.now = timer.at
            timer.callback()
            count = count + 1
            assert(count < 30, "timer loop")
        end
        self.now = untilTime
    end
    return ns, state
end


local function unresolved(channel, target)
    local ns, state = fixture(target or "Camelot", channel)
    state.guid = nil
    ns.db.thanksDelay = 2
    ns.Thanks:Observe(false)
    state:advance(0.8) -- Both original retries exhausted, no further aura event.
    state.units.nameplate7 = CASTER
    return ns, state
end

for _, target in ipairs({ "Camelot", "Mainline" }) do
    for _, channel in ipairs({ "WHISPER", "EMOTE" }) do
        for _, path in ipairs({ "token", "GUID" }) do
            local ns, state = unresolved(channel, target)
            if path == "token" then state.aura.sourceUnit = "nameplate7"
            else
                state.guid = CASTER
                UnitNameFromGUID = nil -- Recover through the matching plate.
            end
            ns.Thanks:NameplateAdded("nameplate7")
            ns.Thanks:NameplateAdded("nameplate7")
            state:advance(0.11)
            assert(ns.Thanks.lastAttribution:find("after nameplate appeared", 1, true))
            ns.Thanks:Observe(false)
            state:advance(3)
            equal(#state.output, 1, target .. channel .. path .. " replies exactly once")
            equal(state.output[1].recipient, channel == "WHISPER" and "Helpful-OtherRealm"
                or (target == "Camelot" and "nameplate7" or "Helpful-OtherRealm"), "verified recipient")
        end
    end
end

for _, failure in ipairs({ "unrelated", "secret GUID", "secret name", "removed", "expired", "baseline",
    "combat", "disabled", "zone", "reset", "already sent", "group", "self", "NPC", "hostile", "no clock" }) do
    local ns, state = unresolved("WHISPER")
    if failure == "unrelated" then state.units.nameplate7 = OTHER
    elseif failure == "secret GUID" then state.guid = secret
    elseif failure == "secret name" then state.guid = CASTER; state.names[CASTER][1] = secret
    elseif failure == "removed" then state.aura = nil
    elseif failure == "expired" then state:advance(5); state.guid = CASTER
    elseif failure == "baseline" then ns.Thanks:Observe(true); state.guid = CASTER
    elseif failure == "already sent" then ns.Thanks.attributedAuras["401"] = "untargeted"; state.guid = CASTER
    elseif failure == "group" then state.guid = CASTER; state.units.party2 = CASTER
    elseif failure == "self" then state.guid = SELF
    elseif failure == "NPC" then state.guid = "Creature-1-npc"
    elseif failure == "hostile" then state.aura.sourceUnit = "nameplate7"; UnitCanAssist = function() return false end
    elseif failure == "no clock" then GetTime = function() return secret end
    else state.guid = CASTER end
    ns.Thanks:NameplateAdded("nameplate7")
    if failure == "combat" then state.combat = true; ns.Thanks:CombatStarted()
    elseif failure == "disabled" then ns.Thanks:SetEnabled(false); ns.Thanks:SetEnabled(true)
    elseif failure == "zone" then ns.Thanks:ZoneTransition(true)
    elseif failure == "reset" then ns.Thanks:Observe(true) end
    state:advance(4)
    equal(#state.output, 0, failure .. " cannot produce a reply")
end

-- A fallback that has already fired is final, but a pending one can become directed.
do
    local ns, state = unresolved("EMOTE")
    state:advance(3)
    equal(#state.output, 1, "unknown fallback sent")
    state.guid = CASTER
    ns.Thanks:NameplateAdded("nameplate7")
    state:advance(3)
    equal(#state.output, 1, "no directed thanks after general thanks")
end

-- A recycled token is revalidated when sending, rather than thanking its new owner.
do
    local ns, state = unresolved("EMOTE")
    state.aura.sourceUnit = "nameplate7"
    ns.Thanks:NameplateAdded("nameplate7")
    state:advance(0.11)
    state.units.nameplate7 = OTHER
    state:advance(3)
    equal(#state.output, 1, "recycled plate gives one reply")
    equal(state.output[1].recipient, "Helpful", "captured identity survives token reuse")
end

-- Appearance events do not extend the original window or schedule work for old buffs.
do
    local ns, state = unresolved("WHISPER")
    local deadline = ns.Thanks.eligibilityDeadline["401"]
    for i = 1, 60 do ns.Thanks:NameplateAdded("nameplate7") end
    equal(#state.timers, 1, "appearance burst coalesces")
    state:advance(0.11)
    equal(ns.Thanks.eligibilityDeadline["401"], deadline, "original deadline retained")
    ns.Thanks:Observe(true)
    ns.Thanks:NameplateAdded("nameplate7")
    equal(#state.timers, 0, "baseline appearance schedules no work")
end
print("Nameplate attribution tests passed")

-- Retry identity includes the original spell, not only the instance number.
do
    local ns, state = unresolved("WHISPER")
    ns.PARTY_BUFFS.PRIEST[2] = { auraID = 1459, label = "Intellect" }
    ns.Thanks.tracked, ns.Thanks.trackedNames = nil, nil
    state.aura.spellId, state.guid = 1459, CASTER
    ns.Thanks:NameplateAdded("nameplate7")
    state:advance(3)
    equal(#state.output, 0, "recycled instance with another recognized spell cannot thank")
end

-- Check expiry again after the coalescing wait, not just when scheduling.
do
    local ns, state = unresolved("WHISPER")
    state:advance(4.15)
    state.guid = CASTER
    ns.Thanks:NameplateAdded("nameplate7")
    state:advance(3)
    equal(#state.output, 0, "window expiring during scheduled wait cannot thank")
end
