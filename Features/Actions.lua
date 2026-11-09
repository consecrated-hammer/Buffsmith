local addonName, ns = ...

ns.Actions = {}
local Actions = ns.Actions
Actions.suppressed = {}

local function playerIsDead()
    return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
end

local function playerOnTaxi()
    return UnitOnTaxi and ns.Plain(UnitOnTaxi("player")) == true
end

-- Moving cancels eating but still uses up the food, so food waits until you stop.
local function playerMoving()
    if IsPlayerMoving then return ns.Plain(IsPlayerMoving()) == true end
    local speed = GetUnitSpeed and tonumber(ns.Plain(GetUnitSpeed("player")))
    return speed ~= nil and speed > 0
end
ns.PlayerMoving = playerMoving

local function currentSpecKey()
    local spec = GetSpecialization and GetSpecialization()
    return tostring(spec or 0)
end

local function auraStatus(unit, auraID, auraIDs, auraName, withSource)
    if ns.IsCombatLocked() then return { state = "unknown" } end
    local function active(aura)
        local duration = tonumber(ns.Plain(aura.duration)) or 0
        local expiration = tonumber(ns.Plain(aura.expirationTime)) or 0
        local remaining = duration > 0 and expiration > 0 and math.max(0, expiration - GetTime()) or nil
        local source = withSource and ns.Plain(aura.sourceUnit)
        local sourceGUID = type(source) == "string" and UnitGUID and ns.Plain(UnitGUID(source)) or nil
        return { state = "active", duration = duration, remaining = remaining, sourceGUID = sourceGUID }
    end
    local getter = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if getter then
        local ids = auraIDs or { auraID }
        for _, spellID in ipairs(ids) do
            if spellID then
            local ok, aura = pcall(getter, unit, spellID)
                if ok and not ns.IsSecret(aura) and aura then return active(aura) end
            end
        end
    end

    -- Spellbook base IDs and applied aura IDs can differ for ranked spells.
    -- A bounded player-only scan resolves that identity without reading combat auras.
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not byIndex or type(auraName) ~= "string" or auraName == "" then return { state = "missing" } end
    for index = 1, 128 do
        local ok, aura = pcall(byIndex, unit, index, "HELPFUL")
        if not ok or ns.IsSecret(aura) or not aura then break end
        if ns.Plain(aura.name) == auraName then return active(aura) end
    end
    return { state = "missing" }
end

-- The player's own aura gives each self-buff's real duration, which decides
-- whether it is short enough to be off by default.
local function learnDuration(unit, entry, status)
    if unit ~= "player" or status.state ~= "active" then return end
    local duration = tonumber(status.duration)
    if not duration or duration <= 0 or not (ns.db and ns.db.buffDurations) then return end
    ns.db.buffDurations[entry.spellID] = math.floor(duration + 0.5)
end

-- A grouped entry is satisfied by any known member of its group.
local function entryStatus(unit, entry)
    local status = auraStatus(unit, entry.auraID, entry.auraIDs, entry.name)
    learnDuration(unit, entry, status)
    if status.state == "active" or not entry.members then return status end
    for _, member in ipairs(entry.members) do
        if member ~= entry then
            local memberStatus = auraStatus(unit, member.auraID, member.auraIDs, member.name)
            learnDuration(unit, member, memberStatus)
            if memberStatus.state == "active" then return memberStatus end
        end
    end
    return status
end

local function shouldShow(entry, status)
    if status.state ~= "active" then return true, status.state end
    if entry.permanent then return false, "active" end
    local fraction = Actions:Percent(entry) / 100
    if status.duration > 0 and status.remaining and status.remaining <= status.duration * fraction then
        return true, "expiring"
    end
    return false, "active"
end

local function timeText(seconds)
    seconds = math.floor((tonumber(seconds) or 0) + 0.5)
    if seconds >= 60 then return math.floor(seconds / 60) .. "m" end
    return seconds .. "s"
end

local function friendlyPlayer(unit)
    return UnitExists(unit) and UnitIsPlayer(unit)
        and UnitCanAssist("player", unit) and not UnitIsDeadOrGhost(unit)
end

-- Only readable PvP flags can establish a safe external recipient. Legacy
-- clients may return nil for false; API failure/secret data stays unknown.
local function pvpFlag(api, unit)
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, unit)
    if not ok or ns.IsSecret(value) then return nil end
    if value == true or value == 1 then return true end
    if value == false or value == nil or value == 0 then return false end
end

function Actions:CanBuffUnit(unit)
    if not ns.db.skipPvPWhileUnflagged or not unit or unit == "player" then return true end
    if UnitIsUnit and ns.Plain(UnitIsUnit("player", unit)) == true then return true end
    local player = pvpFlag(UnitIsPVP, "player")
    local free = UnitIsPVPFreeForAll and pvpFlag(UnitIsPVPFreeForAll, "player")
    if player == true or free == true then return true end
    if player == nil or (UnitIsPVPFreeForAll and free == nil) then return false end
    local flagged = pvpFlag(UnitIsPVP, unit)
    local freeTarget = UnitIsPVPFreeForAll and pvpFlag(UnitIsPVPFreeForAll, unit)
    return flagged == false and (not UnitIsPVPFreeForAll or freeTarget == false)
end

local PET_UNITS = { "pet", "partypet1", "partypet2", "partypet3", "partypet4" }

local function friendlyPet(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit)
        or not UnitCanAssist("player", unit) or UnitIsDeadOrGhost(unit) then return false end
    -- Friendly NPCs are not pets. Known owner tokens also cover the selected
    -- pet when the optional classification API is unavailable or restricted.
    for _, pet in ipairs(PET_UNITS) do
        if unit == pet or (UnitExists(pet) and ns.Plain(UnitIsUnit(unit, pet)) == true) then return true end
    end
    if type(UnitIsOtherPlayersPet) == "function" then
        local ok, isPet = pcall(UnitIsOtherPlayersPet, unit)
        if ok and ns.Plain(isPet) == true then return true end
    end
    return false
end

-- Party aura state is useful only for allies that the client can currently
-- see.  This mirrors the practical boundary used by party-frame buff tools:
-- it is not a spell's exact cast range, but excludes offline, phased and
-- out-of-broadcast-range members that cannot produce a useful prompt.
local function visiblePartyPlayer(unit)
    if not friendlyPlayer(unit) or (UnitIsConnected and not UnitIsConnected(unit)) then return false end
    if UnitIsVisible and ns.Plain(UnitIsVisible(unit)) ~= true then return false end
    if UnitPhaseReason and ns.Plain(UnitPhaseReason(unit)) ~= nil then return false end
    return true
