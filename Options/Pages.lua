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
    text = function() return ns.Preview:IsShown() and "Hide preview" or "Show live preview" end,
    onClick = function() ns.Preview:Toggle() end,
    hint = "Show the bar with sample icons where it sits on screen, so you can see size and direction.",
}
-- Sections share the body search index and refresh list. Hidden sections
-- point search at the switch that enables them.
local function section(panel, parentRow, columns)
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetSize(UI.CONTENT_WIDTH + UI.PAD * 2, 1)
    frame.hcColumns = columns or 2
    frame.hcHeaderOwner = panel.hcHeaderOwner or panel
    frame.hcRefresh, frame.hcRefreshAll = panel.hcRefresh, panel.hcRefreshAll
    frame.hcParentRow = parentRow
    return frame
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end

local function resetKeys(keys)
    for _, key in ipairs(keys) do
        ns.db[key] = copy(ns.defaults[key])
    end
    ns.RefreshAll()
end

local function flow(panel)
    local entries = {}
    local function add(fill, visible, parentRow, columns)
        local frame = section(panel, parentRow, columns)
        local bottom, result = fill(frame, -4)
        entries[#entries + 1] = { frame = frame, height = -UI.Flush(frame, bottom) + 4, visible = visible }
        return result
    end
    UI.OnRefresh(panel, function()
        local y = -8
        for _, entry in ipairs(entries) do
            local shown = not entry.visible or entry.visible()
            entry.frame:SetShown(shown)
            if shown then
                entry.frame:ClearAllPoints()
                entry.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
                entry.frame:SetHeight(entry.height)
                y = y - entry.height
            end
        end
        panel.hcSetBottom(y - 8)
    end)
    return add
end

local TEXT_WIDTH = 210
local SLIDER_X = 330

-- A single label explains the aligned duration sliders on each reminder list.
local function reminderHeading(panel, y)
    local heading = UI.FontString(panel, "GameFontHighlightSmall", "muted")
    heading:SetPoint("TOPLEFT", UI.PAD + SLIDER_X, y - 4)
    heading:SetWidth(UI.CONTENT_WIDTH - SLIDER_X)
    heading:SetJustifyH("LEFT")
    if heading.SetWordWrap then heading:SetWordWrap(false) end
    heading:SetText("Remind when this much time is left")
    UI.AttachTitleHint(panel, heading, "Reminder thresholds",
        "Most sliders use remaining buff time. Permanent buffs have no slider; Read Leyline uses health or mana instead.")
    panel.reminderHeading = heading
    return y - 24
end

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
        if panel.hcRefreshAll then panel.hcRefreshAll() end
    end)
    if item.hint then UI.AttachHint(row, item.label, item.hint) end
    refresh()
    row.refresh = refresh
    UI.RegisterRow(panel, row, item.label)
    row.hcHint = item.hint or "Enable missing buff reminder threshold priority"
    if slider then
        slider.hcParentRow = row
        UI.RegisterRow(panel, slider, item.label .. " reminder threshold")
        slider.hcHint = item.resourceRecovery and "Health or mana percent" or "Remaining duration percent"
        UI.OnRefresh(panel, function() slider:SetShown(item.enabled()); percent:SetShown(item.enabled()) end)
    end
    UI.OnRefresh(panel, refresh)
    return row
end

-- Rows whose set changes while the page exists (ignoring, learning a spell,
-- looting an item).  One frame per key, re-anchored on every layout.
local function rowPool(panel)
    local pool = { frames = {} }
    function pool:Begin()
        for _, frame in pairs(self.frames) do frame:Hide(); frame.hcParentRow = nil end
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
        frame.hcParentRow = self.parentRow
        local shown = not self.visible or self.visible()
        frame:SetShown(shown)
        frame.refresh()
        return shown and (y - ROW_HEIGHT - 2) or y
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
    _, y = UI.PageReset(panel, y, function()
        ns.db.legacyVisibility = nil
        resetKeys({ "visibilityMode", "visibility", "ignoreBuffsInRestedAreas" })
    end, "Reset bar visibility")
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
        "Drag the grip above the bar to move it. Right-click it for the menu.", y,
        function() return ns.db.showHandle end,
        function(value)
            ns.db.showHandle = value
            ns.Handle:Update()
        end)
    y = UI.Columns(panel, 1, y)
    _, y = UI.ActionButton(panel, y, "Re-centre bar", function() HC.Commands:Dispatch("reset position") end,
        "Put the bar back in its starting place.")
    _, y = UI.PageReset(panel, y, function()
        resetKeys({ "orientation", "flyoutVerticalDirection", "flyoutHorizontalDirection", "iconSize", "maxAlternatives", "showHandle" })
        ns.Handle:Update()
    end, "Reset appearance")
    return y
