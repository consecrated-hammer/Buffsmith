local addonName, ns = ...

ns.Thanks = { seen = {}, lastStatus = "not observed" }
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

local function sourceName(sourceUnit)
    if type(sourceUnit) ~= "string" or sourceUnit == "player" then return nil end
    if not UnitExists(sourceUnit) or not UnitIsPlayer(sourceUnit) or not UnitCanAssist("player", sourceUnit) then return nil end
    return UnitName(sourceUnit)
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

function Thanks:Observe(primeOnly)
    if ns.IsCombatLocked() then self.lastStatus = "paused: combat"; return end
    local getter = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getter then self.lastStatus = "unavailable: aura API"; return end
    local current = {}
    for index = 1, 128 do
        local ok, aura = pcall(getter, "player", index, "HELPFUL")
        if not ok or ns.IsSecret(aura) or not aura then break end
        local spellID = tonumber(ns.Plain(aura.spellId))
        local buff = spellID and trackedBuffs()[spellID]
        local provider = buff and sourceName(ns.Plain(aura.sourceUnit))
        if buff and provider then
            local key = tostring(spellID) .. ":" .. provider
            current[key] = true
            if self.initialized and not primeOnly and ns.db.thanksEnabled and not self.seen[key] then
                self:Send(buff.label, provider)
            end
        end
    end
    self.seen = current
    self.initialized = true
    if self.lastStatus == "not observed" then self.lastStatus = "ready" end
end