end

local function cloneForUnit(entry, unit, scope)
    local copy = {}
    for key, value in pairs(entry) do copy[key] = value end
    copy.unit, copy.scope = unit, scope
    copy.unitGUID = UnitGUID and UnitGUID(unit) or nil
    return copy
end

-- A nil range result is intentionally neutral: the client only returns a
-- definite false when it can establish that this spell cannot reach the unit.
-- This keeps party, pet and unusual spell targets actionable when no precise
-- range probe is available.
function Actions:RangeState(entry)
    if entry.kind ~= "spell" or not entry.unit or entry.unit == "player" then return nil end
    local checker = C_Spell and C_Spell.IsSpellInRange
    if type(checker) ~= "function" then return nil end
    local ok, inRange = pcall(checker, entry.castID or entry.spellID, entry.unit)
    if not ok then return nil end
    inRange = ns.Plain(inRange)
    if inRange == false then return false end
    return nil
end

function Actions:UpdateTargetRangeChecks(entries)
    local enable = C_Spell and C_Spell.EnableSpellRangeCheck
    if type(enable) ~= "function" then return end
    local wanted = {}
    for _, entry in ipairs(entries) do
        if entry.kind == "spell" and entry.unit == "target" then wanted[entry.castID or entry.spellID] = true end
    end
    self.rangeChecks = self.rangeChecks or {}
    for spellID in pairs(self.rangeChecks) do
        if not wanted[spellID] then pcall(enable, spellID, false); self.rangeChecks[spellID] = nil end
    end
    for spellID in pairs(wanted) do
        if not self.rangeChecks[spellID] then pcall(enable, spellID, true); self.rangeChecks[spellID] = true end
    end
end

