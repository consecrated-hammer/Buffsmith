local addonName, ns = ...
local HC = ns.HammerCore
local UI, T = HC.UI, HC.Theme

-- Buffsmith's own settings pages.  HammerCore adds the standard Visibility
-- controls, Theme, Commands, Troubleshooting and About.

-- ── Shared row for buffs, consumables and their categories ────────────────
-- Tick, optional icon, name, one-line detail and an optional reminder slider.
-- Clicking anywhere on the row toggles the tick.

local ROW_HEIGHT = 50
-- Items under a consumable category sit in from it, so they read as its group.
local CHILD_INDENT = 28

-- Section heading icons. Old icon paths, so Retail and Forever both have them.
local ICONS = {
    visibility = "Interface\\Icons\\Ability_EyeOfTheOwl",
    appearance = "Interface\\Icons\\INV_Misc_Gear_01",
    tooltips = "Interface\\Icons\\INV_Misc_Note_01",
    targets = "Interface\\Icons\\Spell_Holy_WordFortitude",
    detected = "Interface\\Icons\\Spell_Nature_Regeneration",
    tracking = "Interface\\Icons\\INV_Misc_Flower_02",
    consumables = "Interface\\Icons\\INV_Misc_Food_15",
    thanks = "Interface\\Icons\\INV_Letter_15",
    ignored = "Interface\\Icons\\INV_Misc_Bag_08",
}

-- The header button on pages that change how the bar looks.
local PREVIEW_ACTION = {
    text = function() return ns.Preview:IsShown() and "Hide preview" or "Preview on screen" end,
    onClick = function() ns.Preview:Toggle() end,
    hint = "Show the bar with sample icons where it sits on screen, so you can see size and direction.",
}
local TEXT_WIDTH = 210
local SLIDER_X = 330

local function reminderRow(panel, y, item)
    local row = CreateFrame("Button", nil, panel, "BackdropTemplate")
    row:SetPoint("TOPLEFT", UI.PAD, y)
    row.indent = item.indent or 0
    row:SetSize(UI.CONTENT_WIDTH - row.indent, ROW_HEIGHT)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()

    local tick
    if T.IsClassic() then
        tick = UI.CheckButton(row)
        tick:SetPoint("LEFT", 12, 0)
    else
        -- Just the switch's track: the row's own name sits beside it.
        tick = UI.Switch(row)
        tick:SetSize(40 + UI.CELL_INSET, 20)
        tick:SetPoint("LEFT", 0, 0)
    end
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
    name:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, (item.icon and not item.caveat) and 0 or 6)
    name:SetWidth(TEXT_WIDTH - row.indent)
    name:SetJustifyH("LEFT")
    if name.SetWordWrap then name:SetWordWrap(false) end
    name:SetText(item.label)
    local detail = UI.FontString(row, "GameFontHighlightSmall", "muted")
    detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    detail:SetWidth(TEXT_WIDTH - row.indent)
    detail:SetJustifyH("LEFT")
    if detail.SetWordWrap then detail:SetWordWrap(false) end
    local caveat
    if item.caveat then
        caveat = UI.FontString(row, "GameFontHighlightSmall", "muted")
        caveat:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -3)
        caveat:SetJustifyH("LEFT")
        if caveat.SetWordWrap then caveat:SetWordWrap(false) end
        caveat:SetText(item.caveat)
    end

    local slider, percent
    if not item.permanent then
        slider = CreateFrame("Slider", nil, row)
        slider:SetOrientation("HORIZONTAL")
        slider:SetSize(140, 16)
        -- Sliders line up down the page, indented row or not.
        slider:SetPoint("LEFT", SLIDER_X - row.indent, 0)
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
        UI.AttachHint(slider, "Reminder", item.resourceRecovery
            and "Remind below this health or mana percentage, while the ability is ready."
            or "Remind when this share of the effect's duration is left.")
    end

    local changing = false
    local function refresh()
        tick:SetChecked(item.enabled())
        if caveat then caveat:SetShown(item.enabled()) end
        if item.detail then
            detail:SetText(item.detail)
        elseif item.permanent then
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
    if item.hint then UI.AttachHint(row, item.label, item.hint) end
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
        self.count = 0
    end
    function pool:Place(key, y, build)
        local frame = self.frames[key]
        if not frame then
            frame = reminderRow(panel, y, build())
            self.frames[key] = frame
        end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UI.PAD + frame.indent, y)
        self.count = (self.count or 0) + 1
        T.Fill(frame.stripe, self.count % 2 == 1 and "stripe" or "content")
        frame:Show()
        frame.refresh()
        return y - ROW_HEIGHT - 2
    end
    return pool
