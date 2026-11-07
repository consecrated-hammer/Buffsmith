local addonName, ns = ...

ns.Thanks = { seen = {}, seenAuras = {}, seenProviders = {}, eligibleAuras = {}, attributedAuras = {}, retrying = {}, pending = {}, lastStatus = "not observed", lastScan = "not scanned", lastAttribution = "not probed" }
local Thanks = ns.Thanks
local UNKNOWN_REPLY = {}
local function after(delay, callback)
    C_Timer.After(delay, function()
        callback()
        Thanks:SaveDiagnostics()
    end)
end
local FEATURED_EMOTES = { { "THANK", "Thank" }, { "BOW", "Bow" }, { "CHEER", "Cheer" }, { "APPLAUD", "Applaud" }, { "SALUTE", "Salute" } }

-- Loading screens rebuild aura snapshots; treat them as a fresh baseline.
function Thanks:ResetHistory(preservePending)
    self.seen, self.seenAuras, self.seenProviders, self.seenProviderNames = {}, {}, {}, {}
    self.eligibilityDeadline = {}
    self.eligibleAuras, self.attributedAuras, self.retrying = {}, {}, {}
    if preservePending then self.pending[UNKNOWN_REPLY] = nil else self.pending = {} end
    self.initialized = false
end

function Thanks:FinishZoneTransition(generation)
    if generation and generation ~= self.zoneGeneration then return false end
    if not self.zonePriming or not self.zoneReady or self.loadingWorld or ns.IsCombatLocked() then return false end
    return self:Observe(true)
end

function Thanks:ZoneTransition(loading)
    self:ResetHistory()
    self.zoneGeneration = (self.zoneGeneration or 0) + 1
    self.loadingWorld, self.zonePriming, self.zoneReady = loading == true, true, false
    self.lastStatus = "paused: zone transition"
    if self.loadingWorld then return end
    self:Observe(true)
    local generation = self.zoneGeneration
    local function finish()
        if generation ~= self.zoneGeneration then return end
        self.zoneReady = true
        self:FinishZoneTransition(generation)
    end
    if C_Timer and type(C_Timer.After) == "function" then after(1, finish) else finish() end
end

local function emoteName(command, token)
    local name = type(command) == "string" and command:gsub("^/+", "") or ""
    if not name:match("^[%a][%w _-]*$") then name = token end
    name = name:gsub("[_-]+", " ")
    return name:gsub("(%a)([%w]*)", function(first, rest) return first:upper() .. rest:lower() end)
end

