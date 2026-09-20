local addonName, ns = ...
local Options = ns.Options
Options.pageSpecs = { { id = "overview", label = "Overview" }, { id = "visibility", label = "Visibility" }, { id = "buffs", label = "Buffs" }, { id = "consumables", label = "Consumables" }, { id = "thanks", label = "Thank You" }, { id = "keybindings", label = "Key Bindings" }, { id = "appearance", label = "Appearance" }, { id = "troubleshooting", label = "Troubleshooting" }, { id = "about", label = "About" } }
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
local function text(parent, value, y) local copy = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); copy:SetPoint("TOPLEFT", 18, y or -92); copy:SetWidth(490); copy:SetJustifyH("LEFT"); copy:SetText(value) end
local function reminderRow(parent, y, item)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetPoint("TOPLEFT", 18, y); row:SetSize(500, 46)
    Options.Surface(row, Options.theme.raised, Options.theme.edge)
    local tick = CreateFrame("Frame", nil, row, "BackdropTemplate")
    tick:SetSize(16, 16); tick:SetPoint("LEFT", 10, 0); Options.Surface(tick, Options.theme.rail, Options.theme.edge)
    local mark = tick:CreateTexture(nil, "ARTWORK"); mark:SetPoint("TOPLEFT", 3, -3); mark:SetPoint("BOTTOMRIGHT", -3, 3); mark:SetColorTexture(unpack(Options.theme.selected))
    local icon
    local left = tick
    if item.icon then
        icon = row:CreateTexture(nil, "ARTWORK"); icon:SetSize(28, 28); icon:SetPoint("LEFT", tick, "RIGHT", 8, 0); icon:SetTexture(item.icon)
        left = icon
    end
    local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    name:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, -8); name:SetWidth(185); name:SetJustifyH("LEFT"); name:SetText(item.label)
    local detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4); detail:SetWidth(185); detail:SetJustifyH("LEFT")
    local slider, percent
    if not item.permanent then
        slider = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
        slider:SetPoint("LEFT", 255, 0); slider:SetWidth(120); slider:SetMinMaxValues(0, 50); slider:SetValueStep(1); slider:SetObeyStepOnDrag(true)
        if slider.Low then slider.Low:SetText("") end
        if slider.High then slider.High:SetText("") end
        if slider.Text then slider.Text:SetText("") end
        percent = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        percent:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    end
    local changing = false
    local function refresh()
        local enabled = item.enabled()
        mark:SetShown(enabled); tick:SetBackdropBorderColor(unpack(enabled and Options.theme.selected or Options.theme.edge))
        if item.permanent then
            detail:SetText("Permanent effect — shown only while inactive.")
        else
            changing = true; slider:SetValue(item.get()); changing = false
            percent:SetText(tostring(item.get()) .. "%")
            detail:SetText("Reminder: " .. item.result())
        end
    end
    if slider then slider:SetScript("OnValueChanged", function(_, value)
        if changing then return end
        item.set(math.floor(value + 0.5)); refresh(); if Options.Refresh then Options.Refresh() end
    end) end
    row:SetScript("OnClick", function() item.toggle(); refresh(); if Options.Refresh then Options.Refresh() end end)
    refresh()
    return refresh