end

-- "View ignored (N)", shown only while something of this kind is ignored.
local function ignoredLink(panel)
    local button = UI.Link(panel, "", function() HC.Settings:Show("Ignored") end, "GameFontHighlight")
    return function(kind, y)
        local count = 0
        for _, entry in ipairs(ns.Actions:IgnoredEntries()) do
            if entry.kind == kind then count = count + 1 end
        end
        button:SetShown(count > 0)
        if count == 0 then return y end
        button:SetText("View ignored (" .. count .. ")")
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", UI.PAD + 2, y - 4)
        return y - 28
    end
end

-- ── Visibility: HammerCore's standard page plus the bar's own rules ───────

HC.Settings:AddVisibility()
HC.spec.visibility = function(panel, y)
    _, y = UI.Header(panel, "Bar", y, ICONS.visibility)
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
    _, y = UI.Slider(panel, "Food after stopping",
        "Food hides while you move, since moving wastes it. Seconds to stand still before it comes back.",
        y, 0, 15, 1, function() return ns.db.foodStillSeconds end,
        function(value) ns.Set("foodStillSeconds", value) end,
        function(value) return value .. " s" end)
    return y
end

-- ── Appearance ─────────────────────────────────────────────────────────────

HC.Settings:NewPage({ name = "Appearance", description = "Size, direction and the drag handle.",
    headerAction = PREVIEW_ACTION }, function(panel, y)
    _, y = UI.Header(panel, "Bar", y, ICONS.appearance)
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
    _, y = UI.ActionButton(panel, y, "Reset bar position", function() HC.Commands:Dispatch("reset position") end,
        "Put the bar back in its starting place.")
    return y
end)

-- ── Tooltips ───────────────────────────────────────────────────────────────

HC.Settings:NewPage({ name = "Tooltips", description = "Who a buff is for, and what it does." }, function(panel, y)
    _, y = UI.Header(panel, "Bar tooltip", y, ICONS.tooltips)
    _, y = UI.Check(panel, "Show bar tooltips", "Show buff names, recipients and click instructions when hovering a bar icon.", y,
        function() return ns.db.showTooltip end,
        function(value) ns.Set("showTooltip", value) end)
    _, y = UI.Check(panel, "Show spell descriptions", "Add Blizzard's static description for the offered spell. This can make the tooltip taller.", y,
        function() return ns.db.tooltipSpellDescriptions end,
        function(value) ns.Set("tooltipSpellDescriptions", value) end)
    return y
end)

-- ── Buffs ──────────────────────────────────────────────────────────────────

