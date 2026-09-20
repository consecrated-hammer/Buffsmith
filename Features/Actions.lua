local addonName, ns = ...

ns.Actions = {}
local Actions = ns.Actions
Actions.suppressed = {}

local function currentSpecKey()
    local spec = GetSpecialization and GetSpecialization()
    return tostring(spec or 0)
end

local function auraStatus(unit, auraID, auraIDs, auraName)
    if ns.IsCombatLocked() then return { state = "unknown" } end
    local function active(aura)
        local duration = tonumber(ns.Plain(aura.duration)) or 0
        local expiration = tonumber(ns.Plain(aura.expirationTime)) or 0
        local remaining = duration > 0 and expiration > 0 and math.max(0, expiration - GetTime()) or nil
        return { state = "active", duration = duration, remaining = remaining }
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

local function friendlyPet(unit)
    return UnitExists(unit) and not UnitIsPlayer(unit)
        and UnitCanAssist("player", unit) and not UnitIsDeadOrGhost(unit)
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
    return copy
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
    if not ns.db.showPartyCoverage or not (IsInGroup and IsInGroup()) then
        ns.lastCoverageProbe[1] = "disabled or solo"
        return coverage
    end
    local units, candidates = partyUnits(), {}
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
                candidate.providers[#candidate.providers + 1] = UnitName(provider) or provider
            end
        end
    end
    for _, candidate in pairs(candidates) do
        for _, unit in ipairs(units) do
            local status = auraStatus(unit, candidate.auraID, candidate.auraIDs, candidate.name)
            local display = shouldShow(candidate, status)
            if display then candidate.missing[#candidate.missing + 1] = UnitName(unit) or unit end
        end
        if #candidate.missing > 0 and not self:IsSuppressed(candidate) then
            candidate.count = #candidate.missing
            candidate.providerText = table.concat(candidate.providers, ", ")
            candidate.missingText = table.concat(candidate.missing, ", ")
            coverage[#coverage + 1] = candidate
            ns.lastCoverageProbe[#ns.lastCoverageProbe + 1] = candidate.name .. ": " .. candidate.count .. " missing"
        end
    end
    table.sort(coverage, function(a, b) return a.name < b.name end)
    return coverage
end

function Actions:Entries()
    local entries = {}
    self.nextReminderDelay = nil
    ns.lastAuraProbe = {}
    if ns.db.ignoreBuffsInRestedAreas and IsResting and IsResting() then
        ns.lastAuraProbe[1] = "self-buff checks paused: rested area"
        return entries
    end
    for _, entry in ipairs(ns.KnownSelfBuffs()) do
        local status = auraStatus("player", entry.auraID, entry.auraIDs, entry.name)
        self:ConsiderReminder(entry, status)
        local display, state = shouldShow(entry, status)
        entry.state, entry.auraDuration, entry.auraRemaining = state, status.duration, status.remaining
        ns.lastAuraProbe[#ns.lastAuraProbe + 1] = entry.name .. "=" .. entry.state
        if display and not self:IsSuppressed(entry) then entries[#entries + 1] = entry end
    end
    local known = ns.KnownSelfBuffs()
    local selectedTarget = friendlyPlayer("target") or (ns.db.showPetBuffs and friendlyPet("target"))
    if ns.db.showTargetBuffs and selectedTarget and not UnitIsUnit("player", "target") then
        ns.lastTargetProbe = {}
        for _, entry in ipairs(known) do
            if entry.target then
                local status = auraStatus("target", entry.auraID, entry.auraIDs, entry.name)
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
                    if friendlyPlayer(unit) and not (selectedTarget and UnitIsUnit("target", unit)) then
                        local status = auraStatus(unit, entry.auraID, entry.auraIDs, entry.name)
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
                for _, unit in ipairs({ "pet", "party1pet", "party2pet", "party3pet", "party4pet" }) do
                    if friendlyPet(unit) and not (selectedTarget and UnitIsUnit("target", unit)) then
                        local status = auraStatus(unit, entry.auraID, entry.auraIDs, entry.name)
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
    return entries
end

function Actions:ConsiderReminder(entry, status)
    if entry.permanent then return end
    if status.state ~= "active" or not status.duration or not status.remaining then return end
    local threshold = status.duration * self:Percent(entry) / 100
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
        value = value == nil and reminder.buff or value
    end
    return math.max(0, math.min(50, tonumber(value) or 10))
end

function Actions:ArmReminder()
    local delay = self.nextReminderDelay
    if not delay or ns.IsCombatLocked() then return end
    self.reminderToken = (self.reminderToken or 0) + 1
    local token = self.reminderToken
    C_Timer.After(math.max(1, delay + 0.05), function()
        if token ~= self.reminderToken or ns.IsCombatLocked() then return end
        if ns.Palette then ns.Palette:Refresh() end
    end)
end

function Actions:Key(entry)
    if not entry then return nil end
    if entry.kind == "spell" then return "spell:" .. tostring(entry.spellID) end
    if entry.kind == "item" then return "item:" .. tostring(entry.itemID) end
    if entry.kind == "notice" then return "party:" .. tostring(entry.providerClass) .. ":" .. tostring(entry.spellID) end
end

-- An excluded buff is off everywhere: self, target, party and pet all route
-- through IsSuppressed, so exclusion composes with the session dismissals
-- rather than needing its own check at each call site.
function Actions:IsExcluded(entry)
    return entry.kind == "spell" and ns.db.excludedBuffs[entry.spellID] == true
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
    local message = ("[Buffsmith] %s is missing from %s. Possible provider: %s."):format(
        tostring(entry.name), tostring(entry.missingText), tostring(entry.providerText))
    SendChatMessage(message, channel)
    return true
end

function Actions:ResetDismissals()
    self.suppressed = {}
end

function Actions:Preferred(category, choices)
    local preferred = ns.db.preferred[currentSpecKey()]
    preferred = type(preferred) == "table" and preferred[category] or nil
    for index, choice in ipairs(choices) do
        if choice.itemID == preferred and not self:IsSuppressed(choice) then return index end
    end
    for index, choice in ipairs(choices) do
        if not self:IsSuppressed(choice) then return index end
    end
    return nil
end

function Actions:VisibleChoices(category)
    local choices = {}
    if not ns.db.categories[category] then return choices end
    -- A category-level active effect suppresses alternatives of the same kind.
    -- This prevents a second food or weapon oil appearing while one is active.
    local categoryStatus = ns.Inventory:CategoryStatus(category)
    if categoryStatus then
        local display = shouldShow({ kind = "item", category = category }, categoryStatus)
        if not display then return choices end
    end
    for _, choice in ipairs(ns.Inventory:Choices(category)) do
        if ns.db.excludedConsumables[choice.itemID] then
            choice.state = "excluded"
        else
        local mapping = ns.db.consumableAuras[choice.itemID]
        if mapping then
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
    return choices
end

function Actions:BindingEntries()
    local entries, displayed = {}, self:Entries()
    for _, entry in ipairs(displayed) do
        if entry.kind == "spell" or entry.kind == "item" then entries[#entries + 1] = entry end
    end
    for _, category in ipairs({ "food", "scroll", "flask", "weapon" }) do
        local choices = self:VisibleChoices(category)
        local primary = self:Preferred(category, choices)
        if primary then entries[#entries + 1] = choices[primary] end
    end
    return entries
end

function Actions:ReminderSummary()
    local summaries = {}
    for _, entry in ipairs(ns.KnownSelfBuffs()) do
        local status = auraStatus("player", entry.auraID, entry.auraIDs, entry.name)
        if status.duration and status.duration > 0 then
            summaries[#summaries + 1] = entry.name .. ": " .. timeText(status.duration * self:Percent(entry) / 100)
        end
    end
    return #summaries > 0 and table.concat(summaries, ", ") or "Apply a timed self-buff to show its exact reminder time."
end

function Actions:ReminderFor(entry)
    if entry.permanent then return "while inactive" end
    local status = auraStatus("player", entry.auraID, entry.auraIDs, entry.name)
    if status.duration and status.duration > 0 then
        return timeText(status.duration * self:Percent(entry) / 100)
    end
    return "when active"
end

function Actions:Remember(category, itemID)
    local key = currentSpecKey()
    ns.db.preferred[key] = ns.db.preferred[key] or {}
    ns.db.preferred[key][category] = itemID
end

function Actions:Configure(button, entry)
    if ns.IsCombatLocked() then return false end
    for mouseButton = 1, 5 do
        button:SetAttribute("type" .. mouseButton, nil)
        button:SetAttribute("spell" .. mouseButton, nil)
        button:SetAttribute("item" .. mouseButton, nil)
        button:SetAttribute("unit" .. mouseButton, entry.unit or "player")
    end
    -- Unqualified secure attributes are fallbacks for every mouse button.
    -- Only LeftButton is an action; right-click is strictly a local dismissal.
    button:SetAttribute("type", nil); button:SetAttribute("spell", nil); button:SetAttribute("item", nil)
    button:SetAttribute("unit", entry.unit or "player")
    if entry.kind == "spell" then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", entry.name)
    elseif entry.kind == "item" then
        local item = entry.itemLink or ("item:" .. entry.itemID)
        button:SetAttribute("type1", "item")
        button:SetAttribute("item1", item)
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
