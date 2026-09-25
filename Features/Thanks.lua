local addonName, ns = ...

ns.Thanks = { seen = {}, pending = {}, lastStatus = "not observed" }
local Thanks = ns.Thanks

local function trackedBuffs()
    if Thanks.tracked then return Thanks.tracked end
    local tracked = {}
    for _, classBuffs in pairs(ns.PARTY_BUFFS or {}) do
        for _, buff in ipairs(classBuffs) do
            if buff.auraID then tracked[buff.auraID] = buff end
            for _, auraID in ipairs(buff.auraIDs or {}) do tracked[auraID] = buff end
        end
    end
    Thanks.tracked = tracked
    return tracked
end

local function sourceInfo(sourceUnit)
    if type(sourceUnit) ~= "string" or sourceUnit == "player" then return nil end
    if not UnitExists(sourceUnit) or not UnitIsPlayer(sourceUnit) or not UnitCanAssist("player", sourceUnit) then return nil end
    local name, realm = UnitName(sourceUnit)
    if type(name) ~= "string" or name == "" then return nil end
    local recipient = realm and realm ~= "" and name .. "-" .. realm or name
    local guid = UnitGUID(sourceUnit)
    return recipient, type(guid) == "string" and guid ~= "" and guid or recipient
end

local function messageFor(buff, provider)
    local message = tostring(ns.db.thanksMessage or "Thanks for the {buff}!")
    message = message:gsub("{buff}", tostring(buff)):gsub("{player}", tostring(provider))
    return message:gsub("[\r\n]+", " "):sub(1, 240)
end

function Thanks:Send(buff, provider)
    local channel = ns.db.thanksChannel
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

function Thanks:Queue(buff, provider, providerKey)
    local job = self.pending[providerKey]
    if job then
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
        self:Send(combinedBuffs(job), job.provider)
    end
    job = { provider = provider, delay = delay, buffs = { buff }, buffSet = { [buff] = true } }
    self.pending[providerKey] = job
    self.lastStatus = "queued: " .. delayLabel(delay)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, send)
    else
        send()
    end
end

function Thanks:Observe(primeOnly)
    if ns.IsCombatLocked() then self.lastStatus = "paused: combat"; return end
    local getter = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getter then self.lastStatus = "unavailable: aura API"; return end
    local current = {}
    local skipped
    local queued = false
    for index = 1, 128 do
        local ok, aura = pcall(getter, "player", index, "HELPFUL")
        if not ok or ns.IsSecret(aura) or not aura then break end
        local spellID = tonumber(ns.Plain(aura.spellId))
        local buff = spellID and trackedBuffs()[spellID]
        local provider, providerKey
        if buff then provider, providerKey = sourceInfo(ns.Plain(aura.sourceUnit)) end
        if buff and provider then
            local key = tostring(spellID) .. ":" .. providerKey
            current[key] = true
            if self.initialized and not primeOnly and ns.db.thanksEnabled and not self.seen[key] then
                self:Queue(buff.label, provider, providerKey)
                queued = true
            end
        elseif buff and self.initialized and not primeOnly then
            skipped = buff.label
        end
    end
    self.seen = current
    if skipped and not queued then
        self.lastStatus = "skipped: provider unavailable for " .. tostring(skipped)
    end
    self.initialized = true
    if self.lastStatus == "not observed" then self.lastStatus = "ready" end
end