end)

-- ── Tooltips ───────────────────────────────────────────────────────────────

HC.Settings:NewPage({ name = "Tooltips", description = "Who a buff is for, and what it does." }, function(panel, y)
    _, y = UI.Header(panel, "Bar tooltip", y, ICONS.tooltips)
    local master
    master, y = UI.Check(panel, "Show bar tooltips", "Show buff names, recipients and click instructions when hovering a bar icon.", y,
        function() return ns.db.showTooltip end,
        function(value) ns.Set("showTooltip", value) end)
    y = UI.Columns(panel, 1, y)
    local top = y
    local children = section(panel, master)
    local childY = -4
    _, childY = UI.Check(children, "Show spell descriptions", "Add Blizzard's static description for the offered spell. This can make the tooltip taller.", childY,
        function() return ns.db.tooltipSpellDescriptions end,
        function(value) ns.Set("tooltipSpellDescriptions", value) end)
    _, childY = UI.Check(children, "Show item effects", "Show what food, flasks and other bag items give you, such as the Well Fed buff.", childY,
        function() return ns.db.tooltipItemEffects end,
        function(value) ns.Set("tooltipItemEffects", value) end)
    local reset
    reset, y = UI.PageReset(panel, top, function()
        resetKeys({ "showTooltip", "tooltipSpellDescriptions", "tooltipItemEffects" })
    end, "Reset tooltips")
    UI.OnRefresh(panel, function()
        children:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, top)
        children:SetHeight(-UI.Flush(children, childY) + 4)
        children:SetShown(ns.db.showTooltip)
        reset:ClearAllPoints()
        local bottom = ns.db.showTooltip and (top + childY - 4) or top
        reset:SetPoint("TOPLEFT", UI.PAD, bottom - 10)
        panel.hcSetBottom(bottom - UI.CELL_H - 16)
    end)
    return y
end)

-- ── Buffs ──────────────────────────────────────────────────────────────────

local function buildTargets(panel, y)
    _, y = UI.Header(panel, "Who to buff", y, ICONS.targets)
    _, y = UI.Check(panel, "Your friendly target", "Show targetable buffs your selected friendly player is missing.", y,
        function() return ns.db.showTargetBuffs end, function(value) ns.Set("showTargetBuffs", value) end)
    _, y = UI.Check(panel, "Your party", "Show targetable buffs party members are missing.", y,
        function() return ns.db.showPartyBuffs end, function(value) ns.Set("showPartyBuffs", value) end)
    _, y = UI.Check(panel, "Pets", "Show targetable buffs for your pet and party pets.", y,
        function() return ns.db.showPetBuffs end, function(value) ns.Set("showPetBuffs", value) end)
    _, y = UI.Check(panel, "Skip PvP-flagged players", "While you're not flagged, don't offer buffs for flagged players or pets, so you don't flag yourself. Your own buffs still show.", y,
        function() return ns.db.skipPvPWhileUnflagged end, function(value) ns.Set("skipPvPWhileUnflagged", value) end)
    _, y = UI.Check(panel, "Buffs others could cast", "Shows party buffs someone else's class brings and nobody has cast. Clicking one mentions it in chat. It never casts.", y,
        function() return ns.db.showPartyCoverage end, function(value) ns.Set("showPartyCoverage", value) end)
    _, y = UI.PageReset(panel, y, function()
        resetKeys({ "showTargetBuffs", "showPartyBuffs", "showPetBuffs", "skipPvPWhileUnflagged", "showPartyCoverage" })
    end, "Reset targets")
    return y
end

local function buildReminders(panel, y)
    _, y = UI.Header(panel, "Your buffs", y, ICONS.detected)
    _, y = UI.Text(panel, "Buffsmith found these on this character. Short ones start switched off.", y)
    y = reminderHeading(panel, y)
    local listTop, pool, link = y, rowPool(panel), ignoredLink(panel)
    local none = UI.FontString(panel, "GameFontHighlightSmall", "muted")
    none:SetText("No self-buffs found for your class and level yet.")
    local reset = UI.PageReset(panel, y, function()
        for _, entry in ipairs(ns.KnownSelfBuffCandidates()) do
            ns.db.excludedBuffs[entry.spellID] = nil
            ns.db.reminderPercent.buffBySpell[entry.spellID] = nil
        end
        ns.RefreshAll()
    end, "Reset reminders")
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
                } end)
            end
        end
        none:ClearAllPoints()
        none:SetPoint("TOPLEFT", UI.PAD, y)
        none:SetShown(shown == 0)
        if shown == 0 then y = y - 24 end

        reset:ClearAllPoints()
        reset:SetPoint("TOPLEFT", UI.PAD, y - 10)
        y = y - 48
        panel.hcSetBottom(y)
        return y
    end
    UI.OnRefresh(panel, layout)
    return layout()
