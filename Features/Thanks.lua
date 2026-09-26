local addonName, ns = ...

ns.Thanks = { seen = {}, seenAuras = {}, seenProviders = {}, eligibleAuras = {}, attributedAuras = {}, retrying = {}, pending = {}, lastStatus = "not observed", lastScan = "not scanned", lastAttribution = "not probed" }
local Thanks = ns.Thanks
local FEATURED_EMOTES = { { "THANK", "Thank" }, { "BOW", "Bow" }, { "CHEER", "Cheer" }, { "APPLAUD", "Applaud" }, { "SALUTE", "Salute" } }

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
    if Thanks.tracked then return Thanks.tracked end
    local tracked, names = {}, {}
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
                if type(spellName) == "string" then names[spellName] = buff end
            end
        end
    end
    Thanks.tracked = tracked
    Thanks.trackedNames = names
    return tracked
end

local function isSelfSource(sourceUnit)
    if sourceUnit == "player" then return true end
    if type(sourceUnit) ~= "string" or not UnitExists(sourceUnit) then return false end
    local guid, playerGUID = ns.Plain(UnitGUID(sourceUnit)), ns.Plain(UnitGUID("player"))
    return type(guid) == "string" and guid ~= "" and guid == playerGUID
end

local function sourceInfo(sourceUnit)
    if type(sourceUnit) ~= "string" then return nil, nil, "no caster token" end
    if isSelfSource(sourceUnit) then return nil, nil, "self" end
    if not UnitExists(sourceUnit) then return nil, nil, "caster token unavailable" end
    if not UnitIsPlayer(sourceUnit) then return nil, nil, "caster is not a player" end
    if not UnitCanAssist("player", sourceUnit) then return nil, nil, "caster is not friendly" end
    local name, realm = UnitName(sourceUnit)
    if type(name) ~= "string" or name == "" then return nil, nil, "caster name unavailable" end
    local recipient = realm and realm ~= "" and name .. "-" .. realm or name
    local guid = ns.Plain(UnitGUID(sourceUnit))
    return recipient, type(guid) == "string" and guid ~= "" and guid or recipient
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

local function messageFor(buff, provider)
    local message = tostring(ns.db.thanksMessage or "Thanks for the {buff}!")
    message = message:gsub("{buff}", tostring(buff)):gsub("{player}", tostring(provider))
    return message:gsub("[\r\n]+", " "):sub(1, 240)
end

