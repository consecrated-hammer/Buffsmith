local addonName, ns = ...

ns.Inventory = { items = {}, lastStatus = "not scanned" }
local Inventory = ns.Inventory

local function campRule(itemID)
    return ns.TARGET == "Camelot" and ns.CAMPING_ITEMS[itemID] or nil
end

-- Camp world effects and lockouts are not evidence that a consumed item supplied
-- a food/flask buff. Apply this to new observations and old saved mappings alike.
local function campingAura(spellID)
    if ns.TARGET ~= "Camelot" then return false end
    for _, rule in pairs(ns.CAMPING_ITEMS or {}) do
        if rule.spellID == spellID then return true end
    end
    return false
end

local function spellName(id)
    local modern = C_Spell and C_Spell.GetSpellName
    if type(modern) == "function" then
        local ok, value = pcall(modern, id)
        value = ok and ns.Plain(value)
        if type(value) == "string" and value ~= "" then return string.lower(value) end
    end
    if type(GetSpellInfo) == "function" then
        local ok, value = pcall(GetSpellInfo, id)
        value = ok and ns.Plain(value)
        if type(value) == "string" and value ~= "" then return string.lower(value) end
    end
end

-- Reject only positive class-buff evidence, not unfamiliar legacy food names.
-- Raw catalogues include excluded/unlearned spells; localized base-rank names
-- identify higher ranks without depending on current reminder preferences.
local function classAura(mapping)
    local clock = GetTime and ns.Plain(GetTime())
    if type(clock) ~= "number" then clock = 0 end
    local cache = Inventory.nonFoodCatalogue
    if cache and cache.unresolved and clock >= cache.retryAt then cache = nil end
    if not cache or cache.self ~= ns.SELF_BUFFS or cache.party ~= ns.PARTY_BUFFS then
        cache = { self = ns.SELF_BUFFS, party = ns.PARTY_BUFFS, ids = {}, names = {}, retryAt = clock + 2 }
        for _, catalogue in ipairs({ ns.SELF_BUFFS or {}, ns.PARTY_BUFFS or {} }) do
            for _, entries in pairs(catalogue) do
                for _, entry in ipairs(entries) do
                    if entry.spellID then cache.ids[entry.spellID] = true end
                    if entry.auraID then cache.ids[entry.auraID] = true end
                    for _, id in ipairs(entry.ids or {}) do cache.ids[id] = true end
                    for _, id in ipairs(entry.auraIDs or {}) do cache.ids[id] = true end
                    local label = ns.Plain(entry.label)
                    if type(label) == "string" then cache.names[string.lower(label)] = true end
                    local name = entry.spellID and spellName(entry.spellID)
                    if name then cache.names[name] = true else cache.unresolved = true end
                end
            end
        end
        Inventory.nonFoodCatalogue = cache
    end
    local id, name = ns.Plain(mapping.spellID), ns.Plain(mapping.name)
    if id and cache.ids[id] then return true end
    if type(name) == "string" and cache.names[string.lower(name)] then return true end
    local resolved = id and spellName(id)
    return resolved and cache.names[resolved] == true or false
end

local function foodAura(aura)
    return not campingAura(aura.spellID) and (aura.icon == 136000
        or (type(aura.name) == "string" and string.find(string.lower(aura.name), "well fed", 1, true)))
end

function Inventory:LearnedAura(item)
    local mapping = item and ns.db.consumableAuras[item.itemID]
    if mapping and (campingAura(mapping.spellID) or (item.category == "food" and classAura(mapping))) then return nil end
    return mapping
end

local function helpfulAuras()
    local found = {}
    local getter = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getter or ns.IsCombatLocked() then return found end
    for index = 1, 128 do
        local ok, aura = pcall(getter, "player", index, "HELPFUL")
        if not ok or ns.IsSecret(aura) or not aura then break end
        local spellID = tonumber(ns.Plain(aura.spellId))
        local name = ns.Plain(aura.name)
        if spellID and type(name) == "string" then
            local duration = tonumber(ns.Plain(aura.duration)) or 0
            local expiration = tonumber(ns.Plain(aura.expirationTime)) or 0
            found[spellID] = {
                spellID = spellID, name = name,
                duration = duration,
                remaining = duration > 0 and expiration > 0 and math.max(0, expiration - GetTime()) or nil,
                icon = tonumber(ns.Plain(aura.icon)) or tonumber(ns.Plain(aura.iconFileID)),
            }
        end
    end
    return found
