local addonName, ns = ...
local HC = ns.HammerCore
local UI, T = HC.UI, HC.Theme

-- Buffsmith's own settings pages.  HammerCore adds the standard Visibility
-- controls, Theme, Commands, Troubleshooting and About.

-- ── Shared row for buffs, consumables and their categories ────────────────
-- Tick, optional icon, name, one-line detail and an optional reminder slider.
-- Clicking anywhere on the row toggles the tick.

local ROW_HEIGHT = 50
local TEXT_WIDTH = 210
local SLIDER_X = 330

local function reminderRow(panel, y, item)
    local row = CreateFrame("Button", nil, panel, "BackdropTemplate")
    row:SetPoint("TOPLEFT", UI.PAD, y)
    row:SetSize(UI.CONTENT_WIDTH, ROW_HEIGHT)
    T.Surface(row, "raised", "edge")

    local tick = UI.CheckButton(row)
    tick:SetPoint("LEFT", 12, 0)
    tick:EnableMouse(false)
    local left = tick
    if item.icon then
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("LEFT", tick, "RIGHT", 10, 0)
        icon:SetTexture(item.icon)
        left = icon
    end
    local name = UI.FontString(row)
    name:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, item.icon and 0 or 6)
    name:SetWidth(TEXT_WIDTH)
    name:SetJustifyH("LEFT")
    if name.SetWordWrap then name:SetWordWrap(false) end
    name:SetText(item.label)
    local detail = UI.FontString(row, "GameFontHighlightSmall", "muted")
    detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    detail:SetWidth(TEXT_WIDTH)
    detail:SetJustifyH("LEFT")
    if detail.SetWordWrap then detail:SetWordWrap(false) end

    local slider, percent
    if not item.permanent then
        slider = CreateFrame("Slider", nil, row)
        slider:SetOrientation("HORIZONTAL")
        slider:SetSize(140, 16)
        slider:SetPoint("LEFT", SLIDER_X, 0)
        slider:SetMinMaxValues(0, 50)
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        local track = T.Fill(slider:CreateTexture(nil, "BACKGROUND"), "rail")
        track:SetPoint("LEFT", 4, 0)
        track:SetPoint("RIGHT", -4, 0)
        track:SetHeight(4)
        local thumb = T.Fill(slider:CreateTexture(nil, "OVERLAY"), "selected")
        thumb:SetSize(10, 10)
        if slider.SetThumbTexture then slider:SetThumbTexture(thumb) end
        percent = UI.FontString(row, "GameFontHighlightSmall", "muted")
        percent:SetPoint("LEFT", slider, "RIGHT", 10, 0)
        UI.AttachHint(slider, "Reminder", "Remind when this share of the effect's duration is left.")
    end

    local changing = false
    local function refresh()
        tick:SetChecked(item.enabled())
        if item.permanent then
            detail:SetText("Permanent effect")
        else
            changing = true
            slider:SetValue(item.get())
            changing = false
            percent:SetText(tostring(item.get()) .. "%")
            detail:SetText(item.result())
        end
    end
    if slider then
        slider:SetScript("OnValueChanged", function(_, value)
            if changing then return end
            item.set(math.floor(value + 0.5))
            refresh()
            ns.RefreshAll()
        end)
    end
    row:SetScript("OnClick", function()
        item.toggle()
        refresh()
        ns.RefreshAll()
        if item.changed then item.changed() end
    end)
    refresh()
    row.refresh = refresh
    return row
end

-- Rows whose set changes while the page exists (ignoring, learning a spell,
-- looting an item).  One frame per key, re-anchored on every layout.
local function rowPool(panel)
    local pool = { frames = {} }
    function pool:Begin()
        for _, frame in pairs(self.frames) do frame:Hide() end
    end
    function pool:Place(key, y, build)
        local frame = self.frames[key]
        if not frame then
            frame = reminderRow(panel, y, build())
            self.frames[key] = frame
        end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UI.PAD, y)
        frame:Show()
        frame.refresh()
        return y - ROW_HEIGHT - 6
    end
    return pool
end

