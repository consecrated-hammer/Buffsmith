local addonName, ns = ...

ns.Inventory = { items = {}, lastStatus = "not scanned" }
local Inventory = ns.Inventory

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
        if ok and itemID then return itemID end
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

local function classify(itemType, itemSubType, itemName, itemID)
    if itemType ~= ITEM_CLASS_CONSUMABLE and itemType ~= "Consumable" then return nil end
    local food = ns.CONSUMABLE_CATEGORIES.food.subtypes[itemSubType] or itemSubType == "Food & Drink"
    if food then return foodProvidesBuff(itemID) and "food" or nil end

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
    return nil
end

local function weaponEnchantStatus()
    if type(GetWeaponEnchantInfo) ~= "function" then return nil end
    local ok, mainHand, mainExpires, _, _, offHand, offExpires = pcall(GetWeaponEnchantInfo)
    if not ok or not (mainHand or offHand) then return nil end
    local remaining = math.max(tonumber(mainHand and mainExpires) or 0, tonumber(offHand and offExpires) or 0) / 1000
    return { state = "active", duration = 0, remaining = remaining > 0 and remaining or nil }
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

function Inventory:Refresh()
    if ns.IsCombatLocked() then
        self.lastStatus = "deferred: combat lockdown"
        return false
    end
    local found, unresolved = { food = {}, scroll = {}, flask = {}, weapon = {} }, 0
    self.lastItemInfoAPI = "not queried"
    self.lastContainerAPI = "not queried"
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
                            record = { kind = "item", itemID = itemID, name = name,
                                itemLink = link or ("item:" .. itemID), icon = icon or 134400,
                                category = category, count = 0 }
                            found[category][itemID] = record
                        end
                        record.count = record.count + bagItemCount(bag, slot)
                    end
                end
            end
        end
    end
    self.items = {}
    for category, records in pairs(found) do
        self.items[category] = {}
        for _, record in pairs(records) do self.items[category][#self.items[category] + 1] = record end
        table.sort(self.items[category], function(a, b) return a.name < b.name end)
    end
    self.lastStatus = ("ready: %d food, %d scroll, %d flask, %d weapon, %d uncached item(s)"):format(
        #self.items.food, #self.items.scroll, #self.items.flask, #self.items.weapon, unresolved)
    if ns.Actions then ns.Actions:Refresh() end
    if ns.Palette then ns.Palette:Refresh() end
    return true
end

function Inventory:BeginConsumableUse(entry)
    if not entry or entry.kind ~= "item" then return end
    self.pendingConsumable = { itemID = entry.itemID, before = helpfulAuras() }
end

function Inventory:FinishConsumableUse()
    local pending = self.pendingConsumable
    self.pendingConsumable = nil
    if not pending then return end
    C_Timer.After(0.5, function()
        if ns.IsCombatLocked() then return end
        local after = helpfulAuras()
        for spellID, aura in pairs(after) do
            if not pending.before[spellID] and aura.duration > 0 then
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

function Inventory:Choices(category)
    return self.items[category] or {}
end

function Inventory:CategoryStatus(category)
    if category == "weapon" then return weaponEnchantStatus() end
    local auras = helpfulAuras()
    for _, aura in pairs(auras) do
        -- Blizzard's generic Well Fed icon covers the food effects that should
        -- suppress every food choice, regardless of which bag item applied it.
        if category == "food" and aura.icon == 136000 then
            return { state = "active", duration = aura.duration, remaining = aura.remaining }
        end
        if category == "flask" and type(aura.name) == "string"
            and string.find(string.lower(aura.name), "flask", 1, true) then
            return { state = "active", duration = aura.duration, remaining = aura.remaining }
        end
    end
    -- Once Buffsmith has observed an item's effect, the remembered aura is a
    -- client-neutral category signal as well as an item-specific one.
    for _, item in ipairs(self:Choices(category)) do
        local mapping = ns.db.consumableAuras[item.itemID]
        local aura = mapping and auras[mapping.spellID]
        if aura then
            return { state = "active", duration = aura.duration, remaining = aura.remaining }
        end
    end
    return nil
end

function Inventory:ReminderSummary(category)
    local choices = self:Choices(category)
    if #choices == 0 then return "None in your bags." end
    local summaries = {}
    for _, item in ipairs(choices) do
        local aura = ns.db.consumableAuras[item.itemID]
        if aura and tonumber(aura.duration) and aura.duration > 0 then
            local seconds = math.floor(aura.duration * ns.Actions:Percent(item) / 100 + 0.5)
            summaries[#summaries + 1] = item.name .. ": " .. (seconds >= 60 and math.floor(seconds / 60) .. "m" or seconds .. "s") .. " left"
        end
    end
    if #summaries > 0 then return table.concat(summaries, ", ") end
    if category == "weapon" then return "Reminds while your weapon has no enhancement." end
    return #choices == 1 and "1 in your bags." or (#choices .. " in your bags.")
end

function Inventory:ReminderFor(item)
    local aura = ns.db.consumableAuras[item.itemID]
    if aura and tonumber(aura.duration) and aura.duration > 0 then
        local seconds = math.floor(aura.duration * ns.Actions:Percent(item) / 100 + 0.5)
        return "Reminds with " .. (seconds >= 60 and math.floor(seconds / 60) .. "m" or seconds .. "s") .. " left"
    end
    return "Timer is set after you use it once."
end
