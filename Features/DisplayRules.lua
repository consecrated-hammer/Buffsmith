local addonName, ns = ...
local R = {}
ns.DisplayRules = R
local categories = { "food", "scroll", "flask", "other", "weapon" }
local names = { food = "Food", scroll = "Scrolls", flask = "Flasks", other = "Other buffs", weapon = "Weapon enhancements" }
local labels = { ALWAYS = "Always", INSTANCES = "Dungeons and raids", READY = "Ready checks only", CUSTOM = "Custom...", INHERIT = "Use category settings" }
local locations = { { "world", "Open world" }, { "dungeon", "Dungeons" }, { "raid", "Raids" }, { "pvp", "Battlegrounds / arenas" } }

-- Called by config migration before any refresh. Existing installations retain
-- their availability; recommended defaults apply only to genuinely new saves.
function R:Initialize(db, existing)
    if type(db.displayRules) ~= "table" then db.displayRules = {} end
    local cfg = db.displayRules
    for _, key in ipairs({ "categories", "items", "buffs" }) do
        if type(cfg[key]) ~= "table" then cfg[key] = {} end
    end
    if cfg.version ~= 1 then
        for _, category in ipairs(categories) do
            if cfg.categories[category] == nil then
                cfg.categories[category] = not existing and category ~= "weapon" and "INSTANCES" or "ALWAYS"
            end
        end
        if not existing and ns.TARGET == "Camelot" then
            for id in pairs(ns.CAMPING_ITEMS or {}) do cfg.items[id] = "ALWAYS" end
        end
        cfg.version = 1
    end
end

function R:Config()
    if type(ns.db.displayRules) ~= "table" or ns.db.displayRules.version ~= 1
        or type(ns.db.displayRules.categories) ~= "table" or type(ns.db.displayRules.items) ~= "table"
        or type(ns.db.displayRules.buffs) ~= "table" then self:Initialize(ns.db, true) end
    return ns.db.displayRules
end

function R:Key(entry)
    if entry.kind == "category" then return "categories", entry.category end
    if entry.kind == "item" then return "items", entry.itemID end
    return "buffs", entry.spellID
end

function R:Own(entry)
    local bucket, key = self:Key(entry)
    return key and self:Config()[bucket][key] or nil
end

function R:Effective(entry)
    local rule = self:Own(entry)
    if rule == nil and entry.kind == "item" then rule = self:Config().categories[entry.category] end
    if type(rule) == "table" or labels[rule] and rule ~= "CUSTOM" and rule ~= "INHERIT" then return rule end
    return "ALWAYS"
end

function R:Snapshot(rule)
    if type(rule) == "table" then
        local copy = { ready = rule.ready == true }
        for _, location in ipairs(locations) do copy[location[1]] = rule[location[1]] == true end
        return copy
    end
    return { world = rule ~= "INSTANCES", dungeon = true, raid = true, pvp = rule ~= "INSTANCES", ready = rule == "READY" }
end

function R:Set(entry, value)
    local bucket, key = self:Key(entry)
    if not key then return end
    local cfg = self:Config()
    if value == "INHERIT" then cfg[bucket][key] = nil
    elseif value == "CUSTOM" then cfg[bucket][key] = self:Snapshot(self:Effective(entry))
    elseif type(value) == "table" or value == "ALWAYS" or value == "INSTANCES" or value == "READY" then cfg[bucket][key] = value end
end

function R:Context()
    if type(IsInInstance) ~= "function" then return nil end
    local ok, inside, kind = pcall(IsInInstance)
    if not ok then return nil end
    kind = ns.Plain(kind)
    if kind == "party" or kind == "scenario" then return "dungeon" end
    if kind == "raid" then return "raid" end
    if kind == "pvp" or kind == "arena" then return "pvp" end
    if kind == "none" or ns.Plain(inside) == false then return "world" end
end

function R:Allows(entry)
    local rule = self:Effective(entry)
    if rule == "ALWAYS" then return true end
    local context = self:Context()
    local ready = self.readyUntil and GetTime() < self.readyUntil and IsInGroup and ns.Plain(IsInGroup()) == true
    if rule == "READY" then return ready == true end
    if rule == "INSTANCES" then return context == "dungeon" or context == "raid" end
    return context ~= nil and rule[context] == true and (not rule.ready or ready == true)
end

function R:Refresh()
    ns.RefreshAll()
    if ns.RefreshSettings then ns.RefreshSettings() end
end

function R:ReadyCheck()
    if not IsInGroup or ns.Plain(IsInGroup()) ~= true then return end
    local deadline = GetTime() + 15
    self.readyUntil = deadline
    self:Refresh()
    C_Timer.After(15, function()
        if self.readyUntil == deadline then self.readyUntil = nil; self:Refresh() end
    end)
end

function R:GroupChanged()
    if not IsInGroup or ns.Plain(IsInGroup()) ~= true then self.readyUntil = nil end
end

function R:Recommended()
    ns.db.displayRules = { version = 1, categories = {}, items = {}, buffs = {} }
    for _, category in ipairs(categories) do ns.db.displayRules.categories[category] = category == "weapon" and "ALWAYS" or "INSTANCES" end
    if ns.TARGET == "Camelot" then
        for id in pairs(ns.CAMPING_ITEMS or {}) do ns.db.displayRules.items[id] = "ALWAYS" end
    end
    self:Refresh()
end

