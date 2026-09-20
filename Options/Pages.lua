local addonName, ns = ...
local Options = ns.Options

Options.pageSpecs = {
    { id = "overview", label = "Overview" },
    { id = "visibility", label = "Visibility" },
    { id = "appearance", label = "Appearance" },
    { id = "buffs", label = "Buffs" },
    { id = "consumables", label = "Consumables" },
    { id = "keybindings", label = "Key Bindings" },
    { id = "thanks", label = "Thank You" },
    { id = "troubleshooting", label = "Troubleshooting" },
    { id = "about", label = "About" },
}

-- Placeholder until the real artwork lands; the AddOns-list IconTexture in
-- both TOCs is still a question mark for the same reason.
local ANVIL = "Interface\\Icons\\Trade_BlackSmithing"

local anvilLines = {
    "The anvil gleams. Your buffs approve.",
    "A crisp ring echoes across Azeroth. Somewhere, a paladin nods.",
    "Polished. The forge now grants +1 confidence.",
    "The anvil reflects your face. It has seen worse gear choices.",
    "A tiny spark escapes. It is probably not a fire hazard.",
    "The anvil is immaculate. Your bags remain a separate matter.",
    "A blacksmith somewhere senses a disturbance in the profession window.",
    "Polished to raid-ready shine. The raid may still be less prepared.",
    "The hammer approves, with the restrained enthusiasm of a dwarf.",
    "Your buffs are now culturally significant.",
    "A murloc attempts to inspect the workmanship. It is removed from the premises.",
    "The anvil hums softly. This is normal. Probably.",
    "One polish closer to legendary. Two hundred and forty-seven closer to a mount drop.",
    "No durability was harmed in this ceremonial maintenance.",
    "The forge whispers: remember to eat something with a proper buff.",
    "Shiny enough to distract a rogue for almost half a second.",
    "A nearby mage requests an intellect scroll. The anvil declines to take sides.",
    "The anvil has been buffed. This is not technically useful, but it feels right.",
    "A goblin offers to sell you an anvil-polishing subscription. Declined.",
    "The sparkle is cosmetic. The sense of readiness is entirely real.",
}

local TEXT_WIDTH = 190
local SLIDER_X = 268

-- The name and its sub-text share a block whose top aligns with the icon, and
-- the row grows to fit however many lines that block wraps to. The shipped
-- version anchored the name below the icon's top and fixed the row at 46px,
-- which is what pushed the two-line consumable sub-texts out of their row.
local ROW_HEIGHT = 58

local function reminderRow(parent, y, item)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetPoint("TOPLEFT", Options.LEFT, y); row:SetSize(500, ROW_HEIGHT)
    Options.Surface(row, Options.theme.raised, Options.theme.edge)

    local tick = CreateFrame("Frame", nil, row, "BackdropTemplate")
    tick:SetSize(16, 16); tick:SetPoint("TOPLEFT", 10, -13)
    Options.Surface(tick, Options.theme.rail, Options.theme.edge)
    local mark = tick:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 3, -3); mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetColorTexture(unpack(Options.theme.selected))

    local left = tick
    if item.icon then
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28); icon:SetPoint("TOPLEFT", tick, "TOPRIGHT", 8, 2)
        icon:SetTexture(item.icon)
        left = icon
    end

    -- Fixed line counts and a fixed row height: the summary text changes as
    -- items become known, and a row that regrew on refresh would slide under
    -- the next one, whose position was fixed when the page was built.
    local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    name:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, item.icon and -2 or 0)
    name:SetWidth(TEXT_WIDTH); name:SetJustifyH("LEFT"); name:SetText(item.label)
    if name.SetMaxLines then name:SetMaxLines(1) end
    local detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    detail:SetWidth(TEXT_WIDTH); detail:SetJustifyH("LEFT")
    if detail.SetMaxLines then detail:SetMaxLines(2) end

    local bar, percent
    if not item.permanent then
        bar = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
        bar:SetPoint("LEFT", SLIDER_X, 0); bar:SetWidth(120)
        bar:SetMinMaxValues(0, 50); bar:SetValueStep(1); bar:SetObeyStepOnDrag(true)
        if bar.Low then bar.Low:SetText("") end
        if bar.High then bar.High:SetText("") end
        if bar.Text then bar.Text:SetText("") end
        percent = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        percent:SetPoint("LEFT", bar, "RIGHT", 8, 0)
    end

    local changing = false
    local function refresh()
        local enabled = item.enabled()
        mark:SetShown(enabled)
        tick:SetBackdropBorderColor(unpack(enabled and Options.theme.selected or Options.theme.edge))
        if item.permanent then
            detail:SetText("Permanent effect — shown only while inactive.")
        else
            changing = true; bar:SetValue(item.get()); changing = false
            percent:SetText(tostring(item.get()) .. "%")
            detail:SetText(item.result())
        end
    end
    if bar then
        bar:SetScript("OnValueChanged", function(_, value)
            if changing then return end
            item.set(math.floor(value + 0.5)); refresh()
            if Options.Refresh then Options.Refresh() end
        end)
    end
    row:SetScript("OnClick", function()
        item.toggle(); refresh()
        if Options.Refresh then Options.Refresh() end
    end)
    refresh()
    return refresh, y - ROW_HEIGHT - 6