-- "View ignored (N)", shown only while something of this kind is ignored.
local function ignoredLink(panel)
    local button = UI.Button(panel, 180, 22)
    button:SetScript("OnClick", function() HC.Settings:Show("Ignored") end)
    return function(kind, y)
        local count = 0
        for _, entry in ipairs(ns.Actions:IgnoredEntries()) do
            if entry.kind == kind then count = count + 1 end
        end
        button:SetShown(count > 0)
        if count == 0 then return y end
        button:SetText("View ignored (" .. count .. ")")
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", UI.PAD, y)
        return y - 32
    end
end

-- ── Visibility: HammerCore's standard page plus the bar's own rules ───────

HC.Settings:AddVisibility()
HC.spec.visibility = function(panel, y)
    _, y = UI.Header(panel, "Bar", y)
    local function hasConditions()
        for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
            if ns.db.visibility[condition.key] then return true end
        end
        return false
    end
    local function setMode(mode)
        ns.db.visibilityMode = mode
        ns.db.visibility = {}
        ns.db.legacyVisibility = nil
        ns.RefreshAll()
    end
    local items = {
        { label = "Always", radio = true,
          get = function() return ns.db.visibilityMode ~= "NEVER" and not hasConditions() end,
          set = function() setMode("ALWAYS") end },
        { label = "Never", radio = true,
          get = function() return ns.db.visibilityMode == "NEVER" end,
          set = function() setMode("NEVER") end },
        { label = "Or when any of these match", heading = true },
    }
    for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
        local key = condition.key
        items[#items + 1] = {
            label = condition.label,
            get = function() return ns.db.visibilityMode ~= "NEVER" and ns.db.visibility[key] == true end,
            set = function(value)
                ns.db.visibilityMode = "ALWAYS"
                ns.db.legacyVisibility = nil
                ns.db.visibility[key] = value or nil
                ns.RefreshAll()
            end,
        }
    end
    _, y = UI.MultiSelect(panel, "Show the bar",
        "Choose Always or Never, or tick several rules; any matching rule shows the bar.",
        y, { items = items, summary = function() return ns.Visibility:Summary() end }, 300)
    _, y = UI.Check(panel, "Pause reminders in rested areas",
        "Hide buff and consumable reminders while resting in a city or inn.", y,
        function() return ns.db.ignoreBuffsInRestedAreas end,
        function(value) ns.Set("ignoreBuffsInRestedAreas", value) end)
    return y
end

-- ── Appearance ─────────────────────────────────────────────────────────────

HC.Settings:NewPage({ name = "Appearance", description = "Size, direction and the drag handle." }, function(panel, y)
    _, y = UI.Header(panel, "Bar", y)
    _, y = UI.Dropdown(panel, "Direction", nil, y, { "VERTICAL", "HORIZONTAL" }, { "Vertical", "Horizontal" },
        function() return ns.db.orientation end,
        function(value) ns.Set("orientation", value) end)
    local function flyoutKey()
        return ns.db.orientation == "HORIZONTAL" and "flyoutHorizontalDirection" or "flyoutVerticalDirection"
    end
    _, y = UI.Dropdown(panel, "Flyout direction",
        "Where a category's other choices open. Automatic picks the side with more room.", y,
        function()
            return ns.db.orientation == "HORIZONTAL" and { "AUTO", "UP", "DOWN" } or { "AUTO", "LEFT", "RIGHT" }
        end,
        function()
            return ns.db.orientation == "HORIZONTAL" and { "Automatic", "Above", "Below" }
                or { "Automatic", "Left", "Right" }
        end,
        function() return ns.db[flyoutKey()] end,
        function(value) ns.Set(flyoutKey(), value) end)
    _, y = UI.Slider(panel, "Icon size", nil, y, 24, 64, 2,
        function() return ns.db.iconSize end,
        function(value) ns.Set("iconSize", value) end,
        function(value) return value .. " px" end)
    _, y = UI.Slider(panel, "Flyout choices", "How many other choices a category's flyout shows.", y, 1, 3, 1,
        function() return ns.db.maxAlternatives end,
        function(value) ns.Set("maxAlternatives", value) end)
    _, y = UI.Check(panel, "Show drag handle",
        "Drag the grip above the bar to move it. Right-click it to open settings.", y,
        function() return ns.db.showHandle end,
        function(value)
            ns.db.showHandle = value
            ns.Handle:Update()
        end)
    local reset = UI.Button(panel, 180, 22)
    reset:SetPoint("TOPLEFT", UI.PAD, y - 4)
    reset:SetText("Reset bar position")
    reset:SetScript("OnClick", function() HC.Commands:Dispatch("reset position") end)
    return y - 38
end)

