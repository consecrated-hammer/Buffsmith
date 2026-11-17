local addonName, ns = ...

-- Forever blessings share one slot per caster, not one slot per recipient.
local B = {}
ns.Blessings = B
local MIGHT, KINGS, WISDOM = 19740, 20217, 19742
local classes = {
    { "SELF", "My blessing" }, { "WARRIOR", "Warrior" }, { "ROGUE", "Rogue" },
    { "PALADIN", "Paladin" }, { "HUNTER", "Hunter" }, { "PRIEST", "Priest" },
    { "SHAMAN", "Shaman" }, { "MAGE", "Mage" }, { "WARLOCK", "Warlock" }, { "DRUID", "Druid" },
}
local labels = { [MIGHT] = "Might", [KINGS] = "Kings", [WISDOM] = "Wisdom" }
local valid = { [MIGHT] = true, [KINGS] = true, [WISDOM] = true }

function B:Enabled()
    local _, class = UnitClass("player")
    return ns.TARGET == "Camelot" and class == "PALADIN"
end

function B:Handles(entry)
    return self:Enabled() and entry.group == "paladin-blessing"
end

function B:Config()
    if type(ns.db.blessings) ~= "table" then ns.db.blessings = {} end
    local cfg = ns.db.blessings
    if type(cfg.automatic) ~= "boolean" then cfg.automatic = true end
    if type(cfg.keepActive) ~= "boolean" then cfg.keepActive = true end
    if type(cfg.orders) ~= "table" then cfg.orders = {} end
    return cfg
end

local function allowed(key, id)
    return id ~= WISDOM or (key ~= "WARRIOR" and key ~= "ROGUE")
end

function B:Known()
    local entries = {}
    for _, entry in ipairs(ns.KnownSelfBuffCandidates()) do
        if entry.group == "paladin-blessing" then entries[entry.spellID] = entry end
    end
    return entries
end