HC.Settings:NewPage({ name = "Buffs", description = "Who Buffsmith checks, and when each buff reminds you.",
    headerAction = PREVIEW_ACTION }, function(panel, y)
    _, y = UI.Header(panel, "Targets", y, ICONS.targets)
    _, y = UI.Check(panel, "Friendly target", "Show targetable buffs your selected friendly player is missing.", y,
        function() return ns.db.showTargetBuffs end, function(value) ns.Set("showTargetBuffs", value) end)
    _, y = UI.Check(panel, "Party members", "Show targetable buffs party members are missing.", y,
        function() return ns.db.showPartyBuffs end, function(value) ns.Set("showPartyBuffs", value) end)
    _, y = UI.Check(panel, "Friendly pets", "Show targetable buffs for your pet and party pets.", y,
        function() return ns.db.showPetBuffs end, function(value) ns.Set("showPetBuffs", value) end)
    _, y = UI.Check(panel, "Skip PvP-flagged players while I'm unflagged", "Skip flagged targets, party members and pets while you're unflagged. Unreadable PvP flags also skip that recipient. Self buffs still work.", y,
        function() return ns.db.skipPvPWhileUnflagged end, function(value) ns.Set("skipPvPWhileUnflagged", value) end)
    _, y = UI.Check(panel, "Party coverage", "Show class buffs a party member may provide. These report to chat; they never cast.", y,
        function() return ns.db.showPartyCoverage end, function(value) ns.Set("showPartyCoverage", value) end)
    _, y = UI.Header(panel, "Detected buffs", y, ICONS.detected)
    _, y = UI.Text(panel, "Short buffs are off by default.", y)
    local listTop, pool, link = y, rowPool(panel), ignoredLink(panel)
    local none = UI.FontString(panel, "GameFontHighlightSmall", "muted")
    none:SetText("No self-buffs found for your class and level yet.")
    -- Placed by layout() as the list changes, so it can't be a UI.Header;
    -- it copies that look.
    local trackingHeader = UI.FontString(panel, "GameFontNormalSmall", "section")
    trackingHeader:SetText("TRACKING")
    local trackingRule = panel:CreateTexture(nil, "ARTWORK")
    trackingRule:SetSize(18, 18)
    if trackingRule.SetTexCoord then trackingRule:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    trackingRule:SetTexture(ICONS.tracking)
    local trackingNote = UI.FontString(panel, "GameFontHighlightSmall", "muted")
    trackingNote:SetText("Choose Herbs or Minerals. WoW Forever tracks one at a time.")
    local function layout()
        local y = link("spell", listTop)
        pool:Begin()
        local shown = 0
        for _, buff in ipairs(ns.KnownSelfBuffCandidates()) do
            local entry = buff
            if ns.db.excludedBuffs[entry.spellID] ~= true then
                shown = shown + 1
                y = pool:Place(entry.spellID .. ":" .. entry.castID, y, function() return {
                    label = entry.name,
                    icon = entry.icon, permanent = entry.permanent, resourceRecovery = entry.resourceRecovery,
                    caveat = entry.resourceRecovery and "In a group: shows only, no click or key" or nil,
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

        -- Tracking this character has, from the minimap's own list.
        local tracking = {}
        for _, entry in ipairs(ns.Tracking:Available()) do
            -- On Forever this is a picker, not the old independent set of
            -- ticks.  Retained pre-picker exclusions must not hide Minerals
            -- and make it impossible to choose it again.
            if ns.Tracking.Exclusive() or ns.db.excludedBuffs[entry.spellID] ~= true then
                tracking[#tracking + 1] = entry
            end
        end
        trackingRule:ClearAllPoints()
        trackingRule:SetPoint("TOPLEFT", UI.PAD + 2, y - 10 + 3)
        trackingHeader:ClearAllPoints()
        trackingHeader:SetPoint("LEFT", trackingRule, "RIGHT", 6, 0)
        if tracking[1] and tracking[1].icon then trackingRule:SetTexture(tracking[1].icon) end
        trackingHeader:SetShown(#tracking > 0)
        trackingRule:SetShown(#tracking > 0)
        trackingNote:ClearAllPoints()
        trackingNote:SetPoint("TOPLEFT", UI.PAD + 2, y - 34)
        trackingNote:SetShown(#tracking > 0 and ns.Tracking.Exclusive())
        if #tracking > 0 then
            y = y - 32 - (ns.Tracking.Exclusive() and 22 or 0)
            for _, found in ipairs(tracking) do
                local entry = found
                y = pool:Place("tracking:" .. entry.spellID, y, function() return {
                    label = entry.name, icon = entry.icon, permanent = true, detail = "Tracking",
                    enabled = function()
                        return ns.Tracking.Exclusive() and ns.Tracking:SelectedID() == entry.spellID
                            or not ns.Tracking.Exclusive() and not ns.IsBuffExcluded(entry)
                    end,
                    toggle = function()
                        if ns.Tracking.Exclusive() then
                            ns.Tracking:Select(entry.spellID)
                        else
                            ns.db.excludedBuffs[entry.spellID] = not ns.IsBuffExcluded(entry)
                        end
                    end,
                    changed = function() panel.hcRefreshAll() end,
                } end)
            end
        end
        panel.hcSetBottom(y)
        return y
    end
    UI.OnRefresh(panel, layout)
    return layout()
end)

-- ── Consumables ────────────────────────────────────────────────────────────

local CATEGORIES = { { "food", "Food" }, { "scroll", "Scrolls" }, { "flask", "Flasks" }, { "other", "Other buffs" }, { "weapon", "Weapon enhancements" } }

HC.Settings:NewPage({ name = "Consumables", columns = 1, description = "Items appear while they are in your bags.",
    headerAction = PREVIEW_ACTION }, function(panel, y)
    _, y = UI.Header(panel, "Categories and items", y, ICONS.consumables)
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
            for _, item in ipairs(ns.Inventory:OwnedChoices(key)) do
                local entry = item
                if not ns.db.excludedConsumables[entry.itemID] then
                    y = pool:Place("item:" .. entry.itemID, y, function() return {
                        label = entry.name, icon = entry.icon, indent = CHILD_INDENT,
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
            y = y - 10
        end
        panel.hcSetBottom(y)
        return y
    end
    UI.OnRefresh(panel, layout)
    return layout()
end)

-- ── Ignored ────────────────────────────────────────────────────────────────

HC.Settings:NewPage({ name = "Ignored", columns = 1, description = "Shift-right-click a bar icon to ignore it." }, function(panel, top)
    _, top = UI.Header(panel, "Ignored buffs and items", top, ICONS.ignored)
    local rows = {}
    local empty = UI.FontString(panel, "GameFontHighlightSmall", "muted")
    empty:SetPoint("TOPLEFT", UI.PAD, top)
    empty:SetText("Nothing ignored.")
    local function row(index)
        if rows[index] then return rows[index] end
        local frame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        frame:SetSize(UI.CONTENT_WIDTH, 40)
        frame.stripe = frame:CreateTexture(nil, "BACKGROUND")
        frame.stripe:SetAllPoints()
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
            T.Fill(frame.stripe, index % 2 == 1 and "stripe" or "content")
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
            y = y - 42
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

-- HammerCore's shared page: one item, the Buff trigger, plus the wheel-zoom
-- option once it's bound to a mouse wheel that used to zoom the camera.
local TRIGGER = {
    id = "trigger", name = "Buff trigger", icon = "Interface\\AddOns\\Buffsmith\\Textures\\BuffsmithLogo",
    detail = "Uses the next icon on the bar.",
}

HC.Settings:NewPage({ name = "Key Bindings", columns = 1, description = "One key for your next missing buff." }, function(panel, y)
    local function key()
        local command = ns.Bindings:Command("trigger")
        return GetBindingKey and GetBindingKey(command) or nil
    end
    y = HC.Bindings.Page(panel, y, {
        inputs = { keys = true, mouse = true, wheel = true },
        empty = "Not bound yet. Pick the Buff trigger on the right.",
        poolHint = "Click it, then press a key, mouse button or wheel.",
        pool = function() return { { title = "Buffsmith", items = { TRIGGER } } } end,
        bound = function()
            local bound = key()
            if not bound then return {} end
            return { { id = TRIGGER.id, name = TRIGGER.name, icon = TRIGGER.icon, key = bound } }
        end,
        bind = function(_, pressed)
            local ok, result = ns.Bindings:Set("trigger", pressed)
            if not ok then return false, result end
            HC.Print("Buff trigger bound to " .. HC.Bindings.Label(result) .. ".")
            return true
        end,
        unbind = function()
            local ok, message = ns.Bindings:Clear("trigger")
            if not ok and message then HC.Print(message) end
        end,
    })
    local zoomRow
    zoomRow, y = UI.Check(panel, "Also zoom in/out",
        "Keep this wheel key's previous camera action as well as triggering Buffsmith. Clearing the binding restores camera zoom.", y,
        function() local zoom = ns.Bindings:WheelZoom(); return zoom and zoom.enabled end,
        function(value)
            local ok, message = ns.Bindings:SetWheelZoom(value)
            if not ok then HC.Print(message) end
        end)
    -- As wide as the Active bindings pane above it, not the whole page.
    local zoomWidth = math.floor(UI.CONTENT_WIDTH * 0.42)
    zoomRow:SetWidth(zoomWidth)
    if zoomRow.hcStripe then zoomRow.hcStripe:SetWidth(zoomWidth) end
    UI.OnRefresh(panel, function()
        local zoom = ns.Bindings:WheelZoom()
        -- The bound list grows once the trigger is bound: stay below it.
        local bottom = panel.hcBindingsLayout()
        zoomRow:ClearAllPoints()
        zoomRow:SetPoint("TOPLEFT", UI.PAD, bottom)
        if zoom and panel.hcSetBottom then panel.hcSetBottom(bottom - UI.CELL_H - 4) end
        zoomRow:SetShown(zoom ~= nil)
        zoomRow.hcCheckbox.Text:SetText(zoom and (zoom.action == "CAMERAZOOMIN" and "Also zoom in" or "Also zoom out") or "Also zoom in/out")
    end)
    return y
end)

-- ── Thank You ──────────────────────────────────────────────────────────────

local CHANNELS = { values = { "WHISPER", "SAY", "PARTY", "EMOTE" }, labels = { "Whisper", "Say chat", "Party chat", "Emote" } }

HC.Settings:NewPage({ name = "Thank You", description = "Thank recognised buffs when the client can identify their caster." }, function(panel, y)
    _, y = UI.Header(panel, "Thanks", y, ICONS.thanks)
    _, y = UI.Check(panel, "Thank players for buffs",
        "Caster details can be unavailable on WoW Forever, so a thank-you is not guaranteed. Buffs you already have never trigger one.", y,
        function() return ns.db.thanksEnabled end, function(value) ns.Thanks:SetEnabled(value) end)
    _, y = UI.Check(panel, "Skip party and raid members",
        "Skip thanks when the identified caster is in your party or raid. Unknown-caster emotes still follow their own setting.", y,
        function() return ns.db.thanksSkipGroupMembers end, function(value) ns.db.thanksSkipGroupMembers = value end)
    _, y = UI.Dropdown(panel, "Send thanks as", nil, y, CHANNELS.values, CHANNELS.labels,
        function() return ns.db.thanksChannel end, function(value) ns.db.thanksChannel = value end)
    _, y = UI.Slider(panel, "Delay", "Wait before sending so it feels less robotic. Turning Thank You off cancels a pending one.",
        y, 1, 5, 1, function() return ns.db.thanksDelay end, function(value) ns.db.thanksDelay = value end,
        function(value) return value .. " s" end)

    -- The emote picker and the message field share one row: only the one
    -- matching the chosen channel is shown. One column, so they overlap
    -- exactly instead of pairing up.
    _, y = UI.Header(panel, "What to send", y, "Interface\\Icons\\Spell_Holy_Heal")
    y = UI.Columns(panel, 1, y)
    local emoteRow, messageRow, unknownEmoteRow, unknownEmoteNote
    local emoteY, messageY
    emoteRow, emoteY = UI.SearchPicker(panel, "Emote", "Random picks a different emote each time.", y, {
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
    unknownEmoteRow, emoteY = UI.Check(panel, "Emote when caster is unknown",
        "Use the selected emote without a target when the caster cannot be identified.", emoteY,
        function() return ns.db.thanksUnknownEmote end, function(value) ns.db.thanksUnknownEmote = value end)
    -- This is intentionally the one wrapped explanation on the page: the
    -- limitation needs plain language, not a clipped tooltip.
    unknownEmoteNote = UI.FontString(panel, "GameFontHighlightSmall", "muted")
    unknownEmoteNote:SetPoint("TOPLEFT", UI.PAD, emoteY)
    unknownEmoteNote:SetWidth(UI.CONTENT_WIDTH)
    unknownEmoteNote:SetJustifyH("LEFT")
    if unknownEmoteNote.SetWordWrap then unknownEmoteNote:SetWordWrap(true) end
    unknownEmoteNote:SetText("WoW Forever may report a new buff without telling addons who cast it. Friendly player nameplates can help identify the caster. Whispers still need a known caster.")
    emoteY = emoteY - 36
    messageRow, messageY = UI.TextInput(panel, "Message", "{buff} and {player} are filled in when it is sent.", y,
        function() return ns.db.thanksMessage end,
        function(text) ns.db.thanksMessage = text end, nil, 330)
    y = math.min(emoteY, messageY)
    local preview
    preview, y = UI.ActionButton(panel, y, "Preview message", function()
        local sample = (ns.db.thanksMessage or ""):gsub("{buff}", "Power Word: Fortitude")
            :gsub("{player}", UnitName and UnitName("player") or "a friend")
        HC.Print("preview: " .. sample)
    end, "Print the message to your own chat with a sample buff.")
    UI.OnRefresh(panel, function()
        local emote = ns.db.thanksChannel == "EMOTE"
        local unknownFallback = emote and ns.TARGET == "Camelot"
        emoteRow:SetShown(emote)
        unknownEmoteRow:SetShown(unknownFallback)
        unknownEmoteNote:SetShown(unknownFallback)
        messageRow:SetShown(not emote)
        preview:SetShown(not emote)
    end)
    return y
end)