-- ── Buffs ──────────────────────────────────────────────────────────────────

HC.Settings:NewPage({ name = "Buffs", description = "Who Buffsmith checks, and when each buff reminds you." }, function(panel, y)
    _, y = UI.Header(panel, "Targets", y)
    _, y = UI.Check(panel, "Friendly target", "Show targetable buffs your selected friendly player is missing.", y,
        function() return ns.db.showTargetBuffs end, function(value) ns.Set("showTargetBuffs", value) end)
    _, y = UI.Check(panel, "Party members", "Show targetable buffs party members are missing.", y,
        function() return ns.db.showPartyBuffs end, function(value) ns.Set("showPartyBuffs", value) end)
    _, y = UI.Check(panel, "Friendly pets", "Show targetable buffs for your pet and party pets.", y,
        function() return ns.db.showPetBuffs end, function(value) ns.Set("showPetBuffs", value) end)
    _, y = UI.Check(panel, "Party coverage", "Show class buffs a party member may provide. These report to chat; they never cast.", y,
        function() return ns.db.showPartyCoverage end, function(value) ns.Set("showPartyCoverage", value) end)
    _, y = UI.Header(panel, "Detected buffs", y - 6)
    _, y = UI.Text(panel, "Short buffs are off by default.", y)
    local listTop, pool, link = y, rowPool(panel), ignoredLink(panel)
    local none = UI.FontString(panel, "GameFontHighlightSmall", "muted")
    none:SetText("No self-buffs found for your class and level yet.")
    local function layout()
        local y = link("spell", listTop)
        pool:Begin()
        local shown = 0
        for _, buff in ipairs(ns.KnownSelfBuffCandidates()) do
            local entry = buff
            if ns.db.excludedBuffs[entry.spellID] ~= true then
                shown = shown + 1
                y = pool:Place(entry.spellID .. ":" .. entry.castID, y, function() return {
                    label = entry.name, icon = entry.icon, permanent = entry.permanent,
                    enabled = function() return not ns.IsBuffExcluded(entry) end,
                    toggle = function() ns.db.excludedBuffs[entry.spellID] = not ns.IsBuffExcluded(entry) end,
                    get = function() return ns.Actions:Percent(entry) end,
                    set = function(value) ns.db.reminderPercent.buffBySpell[entry.spellID] = value end,
                    result = function() return ns.Actions:ReminderFor(entry) end,
                    changed = function() panel.hcRefreshAll() end,
                } end)
            end
        end
        none:ClearAllPoints()
        none:SetPoint("TOPLEFT", UI.PAD, y)
        none:SetShown(shown == 0)
        if shown == 0 then y = y - 24 end
        panel.hcSetBottom(y)
        return y
    end
    UI.OnRefresh(panel, layout)
    return layout()
end)

-- ── Consumables ────────────────────────────────────────────────────────────

local CATEGORIES = { { "food", "Food" }, { "scroll", "Scrolls" }, { "flask", "Flasks" }, { "weapon", "Weapon enhancements" } }