function B:Order(key, known)
    local cfg, order, seen = self:Config(), {}, {}
    local function add(id)
        if valid[id] and known[id] and allowed(key, id) and not seen[id] then
            seen[id] = true
            order[#order + 1] = id
        end
    end
    -- Saved orders retain unavailable spells, so changing characters or
    -- temporarily losing a spell never destroys an established preference.
    local saved = cfg.orders[key]
    if type(saved) == "table" then for _, id in ipairs(saved) do add(id) end end
    local defaults = { MIGHT, KINGS, WISDOM }
    if key == "DRUID" then defaults = { KINGS, MIGHT, WISDOM }
    elseif key == "HUNTER" or key == "PRIEST" or key == "SHAMAN" or key == "MAGE" or key == "WARLOCK" then
        defaults = { WISDOM, KINGS, MIGHT }
    end
    for _, id in ipairs(defaults) do add(id) end

    return order
end

function B:LearnedSpellsChanged()
    if not self:Enabled() then return end
    local cfg, known = self:Config(), self:Known()
    for key, saved in pairs(cfg.orders) do
        if type(saved) == "table" then
            local seen = {}
            for _, id in ipairs(saved) do seen[id] = true end
            for _, id in ipairs(self:Order(key, known)) do
                if not seen[id] then saved[#saved + 1] = id; seen[id] = true end
            end
        end
    end
end

function B:Move(key, id, direction)
    local cfg, order = self:Config(), self:Order(key, self:Known())
    for index, current in ipairs(order) do
        local other = index + direction
        if current == id and order[other] then
            order[index], order[other] = order[other], order[index]
            -- Keep unavailable entries after the visible, explicitly ordered set.
            local seen = {}
            for _, value in ipairs(order) do seen[value] = true end
            for _, value in ipairs(cfg.orders[key] or {}) do if not seen[value] then order[#order + 1] = value; seen[value] = true end end
            cfg.orders[key] = order
            return
        end
    end
end

function B:Status(unit, group, readAura)
    if ns.IsCombatLocked() then return { state = "unknown" } end
    local cfg = self:Config()
    local known = {}
    for _, entry in ipairs(group.members or { group }) do known[entry.spellID] = entry end
    local _, class = UnitClass(unit)
    local selfUnit = unit == "player" or (UnitIsUnit and ns.Plain(UnitIsUnit(unit, "player")) == true)
    if not class and not selfUnit then return { state = "active", duration = 0 } end
    local key = selfUnit and "SELF" or class
    local order = self:Order(key, known)
    local statuses, own, uncertain = {}, nil, nil
    for _, id in ipairs({ MIGHT, KINGS, WISDOM }) do
        local entry = known[id]
        if entry then
            local status = readAura(unit, entry.auraID, entry.auraIDs, entry.name, true)
            statuses[id] = status
            if status.state == "active" then
                if status.own then own = id
                elseif not status.sourceGUID then uncertain = id end
            end
        end
    end
    local function result(id)
        local entry, status = known[id], statuses[id]
        if not entry then return { state = "active", duration = 0 } end
        local copy = {}
        for k, value in pairs(status) do copy[k] = value end
        copy.entry = entry
        return copy
    end
    -- An identified own blessing can safely be renewed even if another
    -- blessing has unknown attribution.
    if own and cfg.keepActive then
        if allowed(class, own) and not ns.IsBuffExcluded(known[own]) then return result(own) end
        return { state = "active", duration = 0 }
    end
    -- Unknown attribution cannot establish a free slot for another blessing.
    if uncertain then return { state = "active", duration = 0 } end
    if not cfg.automatic then
        local id = cfg.manual
        if not known[id] then id = order[1] end
        if id and allowed(class, id) and not ns.IsBuffExcluded(known[id]) then
            if statuses[id].state == "active" and not statuses[id].own then return { state = "active", duration = 0 } end
            return result(id)
        end
    else
        for _, id in ipairs(order) do
            local status = statuses[id]
            if not ns.IsBuffExcluded(known[id]) and (status.state ~= "active" or status.own) then return result(id) end
        end
    end
    return { state = "active", duration = 0 }
end

function B:BuildOptions(panel, y)
    local UI = ns.HammerCore.UI
    _, y = UI.Header(panel, "Paladin Blessings", y)
    _, y = UI.Check(panel, "Choose blessing automatically",
        "Select a missing blessing for you to cast, using your priority order and the recipient's existing buffs.", y,
        function() return self:Config().automatic end,
        function(value) self:Config().automatic = value; ns.RefreshAll() end)
    _, y = UI.Check(panel, "Keep my active blessing",
        "Keep and renew your existing blessing, even if another is higher priority. Turn this off to allow replacements. If its caster is unknown, wait until it expires.", y,
        function() return self:Config().keepActive end,
        function(value) self:Config().keepActive = value; ns.RefreshAll() end)
    local help
    help, y = UI.Text(panel, "Work down each list to cast the first missing blessing you know. Blessings from other paladins count towards coverage. Wisdom is never offered to warriors or rogues.", y)
    help:SetWordWrap(true)
    help:SetHeight(44)
    y = y - 30
    local top, rows, expanded = y, {}, { SELF = true }
    local function button(parent, text, width, click)
        local b = UI.Button(parent, width, 22)
        b:SetText(text)
        b:SetScript("OnClick", click)
        return b
    end
    local layout
    local function changed()
        ns.RefreshAll()
        panel.hcRefreshAll()
    end
    local owner = panel.hcHeaderOwner or panel
    local function row(key, label)
        if rows[key] then UI.RegisterRow(panel, rows[key], label); return rows[key] end
        local frame = CreateFrame("Frame", nil, panel)
        frame:SetSize(UI.CONTENT_WIDTH, 26)
        frame.label = UI.FontString(frame, "GameFontHighlightSmall", "text")
        frame.label:SetPoint("LEFT", 4, 0)
        UI.RegisterRow(panel, frame, label)
        frame.searchLabel = label
        rows[key] = frame
        return frame
    end
    local function place(frame, at)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UI.PAD, at)
        frame:Show()
        return at - 30
    end
    layout = function()
        for _, frame in pairs(rows) do
            frame:Hide()
            if frame.searchLabel and owner.hcRows then owner.hcRows[frame.searchLabel] = nil end
        end
        if owner.hcRows then
            owner.hcRows["Blessing to offer"] = nil
            owner.hcRows["Remind me to maintain Righteous Fury"] = nil
        end
        local at, known, cfg = top, self:Known(), self:Config()
        if cfg.automatic then
            for _, info in ipairs(classes) do
                local key, name = info[1], info[2]
                local order = self:Order(key, known)
                if #order > 0 then
                    local header = row("class:" .. key, name .. " blessing priority")
                    local names = {}
                    for _, id in ipairs(order) do names[#names + 1] = labels[id] end
                    header.label:SetText(name .. ": " .. table.concat(names, " > "))
                    if not header.expand then
                        header.expand = button(header, "", 26, function() expanded[key] = not expanded[key]; layout() end)
                        header.expand:SetPoint("RIGHT", -4, 0)
                    end
                    header.expand:SetText(expanded[key] and "-" or "+")
                    at = place(header, at)
                    do
                        for index, id in ipairs(order) do
                            local entry = row(key .. ":" .. id, name .. " " .. labels[id] .. " priority")
                            entry.label:SetText("    " .. index .. ". " .. known[id].name)
                            if not entry.up then
                                entry.up = button(entry, "Up", 48, function() self:Move(key, id, -1); changed() end)
                                entry.down = button(entry, "Down", 48, function() self:Move(key, id, 1); changed() end)
                                entry.down:SetPoint("RIGHT", -4, 0)
                                entry.up:SetPoint("RIGHT", entry.down, "LEFT", -4, 0)
                                entry.hcParentRow = header
                            end
                            entry.up:SetEnabled(index > 1)
                            entry.down:SetEnabled(index < #order)
                            if expanded[key] then at = place(entry, at) end
                        end
                    end
                end
            end
        else
            local order = self:Order("SELF", known)
            if #order > 0 then
                local manual = row("manual", "Manual blessing selection")
                manual.label:Hide()
                if not manual.pick then
                    manual.hcHeaderOwner = panel.hcHeaderOwner or panel
                    manual.hcRefresh, manual.hcRefreshAll = panel.hcRefresh, panel.hcRefreshAll
                    manual.pick = UI.DynamicDropdown(manual, "Blessing to offer", "Choose a learned blessing to cast manually.", -4,
                        function()
                            local values, names = self:Order("SELF", self:Known()), {}
                            for _, id in ipairs(values) do names[#names + 1] = labels[id] end
                            return values, names
                        end,
                        function() local c = self:Config(); return c.manual or self:Order("SELF", self:Known())[1] end,
                        function(value) self:Config().manual = value; ns.RefreshAll() end)
                end
                UI.RegisterRow(panel, manual.pick, "Blessing to offer")
                at = place(manual, at) - 12
            end
        end
        local fury
        for _, entry in ipairs(ns.KnownSelfBuffCandidates()) do if entry.spellID == 25780 then fury = entry end end
        if fury then
            if not rows.fury then
                local frame = CreateFrame("Frame", nil, panel)
                frame:SetSize(UI.CONTENT_WIDTH, 60)
                frame.hcHeaderOwner = panel.hcHeaderOwner or panel
                frame.hcRefresh, frame.hcRefreshAll = panel.hcRefresh, panel.hcRefreshAll
                frame.check = UI.Check(frame, "Remind me to maintain Righteous Fury",
                    "Show a reminder when Righteous Fury is missing. Enable this when tanking; it increases your threat. Off by default.", -4,
                    function() return not ns.IsBuffExcluded(fury) end,
                    function(value) ns.db.excludedBuffs[25780] = not value; ns.RefreshAll() end)
                rows.fury = frame
            end
            UI.RegisterRow(panel, rows.fury.check, "Remind me to maintain Righteous Fury")
            at = place(rows.fury, at - 10) - 30
        end
        local reset = row("reset", "Reset blessing priorities")
        if not reset.button then
            reset.button = button(reset, "Reset blessing priorities", 210, function()
                ns.db.blessings = { automatic = true, keepActive = true, orders = {} }
                for id in pairs(valid) do ns.db.excludedBuffs[id] = nil end
                changed()
            end)
            reset.button:SetPoint("LEFT", 0, 0)
        end
        at = place(reset, at - 10)
        panel.hcSetBottom(at - 10)
        return at - 10
    end
    UI.OnRefresh(panel, layout)
    return layout()
end