function R:Describe(entry)
    local rule = self:Effective(entry)
    local description
    if type(rule) == "table" then
        local selected = {}
        for _, location in ipairs(locations) do if rule[location[1]] == true then selected[#selected + 1] = location[2] end end
        description = #selected > 0 and table.concat(selected, ", ") or "No locations selected"
        if rule.ready then description = description .. " / Ready checks only" end
    else description = labels[rule] end
    if entry.kind == "item" and self:Own(entry) == nil then
        return "Using " .. (names[entry.category] or "category") .. " settings: " .. description
    end
    return description
end

function R:RecommendedButton(panel, y)
    local HC = ns.HammerCore
    return HC.UI.ActionButton(panel, y, "Apply recommended display rules", function()
        HC.Dialog:Confirm({ title = "Apply recommended display rules",
            text = "Reset When to show rules only? Food, flasks, elixirs and scrolls will show in dungeons and raids. Buffs, tracking and weapon enhancements will show everywhere. Camping items stay available outdoors. Other individual overrides will be cleared. Other settings stay as they are.",
            accept = "Apply", onAccept = function() self:Recommended(); panel.hcRefreshAll() end })
    end, "Apply the recommended When to show rules without changing enabled reminders, recipients or thresholds.", nil, 270)
end

-- Each reminder owns a compact rule selector. Only Custom expands the location
-- controls; inline selectors explain inherited category rules in their tooltip.
function R:CreateControl(panel, entry, label, parentRow, indent, inline)
    local UI = ns.HammerCore.UI
    local frame = CreateFrame("Frame", nil, panel)
    indent = indent or 0
    frame:SetSize(UI.CONTENT_WIDTH + UI.PAD * 2 - indent, 1)
    frame.hcColumns = 1
    frame.hcHeaderOwner = panel.hcHeaderOwner or panel
    frame.hcRefresh, frame.hcRefreshAll = panel.hcRefresh, panel.hcRefreshAll
    frame.hcParentRow = parentRow
    local width = UI.CONTENT_WIDTH - indent
    local suffix = entry.kind == "item" and (" (item " .. entry.itemID .. ")") or ""
    local prefix = label .. suffix
    local values = entry.kind == "item" and { "INHERIT", "ALWAYS", "INSTANCES", "READY", "CUSTOM" } or { "ALWAYS", "INSTANCES", "READY", "CUSTOM" }
    local titles = {}
    for _, value in ipairs(values) do titles[#titles + 1] = labels[value] end
    local dropdown, at, selector = UI.Dropdown(frame, prefix .. ": When to show",
        "Limit when this reminder is offered. Existing enabled, recipient and safety settings still apply. Ready checks last 15 seconds from their start.", -4,
        values, titles,
        function()
            local own = self:Own(entry)
            return type(own) == "table" and "CUSTOM" or own or (entry.kind == "item" and "INHERIT" or "ALWAYS")
        end,
        function(value) self:Set(entry, value); self:Refresh() end, width)
    if dropdown.Title then dropdown.Title:SetText("When to show") end
    if inline then
        if dropdown.Title then dropdown.Title:Hide() end
        dropdown:ClearAllPoints()
        dropdown:SetPoint("RIGHT", parentRow, "RIGHT", -6, 0)
        dropdown:SetSize(160, parentRow:GetHeight())
        selector:ClearAllPoints()
        selector:SetPoint("RIGHT", dropdown, "RIGHT", 0, 0)
        selector:SetSize(160, 26)
        UI.AttachHint(selector, prefix .. ": When to show", function()
            return R:Describe(entry) .. "\nLocations and ready-check conditions must both match. Ready checks last 15 seconds."
        end)
    end
    local summary = UI.FontString(frame, "GameFontHighlightSmall", "muted")
    summary:SetPoint("TOPLEFT", UI.PAD + 2, at - 2)
    summary:SetWidth(width - 4)
    summary:SetWordWrap(true)
    summary:SetHeight(30)
    local summaryAt = at
    local base = at - 34
    local children = {}
    for _, info in ipairs({ locations[1], locations[2], locations[3], locations[4], { "ready", "Only during ready checks" } }) do
        local key, title = info[1], info[2]
        local row
        row, at = UI.Check(frame, prefix .. ": " .. title,
            key == "ready" and "Require a ready check within the last 15 seconds, in a selected location." or "Allow reminders in this location.",
            base - #children * UI.CELL_H,
            function() local custom = self:Snapshot(self:Effective(entry)); return custom[key] == true end,
            function(value)
                local custom = self:Snapshot(self:Effective(entry)); custom[key] = value
                self:Set(entry, custom); self:Refresh()
            end, width)
        if row.hcCheckbox and row.hcCheckbox.Text then row.hcCheckbox.Text:SetText(title) end
        row.hcParentRow = dropdown
        children[#children + 1] = row
    end
    function frame:Layout()
        local custom = type(R:Own(entry)) == "table"
        summary:SetText(R:Describe(entry))
        local textHeight = math.max(14, tonumber(summary:GetStringHeight()) or 30)
        summary:SetHeight(textHeight)
        local rowHeight = inline and parentRow:GetHeight() or 0
        local bottom = inline and (-rowHeight - textHeight - 10) or (summaryAt - textHeight - 6)
        summary:ClearAllPoints()
        summary:SetPoint("TOPLEFT", UI.PAD + 2, inline and (-rowHeight - 4) or (summaryAt - 2))
        summary:SetShown(not inline or custom)
        for index, row in ipairs(children) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", UI.PAD, bottom - (index - 1) * UI.CELL_H)
            row:SetShown(custom)
        end
        self.height = inline and not custom and rowHeight or (-bottom + (custom and #children * UI.CELL_H or 0) + 4)
        self:SetHeight(self.height)
        return inline and (self.height - rowHeight) or self.height
    end
    frame.summary = summary
    frame:Layout()
    return frame
end