end

local function visibilityItems()
    local function hasConditions()
        for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
            if ns.db.visibility[condition.key] then return true end
        end
        return false
    end
    local function setMode(mode)
        ns.db.visibilityMode = mode
        ns.db.visibility = {}
    end
    local items = {
        {
            label = "Always, out of combat", radio = true,
            get = function() return ns.db.visibilityMode ~= "NEVER" and not hasConditions() end,
            set = function() setMode("ALWAYS") end,
        },
        {
            label = "Never", radio = true,
            get = function() return ns.db.visibilityMode == "NEVER" end,
            set = function() setMode("NEVER") end,
        },
        { label = "Or when any of these match", heading = true },
    }
    for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
        local key = condition.key
        items[#items + 1] = {
            label = condition.label,
            get = function() return ns.db.visibilityMode ~= "NEVER" and ns.db.visibility[key] == true end,
            set = function(value)
                ns.db.visibilityMode = "ALWAYS"
                ns.db.visibility[key] = value or nil
            end,
        }
    end
    return items
end

local CHANNELS = { { "WHISPER", "Whisper" }, { "SAY", "Say" }, { "PARTY", "Party" } }

function Options.BuildPage(id, parent)
    if id == "overview" then
        local y = Options.Header(parent, "Buffsmith", "Out-of-combat buffs and consumables, one click away.")
        _, y = Options.Text(parent, "Buffsmith shows the self-buffs and consumables that are ready for you. Active self-buffs leave the bar and return when a refresh is useful.", y)
        _, y = Options.Text(parent, "Left-click an icon to use it. Right-click any icon to dismiss it until you change zones.", y)
        _, y = Options.Text(parent, "The bar is always hidden in combat, and so is everything it can do.", y)

    elseif id == "visibility" then
        local y = Options.Header(parent, "Visibility", "Choose when the bar is on screen.")
        local refresh
        refresh, y = Options.Dropdown(parent, y, "Show the bar", {
            items = visibilityItems(),
            summary = function() return ns.Visibility:Summary() end,
            hint = "Pick Always or Never, or tick several rules; any matching rule shows the bar.",
            width = 300,
        })
        _, y = Options.Check(parent, y, "Skip missing-buff checks in rested areas",
            function() return ns.db.ignoreBuffsInRestedAreas end,
            function(v) ns.db.ignoreBuffsInRestedAreas = v end,
            "Pause self-buff reminders while your character is resting in a city or inn.")
        _, y = Options.Text(parent, "Combat overrides every choice here. The bar's clickable actions are deliberately available only out of combat.", y - 6)
        parent.buffsmithRefresh = refresh

    elseif id == "appearance" then
        local y = Options.Header(parent, "Appearance", "Size, direction and the controls around the bar.")
        local refreshSize, refreshOrientation, refreshAlternatives
        refreshOrientation, y = Options.Dropdown(parent, y, "Direction", {
            items = {
                { label = "Vertical", radio = true,
                  get = function() return ns.db.orientation == "VERTICAL" end,
                  set = function() ns.Set("orientation", "VERTICAL") end },
                { label = "Horizontal", radio = true,
                  get = function() return ns.db.orientation == "HORIZONTAL" end,
                  set = function() ns.Set("orientation", "HORIZONTAL") end },
            },
            summary = function() return ns.db.orientation == "VERTICAL" and "Vertical" or "Horizontal" end,
            width = 220,
        })
        refreshSize, y = Options.Slider(parent, y, "Icon size", 24, 64, 2,
            function() return ns.db.iconSize end, function(v) ns.db.iconSize = v end)
        refreshAlternatives, y = Options.Slider(parent, y, "Alternatives shown when a category is expanded", 1, 3, 1,
            function() return ns.db.maxAlternatives end, function(v) ns.db.maxAlternatives = v end, "")
        _, y = Options.Check(parent, y, "Show drag handle",
            function() return ns.db.showHandle end,
            function(v) ns.db.showHandle = v; ns.Handle:Update() end,
            "Drag the gold grip above the bar to move it. Right-click the grip to open settings.")
        _, y = Options.Check(parent, y, "Show minimap button",
            function() return ns.db.showMinimap end,
            function(v) ns.db.showMinimap = v; ns.Minimap:Update() end,
            "Click it to open settings. Drag it around the minimap to move it.")
        local reset = Options.Button(parent, 190, "Reset bar position")
        reset:SetPoint("TOPLEFT", Options.LEFT, y - 4)
        reset:SetScript("OnClick", function()
            ns.db.palettePoint = { "CENTER", "CENTER", 0, -120 }
            ns.Palette.frame:ClearAllPoints(); ns.Palette.frame:SetPoint(unpack(ns.db.palettePoint))
            ns.Preview:ApplyPosition()
        end)
        parent.buffsmithRefresh = function() refreshSize(); refreshOrientation(); refreshAlternatives() end

    elseif id == "buffs" then
        local content = Options.Scroll(parent)
        local y = Options.Header(content, "Buffs", "Who Buffsmith checks, and when each buff becomes a reminder.")
        local refreshes = {}
        _, y = Options.Check(content, y, "Show buffs for a friendly target",
            function() return ns.db.showTargetBuffs end,
            function(v) ns.db.showTargetBuffs = v end,
            "Show targetable buffs when your selected friendly player is missing one.")
        _, y = Options.Check(content, y, "Show buffs for party members",
            function() return ns.db.showPartyBuffs end,
            function(v) ns.db.showPartyBuffs = v end,
            "Show targetable buffs for party members who are missing one.")
        _, y = Options.Check(content, y, "Show buffs for friendly pets",
            function() return ns.db.showPetBuffs end,
            function(v) ns.db.showPetBuffs = v end,
            "Show targetable buffs for your pet and party pets.")
        _, y = Options.Check(content, y, "Show party coverage reminders",
            function() return ns.db.showPartyCoverage end,
            function(v) ns.db.showPartyCoverage = v end,
            "Show missing class buffs a party member may be able to provide. These icons report to chat; they never cast.")
        _, y = Options.SectionLabel(content, "YOUR BUFFS — UNTICK ONE TO IGNORE IT", y - 4)
        for _, buff in ipairs(ns.KnownSelfBuffs()) do
            local entry = buff
            local refresh
            refresh, y = reminderRow(content, y, {
                label = entry.name, icon = entry.icon, permanent = entry.permanent,
                enabled = function() return not ns.db.excludedBuffs[entry.spellID] end,
                toggle = function() ns.db.excludedBuffs[entry.spellID] = (not ns.db.excludedBuffs[entry.spellID]) or nil end,
                get = function() return ns.Actions:Percent(entry) end,
                set = function(value) ns.db.reminderPercent.buffBySpell[entry.spellID] = value end,
                result = function() return ns.Actions:ReminderFor(entry) end,
            })
            refreshes[#refreshes + 1] = refresh
        end
        if #ns.KnownSelfBuffs() == 0 then
            _, y = Options.Text(content, "No self-buffs found for your class and level yet.", y)
        end
        content:SetHeight(math.max(470, -y + 24))
        parent.buffsmithRefresh = function() for _, refresh in ipairs(refreshes) do refresh() end end

    elseif id == "consumables" then
        local content = Options.Scroll(parent)
        local y = Options.Header(content, "Consumables", "Enable, time and exclude each available consumable.")
        _, y = Options.Text(content, "Items appear here while they are in your bags. Each item's reminder time is set after you use it once.", y)
        local refreshes = {}
        local function category(key, label)
            local refresh
            refresh, y = reminderRow(content, y, {
                label = label,
                enabled = function() return ns.db.categories[key] end,
                toggle = function() ns.db.categories[key] = not ns.db.categories[key]; ns.Inventory:Refresh() end,
                get = function() return ns.db.reminderPercent[key] end,
                set = function(value) ns.db.reminderPercent[key] = value end,
                result = function() return ns.Inventory:ReminderSummary(key) end,
            })
            refreshes[#refreshes + 1] = refresh
            for _, item in ipairs(ns.Inventory:Choices(key)) do
                local entry = item
                refresh, y = reminderRow(content, y, {
                    label = entry.name, icon = entry.icon,
                    enabled = function() return not ns.db.excludedConsumables[entry.itemID] end,
                    toggle = function() ns.db.excludedConsumables[entry.itemID] = (not ns.db.excludedConsumables[entry.itemID]) or nil end,
                    get = function() return ns.Actions:Percent(entry) end,
                    set = function(value) ns.db.reminderPercent.item[entry.itemID] = value end,
                    result = function() return ns.Inventory:ReminderFor(entry) end,
                })
                refreshes[#refreshes + 1] = refresh
            end
            y = y - 8
        end
        category("food", "Food")
        category("scroll", "Scrolls")
        category("flask", "Flasks")
        category("weapon", "Weapon enhancements")
        content:SetHeight(math.max(470, -y + 24))
        parent.buffsmithRefresh = function() for _, refresh in ipairs(refreshes) do refresh() end end

    elseif id == "keybindings" then
        local y = Options.Header(parent, "Key Bindings", "One key for your next missing buff.")
        _, y = Options.Text(parent, "Press the Buff trigger to apply the first available Buffsmith icon. Press it again for the next one. Icons that are already active or dismissed are skipped.", y)

        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        card:SetPoint("TOPLEFT", Options.LEFT, y - 4); card:SetSize(500, 56)
        Options.Surface(card, Options.theme.raised, Options.theme.edge)
        local name = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        name:SetPoint("TOPLEFT", 16, -12); name:SetText("Buff trigger")
        local detail = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
        detail:SetWidth(250); detail:SetJustifyH("LEFT")
        detail:SetText("Applies the next available buff or consumable.")

        local clear = Options.Button(card, 70, "Clear")
        clear:SetSize(64, 24); clear:SetPoint("RIGHT", -12, 0)
        local keycap = Options.Button(card, 150, "")
        keycap:SetSize(150, 24); keycap:SetPoint("RIGHT", clear, "LEFT", -8, 0)

        local function refresh()
            local label = ns.Bindings:Label("trigger")
            local bound = label ~= "Unbound"
            keycap.Text:SetText(bound and label or "Not bound")
            keycap.Text:SetTextColor(unpack(bound and { 1, 1, 1 } or Options.theme.muted))
            keycap:SetBackdropBorderColor(unpack(bound and Options.theme.accent or Options.theme.edge))
        end
        keycap:SetScript("OnClick", function()
            keycap.Text:SetText("Press a key…")
            ns.Bindings:Capture(function(key, message)
                if not key then if message then ns.Print(message) end; refresh(); return end
                local ok, result = ns.Bindings:Set("trigger", key)
                ns.Print(ok and ("Buff trigger bound to " .. (GetBindingText and GetBindingText(result, "KEY_") or result) .. ".") or result)
                refresh()
            end)
        end)
        clear:SetScript("OnClick", function()
            local ok, message = ns.Bindings:Clear("trigger")
            if not ok then ns.Print(message) end
            refresh()
        end)
        Options.Text(parent, "Click the key button, then press a key or scroll the mouse wheel. Esc cancels.", y - 72)
        parent.buffsmithRefresh = refresh

    elseif id == "thanks" then
        local y = Options.Header(parent, "Thank You", "Send a short thanks when someone buffs you.")
        local refreshChannel
        _, y = Options.Check(parent, y, "Send thank-you messages",
            function() return ns.db.thanksEnabled end,
            function(v) ns.db.thanksEnabled = v end,
            "Send a short thank-you when a party member buffs you. Buffs you already have never trigger one.")
        refreshChannel, y = Options.Dropdown(parent, y, "Send it to", {
            items = (function()
                local items = {}
                for _, channel in ipairs(CHANNELS) do
                    local key = channel[1]
                    items[#items + 1] = {
                        label = channel[2], radio = true,
                        get = function() return ns.db.thanksChannel == key end,
                        set = function() ns.db.thanksChannel = key end,
                    }
                end
                return items
            end)(),
            summary = function()
                for _, channel in ipairs(CHANNELS) do
                    if ns.db.thanksChannel == channel[1] then return channel[2] end
                end
                return "Whisper"
            end,
            width = 220,
        })
        _, y = Options.Text(parent, "Message — {buff} and {player} are replaced when it is sent.", y)
        local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        edit:SetSize(430, 28); edit:SetPoint("TOPLEFT", Options.LEFT + 6, y)
        edit:SetAutoFocus(false); edit:SetText(ns.db.thanksMessage)
        edit:SetScript("OnEnterPressed", function(self) ns.db.thanksMessage = self:GetText(); self:ClearFocus() end)
        edit:SetScript("OnEditFocusLost", function(self) ns.db.thanksMessage = self:GetText() end)
        y = y - 40

        local preview = Options.Button(parent, 160, "Preview message")
        preview:SetPoint("TOPLEFT", Options.LEFT, y)
        preview:SetScript("OnClick", function()
            local sample = (ns.db.thanksMessage or ""):gsub("{buff}", "Power Word: Fortitude"):gsub("{player}", UnitName and UnitName("player") or "a friend")
            ns.Print("Preview: " .. sample)
        end)
        Options.Text(parent, "Only recognised party buffs are eligible. Buffsmith ignores your own casts and never sends a message for buffs already present when you log in or turn this on.", y - 40)
        parent.buffsmithRefresh = refreshChannel

    elseif id == "troubleshooting" then
        local y = Options.Header(parent, "Troubleshooting", "Copy a concise client and configuration report.")
        local copy = Options.Button(parent, 180, "Copy diagnostics", true)
        copy:SetPoint("TOPLEFT", Options.LEFT, y)
        copy:SetScript("OnClick", function() ns.Diagnostics:ShowCopy() end)
        y = y - 44
        Options.Check(parent, y, "Show load message",
            function() return ns.db.showStartupMessage end,
            function(v) ns.db.showStartupMessage = v end,
            "Show Buffsmith's load confirmation in chat.")

    elseif id == "about" then
        local y = Options.Header(parent, "About Buffsmith", "Version " .. tostring(ns.VERSION))
        _, y = Options.Text(parent, "Buffsmith keeps your useful blessings and bagged provisions within one polite click.", y)

        local anvil = CreateFrame("Button", nil, parent)
        anvil:SetSize(64, 64); anvil:SetPoint("TOP", parent, "TOP", 0, y - 10)
        local art = anvil:CreateTexture(nil, "ARTWORK")
        art:SetAllPoints(); art:SetTexture(ANVIL)
        anvil:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

        local caption = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        caption:SetPoint("TOP", anvil, "BOTTOM", 0, -6); caption:SetText("Polish the anvil")

        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        card:SetPoint("TOP", caption, "BOTTOM", 0, -12); card:SetSize(440, 58)
        Options.Surface(card, Options.theme.raised, Options.theme.edge)
        local quip = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        quip:SetPoint("LEFT", 16, 0); quip:SetPoint("RIGHT", -16, 0)
        quip:SetJustifyH("CENTER")
        -- Morpheus is the closest the client gets to a storybook italic; the
        -- default font stands in wherever that object is missing.
        if _G.MailFont_Large then quip:SetFontObject("MailFont_Large") end
        quip:SetTextColor(0.93, 0.85, 0.66)
        quip:SetText("The anvil awaits its next entirely necessary polish.")

        local fade = quip:CreateAnimationGroup()
        local alpha = fade:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0); alpha:SetToAlpha(1); alpha:SetDuration(0.35)

        local previous
        anvil:SetScript("OnClick", function()
            local index
            repeat index = math.random(#anvilLines) until #anvilLines == 1 or index ~= previous
            previous = index
            quip:SetText(anvilLines[index])
            fade:Stop(); fade:Play()
        end)
    end
end