end
function Options.BuildPage(id, parent)
    if id == "overview" then Options.Header(parent, "Buffsmith", "Out-of-combat self-buff and consumable palette"); text(parent, "Buffsmith shows the self-buffs and consumables that are ready for you. Active self-buffs leave the palette and return when a refresh is useful.")
    elseif id == "visibility" then
        Options.Header(parent, "Visibility", "Choose where Buffsmith can appear.")
        text(parent, "Buffsmith is always hidden in combat. Its clickable actions are deliberately only available out of combat.", -88)
        local function refresh() ns.Palette:Refresh() end
        Options.Check(parent, -136, "Always out of combat", function()
            for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do if ns.db.visibility[condition.key] then return false end end
            return ns.db.visibilityMode ~= "NEVER"
        end, function()
            ns.db.visibilityMode = "ALWAYS"; ns.db.visibility = {}; refresh()
        end, "Show in every out-of-combat situation.")
        Options.Check(parent, -170, "Never show the palette", function() return ns.db.visibilityMode == "NEVER" end,
            function() ns.db.visibilityMode = "NEVER"; ns.db.visibility = {}; refresh() end,
            "Keep Buffsmith loaded, but hide the on-screen palette.")
        text(parent, "Or show when any of these match", -222)
        local y = -250
        for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
            local key, label = condition.key, condition.label
            Options.Check(parent, y, label, function() return ns.db.visibilityMode ~= "NEVER" and ns.db.visibility[key] == true end,
                function(value) ns.db.visibilityMode = "ALWAYS"; ns.db.visibility[key] = value or nil; refresh() end,
                "Combat always overrides this scenario.")
            y = y - 34
        end
    elseif id == "buffs" then
        local content = Options.Scroll(parent)
        Options.Header(content, "Buffs", "One reminder threshold per known buff.")
        Options.Check(content, -86, "Show Buffsmith palette", function() return ns.db.showPalette end, function(v) ns.Set("showPalette", v) end, "Show the movable icon palette outside combat.")
        Options.Check(content, -120, "Show buffs for a friendly target", function() return ns.db.showTargetBuffs end, function(v) ns.db.showTargetBuffs = v; ns.Palette:Refresh() end, "Show targetable buffs when your selected friendly player is missing one.")
        Options.Check(content, -154, "Show buffs for party members", function() return ns.db.showPartyBuffs end, function(v) ns.db.showPartyBuffs = v; ns.Palette:Refresh() end, "Show targetable buffs for party members who are missing one.")
        Options.Check(content, -188, "Show buffs for friendly pets", function() return ns.db.showPetBuffs end, function(v) ns.db.showPetBuffs = v; ns.Palette:Refresh() end, "Show targetable buffs for your pet and party pets. Disabled by default.")
        Options.Check(content, -222, "Show party coverage reminders", function() return ns.db.showPartyCoverage end, function(v) ns.db.showPartyCoverage = v; ns.Palette:Refresh() end, "Show missing class buffs a party member may be able to provide. These icons are informational.")
        Options.Check(content, -256, "Skip missing-buff checks in rested areas", function() return ns.db.ignoreBuffsInRestedAreas end, function(v) ns.db.ignoreBuffsInRestedAreas = v; ns.Palette:Refresh() end, "Pause self-buff reminders while your character is resting.")
        local label = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", 18, -300); label:SetText("BUFF REMINDERS")
        local refreshes, y = {}, -324
        for _, buff in ipairs(ns.KnownSelfBuffs()) do
            local entry = buff
            refreshes[#refreshes + 1] = reminderRow(content, y, {
                label = entry.name, icon = entry.icon,
                permanent = entry.permanent,
                enabled = function() return true end, toggle = function() end,
                get = function() return ns.Actions:Percent(entry) end,
                set = function(value) ns.db.reminderPercent.buffBySpell[entry.spellID] = value end,
                result = function() return ns.Actions:ReminderFor(entry) end,
            })
            y = y - 52
        end
        Options.Check(content, y - 2, "Show load message", function() return ns.db.showStartupMessage end, function(v) ns.db.showStartupMessage = v end, "Show Buffsmith's load confirmation in chat.")
        content:SetHeight(math.max(470, -y + 52))
        parent.buffsmithRefresh = function() for _, refresh in ipairs(refreshes) do refresh() end end
    elseif id == "consumables" then
        local content = Options.Scroll(parent)
        Options.Header(content, "Consumables", "Enable, time and exclude each available consumable.")
        local refreshes, y = {}, -86
        local function category(category, label)
            refreshes[#refreshes + 1] = reminderRow(content, y, {
                label = label, enabled = function() return ns.db.categories[category] end,
                toggle = function() ns.db.categories[category] = not ns.db.categories[category]; ns.Inventory:Refresh() end,
                get = function() return ns.db.reminderPercent[category] end,
                set = function(value) ns.db.reminderPercent[category] = value end,
                result = function() return ns.Inventory:ReminderSummary(category) end,
            })
            y = y - 54
            for _, item in ipairs(ns.Inventory:Choices(category)) do
                local entry = item
                refreshes[#refreshes + 1] = reminderRow(content, y, {
                    label = entry.name, icon = entry.icon,
                    enabled = function() return not ns.db.excludedConsumables[entry.itemID] end,
                    toggle = function() ns.db.excludedConsumables[entry.itemID] = not ns.db.excludedConsumables[entry.itemID] end,
                    get = function() return ns.Actions:Percent(entry) end,
                    set = function(value) ns.db.reminderPercent.item[entry.itemID] = value end,
                    result = function() return ns.Inventory:ReminderFor(entry) end,
                })
                y = y - 52
            end
            y = y - 10
        end
        category("food", "Food reminders")
        category("scroll", "Scroll reminders")
        category("flask", "Flask reminders")
        category("weapon", "Weapon enhancement reminders")
        content:SetHeight(math.max(470, -y + 28))
        parent.buffsmithRefresh = function() for _, refresh in ipairs(refreshes) do refresh() end end
    elseif id == "thanks" then
        Options.Header(parent, "Thank you", "Optional acknowledgement for a recognised party buff received by you.")
        Options.Check(parent, -88, "Send thank-you messages", function() return ns.db.thanksEnabled end, function(v) ns.db.thanksEnabled = v end, "Disabled by default. Existing buffs never trigger a message when you enable it.")
        text(parent, "Delivery", -136)
        local buttons = {}
        local function channelButton(channel, label, x)
            local button = Options.Button(parent, 102, label)
            button:SetPoint("TOPLEFT", x, -160)
            button:SetScript("OnClick", function()
                ns.db.thanksChannel = channel
                for key, value in pairs(buttons) do value:SetBackdropBorderColor(unpack(key == channel and Options.theme.selected or Options.theme.edge)) end
            end)
            buttons[channel] = button
        end
        channelButton("WHISPER", "Whisper", 18)
        channelButton("SAY", "Say", 128)
        channelButton("PARTY", "Party", 238)
        for channel, button in pairs(buttons) do button:SetBackdropBorderColor(unpack(channel == ns.db.thanksChannel and Options.theme.selected or Options.theme.edge)) end
        text(parent, "Message ({buff} and {player} are replaced when sent)", -214)
        local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        edit:SetSize(430, 28); edit:SetPoint("TOPLEFT", 22, -242); edit:SetAutoFocus(false); edit:SetText(ns.db.thanksMessage)
        edit:SetScript("OnEnterPressed", function(self) ns.db.thanksMessage = self:GetText(); self:ClearFocus() end)
        edit:SetScript("OnEditFocusLost", function(self) ns.db.thanksMessage = self:GetText() end)
        text(parent, "Only recognised party buffs are eligible. Buffsmith ignores your own casts and never sends a message for buffs already present when you log in or enable this setting.", -288)
    elseif id == "keybindings" then
        Options.Header(parent, "Key Bindings", "One key for your next missing buff.")
        text(parent, "Press the Buff trigger to apply the first available Buffsmith icon. Press it again to apply the next one. Icons that are already active or dismissed are skipped.")
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        card:SetPoint("TOPLEFT", 18, -130); card:SetSize(520, 70)
        Options.Surface(card, Options.theme.raised, Options.theme.edge)
        local name = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        name:SetPoint("TOPLEFT", 16, -14); name:SetText("Buff trigger")
        local detail = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5); detail:SetWidth(290); detail:SetJustifyH("LEFT")
        detail:SetText("Applies the next available buff or consumable.")
        local keycap = Options.Button(card, 152, "", true)
        keycap:SetSize(170, 42); keycap:SetPoint("RIGHT", -12, 0)
        keycap.Text:SetFontObject("GameFontNormalLarge")
        local clear = Options.Button(card, 70, "Clear")
        clear:SetSize(58, 18); clear:SetPoint("BOTTOMRIGHT", -12, -5)
        local function refresh()
            keycap.Text:SetText(ns.Bindings:Label("trigger"))
            keycap:SetBackdropBorderColor(unpack(ns.Bindings:Label("trigger") == "Unbound" and Options.theme.edge or Options.theme.accent))
        end
        keycap:SetScript("OnClick", function()
            keycap.Text:SetText("Press key…")
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
        text(parent, "Click the large keycap, then press a key or scroll the mouse wheel. Right-click any palette icon to dismiss it until you change zones.", -226)
        parent.buffsmithRefresh = refresh
    elseif id == "appearance" then
        Options.Header(parent, "Appearance", "Palette and minimap controls.")
        local reset = Options.Button(parent, 190, "Reset palette position")
        reset:SetPoint("TOPLEFT", 18, -88)
        reset:SetScript("OnClick", function()
            ns.db.palettePoint = { "CENTER", "CENTER", 0, -120 }
            ns.Palette.frame:ClearAllPoints(); ns.Palette.frame:SetPoint(unpack(ns.db.palettePoint))
        end)
        Options.Check(parent, -128, "Show minimap button", function() return ns.db.showMinimap end,
            function(v) ns.db.showMinimap = v; ns.Minimap:Update() end,
            "Click it to open settings. Drag it around the minimap to move it.")
        Options.Check(parent, -162, "Show drag handle", function() return ns.db.showHandle end,
            function(v) ns.db.showHandle = v; ns.Handle:Update() end,
            "Drag the grip above the palette to move it. Right-click the grip to open settings.")
        local refreshSize = Options.Slider(parent, -208, "Icon size", 24, 64, 2,
            function() return ns.db.iconSize end, function(v) ns.db.iconSize = v end)
        local vertical = Options.Button(parent, 130, "Vertical")
        vertical:SetPoint("TOPLEFT", 18, -288)
        local horizontal = Options.Button(parent, 130, "Horizontal")
        horizontal:SetPoint("LEFT", vertical, "RIGHT", 8, 0)
        local function refreshOrientation()
            vertical:SetBackdropBorderColor(unpack(ns.db.orientation == "VERTICAL" and Options.theme.selected or Options.theme.edge))
            horizontal:SetBackdropBorderColor(unpack(ns.db.orientation == "HORIZONTAL" and Options.theme.selected or Options.theme.edge))
        end
        vertical:SetScript("OnClick", function() ns.db.orientation = "VERTICAL"; ns.Palette:Refresh(); refreshOrientation() end)
        horizontal:SetScript("OnClick", function() ns.db.orientation = "HORIZONTAL"; ns.Palette:Refresh(); refreshOrientation() end)
        text(parent, "Palette orientation", -264)
        parent.buffsmithRefresh = function() refreshSize(); refreshOrientation() end
    elseif id == "troubleshooting" then Options.Header(parent, "Troubleshooting", "Copy a concise client and configuration report."); local copy = Options.Button(parent, 180, "Copy diagnostics", true); copy:SetPoint("TOPLEFT", 18, -88); copy:SetScript("OnClick", function() ns.Diagnostics:ShowCopy() end)
    elseif id == "about" then
        Options.Header(parent, "About Buffsmith", "Version " .. tostring(ns.VERSION))
        text(parent, "Buffsmith keeps your useful blessings and bagged provisions within one polite click.")
        local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        note:SetPoint("TOPLEFT", 18, -148); note:SetWidth(500); note:SetJustifyH("LEFT")
        note:SetText("The anvil awaits its next entirely necessary polish.")
        local button = Options.Button(parent, 190, "Polish the anvil")
        button:SetPoint("TOPLEFT", 18, -220)
        local previous
        button:SetScript("OnClick", function()
            local index
            repeat index = math.random(#anvilLines) until #anvilLines == 1 or index ~= previous
            previous = index
            note:SetText(anvilLines[index])
            ns.Print(anvilLines[index])
        end)
    end
end
