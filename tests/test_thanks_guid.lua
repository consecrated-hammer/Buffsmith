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

for _, target in ipairs({ "Camelot", "Mainline" }) do
    for _, channel in ipairs({ "WHISPER", "EMOTE", "SAY", "PARTY" }) do
        local ns, state = fixture(target, channel)
        ns.Thanks:Observe(false)
        equal(ns.Thanks.lastAttribution, "Fortitude: aura caster GUID", "GUID recovery is visible")
        state:drain()
        equal(#state.output, 1, target .. " " .. channel .. " recovers caster without a unit")
        if channel == "WHISPER" then equal(state.output[1].recipient, "Helpful-OtherRealm", "whisper uses realm-qualified name") end
        if channel == "EMOTE" then
            equal(state.output[1].recipient, target == "Camelot" and "Helpful" or "Helpful-OtherRealm",
                "emote receives the name form used by its client")
        end
        ns.Thanks:Observe(false)
        equal(#state.timers, 0, "same recovered aura does not repeat thanks")
    end
    for _, group in ipairs({ "party1", "raid25" }) do
        local ns, state = fixture(target)
        state.units[group], state.names[CASTER] = CASTER, nil
        ns.Thanks:Observe(false)
        equal(#state.timers, 0, "identified group GUID skips even without a readable name")
        -- A later name and disabled group filter cannot retroactively thank an old buff.
        ns.db.thanksSkipGroupMembers = false
        state.names[CASTER] = { "Helpful", "OtherRealm" }
        ns.Thanks:Observe(false)
        state:drain()
        equal(#state.output, 0, "GUID recovery never thanks an identified group caster")
    end
    local ns, state = fixture(target, "EMOTE")
    state.units.target, state.token = CASTER, "target"
    state.names[CASTER] = { "Helpful", "OtherRealm" }
    ns.Thanks:Observe(false)
    state.units.target, state.units.nameplate7 = OTHER, CASTER
    state:drain()
    equal(state.output[1].recipient, target == "Camelot" and "nameplate7" or "Helpful-OtherRealm", "send reacquires matching GUID instead of reused token")

    ns, state = fixture(target, "EMOTE")
    state.units.target, state.token = CASTER, "target"
    state.names[CASTER] = { "Helpful", "OtherRealm" }
    ns.Thanks:Observe(false)
    state.units.target = OTHER
    state:drain()
    equal(state.output[1].recipient, target == "Camelot" and "Helpful" or "Helpful-OtherRealm", "departed unit falls back to captured original name")

    ns, state = fixture(target)
    ns.Thanks:Observe(false)
    state.units.party2 = CASTER
    state:drain()
    equal(#state.output, 0, "GUID-only caster joining group before sending is skipped")

    ns, state = fixture(target)
    state.token, state.units.target = "target", OTHER
    ns.Thanks:Observe(false)
    state:drain()
    equal(state.output[1].recipient, "Helpful-OtherRealm", "mismatched GUID token cannot redirect reply")

    for _, guid in ipairs({ SELF, "Creature-1-npc" }) do
        ns, state = fixture(target, "EMOTE")
        state.guid = guid
        ns.Thanks:Observe(false)
        state:drain()
        equal(#state.output, 0, "self and NPC GUIDs never use generic fallback")
    end
    for _, failure in ipairs({ "missing", "secret", "error", "secret name", "secret realm", "unresolved" }) do
        ns, state = fixture(target)
        if failure == "missing" then C_UnitAuras.GetAuraCasterGUID = nil
        elseif failure == "secret" then state.guid = secret
        elseif failure == "error" then C_UnitAuras.GetAuraCasterGUID = function() error("restricted") end
        elseif failure == "secret name" then state.names[CASTER][1] = secret
        elseif failure == "secret realm" then state.names[CASTER][2] = secret
        else state.names[CASTER] = nil end
        ns.Thanks:Observe(false)
        state:drain()
        equal(#state.output, 0, "unreadable attribution cannot whisper: " .. failure)
    end
    ns, state = fixture(target, "EMOTE")
    state.units.player = secret
    ns.Thanks:Observe(false)
    state:drain()
    equal(#state.output, 0, "unreadable own GUID cannot cause a self thank or general fallback")
    ns, state = fixture(target)
    state.units.party1 = CASTER
    ns.Thanks:Observe(false)
    state:drain()
    equal(#state.output, 0, "fresh recovered group caster is skipped with a readable name")
    ns, state = fixture(target)
    ns.Thanks:Observe(true)
    ns.Thanks:Observe(false)
    state:drain()
    equal(#state.output, 0, "baseline GUID recovery cannot thank an old buff")
    ns, state = fixture(target)
    ns.Thanks:Observe(false)
    ns.Thanks:ZoneTransition(true)
    state:drain()
    equal(#state.output, 0, "zone transition cancels GUID-based pending replies")
end

local grouped, groupState = fixture("Camelot", "EMOTE")
groupState.units.party1, groupState.names[CASTER] = CASTER, nil
grouped.Thanks:Observe(false)
groupState:drain()
equal(#groupState.output, 0, "identified group GUID with no name cannot fall through to generic emote")

local ns, state = fixture("Camelot")
state.guid = nil
ns.Thanks:Observe(false)
state.guid = CASTER
state:drain()
equal(#state.output, 1, "delayed retry uses GUID recovery")
equal(state.output[1].recipient, "Helpful-OtherRealm", "retry preserves recovered whisper recipient")

ns, state = fixture("Camelot", "EMOTE")
state.guid = nil
ns.Thanks:Observe(false)
state:drain()
equal(#state.output, 1, "failed GUID recovery retains opted-in generic thanks")
equal(state.output[1].recipient, nil, "failed recovery never guesses a recipient")

ns, state = fixture("Camelot", "EMOTE")
state.guid = nil
ns.Thanks:Observe(false)
state.guid = SELF
state:drain()
equal(#state.output, 0, "retry discovering self does not fall through to generic thanks")

ns, state = fixture("Camelot")
UnitNameFromGUID = nil
GetPlayerInfoByGUID = function() return nil, nil, nil, nil, nil, "Helpful", "OtherRealm" end
ns.Thanks:Observe(false)
state:drain()
equal(state.output[1].recipient, "Helpful-OtherRealm", "legacy name lookup can resolve a GUID")

print("GUID thank-you tests passed")