end

local function bagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function containerItemInfo(bag, slot)
    if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(info) == "table" then
        Inventory.lastContainerAPI = "C_Container table"
        return info
    end
    return nil
end

local function bagItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then
        local ok, itemID = pcall(C_Container.GetContainerItemID, bag, slot)
        if ok and itemID then
            Inventory.lastContainerAPI = "C_Container.GetContainerItemID"
            return itemID
        end
    end
    local info = containerItemInfo(bag, slot)
    if info then return info.itemID end
    if GetContainerItemID then return GetContainerItemID(bag, slot) end
    return nil
end

local function bagItemCount(bag, slot)
    local info = containerItemInfo(bag, slot)
    if info then return tonumber(ns.Plain(info.stackCount)) or 1 end
    local _, count = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
    return tonumber(count) or 1
end

local function foodProvidesBuff(itemID)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false end
    local ok, tooltip = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or type(tooltip) ~= "table" or type(tooltip.lines) ~= "table" then return false end
    for _, line in ipairs(tooltip.lines) do
        local text = line.leftText or line.rightText
        if type(text) == "string" and string.find(string.lower(text), "well fed", 1, true) then
            return true
        end
    end
    return false
end

-- A "Use:" line that increases something for minutes or hours is a timed
-- buff worth a reminder.  Seconds-long effects and plain restores are not.
local function itemGivesTimedBuff(itemID)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false end
    local ok, tooltip = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or type(tooltip) ~= "table" or type(tooltip.lines) ~= "table" then return false end
    for _, line in ipairs(tooltip.lines) do
        local text = line.leftText
        if type(text) == "string" then
            text = string.lower(text)
            if string.find(text, "^use:") and string.find(text, "increase", 1, true)
                and (string.find(text, "%d+%s*min") or string.find(text, "%d+%s*hour")) then
                return true
            end
        end
    end
    return false
end

local POTION = ITEM_SUBCLASS_CONSUMABLE_POTION or "Potion"

local function isPoison(itemSubType, itemName)
    if itemSubType == (ITEM_SUBCLASS_CONSUMABLE_POISON or "Poison") then return true end
    if type(itemName) ~= "string" then return false end
    -- Fallback for clients reporting poisons as Other. Do not match elixirs,
    -- food or antidotes merely because their description mentions poison.
    local family = string.lower(itemName):match("^(.+) poison[%s%dixv]*$")
    return family == "instant" or family == "deadly" or family == "wound"
        or family == "crippling" or family == "mind-numbing"
        or family == "occult" or family == "sebacious"
end

local function classify(itemType, itemSubType, itemName, itemID)
    if itemType ~= ITEM_CLASS_CONSUMABLE and itemType ~= "Consumable" then return nil end
    if campRule(itemID) then return "other" end
    if itemSubType ~= POTION and isPoison(itemSubType, itemName) then return "weapon" end
    local food = ns.CONSUMABLE_CATEGORIES.food.subtypes[itemSubType] or itemSubType == "Food & Drink"
    if food then
        if foodProvidesBuff(itemID) then return "food" end
        return itemGivesTimedBuff(itemID) and "other" or nil
    end

    local scroll = ns.CONSUMABLE_CATEGORIES.scroll.subtypes[itemSubType] or itemSubType == "Scroll"
    if scroll then return "scroll" end
    if type(itemName) == "string" and string.match(itemName, "^Scroll") then return "scroll" end

    local flask = ns.CONSUMABLE_CATEGORIES.flask.subtypes[itemSubType] or itemSubType == "Flask"
    if flask or (type(itemName) == "string" and string.match(itemName, "^Flask")) then return "flask" end

    -- Item Enhancement also contains armour kits. A weapon-specific name is
    -- required before presenting it as an oil/stone action.
    if type(itemName) == "string" then
        local name = string.lower(itemName)
        if string.find(name, "oil", 1, true) or string.find(name, "whetstone", 1, true)
            or string.find(name, "weightstone", 1, true) or string.find(name, "sharpening stone", 1, true) then
            return "weapon"
        end
    end

    if ns.CONSUMABLE_CATEGORIES.other.subtypes[itemSubType] or itemSubType == "Elixir" then return "other" end
    -- Potions are for combat; anything else with a timed buff counts.
    if itemSubType ~= POTION and itemGivesTimedBuff(itemID) then return "other" end
    return nil
end

