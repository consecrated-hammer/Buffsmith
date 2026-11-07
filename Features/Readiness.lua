local addonName, ns = ...

-- Input checks are observations, never a deferred cast or an addon spell queue.
ns.Readiness = { lastStatus = "not pressed", blocked = 0 }
local Readiness = ns.Readiness

local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return ns.Plain(value) end
end
local function number(value)
    value = ns.Plain(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge and value or nil
end
local function now() return number(plain(GetTime)) end

function Readiness:QueueWindow()
    local value = plain(C_CVar and C_CVar.GetCVar, "SpellQueueWindow")
    if value == nil then value = plain(GetCVar, "SpellQueueWindow") end
    if type(value) == "string" then value = tonumber(value) end
    value = number(value)
    return value and value / 1000 or nil
end

function Readiness:Key(entry)
    if not entry then return "none" end
    local unit = entry.unit or "player"
    local guid = ns.Plain(entry.unitGUID) or unit
    return table.concat({ tostring(entry.kind), tostring(entry.castID or entry.spellID or entry.itemID or entry.name),
        tostring(guid), tostring(entry.targetSlot or "") }, ":")
end

function Readiness:Cooldown(entry)
    if not entry or (entry.kind ~= "spell" and entry.kind ~= "item") then return nil end
    local id = entry.kind == "item" and entry.itemID or entry.castID or entry.spellID
    local fn
    if entry.kind == "item" then fn = C_Item and C_Item.GetItemCooldown or GetItemCooldown
    else fn = C_Spell and C_Spell.GetSpellCooldown or GetSpellCooldown end
    if type(fn) ~= "function" or not id then return nil end
    local ok, a, b, c, d = pcall(fn, id)
    if not ok or ns.IsSecret(a) then return nil end
    local start, duration, enabled, rate
    if type(a) == "table" then
        start, duration = number(a.startTime), number(a.duration) or number(a.cooldownDuration)
        enabled, rate = ns.Plain(a.isEnabled), a.modRate
        if enabled == nil then enabled = ns.Plain(a.enable) end
    else
        start, duration, enabled, rate = number(a), number(b), ns.Plain(c), d
    end
    if ns.IsSecret(rate) then return nil end
    rate = rate == nil and 1 or number(rate)
    local time = now()
    if not start or not duration or not rate or rate <= 0 or not time then return nil end
    if enabled ~= true and enabled ~= 1 and enabled ~= false and enabled ~= 0 then return nil end
    return { start = start, duration = duration, rate = rate, enabled = enabled == true or enabled == 1,
        ends = start + duration, remaining = math.max(0, start + duration - time) }
end

function Readiness:CastStatus(channel)
    local fn
    if channel then fn = UnitChannelInfo else fn = UnitCastingInfo end
    if type(fn) ~= "function" then return nil end
    local ok, name, _, _, startMS, endMS = pcall(fn, "player")
    name = ok and ns.Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    local start, finish = number(startMS), number(endMS)
    local time = now()
    if finish and time and finish / 1000 <= time then finish = nil end
    return { name = name, kind = channel and "channel" or "cast", label = channel and "Channeling" or "Casting",
        ends = finish and finish / 1000 or nil, start = start and start / 1000 or nil }
end

function Readiness:DisplayAllowed()
    if ns.IsCombatLocked() then return false end
    if (UnitIsDeadOrGhost and plain(UnitIsDeadOrGhost, "player"))
        or (UnitOnTaxi and plain(UnitOnTaxi, "player"))
        or ns.Actions:IsRestedPaused() then return false end
    return true
end

function Readiness:Status()
    if not self:DisplayAllowed() then return nil end
    local meal = ns.Actions:MealStatus(true)
    local eating = meal.active or (meal.available == false and ns.Actions.eatingPaused)
    if eating then return { kind = "meal", label = "Eating/drinking", ends = meal.ends } end
    local cast = self:CastStatus(true) or self:CastStatus(false)
    if cast and ((ns.Palette and ns.Palette.hasActions) or (self.lastEntry and self.lastEntry.name == cast.name)) then return cast end
end

function Readiness:Signature(status)
    local cd = self:Cooldown(self.lastEntry)
    local endTime = cd and cd.enabled and cd.remaining > 0 and cd.ends or nil
    return (status and (status.kind .. ":" .. tostring(status.ends)) or "none") .. ":" .. tostring(endTime)
end

function Readiness:Feedback()
    if ns.IsCombatLocked() or not ns.Palette then return end
    local status = self:Status()
    local signature = self:Signature(status)
    if signature == self.feedbackSignature then return end
    self.feedbackSignature = signature
    if self.feedbackPending then return end
    self.feedbackPending = true
    local function update()
        self.feedbackPending = nil
        if not ns.IsCombatLocked() and ns.Palette.UpdateFeedback then ns.Palette:UpdateFeedback() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, update) else update() end