HC.Settings:NewPage({ name = "Consumables", description = "Items appear while they are in your bags." }, function(panel, y)
    local listTop, pool, link = y, rowPool(panel), ignoredLink(panel)
    local function layout()
        local y = link("item", listTop)
        pool:Begin()
        for _, category in ipairs(CATEGORIES) do
            local key, label = category[1], category[2]
            y = pool:Place("category:" .. key, y, function() return {
                label = label,
                enabled = function() return ns.db.categories[key] end,
                toggle = function()
                    ns.db.categories[key] = not ns.db.categories[key]
                    ns.Inventory:Refresh()
                end,
                get = function() return ns.db.reminderPercent[key] end,
                set = function(value) ns.db.reminderPercent[key] = value end,
                result = function() return ns.Inventory:ReminderSummary(key) end,
            } end)
            for _, item in ipairs(ns.Inventory:Choices(key)) do
                local entry = item
                if not ns.db.excludedConsumables[entry.itemID] then
                    y = pool:Place("item:" .. entry.itemID, y, function() return {
                        label = entry.name, icon = entry.icon,
                        enabled = function() return not ns.db.excludedConsumables[entry.itemID] end,
                        toggle = function()
                            ns.db.excludedConsumables[entry.itemID] = (not ns.db.excludedConsumables[entry.itemID]) or nil
                        end,
                        get = function() return ns.Actions:Percent(entry) end,
                        set = function(value) ns.db.reminderPercent.item[entry.itemID] = value end,
                        result = function() return ns.Inventory:ReminderFor(entry) end,
                        changed = function() panel.hcRefreshAll() end,
                    } end)
                end
            end
            y = y - 8
        end
        panel.hcSetBottom(y)
        return y
    end
    UI.OnRefresh(panel, layout)
    return layout()
end)

-- ── Ignored ────────────────────────────────────────────────────────────────

HC.Settings:NewPage({ name = "Ignored", description = "Shift-right-click a bar icon to ignore it." }, function(panel, top)
    local rows = {}
    local empty = UI.FontString(panel, "GameFontHighlightSmall", "muted")
    empty:SetPoint("TOPLEFT", UI.PAD, top)
    empty:SetText("Nothing ignored.")
    local function row(index)
        if rows[index] then return rows[index] end
        local frame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        frame:SetSize(UI.CONTENT_WIDTH, 40)
        T.Surface(frame, "raised", "edge")
        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetSize(28, 28)
        frame.icon:SetPoint("LEFT", 10, 0)
        frame.name = UI.FontString(frame)
        frame.name:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0)
        frame.name:SetWidth(300)
        frame.name:SetJustifyH("LEFT")
        if frame.name.SetWordWrap then frame.name:SetWordWrap(false) end
        frame.kind = UI.FontString(frame, "GameFontHighlightSmall", "muted")
        frame.kind:SetPoint("RIGHT", -110, 0)
        frame.restore = UI.Button(frame, 90, 22)
        frame.restore:SetPoint("RIGHT", -8, 0)
        frame.restore:SetText("Restore")
        rows[index] = frame
        return frame
    end
    local function layout()
        local entries = ns.Actions:IgnoredEntries()
        local y = top
        for index, entry in ipairs(entries) do
            local frame = row(index)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UI.PAD, y)
            frame.icon:SetTexture(entry.icon)
            frame.name:SetText(entry.name)
            frame.kind:SetText(entry.kind == "spell" and "Buff" or "Item")
            frame.restore:SetScript("OnClick", function()
                ns.Actions:Restore(entry.kind, entry.id)
                ns.Inventory:Refresh()
                panel.hcRefreshAll()
                ns.RefreshAll()
            end)
            frame:Show()
            y = y - 46
        end
        for index = #entries + 1, #rows do rows[index]:Hide() end
        empty:SetShown(#entries == 0)
        if #entries == 0 then y = y - 24 end
        panel.hcSetBottom(y)
        return y
    end
    UI.OnRefresh(panel, layout)
    return layout()
end)

-- ── Key Bindings ───────────────────────────────────────────────────────────