function Thanks:EmoteChoices()
    if self.emoteChoices then return self.emoteChoices end
    local all, seen = {}, {}
    for index = 1, tonumber(MAXEMOTEINDEX) or 1024 do
        local token = _G["EMOTE" .. index .. "_TOKEN"]
        if type(token) == "string" and token ~= "" and not seen[token] then
            seen[token] = true
            local command = _G["EMOTE" .. index .. "_CMD1"]
            all[#all + 1] = { token = token, label = emoteName(command, token) }
        end
    end
    if not seen.THANK then all[#all + 1] = { token = "THANK", label = "thank" }; seen.THANK = true end
    table.sort(all, function(a, b) return a.label:lower() < b.label:lower() end)
    local choices = { { token = "RANDOM", label = "Random" } }
    local featured = {}
    for _, item in ipairs(FEATURED_EMOTES) do
        if seen[item[1]] then
            choices[#choices + 1] = { token = item[1], label = item[2] }
            featured[item[1]] = true
        end
    end
    for _, item in ipairs(all) do
        if not featured[item.token] then choices[#choices + 1] = item end
    end
    self.emoteChoices = choices
    return choices
end

local function selectedEmote()
    local choices = Thanks:EmoteChoices()
    local available = {}
    for index = 2, #choices do available[#available + 1] = choices[index].token end
    local configured = ns.db.thanksEmote
    if configured == "RANDOM" then return available[math.random(#available)] end
    for _, token in ipairs(available) do if configured == token then return token end end
    return "THANK"
end

local function trackedBuffs()
    if Thanks.tracked and not Thanks.namesIncomplete then return Thanks.tracked end
    local tracked, names = {}, {}
    Thanks.namesIncomplete = false
    for _, classBuffs in pairs(ns.PARTY_BUFFS or {}) do
        for _, buff in ipairs(classBuffs) do
            if buff.auraID then tracked[buff.auraID] = buff end
            for _, auraID in ipairs(buff.auraIDs or {}) do tracked[auraID] = buff end
            if ns.TARGET == "Camelot" then
                names[buff.label] = buff
                local spellName
                if C_Spell and type(C_Spell.GetSpellName) == "function" then
                    local ok, value = pcall(C_Spell.GetSpellName, buff.auraID)
                    if ok then spellName = ns.Plain(value) end
                end
                if not spellName and type(GetSpellInfo) == "function" then
                    local ok, value = pcall(GetSpellInfo, buff.auraID)
                    if ok then spellName = ns.Plain(value) end
                end
                if type(spellName) == "string" then names[spellName] = buff
                else Thanks.namesIncomplete = true end
            end
        end
    end
    Thanks.tracked = tracked
    Thanks.trackedNames = names
    return tracked
end

local function plainCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return ns.Plain(value) end
end

function Thanks:SaveDiagnostics()
    if not ns.db then return end
    local signature = table.concat({ tostring(self.lastStatus), tostring(self.lastAttribution), tostring(ns.db.thanksEnabled),
        tostring(ns.db.thanksDelay), tostring(ns.db.thanksSkipGroupMembers), tostring(ns.db.thanksUnknownEmote), tostring(ns.db.thanksChannel) }, " | ")
    if signature == self.savedDiagnosticSignature then return end
    self.savedDiagnosticSignature = signature
    local history = ns.db.thanksDiagnostics
    if type(history) ~= "table" then history = {}; ns.db.thanksDiagnostics = history end
    local pending = 0
    for _ in pairs(self.pending) do pending = pending + 1 end
    history[#history + 1] = {
        at = plainCall(date, "%Y-%m-%d %H:%M:%S") or "time unavailable",
        status = self.lastStatus, scan = self.lastScan, attribution = self.lastAttribution,
        pending = pending, delay = ns.db.thanksDelay, skipGroup = ns.db.thanksSkipGroupMembers,
        unknownEmote = ns.db.thanksUnknownEmote, channel = ns.db.thanksChannel,
    }
    while #history > 12 do table.remove(history, 1) end
end

local function isSelfSource(sourceUnit)
    if sourceUnit == "player" then return true end
    if type(sourceUnit) ~= "string" or not plainCall(UnitExists, sourceUnit) then return false end
    local guid, playerGUID = plainCall(UnitGUID, sourceUnit), plainCall(UnitGUID, "player")
    return type(guid) == "string" and guid ~= "" and guid == playerGUID
end

local function sourceInfo(sourceUnit)
    if type(sourceUnit) ~= "string" then return nil, nil, "no caster token" end
    if isSelfSource(sourceUnit) then return nil, nil, "self" end
    if not plainCall(UnitExists, sourceUnit) then return nil, nil, "caster token unavailable" end
    local player = plainCall(UnitIsPlayer, sourceUnit)
    if player == false then return nil, nil, "caster is not a player" end
    if player ~= true then return nil, nil, "caster player identity unavailable" end
    if not plainCall(UnitGUID, "player") then return nil, nil, "player identity unavailable" end
    local guid = plainCall(UnitGUID, sourceUnit)
    guid = type(guid) == "string" and guid ~= "" and guid or nil
    local friendly = plainCall(UnitCanAssist, "player", sourceUnit)
    if friendly == false then return nil, guid, "caster is not friendly" end
    if friendly ~= true then return nil, guid, "caster friendliness unavailable" end
    local ok, name, realm = pcall(UnitName, sourceUnit)
    if not ok or ns.IsSecret(name) or ns.IsSecret(realm) then return nil, guid, "caster name unavailable" end
    name, realm = ns.Plain(name), ns.Plain(realm)
    if type(name) ~= "string" or name == "" then return nil, guid, "caster name unavailable" end
    local recipient = realm and realm ~= "" and name .. "-" .. realm:gsub("%s", "") or name
    return recipient, guid or recipient
end

-- GUID reads can succeed even when Forever supplies no source unit token.
local function unitForGUID(guid, preferred, quick)
    local function matches(unit)
        return type(unit) == "string" and plainCall(UnitGUID, unit) == guid
    end
    if matches(preferred) then return preferred end
    local resolved = plainCall(UnitTokenFromGUID, guid)
    if matches(resolved) then return resolved end
    for _, unit in ipairs({ "player", "target", "focus", "mouseover" }) do
        if matches(unit) then return unit end
    end
    if quick then return nil end
    for index = 1, 40 do
        if index <= 4 and matches("party" .. index) then return "party" .. index end
        if matches("raid" .. index) then return "raid" .. index end
        if matches("nameplate" .. index) then return "nameplate" .. index end
    end
end

local function nameForGUID(guid)
    local name, realm
    if type(UnitNameFromGUID) == "function" then
        local ok, value, server = pcall(UnitNameFromGUID, guid)
        if ok then name, realm = ns.Plain(value), ns.Plain(server) end
        -- A secret realm must not become an unqualified cross-realm recipient.
        if ok and ns.IsSecret(server) then return nil end
    end
    if (type(name) ~= "string" or name == "") and type(GetPlayerInfoByGUID) == "function" then
        local ok, _, _, _, _, _, value, server = pcall(GetPlayerInfoByGUID, guid)
        if ok then name, realm = ns.Plain(value), ns.Plain(server) end
        if ok and ns.IsSecret(server) then return nil end
    end
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) == "string" and realm ~= "" then return name .. "-" .. realm:gsub("%s", "") end
    return name
end

local function auraSource(aura, sourceUnit)
    local provider, key, reason = sourceInfo(sourceUnit)
    if reason ~= "self" and reason ~= "caster is not a player" then
        local ownGUID = plainCall(UnitGUID, "player")
        if type(ownGUID) ~= "string" or ownGUID == "" then return nil, nil, "player identity unavailable" end
    end
    if provider or reason == "self" or reason == "caster is not a player"
        or reason == "player identity unavailable" or reason == "caster is not friendly"
        or reason == "caster friendliness unavailable" then
        return provider, key, reason, sourceUnit
    end
    local instanceID = ns.Plain(aura.auraInstanceID)
    local getter = C_UnitAuras and C_UnitAuras.GetAuraCasterGUID
    if type(instanceID) ~= "number" or type(getter) ~= "function" then
        return nil, key, reason, sourceUnit
    end
    local guid = plainCall(getter, "player", instanceID)
    if type(guid) ~= "string" or guid == "" then
        return nil, key, "caster GUID unavailable or restricted", sourceUnit
    end
    local ownGUID = plainCall(UnitGUID, "player")
    if type(ownGUID) ~= "string" or ownGUID == "" then return nil, nil, "player identity unavailable" end
    if guid == ownGUID then return nil, nil, "self" end
    if not guid:match("^Player%-") then return nil, nil, "caster is not a player" end
    local name = nameForGUID(guid)
    -- A GUID-resolved name avoids a full roster/nameplate walk on each aura
    -- update. Queue/Send still check current membership and identity.
    local unit = unitForGUID(guid, sourceUnit, name ~= nil)
    if unit then
        provider, key, reason = sourceInfo(unit)
        if provider and key == guid then return provider, guid, nil, unit, "aura caster GUID" end
        -- A known unfriendly/non-player unit must not degrade to a name lookup.
        if reason == "self" or reason == "caster is not friendly" or reason == "caster is not a player" then
            return nil, nil, reason, unit
        end
    end
    provider = name
    if provider then return provider, guid, nil, nil, "aura caster GUID" end
    return nil, guid, "caster GUID has no readable player name", nil
end

local function eventSource(aura, updateInfo)
    if type(updateInfo) ~= "table" or ns.IsSecret(updateInfo) then return nil end
    local added = ns.Plain(updateInfo.addedAuras)
    local instanceID = ns.Plain(aura.auraInstanceID)
    local spellID = ns.Plain(aura.spellId)
    if type(added) ~= "table" or type(instanceID) ~= "number" then return nil end
    for _, entry in ipairs(added) do
        if type(entry) == "table" and not ns.IsSecret(entry)
            and ns.Plain(entry.auraInstanceID) == instanceID
            and ns.Plain(entry.spellId) == spellID then
            return ns.Plain(entry.sourceUnit)
        end
    end
end

local function legacyProbe(aura)
    if type(UnitBuff) ~= "function" then return "UnitBuff unavailable" end
    local name, spellID = ns.Plain(aura.name), ns.Plain(aura.spellId)
    for index = 1, 40 do
        local values = { pcall(UnitBuff, "player", index) }
        if not values[1] then return "UnitBuff error" end
        local first = ns.Plain(values[2])
        if first == nil then return "UnitBuff no matching aura" end
        local same = type(name) == "string" and first == name
        if type(first) == "table" and not ns.IsSecret(first) then
            same = ns.Plain(first.spellId) == spellID
        end
        if same then
            local slots = {}
            for slot = 3, 18 do
                local value = ns.Plain(values[slot])
                if type(value) == "string" then
                    local ok, exists = pcall(UnitExists, value)
                    if ok and exists then slots[#slots + 1] = tostring(slot - 1) end
                end
            end
            return "UnitBuff matched; unit slots " .. (#slots > 0 and table.concat(slots, ",") or "none")
        end
    end
    return "UnitBuff no matching aura"
end

local GROUP_ROSTERS = { { "party", 4 }, { "raid", 40 } }

local function skipGroupProvider(provider, providerKey, sourceUnit)
    if not ns.db.thanksSkipGroupMembers then return false end
    -- A unit token can change during the thank-you delay. Only trust its
    -- membership when it still identifies the caster that supplied the buff.
    local currentProvider, currentKey = sourceInfo(sourceUnit)
    if currentProvider == provider and currentKey == providerKey then
        local party = plainCall(UnitInParty, sourceUnit)
        local raid = plainCall(UnitInRaid, sourceUnit)
        if party == true or raid == true or (type(raid) == "number" and raid >= 0) then return true end
    end
    -- A known caster can join the group, move slots or lose their original
    -- token before sending. Match roster GUIDs rather than guessing by name.
    if type(providerKey) == "string" and UnitGUID then
        for _, group in ipairs(GROUP_ROSTERS) do
            for index = 1, group[2] do
                local unit = group[1] .. index
                if plainCall(UnitExists, unit) and plainCall(UnitGUID, unit) == providerKey then return true end
            end
        end
    end
    return false
end

local function messageFor(buff, provider)
    local message = tostring(ns.db.thanksMessage or "Thanks for the {buff}!")
    message = message:gsub("{buff}", function() return tostring(buff) end)
        :gsub("{player}", function() return tostring(provider) end)
    return message:gsub("[\r\n]+", " "):sub(1, 240)
end

function Thanks:Send(buff, provider, providerKey, sourceUnit)
    local currentProvider, currentKey = sourceInfo(sourceUnit)
    if providerKey == provider and currentProvider == provider then providerKey = currentKey end
    if skipGroupProvider(provider, providerKey, sourceUnit) then
        self.lastStatus = "skipped: caster is in your party or raid"
        return
    end
    local channel = ns.db.thanksChannel
    if channel == "EMOTE" then
        local currentProvider, currentKey = sourceInfo(sourceUnit)
        local emoteTarget = sourceUnit
        if currentProvider ~= provider or currentKey ~= providerKey then
            -- Recover a moved token by GUID; otherwise use the captured player
            -- name. Never redirect the emote at the replacement in an old slot.
            local unit = type(providerKey) == "string" and providerKey:match("^Player%-")
                and unitForGUID(providerKey, sourceUnit)
            if unit then
                currentProvider, currentKey = sourceInfo(unit)
                if currentProvider == provider and currentKey == providerKey then emoteTarget = unit else unit = nil end
            end
            if not unit then
                if type(providerKey) ~= "string" or not providerKey:match("^Player%-") then
                    self.lastStatus = "skipped: emote target unavailable"
                    return
                end
                emoteTarget = provider:match("^[^-]+")
            end
        end
        local token = selectedEmote()
        if ns.TARGET == "Camelot" then
            if type(DoEmote) ~= "function" then self.lastStatus = "skipped: emote API unavailable"; return end
            local ok, success = pcall(DoEmote, token, emoteTarget)
            if not ok or success == false then self.lastStatus = "skipped: emote rejected"; return end
        elseif C_ChatInfo and type(C_ChatInfo.PerformEmote) == "function" then
            local ok, success = pcall(C_ChatInfo.PerformEmote, token, provider)
            if not ok or success == false then self.lastStatus = "skipped: emote rejected"; return end
        elseif type(DoEmote) == "function" then
            local ok, success = pcall(DoEmote, token, emoteTarget)
            if not ok or success == false then self.lastStatus = "skipped: emote rejected"; return end
        else
            self.lastStatus = "skipped: emote API unavailable"
            return
        end
        self.lastStatus = "emoted: " .. token
        return
    end
    if type(SendChatMessage) ~= "function" or (channel ~= "WHISPER" and channel ~= "SAY" and channel ~= "PARTY") then
        self.lastStatus = "skipped: chat API or channel unavailable"
        return
    end
    local message = messageFor(buff, provider)
    local ok, success
    if channel == "WHISPER" then
        ok, success = pcall(SendChatMessage, message, "WHISPER", nil, provider)
    elseif channel == "PARTY" and IsInGroup and IsInGroup() then
        local instanceCategory = LE_PARTY_CATEGORY_INSTANCE or (Enum and Enum.PartyCategory and Enum.PartyCategory.Instance)
        ok, success = pcall(SendChatMessage, message, instanceCategory and IsInGroup(instanceCategory) and "INSTANCE_CHAT" or "PARTY")
    elseif channel == "SAY" then
        ok, success = pcall(SendChatMessage, message, "SAY")
    else
        self.lastStatus = "skipped: party channel unavailable while solo"
        return
    end
    self.lastStatus = ok and success ~= false and "sent" or "skipped: chat rejected"
end

-- Forever can expose a newly applied buff without any usable caster token.
-- If GUID recovery also fails, the opt-in untargeted emote remains available.
-- Whispers need a recipient; never guess one from the roster.
function Thanks:FallbackEmote(buff, auraKey)
    if not ns.db.thanksUnknownEmote or ns.db.thanksChannel ~= "EMOTE" then return false end
    local token = selectedEmote()
    -- Omitting the recipient lets the client emote at the selected target.
    -- "none" explicitly requests a general emote without changing selection.
    local ok, success
    if ns.TARGET == "Camelot" and type(DoEmote) == "function" then
        ok, success = pcall(DoEmote, token, "none")
    elseif C_ChatInfo and type(C_ChatInfo.PerformEmote) == "function" then
        ok, success = pcall(C_ChatInfo.PerformEmote, token, "none")
    elseif type(DoEmote) == "function" then
        ok, success = pcall(DoEmote, token, "none")
    end
    if not ok or success == false then
        self.lastStatus = "skipped: untargeted emote rejected"
        return false
    end
    self.attributedAuras[auraKey] = "untargeted"
    self.lastStatus = "emoted without caster: " .. token
    return true
end

-- Unknown replies share one delayed job. A later attribution, removal or
-- baseline snapshot invalidates that aura's entry before delivery.
function Thanks:QueueFallback(buff, auraKey)
    if not ns.db.thanksEnabled or not ns.db.thanksUnknownEmote or ns.db.thanksChannel ~= "EMOTE"
        or not self.eligibleAuras[auraKey] or self.attributedAuras[auraKey] then return false end
    self.attributedAuras[auraKey] = "fallback pending"
    local job = self.pending[UNKNOWN_REPLY]
    if job then job.auras[auraKey] = buff; return true end
    job = { auras = { [auraKey] = buff } }
    self.pending[UNKNOWN_REPLY] = job
    self.lastStatus = "queued: unknown-caster emote"
    local function send()
        if self.pending[UNKNOWN_REPLY] ~= job then return end
        self.pending[UNKNOWN_REPLY] = nil
        if not ns.db.thanksEnabled or not ns.db.thanksUnknownEmote or ns.db.thanksChannel ~= "EMOTE" then
            self.lastStatus = "cancelled: unknown-caster emote disabled"
            return
        end
        if ns.IsCombatLocked() then self.lastStatus = "cancelled: combat"; return end
        local first, keys = nil, {}
        for key, entry in pairs(job.auras) do
            if self.eligibleAuras[key] and self.attributedAuras[key] == "fallback pending" then
                first = first or entry
                keys[#keys + 1] = key
            end
        end
        if not first then
            self.lastStatus = "cancelled: no eligible unknown-caster buffs"
        elseif self:FallbackEmote(first, keys[1]) then
            for _, key in ipairs(keys) do self.attributedAuras[key] = "untargeted" end
        else
            for _, key in ipairs(keys) do
                self.attributedAuras[key], self.eligibleAuras[key] = "rejected", nil
            end
        end
    end
    local delay = math.max(1, math.min(5, tonumber(ns.db.thanksDelay) or 1))
    if C_Timer and type(C_Timer.After) == "function" then after(delay, send) else send() end
    return true
end

function Thanks:SuppressAura(auraKey)
    self.attributedAuras[auraKey] = "suppressed"
    self.eligibleAuras[auraKey], self.retrying[auraKey] = nil, nil
end

function Thanks:SetEnabled(enabled)
    ns.db.thanksEnabled = enabled == true
    self:ResetHistory()
    self:Observe(true)
    self.lastStatus = enabled and "ready: Thank You enabled" or "cancelled: Thank You disabled"
    self:SaveDiagnostics()
end

function Thanks:CombatStarted()
    self.pending, self.retrying, self.eligibleAuras = {}, {}, {}
    self.combatPriming = true
    self.lastStatus = "paused: combat"
end

function Thanks:CombatEnded()
    if self.zonePriming then
        self:FinishZoneTransition()
    elseif self.combatPriming then
        self:Observe(true)
    end
    self.combatPriming = nil
end

local function combinedBuffs(job)
    if #job.buffs == 1 then return job.buffs[1] end
    if #job.buffs == 2 then return job.buffs[1] .. " and " .. job.buffs[2] end
    return table.concat(job.buffs, ", ", 1, #job.buffs - 1) .. ", and " .. job.buffs[#job.buffs]
end

local function delayLabel(delay)
    return tostring(delay) .. (delay == 1 and " second" or " seconds")
end

function Thanks:Queue(buff, provider, providerKey, sourceUnit)
    if skipGroupProvider(provider, providerKey, sourceUnit) then
        self.lastStatus = "skipped: caster is in your party or raid"
        return false
    end
    local job = self.pending[providerKey]
    if not job then
        for key, candidate in pairs(self.pending) do
            if candidate.provider == provider and (key == provider or providerKey == provider) then
                job = candidate
                if key == provider and providerKey ~= provider then
                    self.pending[key], self.pending[providerKey], job.key = nil, job, providerKey
                end
                break
            end
        end
    end
    if job then
        if type(sourceUnit) == "string" then job.sourceUnit = sourceUnit end
        if not job.buffSet[buff] then
            job.buffSet[buff] = true
            job.buffs[#job.buffs + 1] = buff
            self.lastStatus = "queued: " .. delayLabel(job.delay) .. " (" .. tostring(#job.buffs) .. " buffs)"
        end
        return true
    end
    local delay = math.max(1, math.min(5, tonumber(ns.db.thanksDelay) or 1))
    local function send()
        if self.pending[job.key] ~= job then return end
        self.pending[job.key] = nil
        if not ns.db.thanksEnabled then
            self.lastStatus = "cancelled: Thank You disabled"
            return
        end
        if ns.IsCombatLocked() then
            self.lastStatus = "cancelled: combat"
            return
        end
        self:Send(combinedBuffs(job), job.provider, job.key, job.sourceUnit)
    end
    job = { key = providerKey, provider = provider, sourceUnit = sourceUnit, delay = delay, buffs = { buff }, buffSet = { [buff] = true } }
    self.pending[providerKey] = job
    self.lastStatus = "queued: " .. delayLabel(delay)
    if C_Timer and type(C_Timer.After) == "function" then
        after(delay, send)
    else
        send()
    end
    return true
end

local function auraByInstance(instanceID)
    local byID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    if type(byID) == "function" then
        local ok, aura = pcall(byID, "player", instanceID)
        if ok and aura and not ns.IsSecret(aura) then return aura end
    end
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if type(byIndex) ~= "function" then return nil end
    for index = 1, 128 do
        local ok, aura = pcall(byIndex, "player", index, "HELPFUL")
        if not ok or ns.IsSecret(aura) or not aura then break end
        if ns.Plain(aura.auraInstanceID) == instanceID then return aura end
    end
end

function Thanks:RetryAttribution(aura, buff, auraKey)
    local instanceID = ns.Plain(aura.auraInstanceID)
    if type(instanceID) ~= "number" then
        self.lastAttribution = buff.label .. ": no aura instance ID for retry; " .. legacyProbe(aura)
        return false
    end
    if self.retrying[auraKey] then return true end
    if not C_Timer or type(C_Timer.After) ~= "function" then return false end
    local spellID = ns.Plain(aura.spellId)
    local marker = {}
    self.retrying[auraKey] = marker
    local function check(attempt)
        after(attempt == 1 and 0.2 or 0.5, function()
            if self.retrying[auraKey] ~= marker then return end
            if not ns.db.thanksEnabled or not self.eligibleAuras[auraKey]
                or ns.IsCombatLocked() or self.attributedAuras[auraKey] then
                self.retrying[auraKey] = nil
                return
            end
            local now = plainCall(GetTime)
            local deadline = self.eligibilityDeadline and self.eligibilityDeadline[auraKey]
            if deadline and type(now) == "number" and now > deadline then
                self.retrying[auraKey], self.eligibleAuras[auraKey] = nil, nil
                self.lastAttribution = buff.label .. ": attribution expired"
                return
            end
            local current = auraByInstance(instanceID)
            if not current or ns.Plain(current.spellId) ~= spellID then
                self.retrying[auraKey] = nil
                self.lastAttribution = buff.label .. ": aura gone before caster appeared"
                return
            end
            local sourceUnit = ns.Plain(current.sourceUnit)
            local provider, providerKey, reason, resolvedUnit, origin = auraSource(current, sourceUnit)
            if provider then
                self.retrying[auraKey] = nil
                self.attributedAuras[auraKey] = providerKey
                self:Queue(buff.label, provider, providerKey, resolvedUnit)
                self.lastAttribution = buff.label .. ": " .. (origin or "indexed aura") .. " after retry " .. tostring(attempt)
            elseif reason == "self" or reason == "caster is not a player" or reason == "caster is not friendly"
                or (providerKey and skipGroupProvider(nil, providerKey, resolvedUnit)) then
                self.retrying[auraKey] = nil
                self:SuppressAura(auraKey)
                self.lastAttribution = buff.label .. ": " .. (reason or "caster is in your party or raid")
            elseif attempt < 2 then
                check(2)
            else
                self.retrying[auraKey] = nil
                self.lastAttribution = buff.label .. ": no caster after 0.7 seconds; " .. legacyProbe(current)
                if reason ~= "player identity unavailable" then self:QueueFallback(buff, auraKey) end
            end
        end)
    end
    check(1)
    return true
end

function Thanks:Observe(primeOnly, updateInfo)
    if ns.IsCombatLocked() then self.lastStatus = "paused: combat"; return end
    if self.loadingWorld then self.lastStatus = "paused: loading world"; return end
    local getter = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getter then self.lastStatus = "unavailable: aura API"; return end
    local snapshot = {}
    for index = 1, 128 do
        local ok, aura = pcall(getter, "player", index, "HELPFUL")
        if not ok or ns.IsSecret(aura) then
            self.scanRecovery = true
            self.lastScan = "unavailable: incomplete aura snapshot"
            return false
        end
        if not aura then break end
        snapshot[#snapshot + 1] = aura
    end
    if self.scanRecovery then primeOnly = true; self.scanRecovery = nil end
    if self.zonePriming or (type(updateInfo) == "table" and not ns.IsSecret(updateInfo)
        and ns.Plain(updateInfo.isFullUpdate) == true) then primeOnly = true end
    if primeOnly then self:ResetHistory(not self.zonePriming) end
    self.seenProviderNames = self.seenProviderNames or {}
    self.eligibilityDeadline = self.eligibilityDeadline or {}
    local now = plainCall(GetTime)
    local tracked = trackedBuffs()
    local current, currentAuras = {}, {}
    local skipped
    local queued = false
    local scanned, byID, byName, noProvider, selfBuffs = 0, 0, 0, 0, 0
    for _, aura in ipairs(snapshot) do
        scanned = scanned + 1
        local spellID = tonumber(ns.Plain(aura.spellId))
        local buff = spellID and tracked[spellID]
        if buff then byID = byID + 1 end
        if not buff and ns.TARGET == "Camelot" then
            local name = ns.Plain(aura.name)
            buff = type(name) == "string" and Thanks.trackedNames[name]
            if buff then byName = byName + 1 end
        end
        local provider, providerKey, sourceReason
        local sourceUnit = buff and ns.Plain(aura.sourceUnit)
        local sourceOrigin = "indexed aura"
        if buff and not sourceUnit and ns.TARGET == "Camelot" then
            sourceUnit = eventSource(aura, updateInfo)
            if sourceUnit then sourceOrigin = "UNIT_AURA added aura" end
        end
        if buff then
            local origin
            provider, providerKey, sourceReason, sourceUnit, origin = auraSource(aura, sourceUnit)
            sourceOrigin = origin or sourceOrigin
            if not provider and sourceReason ~= "self" and sourceReason ~= "caster is not a player"
                and sourceReason ~= "player identity unavailable" and sourceReason ~= "caster is not friendly" then
                local eventUnit = eventSource(aura, updateInfo)
                if eventUnit and eventUnit ~= sourceUnit then
                    local eventProvider, eventKey, eventReason, resolvedUnit, eventOrigin = auraSource(aura, eventUnit)
                    if eventProvider or eventReason == "self" or eventReason == "caster is not a player" then
                        provider, providerKey, sourceReason, sourceUnit = eventProvider, eventKey, eventReason, resolvedUnit
                        sourceOrigin = eventOrigin or "UNIT_AURA added aura"
                    end
                end
            end
        end
        local auraKey
        if buff then
            auraKey = tostring(ns.Plain(aura.auraInstanceID) or spellID or buff.auraID)
            currentAuras[auraKey] = true
            if self.initialized and not primeOnly and ns.db.thanksEnabled and not self.seenAuras[auraKey] then
                self.eligibleAuras[auraKey] = true
                self.eligibilityDeadline[auraKey] = type(now) == "number" and now + 5 or nil
            end
            local previousProvider = self.seenProviders[auraKey]
            local previousName = self.seenProviderNames[auraKey]
            if provider and previousProvider and providerKey == provider and previousName == provider then
                providerKey = previousProvider
            end
            local bothGUIDs = type(previousProvider) == "string" and previousProvider:match("^Player%-")
                and type(providerKey) == "string" and providerKey:match("^Player%-")
            local providerChanged = previousProvider and providerKey and previousProvider ~= providerKey
                and (bothGUIDs or (provider and previousName and provider ~= previousName))
            if self.initialized and not primeOnly and ns.db.thanksEnabled and providerChanged then
                self.eligibleAuras[auraKey] = true
                self.attributedAuras[auraKey] = nil
                self.eligibilityDeadline[auraKey] = type(now) == "number" and now + 5 or nil
            elseif previousProvider and providerKey and previousProvider ~= providerKey
                and self.attributedAuras[auraKey] == previousProvider then
                self.attributedAuras[auraKey] = providerKey
            end
            if provider then self.seenProviderNames[auraKey] = provider end
            local deadline = self.eligibilityDeadline[auraKey]
            if deadline and type(now) == "number" and now > deadline and not self.attributedAuras[auraKey] then
                self.eligibleAuras[auraKey], self.retrying[auraKey] = nil, nil
            end
            if providerKey then self.seenProviders[auraKey] = providerKey end
        end
        if buff and provider then
            local key = tostring(spellID or buff.auraID) .. ":" .. providerKey
            current[key] = true
            if self.initialized and not primeOnly and ns.db.thanksEnabled
                and self.eligibleAuras[auraKey] and not self.seen[key]
                and self.attributedAuras[auraKey] ~= providerKey
                and self.attributedAuras[auraKey] ~= "untargeted" then
                self.attributedAuras[auraKey] = providerKey
                queued = self:Queue(buff.label, provider, providerKey, sourceUnit) or queued
                self.lastAttribution = buff.label .. ": " .. sourceOrigin
            end
        elseif buff and self.initialized and not primeOnly then
            if sourceReason == "self" then
                self:SuppressAura(auraKey)
                selfBuffs = selfBuffs + 1
            elseif sourceReason == "caster is not a player" or sourceReason == "caster is not friendly"
                or (providerKey and skipGroupProvider(nil, providerKey, sourceUnit)) then
                self:SuppressAura(auraKey)
            else
                noProvider = noProvider + 1
                if not self.seenAuras[auraKey] then
                    skipped = buff.label .. " (" .. tostring(sourceReason) .. ")"
                    if ns.TARGET == "Camelot" and ns.db.thanksEnabled
                        and not self:RetryAttribution(aura, buff, auraKey) then
                        if sourceReason ~= "player identity unavailable" then self:QueueFallback(buff, auraKey) end
                    end
                end
            end
        end
    end
    self.lastScan = ("%d auras; %d ID matches; %d name matches; %d self; %d without provider"):format(scanned, byID, byName, selfBuffs, noProvider)
    self.seen = current
    self.seenAuras = currentAuras
    for auraKey in pairs(self.attributedAuras) do
        if not currentAuras[auraKey] then self.attributedAuras[auraKey] = nil end
    end
    for auraKey in pairs(self.seenProviders) do
        if not currentAuras[auraKey] then
            self.seenProviders[auraKey], self.seenProviderNames[auraKey], self.eligibilityDeadline[auraKey] = nil, nil, nil
        end
    end
    for auraKey in pairs(self.eligibleAuras) do
        if not currentAuras[auraKey] or not ns.db.thanksEnabled then self.eligibleAuras[auraKey] = nil end
    end
    for auraKey in pairs(self.eligibilityDeadline) do
        if not currentAuras[auraKey] then self.eligibilityDeadline[auraKey] = nil end
    end
    for auraKey in pairs(self.retrying) do
        if not currentAuras[auraKey] then self.retrying[auraKey] = nil end
    end
    if skipped and not queued then
        self.lastStatus = "skipped: provider unavailable for " .. tostring(skipped)
    end
    self.initialized = true
    if self.lastStatus == "not observed" then self.lastStatus = "ready" end
    if self.zonePriming and self.zoneReady then
        self.zonePriming, self.zoneReady = false, false
        self.lastStatus = "primed: zone transition"
    end
    return true
end
