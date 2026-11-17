local addonName, ns = ...
local C = {}
ns.ClassBuffs = C

function C:IsClass(class)
    local _, current = UnitClass("player")
    return ns.TARGET == "Camelot" and current == class
end

function C:Config()
    if type(ns.db.classBuffs) ~= "table" then ns.db.classBuffs = {} end
    return ns.db.classBuffs
end

function C:Druid(entry)
    local cfg = self:Config()
    if type(cfg.druid) ~= "table" then cfg.druid = {} end
    local id = entry.spellID
    if type(cfg.druid[id]) ~= "table" then
        cfg.druid[id] = { self = true, target = ns.db.showTargetBuffs == true,
            party = ns.db.showPartyBuffs == true and "ALL" or "NONE", pets = ns.db.showPetBuffs == true }
    end
    return cfg.druid[id]
end

function C:IsTank(unit)
    if UnitGroupRolesAssigned then
        local ok, role = pcall(UnitGroupRolesAssigned, unit)
        if ok and ns.Plain(role) == "TANK" then return true end
    end
    if GetPartyAssignment then
        local ok, assigned = pcall(GetPartyAssignment, "MAINTANK", unit)
        if ok and ns.Plain(assigned) == true then return true end
    end
    return false
end

function C:Allows(entry, scope, unit)
    if not self:IsClass("DRUID") or (entry.spellID ~= 1126 and entry.spellID ~= 467) then return true end
    local cfg = self:Druid(entry)
    if scope == "self" then return cfg.self ~= false end
    if scope == "target" then
        return cfg.target == true and (not UnitIsPlayer or ns.Plain(UnitIsPlayer(unit)) == true or cfg.pets == true)
    end
    if scope == "pet" then return cfg.pets == true end
    return cfg.party == "ALL" or (cfg.party == "TANK" and self:IsTank(unit))
end

function C:ShieldStatus(unit, group, readAura)
    local cfg = self:Config()
    local desired = group
    for _, member in ipairs(group.members or { group }) do
        local status = readAura(unit, member.auraID, member.auraIDs, member.name)
        if status.state == "active" and cfg.keepShield ~= false then
            if ns.IsBuffExcluded(member) then return { state = "active", duration = 0 } end
            status.entry = member
            return status
        end
    end
    local status = readAura(unit, desired.auraID, desired.auraIDs, desired.name)
    status.entry = desired
    return status
end

function C:PoisonPreference(slot)
    local spec = tostring(GetSpecialization and GetSpecialization() or 0)
    local saved = ns.db.preferred[spec]
    saved = type(saved) == "table" and saved or {}
    local value = saved["poison:" .. slot]
    if value == nil and not self:Config().ignoreLegacyPoison and saved.weapon
        and ns.Inventory:IsPoisonItem(saved.weapon) then value = saved.weapon end
    if value == -1 then return nil end -- explicit Automatic
    return value
end

function C:SetPoisonPreference(slot, value)
    ns.Actions:Remember("poison:" .. slot, value)
end

-- Resolve a ready poison and a bare weapon together, so an unavailable first
-- hand cannot block the other hand. Never replace any temporary coating.
function C:PoisonSelection()
    if ns.IsCombatLocked() or not self:IsClass("ROGUE") or self:Config().poisons == false then return nil end
    if type(GetWeaponEnchantInfo) ~= "function" or type(GetInventoryItemID) ~= "function" then return nil end
    local ok, main, _, _, _, off = pcall(GetWeaponEnchantInfo)
    if not ok or ns.IsSecret(main) or ns.IsSecret(off) then return nil end
    local candidates = ns.Inventory:Choices("weapon")
    for _, slot in ipairs({ 16, 17 }) do
        local equipped = slot == 16 and GetInventoryItemID("player", 16)
            or slot == 17 and OffhandHasWeapon and OffhandHasWeapon()
        if equipped and not (slot == 16 and main or slot == 17 and off) then
            local preferred, first, exact = self:PoisonPreference(slot)
            if preferred ~= 0 then
                for _, item in ipairs(candidates) do
                    if item.poison and not ns.db.excludedConsumables[item.itemID] and not ns.Actions:IsSuppressed(item) then
                        local cooldown = ns.Inventory:CooldownRemaining(item)
                        if cooldown then ns.Inventory:RefreshAfterCooldown(item, cooldown)
                        else
                            first = first or item
                            if item.itemID == preferred then exact = item end
                        end
                    end
                end
                local chosen = exact or ((not preferred or self:Config().poisonFallback == true) and first)
                if chosen then return slot, chosen, preferred ~= nil and exact == nil end
            end
        end
    end