local function weaponEnchantStatus()
    if type(GetWeaponEnchantInfo) ~= "function" then return nil end
    local ok, mainHand, mainExpires, _, _, offHand, offExpires = pcall(GetWeaponEnchantInfo)
    if not ok or not (mainHand or offHand) then return nil end
    local remaining = math.max(tonumber(mainHand and mainExpires) or 0, tonumber(offHand and offExpires) or 0) / 1000
    return { state = "active", duration = 0, remaining = remaining > 0 and remaining or nil }
end

-- Poison items coat one weapon at a time without replacing existing coatings.
function Inventory:PoisonTargetSlot()
    if type(GetWeaponEnchantInfo) ~= "function" or type(GetInventoryItemID) ~= "function" then return nil end
    local ok, mainHand, _, _, _, offHand = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    if GetInventoryItemID("player", 16) and not ns.Plain(mainHand) then return 16 end
    if OffhandHasWeapon and OffhandHasWeapon() and not ns.Plain(offHand) then return 17 end
    return nil
end

function Inventory:WeaponStatus()
    return weaponEnchantStatus()
end

-- Item cooldown APIs have existed in both namespace and global forms, with
-- some clients returning a table and others returning separate values.  Keep
-- this at the inventory boundary so an unavailable or differently shaped API
-- never prevents the bar from offering an item.
local function itemCooldown(itemID)
    local function number(value)
        value = tonumber(ns.Plain(value))
        if value and value == value and value >= 0 and value < math.huge then return value end
    end
    local function read(getter)
        if type(getter) ~= "function" then return nil end
        local ok, first, duration, enabled = pcall(getter, itemID)
        if not ok or ns.IsSecret(first) then return nil end
        if type(first) == "table" then
            duration = ns.Plain(first.duration) or ns.Plain(first.cooldownDuration)
            if ns.IsSecret(first.isEnabled) then return nil end
            enabled = ns.Plain(first.isEnabled)
            first = ns.Plain(first.startTime) or ns.Plain(first.start)
        end
        if ns.IsSecret(enabled) then return nil end
        first, duration, enabled = number(first), number(duration), ns.Plain(enabled)
        if enabled == false or enabled == 0 or not first or not duration or duration <= 0 then return nil end
        local clockOK, clock
        if GetTime then clockOK, clock = pcall(GetTime) end
        clock = clockOK and number(clock)
        if not clock then return nil end
        local remaining = first + duration - clock
        return remaining > 0 and remaining or nil
    end
    local remaining = read(C_Item and C_Item.GetItemCooldown)
    if remaining ~= nil then return remaining end
    return read(GetItemCooldown)
end

-- Class, level and similar item restrictions belong to the client.  Do not
-- offer a bag consumable unless its on-use action is usable by this character.
-- Running out of mana is temporary, so it remains a choice rather than being
-- confused with a class restriction.
local function itemUsable(itemID)
    local function read(getter)
        if type(getter) ~= "function" then return nil end
        local ok, usable, noMana = pcall(getter, itemID)
        if not ok or ns.IsSecret(usable) or ns.IsSecret(noMana) then return nil end
        usable, noMana = ns.Plain(usable), ns.Plain(noMana)
        if usable == 0 then usable = false elseif usable == 1 then usable = true end
        if type(usable) ~= "boolean" then return nil end
        return usable or noMana == true
    end
    local usable = read(C_Item and C_Item.IsUsableItem)
    if usable ~= nil then
        Inventory.lastUsabilityAPI = "C_Item.IsUsableItem"
        return usable, true
    end
    usable = read(IsUsableItem)
    if usable ~= nil then
        Inventory.lastUsabilityAPI = "IsUsableItem"
        return usable, true
    end
    Inventory.lastUsabilityAPI = "unavailable; native input fallback"
    return true, false
end

local function itemInfo(itemID)
    -- C_Item uses an ItemInfo table; legacy clients return multiple values.
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, first, link, _, _, _, itemType, itemSubType, _, _, icon = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(first) == "table" then
            Inventory.lastItemInfoAPI = "C_Item table"
            return ns.Plain(first.itemName or first.name),
                ns.Plain(first.itemLink or first.link),
                ns.Plain(first.itemType), ns.Plain(first.itemSubType),
                ns.Plain(first.itemTexture or first.iconFileID)
        end
        if ok and type(first) == "string" then
            Inventory.lastItemInfoAPI = "C_Item values"
            return ns.Plain(first), ns.Plain(link), ns.Plain(itemType),
                ns.Plain(itemSubType), ns.Plain(icon)
        end
        return nil
    end

    if type(GetItemInfo) ~= "function" then return nil end
    local ok, name, link, _, _, _, itemType, itemSubType, _, _, icon = pcall(GetItemInfo, itemID)
    if not ok then return nil end
    Inventory.lastItemInfoAPI = "GetItemInfo values"
    return ns.Plain(name), ns.Plain(link), ns.Plain(itemType), ns.Plain(itemSubType), ns.Plain(icon)