HC.Settings:NewPage({ name = "Key Bindings", description = "One key for your next missing buff." }, function(panel, y)
    local card
    card, y = UI.Card(panel, y, 56)
    local name = UI.FontString(card)
    name:SetPoint("TOPLEFT", 16, -12)
    name:SetText("Buff trigger")
    local detail = UI.FontString(card, "GameFontHighlightSmall", "muted")
    detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    detail:SetText("Uses the next icon on the bar.")
    local clear = UI.Button(card, 64, 24)
    clear:SetPoint("RIGHT", -12, 0)
    clear:SetText("Clear")
    local keycap = UI.Button(card, 150, 24)
    keycap:SetPoint("RIGHT", clear, "LEFT", -8, 0)
    UI.AttachHint(keycap, "Buff trigger", "Click, then press a key or scroll the mouse wheel. Esc cancels.")
    local function refresh()
        local label = ns.Bindings:Label("trigger")
        local bound = label ~= "Unbound"
        keycap:SetText(bound and label or "Not bound")
        T.Text(keycap.Text, bound and "text" or "muted")
        T.Border(keycap, bound and "accent" or "edge")
    end
    keycap:SetScript("OnClick", function()
        keycap:SetText("Press a key…")
        ns.Bindings:Capture(function(key, message)
            if not key then
                if message then HC.Print(message) end
                refresh()
                return
            end
            local ok, result = ns.Bindings:Set("trigger", key)
            HC.Print(ok and ("Buff trigger bound to " .. (GetBindingText and GetBindingText(result, "KEY_") or result) .. ".") or result)
            refresh()
        end)
    end)
    clear:SetScript("OnClick", function()
        local ok, message = ns.Bindings:Clear("trigger")
        if not ok then HC.Print(message) end
        refresh()
    end)
    UI.OnRefresh(panel, refresh)
    refresh()
    return y
end)

-- ── Thank You ──────────────────────────────────────────────────────────────

local CHANNELS = { values = { "WHISPER", "SAY", "PARTY", "EMOTE" }, labels = { "Whisper", "Say chat", "Party chat", "Emote" } }

HC.Settings:NewPage({ name = "Thank You", description = "Thank the player who gave you a recognised buff." }, function(panel, y)
    _, y = UI.Check(panel, "Thank players for buffs",
        "Thank an identifiable friendly player for a recognised buff. Buffs you already have never trigger one.", y,
        function() return ns.db.thanksEnabled end, function(value) ns.db.thanksEnabled = value end)
    _, y = UI.Dropdown(panel, "Send thanks as", nil, y, CHANNELS.values, CHANNELS.labels,
        function() return ns.db.thanksChannel end, function(value) ns.db.thanksChannel = value end)
    _, y = UI.Slider(panel, "Delay", "Wait before sending so it feels less robotic. Turning Thank You off cancels a pending one.",
        y, 1, 5, 1, function() return ns.db.thanksDelay end, function(value) ns.db.thanksDelay = value end,
        function(value) return value .. " s" end)

    -- The emote picker and the message field share one row: only the one
    -- matching the chosen channel is shown.
    local emoteRow, messageRow
    emoteRow = UI.SearchPicker(panel, "Emote", "Random picks a different emote each time.", y, {
        width = 220,
        items = function()
            local items = {}
            for _, choice in ipairs(ns.Thanks:EmoteChoices()) do
                items[#items + 1] = { value = choice.token, label = choice.label }
            end
            return items
        end,
        get = function() return ns.db.thanksEmote end,
        set = function(token) ns.db.thanksEmote = token end,
    })
    messageRow, y = UI.TextInput(panel, "Message", "{buff} and {player} are filled in when it is sent.", y,
        function() return ns.db.thanksMessage end,
        function(text) ns.db.thanksMessage = text end, nil, 330)
    local preview = UI.Button(panel, 150, 22)
    preview:SetPoint("TOPLEFT", UI.PAD, y - 2)
    preview:SetText("Preview message")
    preview:SetScript("OnClick", function()
        local sample = (ns.db.thanksMessage or ""):gsub("{buff}", "Power Word: Fortitude")
            :gsub("{player}", UnitName and UnitName("player") or "a friend")
        HC.Print("preview: " .. sample)
    end)
    UI.OnRefresh(panel, function()
        local emote = ns.db.thanksChannel == "EMOTE"
        emoteRow:SetShown(emote)
        messageRow:SetShown(not emote)
        preview:SetShown(not emote)
    end)
    return y - 34
end)