end

function C:PoisonOptions(slot)
    local values, labels, found = { -1, 0 }, { "Automatic", "Off" }, {}
    for _, item in ipairs(ns.Inventory:OwnedChoices("weapon")) do
        if item.poison and item.usable then
            values[#values + 1] = item.itemID
            labels[#labels + 1] = item.name .. " (" .. (item.count or 0) .. ")"
            found[item.itemID] = true
        end
    end
    local preferred = self:PoisonPreference(slot)
    if type(preferred) == "number" and preferred > 0 and not found[preferred] then
        local name = ns.Inventory.ItemInfo(preferred)
        local reason = "not in bags"
        for _, item in ipairs(ns.Inventory:OwnedChoices("weapon")) do
            if item.itemID == preferred then reason = "not usable" end
        end
        values[#values + 1] = preferred
        labels[#labels + 1] = (name or ("Item " .. preferred)) .. " (" .. reason .. ")"
    end
    return values, labels
end

local function section(panel)
    local UI = ns.HammerCore.UI
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetSize(UI.CONTENT_WIDTH, 1)
    frame.hcColumns = 1
    frame.hcHeaderOwner = panel.hcHeaderOwner or panel
    frame.hcRefresh, frame.hcRefreshAll = panel.hcRefresh, panel.hcRefreshAll
    return frame
end

function C:BuildPoisons(panel, y)
    local UI = ns.HammerCore.UI
    _, y = UI.Header(panel, "Poisons", y)
    _, y = UI.Check(panel, "Remind me to apply poisons", "Offer poisons for bare equipped weapons. Weapon enhancements must also be enabled in Consumables.", y,
        function() return self:Config().poisons ~= false end,
        function(value) self:Config().poisons = value; ns.RefreshAll() end)
    for _, slot in ipairs({ 16, 17 }) do
        _, y = UI.DynamicDropdown(panel, slot == 16 and "Main-hand poison" or "Off-hand poison",
            "Choose an owned usable poison, Automatic, or Off. Ignored poisons stay ignored; restore them on Ignored.", y,
            function() return self:PoisonOptions(slot) end,
            function() return self:PoisonPreference(slot) or -1 end,
            function(value) self:SetPoisonPreference(slot, value); ns.RefreshAll() end)
    end
    _, y = UI.Dropdown(panel, "If preferred poison is unavailable", "Wait for the preferred poison, or use another ready poison without changing the saved choice.", y,
        { false, true }, { "Wait for it", "Use another available poison" },
        function() return self:Config().poisonFallback == true end,
        function(value) self:Config().poisonFallback = value; ns.RefreshAll() end)
    _, y = UI.Text(panel, "Keep existing coatings until they wear off. Each click coats one weapon.", y)
    _, y = UI.PageReset(panel, y, function()
        local spec = tostring(GetSpecialization and GetSpecialization() or 0)
        local saved = ns.db.preferred[spec]
        if type(saved) == "table" then saved["poison:16"], saved["poison:17"] = nil, nil end
        self:Config().ignoreLegacyPoison = true
        self:Config().poisonFallback = false
        ns.RefreshAll()
    end, "Reset poison choices")
    return y
end

function C:BuildShield(panel, y)
    local UI = ns.HammerCore.UI
    _, y = UI.Header(panel, "Shields", y)
    local function choices()
        local values, labels = {}, {}
        for _, entry in ipairs(ns.KnownSelfBuffCandidates()) do
            if entry.group == "shaman-shield" then values[#values + 1] = entry.spellID; labels[#labels + 1] = entry.name end
        end
        return values, labels
    end
    _, y = UI.DynamicDropdown(panel, "Preferred shield", "Choose a learned shield. Ignored shields are skipped; enable them in Reminders.", y, choices,
        function()
            for _, entry in ipairs(ns.KnownSelfBuffs()) do if entry.group == "shaman-shield" then return entry.spellID end end
        end,
        function(value) ns.Actions:Remember("shaman-shield", value); ns.RefreshAll() end)
    _, y = UI.Check(panel, "Keep my active shield", "Keep and renew the active shield. Turn this off to offer your preferred shield instead.", y,
        function() return self:Config().keepShield ~= false end,
        function(value) self:Config().keepShield = value; ns.RefreshAll() end)
    _, y = UI.PageReset(panel, y, function()
        local spec = tostring(GetSpecialization and GetSpecialization() or 0)
        local saved = ns.db.preferred[spec]
        if type(saved) == "table" then saved["shaman-shield"] = nil end
        self:Config().keepShield = nil
        ns.RefreshAll()
    end, "Reset shield choices")
    return y
end

function C:BuildDruid(panel, y)
    local UI = ns.HammerCore.UI
    _, y = UI.Text(panel, "These recipient choices follow your Targets settings. Renewal thresholds and When to show stay in Reminders.", y)
    local top, frames = y, {}
    local owner = panel.hcHeaderOwner or panel
    local function make(entry)
        local frame = section(panel)
        local before = {}
        for label in pairs(owner.hcRows or {}) do before[label] = true end
        local at = -4
        _, at = UI.Header(frame, entry.name, at, entry.icon)
        local prefix = entry.spellID == 467 and "Thorns" or "Mark"
        _, at = UI.Check(frame, "Maintain " .. prefix, "Use the existing reminder setting for this spell.", at,
            function() return not ns.IsBuffExcluded(entry) end,
            function(value) ns.db.excludedBuffs[entry.spellID] = not value; ns.RefreshAll() end)
        for _, info in ipairs({ { "self", "Myself" }, { "target", "Selected friendly target" }, { "pets", "Pets" } }) do
            local key, label = info[1], info[2]
            _, at = UI.Check(frame, prefix .. ": " .. label, "Initially copied from Targets, then saved separately. Global Targets switches still limit these recipients.", at,
                function() return self:Druid(entry)[key] == true end,
                function(value) self:Druid(entry)[key] = value; ns.RefreshAll() end)
        end
        local values, labels = { "ALL", "NONE" }, { "Everyone", "Nobody" }
        if entry.spellID == 467 then values, labels = { "ALL", "TANK", "NONE" }, { "Everyone", "Assigned tanks", "Nobody" } end
        _, at = UI.Dropdown(frame, prefix .. ": Party recipients", "Assigned tanks uses explicit group roles only. Without an assigned tank, use your selected friendly target.", at,
            values, labels, function() return self:Druid(entry).party end,
            function(value) self:Druid(entry).party = value; ns.RefreshAll() end)
        frame.tankNote, at = UI.Text(frame, "", at)
        frame.labels = {}
        for label, row in pairs(owner.hcRows or {}) do if not before[label] then frame.labels[label] = row end end
        frame.height = -UI.Flush(frame, at) + 8
        return frame
    end
    local reset = UI.PageReset(panel, top, function() self:Config().druid = nil; ns.RefreshAll() end, "Reset druid recipients")
    local function layout()
        for _, frame in pairs(frames) do
            frame:Hide()
            for label in pairs(frame.labels) do owner.hcRows[label] = nil end
        end
        local at = top
        for _, entry in ipairs(ns.KnownSelfBuffCandidates()) do
            if entry.spellID == 1126 or entry.spellID == 467 then
                self:Druid(entry)
                local frame = frames[entry.spellID]
                if not frame then frame = make(entry); frames[entry.spellID] = frame end
                for label, row in pairs(frame.labels) do UI.RegisterRow(panel, row, label) end
                frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", 0, at); frame:Show()
                local tank = false
                for i = 1, 4 do if UnitExists("party" .. i) and self:IsTank("party" .. i) then tank = true end end
                frame.tankNote:SetText(entry.spellID == 467 and self:Druid(entry).party == "TANK" and not tank
                    and "No assigned party tank found. Select a friendly target to buff them." or "")
                at = at - frame.height
            end
        end
        reset:ClearAllPoints(); reset:SetPoint("TOPLEFT", UI.PAD, at - 8)
        panel.hcSetBottom(at - 52)
        return at - 52
    end
    UI.OnRefresh(panel, layout)
    return layout()
end