function Thanks:Send(buff, provider, providerKey, sourceUnit)
    local channel = ns.db.thanksChannel
    if channel == "EMOTE" then
        local currentProvider, currentKey = sourceInfo(sourceUnit)
        if currentProvider ~= provider or currentKey ~= providerKey then
            self.lastStatus = "skipped: emote target unavailable"
            return
        end
        local token = selectedEmote()
        if ns.TARGET == "Camelot" then
            if type(DoEmote) ~= "function" then self.lastStatus = "skipped: emote API unavailable"; return end
            if not pcall(DoEmote, token, sourceUnit) then self.lastStatus = "skipped: emote rejected"; return end
        elseif C_ChatInfo and type(C_ChatInfo.PerformEmote) == "function" then
            local ok, success = pcall(C_ChatInfo.PerformEmote, token, provider)
            if not ok or success == false then self.lastStatus = "skipped: emote rejected"; return end
        elseif type(DoEmote) == "function" then
            if not pcall(DoEmote, token, sourceUnit) then self.lastStatus = "skipped: emote rejected"; return end
        else
            self.lastStatus = "skipped: emote API unavailable"
            return
        end
        self.lastStatus = "emoted: " .. token
        return
    end
    if type(SendChatMessage) ~= "function" or (channel ~= "WHISPER" and channel ~= "SAY" and channel ~= "PARTY") then return end
    local message = messageFor(buff, provider)
    if channel == "WHISPER" then
        SendChatMessage(message, "WHISPER", nil, provider)
    elseif channel == "PARTY" and IsInGroup and IsInGroup() then
        local instanceCategory = LE_PARTY_CATEGORY_INSTANCE or (Enum and Enum.PartyCategory and Enum.PartyCategory.Instance)
        SendChatMessage(message, instanceCategory and IsInGroup(instanceCategory) and "INSTANCE_CHAT" or "PARTY")
    elseif channel == "SAY" then
        SendChatMessage(message, "SAY")
    else
        return
    end
    self.lastStatus = "sent"
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
    local job = self.pending[providerKey]
    if job then
        if type(sourceUnit) == "string" then job.sourceUnit = sourceUnit end
        if not job.buffSet[buff] then
            job.buffSet[buff] = true
            job.buffs[#job.buffs + 1] = buff
            self.lastStatus = "queued: " .. delayLabel(job.delay) .. " (" .. tostring(#job.buffs) .. " buffs)"
        end
        return
    end
    local delay = math.max(1, math.min(5, tonumber(ns.db.thanksDelay) or 1))
    local function send()
        self.pending[providerKey] = nil
        if not ns.db.thanksEnabled then
            self.lastStatus = "cancelled: Thank You disabled"
            return
        end
        if ns.IsCombatLocked() then
            self.lastStatus = "cancelled: combat"
            return
        end
        self:Send(combinedBuffs(job), job.provider, providerKey, job.sourceUnit)
    end
    job = { provider = provider, sourceUnit = sourceUnit, delay = delay, buffs = { buff }, buffSet = { [buff] = true } }
    self.pending[providerKey] = job
    self.lastStatus = "queued: " .. delayLabel(delay)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, send)
    else
        send()
    end
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
        return
    end
    if self.retrying[auraKey] or not C_Timer or type(C_Timer.After) ~= "function" then return end
    local spellID = ns.Plain(aura.spellId)
    local marker = {}
    self.retrying[auraKey] = marker
    local function check(attempt)
        C_Timer.After(attempt == 1 and 0.2 or 0.5, function()
            if self.retrying[auraKey] ~= marker then return end
            if not ns.db.thanksEnabled or not self.eligibleAuras[auraKey]
                or ns.IsCombatLocked() or self.attributedAuras[auraKey] then
                self.retrying[auraKey] = nil
                return
            end
            local current = auraByInstance(instanceID)
            if not current or ns.Plain(current.spellId) ~= spellID then
                self.retrying[auraKey] = nil
                self.lastAttribution = buff.label .. ": aura gone before caster appeared"
                return
            end
            local sourceUnit = ns.Plain(current.sourceUnit)
            local provider, providerKey = sourceInfo(sourceUnit)
            if provider then
                self.retrying[auraKey] = nil
                self.attributedAuras[auraKey] = providerKey
                self:Queue(buff.label, provider, providerKey, sourceUnit)
                self.lastAttribution = buff.label .. ": indexed aura after retry " .. tostring(attempt)
            elseif attempt < 2 then
                check(2)
            else
                self.retrying[auraKey] = nil
                self.lastAttribution = buff.label .. ": no caster after 0.7 seconds; " .. legacyProbe(current)
            end
        end)
    end
    check(1)
end

function Thanks:Observe(primeOnly, updateInfo)
    if ns.IsCombatLocked() then self.lastStatus = "paused: combat"; return end
    local getter = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getter then self.lastStatus = "unavailable: aura API"; return end
    local tracked = trackedBuffs()
    local current, currentAuras = {}, {}
    local skipped
    local queued = false
    local scanned, byID, byName, noProvider, selfBuffs = 0, 0, 0, 0, 0
    for index = 1, 128 do
        local ok, aura = pcall(getter, "player", index, "HELPFUL")
        if not ok or ns.IsSecret(aura) or not aura then break end
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
        if buff then provider, providerKey, sourceReason = sourceInfo(sourceUnit) end
        local auraKey
        if buff then
            auraKey = tostring(ns.Plain(aura.auraInstanceID) or spellID or buff.auraID)
            currentAuras[auraKey] = true
            if self.initialized and not primeOnly and ns.db.thanksEnabled and not self.seenAuras[auraKey] then
                self.eligibleAuras[auraKey] = true
            end
            local previousProvider = self.seenProviders[auraKey]
            if self.initialized and not primeOnly and ns.db.thanksEnabled
                and previousProvider and providerKey and previousProvider ~= providerKey then
                self.eligibleAuras[auraKey] = true
            end
            if providerKey then self.seenProviders[auraKey] = providerKey end
        end
        if buff and provider then
            local key = tostring(spellID or buff.auraID) .. ":" .. providerKey
            current[key] = true
            if self.initialized and not primeOnly and ns.db.thanksEnabled
                and self.eligibleAuras[auraKey] and not self.seen[key]
                and self.attributedAuras[auraKey] ~= providerKey then
                self.attributedAuras[auraKey] = providerKey
                self:Queue(buff.label, provider, providerKey, sourceUnit)
                self.lastAttribution = buff.label .. ": " .. sourceOrigin
                queued = true
            end
        elseif buff and self.initialized and not primeOnly then
            if sourceReason == "self" then
                selfBuffs = selfBuffs + 1
            else
                noProvider = noProvider + 1
                if not self.seenAuras[auraKey] then
                    skipped = buff.label .. " (" .. tostring(sourceReason) .. ")"
                    if ns.TARGET == "Camelot" and ns.db.thanksEnabled then self:RetryAttribution(aura, buff, auraKey) end
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
        if not currentAuras[auraKey] then self.seenProviders[auraKey] = nil end
    end
    for auraKey in pairs(self.eligibleAuras) do
        if not currentAuras[auraKey] or not ns.db.thanksEnabled then self.eligibleAuras[auraKey] = nil end
    end
    for auraKey in pairs(self.retrying) do
        if not currentAuras[auraKey] then self.retrying[auraKey] = nil end
    end
    if skipped and not queued then
        self.lastStatus = "skipped: provider unavailable for " .. tostring(skipped)
    end
    self.initialized = true
    if self.lastStatus == "not observed" then self.lastStatus = "ready" end
end