local function partyUnits()
    local units = { "player" }
    if IsInGroup and IsInGroup() then
        for index = 1, 4 do
            local unit = "party" .. index
            if visiblePartyPlayer(unit) then units[#units + 1] = unit end
        end
    end
    return units
end

function Actions:PartyCoverage()
    local coverage = {}
    ns.lastCoverageProbe = {}
    if playerIsDead() or playerOnTaxi() then
        ns.lastCoverageProbe[1] = "paused: player dead, ghost or on a flight path"
        return coverage
    end
    if not ns.db.showPartyCoverage or not (IsInGroup and IsInGroup()) then
        self.coverageEvidence = {}
        ns.lastCoverageProbe[1] = "disabled or solo"
        return coverage
    end
    local units, candidates, evidence = partyUnits(), {}, {}
    -- Preserve observations for actual roster members even while they are dead,
    -- phased or out of range. Only visible, living members can be offered below.
    if ns.TARGET == "Camelot" then
        for index = 1, 4 do
            local unit = "party" .. index
            local guid = UnitExists(unit) and UnitGUID and ns.Plain(UnitGUID(unit))
            if type(guid) == "string" then
                local _, class = UnitClass(unit)
                for _, buff in ipairs(ns.PARTY_BUFFS[class] or {}) do
                    local key = guid .. ":" .. buff.spellID
                    evidence[key] = (self.coverageEvidence or {})[key]
                end
            end
        end
    end
    for _, provider in ipairs(units) do
        if provider ~= "player" then
            local _, class = UnitClass(provider)
            for _, buff in ipairs(ns.PARTY_BUFFS[class] or {}) do
                local key = tostring(class) .. ":" .. tostring(buff.spellID)
                local candidate = candidates[key]
                if not candidate then
                    candidate = { kind = "notice", spellID = buff.spellID, auraID = buff.auraID,
                        auraIDs = buff.auraIDs, name = buff.label, icon = buff.icon or 134400,
                        providerClass = class, providers = {}, missing = {} }
                    candidates[key] = candidate
                end
                local guid = UnitGUID and ns.Plain(UnitGUID(provider))
                local sourceGUID = guid
                if buff.pet then
                    local pet = provider:gsub("^party", "partypet")
                    sourceGUID = friendlyPet(pet)
                        and UnitGUID and ns.Plain(UnitGUID(pet)) or nil
                end
                candidate.providers[#candidate.providers + 1] = {
                    name = UnitName(provider) or provider, guid = guid, sourceGUID = sourceGUID,
                }
            end
        end
    end
    for _, candidate in pairs(candidates) do
        local sources = {}
        for _, unit in ipairs(units) do
            local status = auraStatus(unit, candidate.auraID, candidate.auraIDs, candidate.name, ns.TARGET == "Camelot")
            if type(status.sourceGUID) == "string" then sources[status.sourceGUID] = true end
            local display = shouldShow(candidate, status)
            if display then candidate.missing[#candidate.missing + 1] = UnitName(unit) or unit end
        end
        local providers = {}
        for _, provider in ipairs(candidate.providers) do
            local available = ns.TARGET ~= "Camelot"
            if ns.TARGET == "Camelot" and type(provider.guid) == "string"
                and type(provider.sourceGUID) == "string" then
                local key = provider.guid .. ":" .. candidate.spellID
                available = sources[provider.sourceGUID] == true
                    or (self.coverageEvidence or {})[key] == provider.sourceGUID
                if available then evidence[key] = provider.sourceGUID end
            end
            if available then providers[#providers + 1] = provider.name end
        end
        if #providers > 0 and #candidate.missing > 0 and not self:IsSuppressed(candidate) then
            candidate.count = #candidate.missing
            candidate.providerText = table.concat(providers, ", ")
            candidate.providerNames = providers
            candidate.missingText = table.concat(candidate.missing, ", ")
            coverage[#coverage + 1] = candidate
            ns.lastCoverageProbe[#ns.lastCoverageProbe + 1] = candidate.name .. ": " .. candidate.count .. " missing"
        end
    end
    -- Session-only proof, keyed by character and (for pet buffs) the current pet.
    -- Drop departed providers so party-slot reuse cannot inherit their spells.
    self.coverageEvidence = evidence
    table.sort(coverage, function(a, b) return a.name < b.name end)
    return coverage
end

-- The rested-area pause covers the whole bar: buffs and consumables alike.
function Actions:IsRestedPaused()
    return ns.db.ignoreBuffsInRestedAreas and IsResting and IsResting() or false
end

-- Eating and drinking auras, by localised name.  Food and drink items apply
-- their own spell IDs, but every client names the sitting aura after one of
-- these few spells.
local EATING_SPELLS = { 433, 430, 192002, 167152 } -- Food, Drink, Food & Drink, Refreshment
local eatingNames
local function eatingAuraNames()
    if eatingNames then return eatingNames end
    eatingNames = { Food = true, Drink = true, ["Food & Drink"] = true, Refreshment = true }
    for _, spellID in ipairs(EATING_SPELLS) do
        local ok, name
        if C_Spell and C_Spell.GetSpellName then ok, name = pcall(C_Spell.GetSpellName, spellID) end
        name = ok and ns.Plain(name)
        if type(name) ~= "string" or name == "" then
            if GetSpellInfo then ok, name = pcall(GetSpellInfo, spellID); name = ok and ns.Plain(name) end
        end
        if type(name) == "string" and name ~= "" then eatingNames[name] = true end
    end
    return eatingNames
end

function Actions:IsMealAura(aura)
    local id = ns.Plain(aura.spellId) or ns.Plain(aura.spellID)
    for _, knownID in ipairs(EATING_SPELLS) do if id == knownID then return true end end
    return eatingAuraNames()[ns.Plain(aura.name)] == true
end

-- Shown in the middle of the screen, like the game's own "can't do that"
-- errors, when a click or the trigger is ignored mid-meal.
Actions.EATING_NOTICE = "Waits until you finish eating or drinking."
function Actions:ShowEatingNotice()
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage("Buffsmith waits until you finish eating or drinking.", 1, 0.82, 0)
    end
end

function Actions:MealStatus(cached)
    if cached and self.mealStatus and self.mealStatus.available ~= false then
        local finish = self.mealStatus.ends
        if not finish or (GetTime and finish > GetTime()) then return self.mealStatus end
    end
    local getter = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getter or ns.IsCombatLocked() then return { active = false, available = false } end
    local active, finish, unknown, available = false, nil, false, true
    local meals = {}
    for index = 1, 128 do
        local ok, aura = pcall(getter, "player", index, "HELPFUL")
        if not ok or ns.IsSecret(aura) then unknown, available = true, false; break end
        if not aura then break end
        if self:IsMealAura(aura) then
            active = true
            local meal = { name = ns.Plain(aura.name), icon = ns.Plain(aura.icon) or ns.Plain(aura.iconFileID),
                spellID = ns.Plain(aura.spellId) }
            meals[#meals + 1] = meal
            local expiration, duration = ns.Plain(aura.expirationTime), ns.Plain(aura.duration)
            if type(expiration) == "number" and expiration == expiration and expiration > 0 and expiration < math.huge
                and type(duration) == "number" and duration == duration and duration > 0 and duration < math.huge then
                finish = math.max(finish or 0, expiration)
                meal.ends, meal.duration = expiration, duration
            else unknown = true end
        end
    end
    local ok, time
    if GetTime then ok, time = pcall(GetTime) end
    time = ok and ns.Plain(time)
    if unknown or not finish or type(time) ~= "number" or finish <= time then finish = nil end
    self.mealStatus = { active = active, ends = finish, available = available, auras = meals }
    return self.mealStatus
end

-- One informational progress entry replaces the food reminder while eating.
-- A satisfied food benefit hides it; active buffs are never persistent icons.
function Actions:MealEntries()
    if ns.IsCombatLocked() or playerIsDead() or playerOnTaxi() or self:IsRestedPaused()
        or (ns.db.categories and ns.db.categories.food == false) then return {} end
    local meal = self:MealStatus(true)
    if not meal.active then return {} end
    local food = ns.Inventory and ns.Inventory:CategoryStatus("food")
    if food and not shouldShow({ kind = "item", category = "food" }, food) then return {} end
    local aura = meal.auras and meal.auras[1]
    if not aura then return {} end
    return { { kind = "meal", displayOnly = true, name = type(aura.name) == "string" and aura.name or "Food / Drink",
        icon = aura.icon or 134062, spellID = aura.spellID,
        auraEnds = aura.ends, auraDuration = aura.duration } }
end

function Actions:IsEating()
    return self:MealStatus().active
end


local function resourceValue(api, ...)
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, ...)
    if ok then
        value = ns.Plain(value)
        if type(value) == "number" and value == value and value >= 0 and value < math.huge then return value end
    end
end

local function rawSecret(api, ...)
    if type(api) ~= "function" then return false end
    local ok, value = pcall(api, ...)
    return ok and ns.IsSecret(value) or false
end

-- Grouped on WoW Forever, current health and mana are secret: Lua can show
-- them but never compare them. The client can still turn a percentage into
-- an icon alpha through a step curve, so the bar can carry a ready reminder
-- that only becomes visible when a resource is actually low.
function Actions:CanFadeRecovery()
    return type(C_CurveUtil) == "table" and type(C_CurveUtil.CreateCurve) == "function"
        and type(Enum) == "table" and type(Enum.LuaCurveType) == "table"
        and type(UnitHealthPercent) == "function" and type(UnitPowerPercent) == "function"
end

function Actions:RecoveryStatus(entry)
    if ns.IsCombatLocked() then return false, "combat" end
    local threshold = self:Percent(entry) / 100
    local health, maxHealth = resourceValue(UnitHealth, "player"), resourceValue(UnitHealthMax, "player")
    local manaType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    local mana, maxMana = resourceValue(UnitPower, "player", manaType), resourceValue(UnitPowerMax, "player", manaType)
    local healthLow = health and maxHealth and maxHealth > 0 and health / maxHealth < threshold
    local manaLow = mana and maxMana and maxMana > 0 and mana / maxMana < threshold
    local hidden = false
    if not healthLow and not manaLow then
        hidden = (rawSecret(UnitHealth, "player") or rawSecret(UnitPower, "player", manaType))
            and self:CanFadeRecovery()
        if not hidden then return false, "resources sufficient or unreadable" end
    end

    local reason = hidden and "hidden resources" or healthLow and "low health" or "low mana"
    local start, duration, enabled, rate, active, onGCD
    local getter = C_Spell and C_Spell.GetSpellCooldown
    if type(getter) == "function" then
        local ok, info = pcall(getter, entry.castID or entry.spellID)
        if not ok or ns.IsSecret(info) or type(info) ~= "table" then return false, "cooldown unknown" end
        if ns.IsSecret(info.isEnabled) or ns.IsSecret(info.modRate) then return false, "cooldown unknown" end
        start, duration, enabled = ns.Plain(info.startTime), ns.Plain(info.duration), info.isEnabled
        rate = ns.Plain(info.modRate)
        if not (ns.IsSecret(info.isActive) or ns.IsSecret(info.isOnGCD)) then
            active, onGCD = info.isActive, info.isOnGCD
        end
    elseif type(GetSpellCooldown) == "function" then
        local ok, a, b, c, d = pcall(GetSpellCooldown, entry.castID or entry.spellID)
        if not ok or ns.IsSecret(d) or ns.IsSecret(c) then return false, "cooldown unknown" end
        start, duration, enabled, rate = ns.Plain(a), ns.Plain(b), c, ns.Plain(d)
    else
        return false, "cooldown unknown"
    end
    -- Only an explicit "disabled" counts: WoW Forever leaves isEnabled out,
    -- which used to read as unreadable and hid the reminder for good.
    if enabled == false or enabled == 0 then return false, "cooldown disabled" end
    -- The client's own flags come first, as in Salve's cooldown icons: not
    -- active, or only the global cooldown, is ready.
    if active == false or (active == true and onGCD == true) then return true, reason end
    if type(start) ~= "number" or type(duration) ~= "number" or start ~= start or duration ~= duration
        or start < 0 or duration < 0 or start == math.huge or duration == math.huge then
        -- Known to be cooling but not for how long: look again shortly.
        if active == true then return false, "cooldown", 5 end
        return false, "cooldown unknown"
    end
    if duration > 0 then
        local now = resourceValue(GetTime)
        rate = rate == nil and 1 or rate
        if not now or type(rate) ~= "number" or rate <= 0 or rate ~= rate or rate == math.huge then return false, "cooldown unknown" end
        -- Blizzard's Forever broadcaster uses start + duration - now;
        -- modRate controls cooldown presentation, not an earlier ready time.
        local remaining = start + duration - now
        if remaining > 0 then
            return false, "cooldown", remaining
        end
    end
    return true, reason
end

-- Resource events are frequent. Rebuild secure buttons only when this
-- reminder changes visibility; cooldown wakeups share the normal timer.
function Actions:RefreshRecovery()
    if ns.IsCombatLocked() then return end
    local entry = ns.KnownRecoveryEntry and ns.KnownRecoveryEntry()
    if not entry or self:IsSuppressed(entry) then return end
    local display, _, remaining
    if playerIsDead() or playerOnTaxi() or self:IsRestedPaused() then
        display = false
    else
        display, _, remaining = self:RecoveryStatus(entry)
    end
    if display ~= (ns.Palette and ns.Palette.recoveryDisplayed or false) then
        ns.RefreshAll()
    elseif remaining then
        self:ArmReminder(remaining)
    end
end

function Actions:Entries()
    local entries = {}
    self.nextReminderDelay = nil
    ns.lastAuraProbe = {}
    if ns.IsCombatLocked() then
        self.eatingPaused = false
        ns.lastAuraProbe[1] = "buff checks paused: combat"
        return entries
    end
    if playerIsDead() or playerOnTaxi() then
        self.eatingPaused = false
        ns.lastAuraProbe[1] = "buff checks paused: dead, ghost or on a flight path"
        return entries
    end
    -- Casting mid-meal would stand the player up, so while eating or drinking
    -- the bar stays visible but its icons and trigger cast nothing.
    self.eatingPaused = self:IsEating()
    if self:IsRestedPaused() then
        ns.lastAuraProbe[1] = "self-buff checks paused: rested area"
        return entries
    end
    for _, entry in ipairs(ns.KnownSelfBuffs()) do
        local status, display, state
        if entry.resourceRecovery then
            local remaining
            display, state, remaining = self:RecoveryStatus(entry)
            entry.secretRecovery = display and state == "hidden resources" or nil
            if remaining and not self:IsSuppressed(entry) then
                self.nextReminderDelay = math.min(self.nextReminderDelay or remaining, remaining)
            end
            status = {}
        else
            status = entryStatus("player", entry)
            self:ConsiderReminder(entry, status)
            display, state = shouldShow(entry, status)
        end
        entry.state, entry.auraDuration, entry.auraRemaining = state, status.duration, status.remaining
        ns.lastAuraProbe[#ns.lastAuraProbe + 1] = entry.name .. "=" .. entry.state
        if display and not self:IsSuppressed(entry) then entries[#entries + 1] = entry end
    end
    -- Tracking that is off; Tracking:Entries applies ticks and dismissals.
    ns.lastTrackingProbe = {}
    for _, entry in ipairs(ns.Tracking and ns.Tracking:Entries() or {}) do
        entry.state = "missing"
        entries[#entries + 1] = entry
        ns.lastTrackingProbe[#ns.lastTrackingProbe + 1] = entry.name
    end
    local known = ns.KnownSelfBuffs()
    local selectedTarget = ns.db.showTargetBuffs and self:CanBuffUnit("target")
        and (friendlyPlayer("target") or (ns.db.showPetBuffs and friendlyPet("target")))
    if ns.db.showTargetBuffs and selectedTarget and not UnitIsUnit("player", "target") then
        ns.lastTargetProbe = {}
        for _, entry in ipairs(known) do
            if entry.target then
                local status = entryStatus("target", entry)
                self:ConsiderReminder(entry, status)
                local display, state = shouldShow(entry, status)
                ns.lastTargetProbe[#ns.lastTargetProbe + 1] = entry.name .. "=" .. state
                if display and not self:IsSuppressed(entry) then
                    local copy = cloneForUnit(entry, "target", "target")
                    copy.state, copy.auraDuration, copy.auraRemaining = state, status.duration, status.remaining
                    entries[#entries + 1] = copy
                end
            end
        end
    else
        ns.lastTargetProbe = { "not applicable" }
    end
    ns.lastPartyProbe = {}
    if ns.db.showPartyBuffs and IsInGroup and IsInGroup() then
        for _, entry in ipairs(known) do
            if entry.target and not self:IsSuppressed(entry) then
                for _, unit in ipairs({ "party1", "party2", "party3", "party4" }) do
                    if visiblePartyPlayer(unit) and self:CanBuffUnit(unit) and not (selectedTarget and UnitIsUnit("target", unit)) then
                        local status = entryStatus(unit, entry)
                        self:ConsiderReminder(entry, status)
                        local display, state = shouldShow(entry, status)
                        if display then
                            local copy = cloneForUnit(entry, unit, "party")
                            copy.state, copy.auraDuration, copy.auraRemaining = state, status.duration, status.remaining
                            entries[#entries + 1] = copy
                            ns.lastPartyProbe[#ns.lastPartyProbe + 1] = entry.name .. "=" .. state
                            break
                        end
                    end
                end
            end
        end
    end
    ns.lastPetProbe = {}
    if ns.db.showPetBuffs then
        for _, entry in ipairs(known) do
            if entry.target and not self:IsSuppressed(entry) then
                for _, unit in ipairs(PET_UNITS) do
                    if friendlyPet(unit) and self:CanBuffUnit(unit) and not (selectedTarget and UnitIsUnit("target", unit)) then
                        local status = entryStatus(unit, entry)
                        self:ConsiderReminder(entry, status)
                        local display, state = shouldShow(entry, status)
                        if display then
                            local copy = cloneForUnit(entry, unit, "pet")
                            copy.state, copy.auraDuration, copy.auraRemaining = state, status.duration, status.remaining
                            entries[#entries + 1] = copy
                            ns.lastPetProbe[#ns.lastPetProbe + 1] = entry.name .. "=" .. state
                            break
                        end
                    end
                end
            end
        end
    end
    for _, notice in ipairs(self:PartyCoverage()) do entries[#entries + 1] = notice end
    for _, entry in ipairs(entries) do entry.outOfRange = self:RangeState(entry) == false end
    return entries
end

function Actions:ConsiderReminder(entry, status, percent)
    if entry.permanent then return end
    if status.state ~= "active" or not status.duration or not status.remaining then return end
    local threshold = status.duration * (percent or self:Percent(entry)) / 100
    local delay = status.remaining - threshold
    if delay > 0 and (not self.nextReminderDelay or delay < self.nextReminderDelay) then
        self.nextReminderDelay = delay
    end
end

function Actions:Percent(entry)
    local reminder = ns.db.reminderPercent
    local value
    if entry.kind == "item" then
        value = reminder.item and reminder.item[entry.itemID]
        value = value == nil and reminder[entry.category] or value
    else
        value = reminder.buffBySpell and reminder.buffBySpell[entry.spellID]
        value = value == nil and (entry.resourceRecovery and 50 or reminder.buff) or value
    end
    return math.max(0, math.min(50, tonumber(value) or 10))
end

function Actions:ArmReminder(delay)
    delay = delay or self.nextReminderDelay
    if not delay or ns.IsCombatLocked() then return end
    local now = GetTime and GetTime() or 0
    local wait = math.max(1, delay + 0.05)
    local wakeAt = now + wait
    if self.reminderWakeAt and self.reminderWakeAt <= wakeAt + 0.1 then return end
    self.reminderWakeAt = wakeAt
    self.reminderToken = (self.reminderToken or 0) + 1
    local token = self.reminderToken
    C_Timer.After(wait, function()
        if token ~= self.reminderToken then return end
        self.reminderWakeAt = nil
        if ns.IsCombatLocked() then return end
        if ns.Palette then ns.Palette:Refresh() end
    end)
end

function Actions:Key(entry)
    if not entry then return nil end
    if entry.kind == "spell" then
        local unit = entry.unit or "player"
        local identity = entry.unitGUID or (UnitGUID and UnitGUID(unit)) or unit
        return "spell:" .. tostring(entry.spellID) .. ":" .. tostring(entry.scope or "self")
            .. ":" .. tostring(identity)
    end
    if entry.kind == "item" then return "item:" .. tostring(entry.itemID) end
    if entry.kind == "notice" then return "party:" .. tostring(entry.providerClass) .. ":" .. tostring(entry.spellID) end
end

-- An excluded buff is off everywhere: self, target, party and pet all route
-- through IsSuppressed, so exclusion composes with the session dismissals
-- rather than needing its own check at each call site.
function Actions:IsExcluded(entry)
    return entry.kind == "spell" and ns.IsBuffExcluded(entry)
end

function Actions:IsSuppressed(entry)
    if self:IsExcluded(entry) then return true end
    local key = self:Key(entry)
    return key and self.suppressed[key] == true or false
end

function Actions:Dismiss(entry)
    local key = self:Key(entry)
    if key then self.suppressed[key] = true end
end

-- Shift-right-click: a lasting exclusion, reversible from the Buffs or
-- Consumables page.  Party notices have no saved exclusion, so they dismiss.
function Actions:Ignore(entry)
    if entry.kind == "item" then
        ns.db.excludedConsumables[entry.itemID] = true
    elseif entry.kind == "spell" then
        ns.db.excludedBuffs[entry.spellID] = true
    else
        self:Dismiss(entry)
    end
end

-- Everything the player has explicitly ignored, including items no longer in
-- their bags.  Short buffs that are merely off by default are not listed.
function Actions:IgnoredEntries()
    local entries = {}
    -- Exclusions are retained so changing characters does not destroy a
    -- player's choices, but the Ignored page is character-specific.  A Druid
    -- must not be offered an old Paladin exclusion to restore.
    local currentBuffs
    if type(ns.KnownSelfBuffCandidates) == "function" then
        currentBuffs = {}
        for _, entry in ipairs(ns.KnownSelfBuffCandidates()) do currentBuffs[entry.spellID] = entry end
        -- Tracking uses the same exclusion store, but is not a self-buff.
        -- Keep an ignored tracker restorable, especially on Retail where
        -- several trackers can be independently disabled.
        if ns.Tracking and type(ns.Tracking.Available) == "function" then
            for _, entry in ipairs(ns.Tracking:Available()) do currentBuffs[entry.spellID] = entry end
        end
    end
    for spellID, ignored in pairs(ns.db.excludedBuffs) do
        if ignored == true and (not currentBuffs or currentBuffs[spellID]) then
            local name, icon
            local entry = currentBuffs and currentBuffs[spellID]
            if entry then name, icon = entry.name, entry.icon end
            if not name and type(spellID) == "number" and C_Spell and C_Spell.GetSpellInfo then
                local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
                if ok and type(info) == "table" then name, icon = ns.Plain(info.name), ns.Plain(info.iconID) end
            end
            entries[#entries + 1] = { kind = "spell", id = spellID,
                name = name or ("Spell " .. spellID), icon = icon or 134400 }
        end
    end
    for itemID, ignored in pairs(ns.db.excludedConsumables) do
        if ignored == true then
            local name, _, _, _, icon = ns.Inventory.ItemInfo(itemID)
            if not name and C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, itemID)
            end
            entries[#entries + 1] = { kind = "item", id = itemID,
                name = name or ("Item " .. itemID), icon = icon or 134400 }
        end
    end
    table.sort(entries, function(a, b)
        if a.kind ~= b.kind then return a.kind == "spell" end
        return a.name < b.name
    end)
    return entries
end

-- A restored buff is recorded as explicitly on, so a short buff the player
-- chose to ignore comes back rather than returning to its unticked default.
function Actions:Restore(kind, id)
    if kind == "spell" then
        ns.db.excludedBuffs[id] = false
    else
        ns.db.excludedConsumables[id] = nil
    end
end

function Actions:BeginAttempt(entry)
    local key = self:Key(entry)
    if not key then return end
    self.lastAttempt = { key = key, spellID = entry.castID or entry.spellID, untilTime = (GetTime and GetTime() or 0) + 0.25 }
    return self.lastAttempt
end

function Actions:FinishAttempt(spellID)
    if ns.IsSecret and ns.IsSecret(spellID) then return end
    -- Successful poison casts from action bars also update the saved choice.
    -- Use catalogue data here so combat casts never enumerate the spellbook.
    local changed = false
    local _, class = UnitClass("player")
    if ns.TARGET ~= "Camelot" and class == "ROGUE" then
        for _, entry in ipairs(ns.SELF_BUFFS and ns.SELF_BUFFS.ROGUE or {}) do
            if entry.spellID == spellID then
                self:Remember(entry.group, entry.spellID)
                changed = true
            end
        end
    end
    local attempt = self.lastAttempt
    if attempt and attempt.spellID and attempt.spellID == spellID then self.lastAttempt = nil end
    return changed
end

function Actions:ExpireAttempt(entry, token)
    local attempt = self.lastAttempt
    if attempt and (not token or attempt == token) and attempt.key == self:Key(entry) then self.lastAttempt = nil end
end

-- The server, rather than addon-visible aura data, is authoritative for
-- overlapping effects with different strengths (for example a scroll versus
-- a stronger class buff). The window is deliberately one UI frame long: a
-- generic UI_ERROR_MESSAGE carries no spell/item identity, so a stale click
-- must never be mistaken for a later unrelated failure.
function Actions:HandleAuraBounce(message)
    if ns.IsCombatLocked() then return false end
    local attempt = self.lastAttempt
    if not attempt then return false end
    if (GetTime and GetTime() or 0) > attempt.untilTime then self.lastAttempt = nil; return false end
    if message ~= SPELL_FAILED_AURA_BOUNCED then return false end
    self.lastAttempt = nil
    self.suppressed[attempt.key] = true
    self.lastSuppression = "stronger effect already active"
    return true
end

local PROVIDER_HINTS = {
    "%s might have a little magic to spare.",
    "Perhaps %s could lend an enchantment.",
    "Rumour has it %s might know a spell for this.",
    "A little help from %s wouldn't go amiss.",
    "The winds whisper that %s might help.",
    "Perhaps %s could spare a blessing.",
    "A polite bow to %s might work wonders.",
    "%s may have just the incantation.",
    "A hopeful glance towards %s might be in order.",
    "With luck, %s could lend a little sparkle.",
    "%s might have the right words of power.",
    "Perhaps %s could weave a little protection.",
}

function Actions:ProviderHint(entry, renew)
    local names = entry.providerNames
    local text = tostring(entry.providerText or "a kind soul")
    if type(names) == "table" and #names > 1 then
        text = table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
    end
    self.providerHints = self.providerHints or {}
    local key = self:Key(entry) or entry.name or "coverage"
    local cached = self.providerHints[key]
    if not renew and cached and cached.providers == text then
        entry.providerHint = cached.hint
        return cached.hint
    end
    self.providerHintIndex = ((self.providerHintIndex or math.random(#PROVIDER_HINTS)) % #PROVIDER_HINTS) + 1
    entry.providerHint = PROVIDER_HINTS[self.providerHintIndex]:format(text)
    self.providerHints[key] = { providers = text, hint = entry.providerHint }
    return entry.providerHint
end

function Actions:ReportPartyCoverage(entry)
    if not entry or entry.kind ~= "notice" or type(SendChatMessage) ~= "function" then return false end
    if not (IsInGroup and IsInGroup()) then return false end
    local now = GetTime and GetTime() or 0
    local key = self:Key(entry)
    self.lastPartyReport = self.lastPartyReport or {}
    if key and self.lastPartyReport[key] and now - self.lastPartyReport[key] < 3 then return false end
    if key then self.lastPartyReport[key] = now end
    local instanceCategory = (LE_PARTY_CATEGORY_INSTANCE or (Enum and Enum.PartyCategory and Enum.PartyCategory.Instance))
    local channel = instanceCategory and IsInGroup(instanceCategory) and "INSTANCE_CHAT" or "PARTY"
    local message = ("[Buffsmith] %s is missing from %s. %s"):format(
        tostring(entry.name), tostring(entry.missingText), self:ProviderHint(entry))
    if #message > 255 then
        -- Drop a possibly partial trailing UTF-8 codepoint before the ellipsis.
        message = message:sub(1, 252):gsub("[\194-\244][\128-\191]*$", "") .. "..."
    end
    SendChatMessage(message, channel)
    return true
end

function Actions:ResetDismissals()
    self.suppressed = {}
end

function Actions:Preferred(category, choices)
    local saved = ns.db.preferred[currentSpecKey()]
    saved = type(saved) == "table" and saved or {}
    local preferred = saved[category]
    for index, choice in ipairs(choices) do
        local selected = choice.poison and saved["poison:" .. tostring(choice.targetSlot)] or preferred
        selected = selected or preferred
        if choice.itemID == selected and not self:IsSuppressed(choice) then return index end
    end
    for index, choice in ipairs(choices) do
        if not self:IsSuppressed(choice) then return index end
    end
    return nil
end

function Actions:VisibleChoices(category)
    local choices = {}
    if playerIsDead() or playerOnTaxi() or not ns.db.categories[category] or self:IsRestedPaused() then return choices end
    if category == "food" and playerMoving() then return choices end
    -- A category-level active effect suppresses alternatives of the same kind.
    -- This prevents a second food or weapon oil appearing while one is active.
    local categoryStatus = ns.Inventory:CategoryStatus(category)
    if categoryStatus then
        local display = shouldShow({ kind = "item", category = category }, categoryStatus)
        if not display then return choices end
    end
    for _, item in ipairs(ns.Inventory:Choices(category)) do
        local choice = item
        if item.poison then
            -- Keep each configured action's weapon target stable when another
            -- bar or keybinding query resolves the next bare hand.
            choice = {}
            for key, value in pairs(item) do choice[key] = value end
            choice.targetSlot = ns.Inventory:PoisonTargetSlot()
        end
        if ns.db.excludedConsumables[choice.itemID] then
            choice.state = "excluded"
        elseif choice.poison and not choice.targetSlot then
            choice.state = "active"
        elseif category == "weapon" and not choice.poison and ns.Inventory:WeaponStatus() then
            choice.state = "active"
        else
            local cooldown = ns.Inventory:CooldownRemaining(choice)
            if cooldown then
                -- A bag item remains in the scan while it is cooling down, but is
                -- not actionable.  Leave another ready choice in the category
                -- available instead of presenting a click that the game rejects.
                choice.state = "cooldown"
                ns.Inventory:RefreshAfterCooldown(choice, cooldown)
            else
                local camping = ns.Inventory.CampingStatus and ns.Inventory:CampingStatus(choice)
                local mapping = not choice.poison and ns.Inventory:LearnedAura(choice)
                if camping then
                    choice.state, choice.auraDuration, choice.auraRemaining = camping.state, camping.duration, camping.remaining
                    -- Camp Benefits hides the chair until it is actually gone.
                    -- Boosted Rest is a tent lockout, never a chair signal.
                    self:ConsiderReminder(choice, camping, 0)
                    if camping.state == "unknown" then
                        self.nextReminderDelay = math.min(self.nextReminderDelay or 5, 5)
                    end
                    if camping.state == "missing" and not self:IsSuppressed(choice) then choices[#choices + 1] = choice end
                elseif mapping then
                    local status = auraStatus("player", mapping.spellID, nil, mapping.name)
                    self:ConsiderReminder(choice, status)
                    local display, state = shouldShow(choice, status)
                    choice.state, choice.auraDuration, choice.auraRemaining = state, status.duration, status.remaining
                    if display and not self:IsSuppressed(choice) then choices[#choices + 1] = choice end
                elseif not self:IsSuppressed(choice) then
                    choice.state = "untracked"
                    choices[#choices + 1] = choice
                end
            end
        end
    end
    return choices
end

function Actions:BindingEntries()
    local entries, displayed = {}, self:Entries()
    for _, entry in ipairs(displayed) do
        -- A faded recovery reminder may be invisible; the key must not cast it.
        if (entry.kind == "spell" or entry.kind == "item") and not entry.secretRecovery then
            entries[#entries + 1] = entry
        end
    end
    for _, category in ipairs(ns.CONSUMABLE_ORDER) do
        local choices = self:VisibleChoices(category)
        local primary = self:Preferred(category, choices)
        if primary then entries[#entries + 1] = choices[primary] end
    end
    return entries
end

function Actions:ReminderSummary()
    local summaries = {}
    for _, entry in ipairs(ns.KnownSelfBuffs()) do
        local status = entryStatus("player", entry)
        if status.duration and status.duration > 0 then
            summaries[#summaries + 1] = entry.name .. ": " .. timeText(status.duration * self:Percent(entry) / 100)
        end
    end
    return #summaries > 0 and table.concat(summaries, ", ") or "Apply a timed self-buff to show its exact reminder time."
end

function Actions:ReminderFor(entry)
    if entry.resourceRecovery then return "Health or mana below " .. self:Percent(entry) .. "%" end
    if entry.permanent then return "Permanent effect" end
    if ns.IsShortBuff(entry) then return "Short duration" end
    local status = entryStatus("player", entry)
    if status.duration and status.duration > 0 then
        return "Reminds with " .. timeText(status.duration * self:Percent(entry) / 100) .. " left"
    end
    return "Time left is learned while the buff is active."
end

function Actions:RememberItem(entry)
    self:Remember(entry.category, entry.itemID)
    if entry.poison and entry.targetSlot then
        self:Remember("poison:" .. entry.targetSlot, entry.itemID)
    end
end

function Actions:Remember(category, itemID)
    local key = currentSpecKey()
    if type(ns.db.preferred[key]) ~= "table" then ns.db.preferred[key] = {} end
    ns.db.preferred[key][category] = itemID
end

function Actions:Configure(button, entry)
    if ns.IsCombatLocked() then return false end
    button.buffsmithReadinessDisarmed = nil
    -- Securely disarm weapon-targeted item actions on combat entry, even if
    -- the bar stays visible. The normal out-of-combat refresh arms them again.
    if entry.poison and not button.buffsmithPoisonGuard then
        button:SetAttribute("_onstate-poisoncombat", [[
            if newstate == "combat" and self:GetAttribute("buffsmith-poison") then
                self:SetAttribute("type1", nil)
            end
        ]])
        RegisterStateDriver(button, "poisoncombat", "[combat] combat; safe")
        button.buffsmithPoisonGuard = true
    end
    local pvpGuard = ns.db.skipPvPWhileUnflagged and entry.kind == "spell"
        and entry.unit and entry.unit ~= "player"
    if pvpGuard and not button.buffsmithPvPGuard then
        button:SetAttribute("_onstate-buffsmithpvpcombat", [[
            if newstate == "combat" and self:GetAttribute("buffsmith-pvp-guard") then
                self:SetAttribute("type1", nil)
            end
        ]])
        RegisterStateDriver(button, "buffsmithpvpcombat", "[combat] combat; safe")
        button.buffsmithPvPGuard = true
    end
    button:SetAttribute("buffsmith-pvp-guard", pvpGuard == true)
    button:SetAttribute("buffsmith-poison", entry.poison == true)
    for mouseButton = 1, 5 do
        button:SetAttribute("type" .. mouseButton, nil)
        button:SetAttribute("spell" .. mouseButton, nil)
        button:SetAttribute("item" .. mouseButton, nil)
        button:SetAttribute("target-slot" .. mouseButton, nil)
        button:SetAttribute("unit" .. mouseButton, entry.unit or "player")
    end
    -- Unqualified secure attributes are fallbacks for every mouse button.
    -- Only LeftButton is an action; right-click is strictly a local dismissal.
    button:SetAttribute("type", nil); button:SetAttribute("spell", nil); button:SetAttribute("item", nil)
    button:SetAttribute("target-slot", nil)
    button:SetAttribute("unit", entry.unit or "player")
    if entry.displayOnly or entry.cooldownOnly or (self.eatingPaused and entry.kind ~= "none") then
        button.buffsmithEntry = entry
        return false
    elseif entry.kind == "spell" then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", entry.name)
    elseif entry.kind == "item" then
        local item = entry.itemLink or ("item:" .. entry.itemID)
        button:SetAttribute("type1", "item")
        button:SetAttribute("item1", item)
        button:SetAttribute("target-slot1", entry.targetSlot)
    else
        -- Informational party-coverage icons deliberately have no secure
        -- action, but still need their entry for tooltip, reporting and
        -- right-click dismissal.
        button.buffsmithEntry = entry
        return false
    end
    button.buffsmithEntry = entry
    ns.lastSecureButtonCount = (ns.lastSecureButtonCount or 0) + 1
    return true
end

function Actions:Refresh()
    if ns.IsCombatLocked() then return false end
    return true
end

-- /buffsmith leyline: every check behind the Read Leyline reminder, printed
-- and kept in saved settings (lastRecoveryDebug) so it can be read after a
-- reload.  Read-only: it changes nothing.
function Actions:DebugRecovery()
    local lines = {}
    local function show(value)
        if ns.IsSecret(value) then return "secret" end
        return tostring(value)
    end
    local function add(text) lines[#lines + 1] = text end
    add("client=" .. tostring(ns.TARGET) .. " combatLocked=" .. show(ns.IsCombatLocked()))
    local spellID = ns.RECOVERY_SPELLS and ns.RECOVERY_SPELLS[1] and ns.RECOVERY_SPELLS[1].spellID
    add("spellID=" .. show(spellID))
    if spellID then
        if C_SpellBook and C_SpellBook.IsSpellKnown then
            local ok, v = pcall(C_SpellBook.IsSpellKnown, spellID, Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0)
            add("C_SpellBook.IsSpellKnown=" .. (ok and show(v) or "error"))
        end
        if IsPlayerSpell then local ok, v = pcall(IsPlayerSpell, spellID); add("IsPlayerSpell=" .. (ok and show(v) or "error")) end
        if IsSpellKnown then local ok, v = pcall(IsSpellKnown, spellID); add("IsSpellKnown=" .. (ok and show(v) or "error")) end
        if C_Spell and C_Spell.GetSpellName then local ok, v = pcall(C_Spell.GetSpellName, spellID); add("name=" .. (ok and show(v) or "error")) end
    end
    if ns.ResetSpellbook then ns.ResetSpellbook() end
    local entry = ns.KnownRecoveryEntry and ns.KnownRecoveryEntry()
    add("knownEntry=" .. (entry and ("castID " .. show(entry.castID)) or "nil"))
    local probe = {}
    for _, line in ipairs(ns.lastSelfBuffProbe or {}) do
        if line:find("Leyline", 1, true) then probe[#probe + 1] = line end
    end
    add("candidateProbe=" .. (#probe > 0 and table.concat(probe, ", ") or "none"))
    local manaType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    add(("health=%s/%s mana=%s/%s manaType=%s"):format(show(resourceValue(UnitHealth, "player")),
        show(resourceValue(UnitHealthMax, "player")), show(resourceValue(UnitPower, "player", manaType)),
        show(resourceValue(UnitPowerMax, "player", manaType)), show(manaType)))
    local function raw(api, ...)
        if type(api) ~= "function" then return "missing" end
        local ok, value = pcall(api, ...)
        return ok and show(value) or "error"
    end
    add(("raw health=%s/%s mana=%s/%s powerType=%s inGroup=%s"):format(raw(UnitHealth, "player"),
        raw(UnitHealthMax, "player"), raw(UnitPower, "player", manaType), raw(UnitPowerMax, "player", manaType),
        raw(UnitPowerType, "player"), raw(IsInGroup)))
    if UnitPowerPercent then
        add("UnitPowerPercent mana=" .. raw(UnitPowerPercent, "player", manaType, true,
            CurveConstants and CurveConstants.ScaleTo100))
    end
    if entry then
        add("threshold=" .. show(self:Percent(entry)) .. "%")
        local id = entry.castID or entry.spellID
        if C_Spell and C_Spell.GetSpellCooldown then
            local ok, info = pcall(C_Spell.GetSpellCooldown, id)
            if ok and type(info) == "table" then
                local fields = {}
                for _, key in ipairs({ "startTime", "duration", "isEnabled", "modRate", "isActive", "isOnGCD" }) do
                    fields[#fields + 1] = key .. "=" .. show(info[key])
                end
                add("C_Spell.GetSpellCooldown: " .. table.concat(fields, " "))
            else
                add("C_Spell.GetSpellCooldown: " .. (ok and show(info) or "error"))
            end
        end
        if GetSpellCooldown then
            local ok, a, b, c, d = pcall(GetSpellCooldown, id)
            add("GetSpellCooldown: " .. (ok and (show(a) .. " " .. show(b) .. " " .. show(c) .. " " .. show(d)) or "error"))
        end
        add("GetTime=" .. show(resourceValue(GetTime)))
        local display, state, remaining = self:RecoveryStatus(entry)
        add("RecoveryStatus=" .. show(display) .. " / " .. show(state) .. " / " .. show(remaining))
        add("client fade=" .. (self:CanFadeRecovery() and "yes" or "no"))
        add("excluded=" .. show(self:IsExcluded(entry)) .. " suppressed=" .. show(self:IsSuppressed(entry)))
    end
    add("rested=" .. show(self:IsRestedPaused()) .. " eating=" .. show(self:IsEating())
        .. " dead=" .. show(playerIsDead()) .. " taxi=" .. show(playerOnTaxi()))
    local inList = false
    for _, known in ipairs(ns.KnownSelfBuffs and ns.KnownSelfBuffs() or {}) do
        if known.resourceRecovery then inList = true end
    end
    add("inKnownSelfBuffs=" .. show(inList))
    local onBar = false
    for _, shown in ipairs(self:Entries()) do
        if shown.resourceRecovery then onBar = true end
    end
    add("inEntries=" .. show(onBar) .. " auraProbe=" .. table.concat(ns.lastAuraProbe or {}, ", "))
    if ns.db then ns.db.lastRecoveryDebug = lines end
    -- Chat can't be copied, so the report opens in a copy box.
    local copy = ns.HammerCore and ns.HammerCore.Copy
    if copy and copy.Show then
        copy:Show("Read Leyline check", table.concat(lines, "\n"), "Press Ctrl+C to copy, then paste it to Claude.")
    else
        ns.Print("Read Leyline check")
        for _, line in ipairs(lines) do print("  " .. line) end
    end
    return lines
end