end

local function buildTracking(panel, y)
    local listTop, pool = y, rowPool(panel)
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
    local reset = UI.PageReset(panel, y, function()
        for _, entry in ipairs(ns.Tracking:Available()) do ns.db.excludedBuffs[entry.spellID] = nil end
        ns.db.trackingChoice = nil
        ns.RefreshAll()
    end, "Reset tracking")
    local function layout()
        local y = listTop
        pool:Begin()
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
                } end)
            end
        end
        reset:ClearAllPoints()
        reset:SetPoint("TOPLEFT", UI.PAD, y - 10)
        y = y - 48
        panel.hcSetBottom(y)
        return y
    end
    UI.OnRefresh(panel, layout)
    return layout()
end

HC.Settings:NewPage({ name = "Buffs", description = "Choose reminders, recipients and tracking.",
    headerAction = PREVIEW_ACTION, columns = 1, tabs = {
        { name = "Reminders", build = buildReminders },
        { name = "Targets", columns = 2, build = buildTargets },
        { name = "Tracking", build = buildTracking },
    } })


-- ── Consumables ────────────────────────────────────────────────────────────

local CATEGORIES = { { "food", "Food" }, { "scroll", "Scrolls" }, { "flask", "Flasks" }, { "other", "Other buffs" }, { "weapon", "Weapon enhancements" } }

HC.Settings:NewPage({ name = "Consumables", columns = 1, description = "Items appear while they are in your bags.",
    headerAction = PREVIEW_ACTION }, function(panel, y)
    _, y = UI.Slider(panel, "Show food after standing still",
        "Food hides while you move, since moving wastes it. Seconds to stand still before it comes back.",
        y, 0, 15, 1, function() return ns.db.foodStillSeconds end,
        function(value) ns.Set("foodStillSeconds", value) end,
        function(value) return value .. " s" end)
    _, y = UI.Header(panel, "Categories and items", y, ICONS.consumables)
    y = reminderHeading(panel, y)
    local listTop, pool, link = y, rowPool(panel), ignoredLink(panel)
    local reset = UI.PageReset(panel, y, function()
        resetKeys({ "categories", "foodStillSeconds" })
        for _, key in ipairs({ "food", "scroll", "flask", "other", "weapon" }) do
            ns.db.reminderPercent[key] = ns.defaults.reminderPercent[key]
        end
        -- Item choices and ignored items belong to the player, not this reset.
        ns.db.reminderPercent.item = {}
        ns.Inventory:Refresh()
    end, "Reset consumable reminders")
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
            local categoryRow = pool.frames["category:" .. key]
            pool.parentRow = categoryRow
            pool.visible = function() return ns.db.categories[key] end
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
                        } end)
                end
            end
            pool.parentRow, pool.visible = nil, nil
            y = y - 10
        end
        reset:ClearAllPoints()
        reset:SetPoint("TOPLEFT", UI.PAD, y - 10)
        y = y - 48
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
        local owner = panel.hcHeaderOwner or panel
        for _, frame in ipairs(rows) do
            if frame.searchLabel then owner.hcRows[frame.searchLabel] = nil end
        end
        local entries = ns.Actions:IgnoredEntries()
        local y = top
        for index, entry in ipairs(entries) do
            local frame = row(index)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UI.PAD, y)
            T.Fill(frame.stripe, index % 2 == 1 and "stripe" or "content")
            frame.icon:SetTexture(entry.icon)
            frame.searchLabel = "Restore " .. entry.name .. " (" .. entry.kind .. " " .. entry.id .. ")"
            UI.RegisterRow(panel, frame, frame.searchLabel)
            frame.hcHint = "Ignored excluded buff item restore"
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

-- HammerCore's shared page: one item, the Next buff key, plus the wheel-zoom
-- option once it's bound to a mouse wheel that used to zoom the camera.
local TRIGGER = {
    id = "trigger", name = "Next buff key", icon = "Interface\\AddOns\\Buffsmith\\Textures\\BuffsmithLogo",
    detail = "Uses the next icon on the bar.",
}