end

Inventory.ItemInfo = itemInfo

function Inventory:Refresh()
    if ns.IsCombatLocked() then
        self.lastStatus = "deferred: combat lockdown"
        return false
    end
    self.usabilityDeferred = nil
    local found, unresolved = {}, 0
    for _, category in ipairs(ns.CONSUMABLE_ORDER) do found[category] = {} end
    self.lastItemInfoAPI = "not queried"
    self.lastContainerAPI = "not queried"
    self.lastUsabilityAPI = "not queried"
    local maxBags = NUM_BAG_SLOTS or 4
    for bag = 0, maxBags do
        for slot = 1, bagSlots(bag) do
            local rawItemID = bagItemID(bag, slot)
            local itemID = rawItemID and tonumber(rawItemID)
            if itemID then
                local name, link, itemType, itemSubType, icon = itemInfo(itemID)
                if not name then
                    unresolved = unresolved + 1
                else
                    local category = classify(itemType, itemSubType, name, itemID)
                    if category then
                        local record = found[category][itemID]
                        if not record then
                            local usable, known = itemUsable(itemID)
                            record = { kind = "item", itemID = itemID, name = name,
                                itemLink = link or ("item:" .. itemID), icon = icon or 134400,
                                category = category, count = 0, usable = usable, usabilityKnown = known, poison = category == "weapon" and isPoison(itemSubType, name) or nil }
                            found[category][itemID] = record
                        end
                        record.count = record.count + bagItemCount(bag, slot)
                    end
                end
            end
        end
    end
    self.items, self.ownedItems = {}, {}
    for category, records in pairs(found) do
        self.items[category], self.ownedItems[category] = {}, {}
        for _, record in pairs(records) do
            self.ownedItems[category][#self.ownedItems[category] + 1] = record
            if record.usable then self.items[category][#self.items[category] + 1] = record
            end
        end
        table.sort(self.items[category], function(a, b) return a.name < b.name end)
        table.sort(self.ownedItems[category], function(a, b) return a.name < b.name end)
    end
    self.uncachedItems = unresolved
    self:UpdateUsabilityStatus()
    self:PlanUsabilityWake()
    if ns.Actions then ns.Actions:Refresh() end
    if ns.Palette then ns.Palette:Refresh() end
    return true
end

function Inventory:BeginConsumableUse(entry)
    if not entry or entry.kind ~= "item" then return end
    if entry.poison or campRule(entry.itemID) then
        self.pendingConsumable = nil
        return
    end
    self.pendingConsumable = { itemID = entry.itemID, category = entry.category, before = helpfulAuras() }
end

function Inventory:CooldownRemaining(item)
    if not item or not item.itemID then return nil end
    return itemCooldown(item.itemID)
end

function Inventory:IsUsableItem(itemID)
    return itemUsable(itemID)
end

function Inventory:UpdateUsabilityStatus()
    local unavailable, unknown = 0, 0
    for _, records in pairs(self.ownedItems or {}) do
        for _, record in ipairs(records) do
            if not record.usable then unavailable = unavailable + 1 end
            if record.usabilityKnown == false then unknown = unknown + 1 end
        end
    end
    self.ownedItemCount = 0
    for _, records in pairs(self.ownedItems or {}) do self.ownedItemCount = self.ownedItemCount + #records end
    local function count(category) return #(self.items[category] or {}) end
    self.lastStatus = ("eligible: %d food, %d scroll, %d flask, %d other, %d weapon, %d uncached item(s)"):format(
        count("food"), count("scroll"), count("flask"), count("other"), count("weapon"), self.uncachedItems or 0)
        .. ("; %d unavailable; %d unknown readiness (native input fallback)"):format(unavailable, unknown)
end

function Inventory:PlanUsabilityWake()
    for _, records in pairs(self.ownedItems or {}) do
        for _, item in ipairs(records) do
            local remaining = itemCooldown(item.itemID)
            item.cooling = remaining ~= nil
            if item.category == "food" and ns.db.consumableAuras[item.itemID] then
                item.foodMappingValid = self:LearnedAura(item) ~= nil
            else item.foodMappingValid = nil end
            if remaining then self:RefreshAfterCooldown(item, remaining) end
        end
    end
end

function Inventory:RefreshUsability()
    if ns.IsCombatLocked() then self.usabilityDeferred = true; return false end
    if not self.ownedItems then return false end
    self.usabilityDeferred = nil
    local changed = false
    for _, records in pairs(self.ownedItems) do
        for _, item in ipairs(records) do
            local usable, known = itemUsable(item.itemID)
            local remaining = itemCooldown(item.itemID)
            local cooling = remaining ~= nil
            local mappingValid
            if item.category == "food" and ns.db.consumableAuras[item.itemID] then mappingValid = self:LearnedAura(item) ~= nil end
            if item.usable ~= usable or item.usabilityKnown ~= known or item.cooling ~= cooling
                or item.foodMappingValid ~= mappingValid then changed = true end
            item.usable, item.usabilityKnown, item.cooling, item.foodMappingValid = usable, known, cooling, mappingValid
            if remaining then self:RefreshAfterCooldown(item, remaining) end
        end
    end
    if changed then
        self.items = {}
        for category, records in pairs(self.ownedItems) do
            self.items[category] = {}
            for _, item in ipairs(records) do
                if item.usable then self.items[category][#self.items[category] + 1] = item end
            end
        end
    end
    if changed then self:UpdateUsabilityStatus() end
    return changed
end

function Inventory:QueueUsabilityRefresh()
    if ns.IsCombatLocked() then self.usabilityDeferred = true; return end
    if self.ownedItemCount == 0 or self.usabilityPending then return end
    self.usabilityPending = true
    C_Timer.After(0.2, function()
        self.usabilityPending = nil
        if self:RefreshUsability() and ns.RefreshAll then ns.RefreshAll() end
    end)
end

function Inventory:RefreshAfterCooldown(item, remaining)
    remaining = remaining or self:CooldownRemaining(item)
    if not remaining or not (C_Timer and type(C_Timer.After) == "function") then return end
    local wakeAt = (GetTime and GetTime() or 0) + remaining
    if self.usabilityWakeAt and self.usabilityWakeAt <= wakeAt + 0.1 then return end
    self.usabilityWakeAt = wakeAt
    C_Timer.After(remaining + 0.1, function()
        if self.usabilityWakeAt ~= wakeAt then return end
        self.usabilityWakeAt = nil
        if self:RefreshUsability() and ns.RefreshAll then ns.RefreshAll() end
    end)
end

function Inventory:FinishConsumableUse()
    local pending = self.pendingConsumable
    self.pendingConsumable = nil
    if not pending then return end
    C_Timer.After(0.5, function()
        if ns.IsCombatLocked() then return end
        local after = helpfulAuras()
        for spellID, aura in pairs(after) do
            if not pending.before[spellID] and aura.duration > 0 and not campingAura(spellID)
                and (pending.category ~= "food" or foodAura(aura)) then
                ns.db.consumableAuras[pending.itemID] = {
                    spellID = aura.spellID, name = aura.name, duration = aura.duration,
                }
                self.lastConsumableAura = "learned " .. tostring(aura.duration) .. " second effect"
                self:Refresh()
                return
            end
        end
        self.lastConsumableAura = "no new timed effect observed"
    end)
end

-- Ownership belongs to settings/diagnostics; action choices retain the client's
-- usability filter. A temporary restriction is never evidence of an empty bag.
function Inventory:OwnedChoices(category)
    return self.ownedItems and self.ownedItems[category] or self:Choices(category)
end

function Inventory:FoodMappingSummary()
    local found = {}
    for _, item in ipairs(self:OwnedChoices("food")) do
        local mapping = ns.db.consumableAuras[item.itemID]
        if mapping then
            found[#found + 1] = tostring(item.itemID) .. " -> spell " .. tostring(mapping.spellID)
                .. (self:LearnedAura(item) and " (retained)" or " (ignored: non-food)")
            if #found == 6 then break end
        end
    end
    return #found > 0 and table.concat(found, "; ") or "none for food currently in bags"
end

function Inventory:Choices(category)
    return self.items[category] or {}
end

function Inventory:CampingStatus(item)
    local rule = campRule(item.itemID)
    if not rule then return nil end
    local getter = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getter or ns.IsCombatLocked() then return { state = "unknown" } end
    for index = 1, 128 do
        local ok, aura = pcall(getter, "player", index, rule.filter)
        if not ok or ns.IsSecret(aura) then return { state = "unknown" } end
        if not aura then return { state = "missing" } end
        local spellID = ns.Plain(aura.spellId)
        if not spellID then return { state = "unknown" } end
        if spellID == rule.spellID then
            local duration = tonumber(ns.Plain(aura.duration)) or 0
            local expiration = tonumber(ns.Plain(aura.expirationTime)) or 0
            local remaining = duration > 0 and expiration > 0 and math.max(0, expiration - GetTime()) or nil
            if remaining == 0 then return { state = "missing" } end
            return { state = "active", duration = duration, remaining = remaining }
        end
    end
    return { state = "unknown" }
end

function Inventory:CategoryStatus(category)
    if category == "weapon" then
        for _, item in ipairs(self:Choices(category)) do
            if item.poison and self:PoisonTargetSlot() then return nil end
        end
        return weaponEnchantStatus()
    end
    -- Other buffs are unrelated to each other (a stamina drink doesn't cover an
    -- agility elixir), so each item is judged by its own learned effect.
    if category == "other" then return nil end
    local auras = helpfulAuras()
    for _, aura in pairs(auras) do
        -- Blizzard's generic Well Fed icon covers the food effects that should
        -- suppress every food choice, regardless of which bag item applied it.
        -- The generic icon is present on many clients, but not all food buffs
        -- use it.  The client-facing Well Fed name is a second safe signal;
        -- item-specific effects continue to use the learned mapping below.
        if category == "food" and foodAura(aura) then
            return { state = "active", duration = aura.duration, remaining = aura.remaining }
        end
        if category == "flask" and type(aura.name) == "string"
            and string.find(string.lower(aura.name), "flask", 1, true) then
            return { state = "active", duration = aura.duration, remaining = aura.remaining }
        end
    end
    -- Once Buffsmith has observed an item's effect, the remembered aura is a
    -- client-neutral category signal as well as an item-specific one.
    for _, item in ipairs(self:OwnedChoices(category)) do
        local mapping = self:LearnedAura(item)
        local aura = mapping and auras[mapping.spellID]
        if aura then
            return { state = "active", duration = aura.duration, remaining = aura.remaining }
        end
    end
    return nil
end

function Inventory:ReminderSummary(category)
    local choices = self:OwnedChoices(category)
    if #choices == 0 then return "None in your bags." end
    local unavailable = 0
    for _, item in ipairs(choices) do if item.usable == false then unavailable = unavailable + 1 end end
    local function availability(text)
        if unavailable == 0 then return text end
        local suffix = unavailable == #choices and "; currently unavailable."
            or ("; " .. unavailable .. " currently unavailable.")
        return text:gsub("%.$", "") .. suffix
    end
    local summaries = {}
    for _, item in ipairs(choices) do
        local aura = self:LearnedAura(item)
        if aura and tonumber(aura.duration) and aura.duration > 0 then
            local seconds = math.floor(aura.duration * ns.Actions:Percent(item) / 100 + 0.5)
            summaries[#summaries + 1] = item.name .. ": " .. (seconds >= 60 and math.floor(seconds / 60) .. "m" or seconds .. "s") .. " left"
        end
    end
    if #summaries > 0 then return availability(table.concat(summaries, ", ")) end
    if category == "weapon" then return availability("Reminds while your weapon has no enhancement.") end
    return availability(#choices == 1 and "1 in your bags." or (#choices .. " in your bags."))
end

function Inventory:ReminderFor(item)
    local prefix = item.usable == false and "Currently unavailable. " or ""
    local camp = campRule(item.itemID)
    if camp then return prefix .. "Reminds when " .. camp.label .. " is missing." end
    if item.poison then return prefix .. "Reminds while an equipped weapon has no coating." end
    local aura = self:LearnedAura(item)
    if aura and tonumber(aura.duration) and aura.duration > 0 then
        local seconds = math.floor(aura.duration * ns.Actions:Percent(item) / 100 + 0.5)
        return prefix .. "Reminds with " .. (seconds >= 60 and math.floor(seconds / 60) .. "m" or seconds .. "s") .. " left"
    end
    return prefix .. "Timer is set after you use it once."
end