end

function Readiness:Check(entry)
    if not entry or entry.kind == "none" or entry.kind == "notice" then return { allow = true } end
    if entry.cooldownOnly then return { allow = false, reason = "cooldown display only" } end
    local time = now()
    if entry.kind == "spell" and not ns.Actions:CanBuffUnit(entry.unit) then
        return { allow = false, reason = "PvP recipient skipped" }
    end
    local meal = ns.Actions:MealStatus()
    local eating = meal.active or (meal.available == false and ns.Actions.eatingPaused)
    ns.Actions.eatingPaused = eating
    if eating then return { allow = false, reason = "eating/drinking", ends = meal.ends } end
    local intended, current = ns.Plain(entry.unitGUID), plain(UnitGUID, entry.unit or "player")
    if type(intended) == "string" and type(current) == "string" and current ~= intended then
        return { allow = false, reason = "recipient changed" }
    end
    if time and self.queueUntil and self.queueUntil > time then
        return { allow = false, reason = "native queue window", ends = self.queueUntil }
    end
    local channel = self:CastStatus(true)
    if channel then return { allow = false, reason = "channeling", ends = channel.ends } end
    local window, finish = self:QueueWindow(), nil
    local cast = self:CastStatus(false)
    if cast and time and cast.ends and window then
        if entry.kind == "item" or cast.ends - time > window then return { allow = false, reason = "casting", ends = cast.ends } end
        if cast.ends > time then finish = cast.ends end
    end
    local cd = self:Cooldown(entry)
    if cd and cd.enabled then
        if cd.remaining > 0 then
            -- Items do not participate in the native spell queue. If its window
            -- cannot be read, retain existing spell input rather than guessing.
            if entry.kind == "item" or (window and cd.remaining > window) then
                return { allow = false, reason = "cooldown", ends = cd.ends }
            end
            if window then finish = math.max(finish or 0, cd.ends) end
        end
    end
    return { allow = true, reason = finish and "native queue window" or (cd and cd.enabled) and "ready" or "readiness unavailable; native input", ends = finish }
end

function Readiness:Press(button, entry)
    -- Protected attributes retain their existing combat behavior. Never branch
    -- on combat secrets or mutate secure buttons during lockdown.
    if ns.IsCombatLocked() then return { allow = true, entry = entry } end
    local result = self:Check(entry)
    if entry then
        result.entry = {}
        for key, value in pairs(entry) do result.entry[key] = value end
        result.key = self:Key(entry)
    end
    self.lastStatus = result.reason or "no action"
    if entry and not entry.cooldownOnly and entry.kind ~= "none" and entry.kind ~= "notice" then self.lastEntry = result.entry end
    if not result.allow then
        button:SetAttribute("type1", nil)
        button.buffsmithReadinessDisarmed = true
        self.blocked = self.blocked + 1
    else
        if entry and (entry.kind == "spell" or entry.kind == "item")
            and (button.buffsmithReadinessDisarmed or button:GetAttribute("type1") == nil) then
            ns.Actions:Configure(button, entry)
        end
        if result.ends and self.queueUntil ~= result.ends then
            self.queueUntil = result.ends
            local deadline = result.ends
            if C_Timer and C_Timer.After then
                C_Timer.After(math.max(0, deadline - (now() or deadline)), function()
                    if self.queueUntil ~= deadline then return end
                    self.queueUntil = nil
                    self:Feedback()
                    if not ns.IsCombatLocked() and ns.Bindings then ns.Bindings:Prepare() end
                end)
            end
        end
    end
    self:Feedback()
    return result
end