HC.Settings:NewPage({ name = "Key Bindings", columns = 1, description = "One key for your next missing buff." }, function(panel, y)
    local function key()
        local command = ns.Bindings:Command("trigger")
        return GetBindingKey and GetBindingKey(command) or nil
    end
    y = HC.Bindings.Page(panel, y, {
        inputs = { keys = true, mouse = true, wheel = true },
        empty = "Not bound yet. Pick the Next buff key on the right.",
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
            HC.Print("Next buff key bound to " .. HC.Bindings.Label(result) .. ".")
            return true
        end,
        unbind = function()
            local ok, message = ns.Bindings:Clear("trigger")
            if not ok and message then HC.Print(message) end
        end,
    })
    local owner = panel.hcHeaderOwner or panel
    local available = owner.hcRows and owner.hcRows.Available
    if available then available.hcHint = "Next buff key key mouse wheel binding" end
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
    zoomRow.hcParentRow = available
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

HC.Settings:NewPage({ name = "Thank You", description = "Optional replies when someone buffs you." }, function(panel)
    local add = flow(panel)
    local master = add(function(frame, y)
        local row
        row, y = UI.Check(frame, "Thank players for buffs",
            "Off by default. Caster details can be unavailable, especially on WoW Forever. Existing buffs never trigger thanks.", y,
            function() return ns.db.thanksEnabled end, function(value) ns.Thanks:SetEnabled(value) end)
        return y, row
    end)
    local function enabled() return ns.db.thanksEnabled end
    local channel = add(function(frame, y)
        _, y = UI.Header(frame, "Delivery", y, ICONS.thanks)
        local row
        row, y = UI.Dropdown(frame, "Send thanks as", "Choose a private reply, chat message or emote.", y, CHANNELS.values, CHANNELS.labels,
            function() return ns.db.thanksChannel end, function(value) ns.db.thanksChannel = value end)
        _, y = UI.Check(frame, "Skip party and raid members",
            "Skip identified group casters. Unknown-caster emotes follow their own setting.", y,
            function() return ns.db.thanksSkipGroupMembers end, function(value) ns.db.thanksSkipGroupMembers = value end)
        _, y = UI.Slider(frame, "Thank-you delay", "Wait before sending. Turning Thank You off cancels pending replies.", y, 1, 5, 1,
            function() return ns.db.thanksDelay end, function(value) ns.db.thanksDelay = value end,
            function(value) return value .. " s" end)
        return y, row
    end, enabled, master)
    local emote = add(function(frame, y)
        local row
        row, y = UI.SearchPicker(frame, "Emote", "Random picks a different emote each time.", y, {
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
        return y, row
    end, function() return enabled() and ns.db.thanksChannel == "EMOTE" end, channel, 1)
    add(function(frame, y)
        _, y = UI.Check(frame, "Emote when caster is unknown",
            "WoW Forever may report a new buff without telling addons who cast it. Friendly player nameplates can help identify the caster. Whispers still need a known caster.", y,
            function() return ns.db.thanksUnknownEmote end, function(value) ns.db.thanksUnknownEmote = value end)
        return y
    end, function() return enabled() and ns.db.thanksChannel == "EMOTE" and ns.TARGET == "Camelot" end, emote, 1)
    add(function(frame, y)
        local preview
        local function showSample()
            local sample = (ns.db.thanksMessage or ""):gsub("{buff}", "Power Word: Fortitude")
                :gsub("{player}", function() return UnitName and UnitName("player") or "a friend" end)
            if preview then preview:SetText("Sample: " .. sample) end
        end
        _, y = UI.TextInput(frame, "Message", "{buff} and {player} are filled in when sent.", y,
            function() return ns.db.thanksMessage end,
            function(text) ns.db.thanksMessage = text; showSample() end, nil, 330)
        y = UI.Columns(frame, 1, y)
        preview, y = UI.Text(frame, "", y)
        panel.thanksPreview = preview
        UI.OnRefresh(frame, showSample)
        showSample()
        return y
    end, function() return enabled() and ns.db.thanksChannel ~= "EMOTE" end, channel, 1)
    add(function(frame, y)
        _, y = UI.PageReset(frame, y, function()
            ns.Thanks:SetEnabled(false)
            resetKeys({ "thanksEnabled", "thanksChannel", "thanksEmote", "thanksUnknownEmote", "thanksSkipGroupMembers", "thanksDelay", "thanksMessage" })
        end, "Reset thank you")
        return y
    end)
    return -8
end)

-- Put the setup path first; reference pages retain HammerCore's ordering.
HC.Settings:AddVisibility()
local order = { Buffs = 1, Consumables = 2, ["Key Bindings"] = 3, Appearance = 4,
    Tooltips = 5, ["Thank You"] = 6, Ignored = 7, Visibility = 8 }
table.sort(HC.Settings.queue, function(a, b)
    return (order[a.name] or 100) < (order[b.name] or 100)
end)

-- Keep the dynamic lists and their search registrations current even while
-- another page is selected. Inventory refresh also covers spell/tracking events.
function ns.RefreshSettings()
    if not HC.Settings:IsShown() then return end
    for _, name in ipairs({ "Buffs", "Consumables", "Ignored" }) do
        local page = HC.Settings.pages[name]
        if page and page.hcRefreshAll then page.hcRefreshAll() end
    end
end
