local addonName, ns = ...

-- Minimap tracking (Find Herbs, Find Minerals, class and racial senses).
-- Buffsmith reads the character's own tracking list and offers each
-- spell-based type as a bar action.  The icon casts the tracking spell
-- through the bar's secure button: C_Minimap.SetTracking is restricted to
-- untainted code, so Buffsmith never switches tracking itself.

ns.Tracking = {}
local Tracking = ns.Tracking

-- Gathering professions start ticked; class and racial tracking start off.
-- Find Herbs, Find Minerals, Find Fish.
Tracking.DEFAULT_ON = { [2383] = true, [2580] = true, [43308] = true }

local function trackingAPI()
    local minimap = C_Minimap
    if minimap and minimap.GetNumTrackingTypes and minimap.GetTrackingInfo then
        return minimap.GetNumTrackingTypes, minimap.GetTrackingInfo
    end
    if GetNumTrackingTypes and GetTrackingInfo then return GetNumTrackingTypes, GetTrackingInfo end
end

-- Mainline returns a table; older clients returned the same fields in order.
local function readInfo(getInfo, index)
    local ok, first, texture, active, kind, subType, spellID = pcall(getInfo, index)
    if not ok or first == nil then return nil end
    if type(first) == "table" then return first end
    return { name = first, texture = texture, active = active, type = kind, subType = subType, spellID = spellID }
end

-- Remembers a client that allows several tracking types at once; see
-- Tracking.Exclusive.
local function observeConcurrency(list)
    if not ns.db or ns.db.trackingConcurrent then return end
    local active = 0
    for _, entry in ipairs(list) do
        if entry.active then active = active + 1 end
    end
    if active >= 2 then ns.db.trackingConcurrent = true end
end

-- Every spell-based tracking type this character has, in the client's order.
function Tracking:Available()
    local list = {}
    local count, getInfo = trackingAPI()
    if not count then
        self.lastStatus = "tracking API unavailable"
        return list
    end
    local ok, total = pcall(count)
    total = ok and tonumber(ns.Plain(total)) or 0
    for index = 1, math.min(total, 64) do
        local info = readInfo(getInfo, index)
        local spellID = info and tonumber(ns.Plain(info.spellID))
        if info and ns.Plain(info.type) == "spell" and spellID then
            list[#list + 1] = {
                kind = "spell", tracking = true, index = index,
                spellID = spellID, castID = spellID,
                name = ns.Plain(info.name) or ("Spell " .. spellID),
                icon = ns.Plain(info.texture) or 134400,
                active = ns.Plain(info.active) == true,
                permanent = true,
                defaultOff = not Tracking.DEFAULT_ON[spellID],
            }
        end
    end
    -- With no competing spell-based tracker, this is a useful default even
    -- for a racial/class sense. Explicit scoped Off choices still win.
    if #list == 1 then list[1].defaultOff = false end
    self.lastStatus = #list .. " tracking types"
    observeConcurrency(list)
    return list
end

-- Classic-era clients are expected to track one thing at a time, so on WoW
-- Forever the ticked tracking types share one slot, like Paladin blessings.
-- The assumption is checked, not trusted: the first time two tracking types
-- are seen active together, this client is remembered as allowing several.
function Tracking.Exclusive()
    if ns.db and ns.db.trackingConcurrent then return false end
    return ns.TARGET == "Camelot"
end

local function offered(entry)
    return not ns.IsBuffExcluded(entry) and not (ns.Actions and ns.Actions:IsSuppressed(entry))
end

-- Scope is configured per tracking type. Legacy account choices remain intact
-- and are adopted only when the player explicitly enables Shared for that type.
local cachedDB, cachedRoot, cachedCharacters, cachedAccount, cachedShared
local EMPTY = {}
local function settings()
    if not ns.db then return end
    local root = ns.db.trackingPreferences
    if ns.db == cachedDB and root == cachedRoot and type(root) == "table"
        and root.characters == cachedCharacters and root.account == cachedAccount and root.sharedTypes == cachedShared
        and type(root.serial) == "number" and root.serial == root.serial and root.serial < math.huge then return root end
    if type(root) ~= "table" then root = {}; ns.db.trackingPreferences = root end
    for _, key in ipairs({ "sharedTypes", "account", "characters" }) do
        if type(root[key]) ~= "table" then root[key] = {} end
    end
    local serial = tonumber(root.serial)
    root.serial = serial and serial == serial and serial < math.huge and math.max(0, math.floor(serial)) or 0
    cachedDB, cachedRoot = ns.db, root
    cachedCharacters, cachedAccount, cachedShared = root.characters, root.account, root.sharedTypes
    return root
end
local function character(root, create)
    local guid = UnitGUID and ns.Plain(UnitGUID("player"))
    if type(guid) == "string" and guid ~= "" then
        if type(root.characters[guid]) ~= "table" then
            if not create then return EMPTY end
            root.characters[guid] = {}
        end
        return root.characters[guid]
    end
    -- Do not accept a choice under a temporary/unknown identity.
end
local function valid(record)
    return type(record) == "table" and type(record.enabled) == "boolean"
end
local function duplicate(pref)
    return { enabled = pref.enabled, order = pref.order, ignored = pref.ignored }
end
function Tracking:IsShared(spellID)
    local root = settings()
    return root and root.sharedTypes[spellID] == true or false
end
function Tracking:Preference(entry)
    local root = settings()
    if not root then return { enabled = not entry.defaultOff, order = 0 } end
    local store = self:IsShared(entry.spellID) and root.account or character(root)
    local pref = store and store[entry.spellID]
    if valid(pref) then return pref end
    return { enabled = not entry.defaultOff, order = 0 }
end
function Tracking:IsExcluded(entry) return not self:Preference(entry).enabled end
function Tracking:IsIgnored(entry) return self:Preference(entry).ignored == true end
function Tracking:SetEnabled(entry, enabled, ignored)
    local root = settings()
    local own = root and character(root, true)
    if not own then
        if ns.HammerCore then ns.HammerCore.Print("Tracking preference not saved: your character is still loading.") end
        return false
    end
    local selected = ignored and self.Exclusive() and self:SelectedID()
    local store = self:IsShared(entry.spellID) and root.account or own
    root.serial = root.serial + 1
    local rank = ignored and self:Preference(entry).order or root.serial
    store[entry.spellID] = { enabled = enabled == true, order = rank or 0, ignored = ignored == true }
    if selected == entry.spellID and not enabled then own.selection = { id = false, order = root.serial, ignored = entry.spellID } end
    return true
end
-- Restoring an ignore preserves ordering, so it cannot steal an existing selection.
function Tracking:Restore(entry)
    local root = settings()
    local own = root and character(root, true)
    if not own then return false end
    local store = self:IsShared(entry.spellID) and root.account or own
    local pref = duplicate(self:Preference(entry))
    pref.enabled, pref.ignored = true, false
    store[entry.spellID] = pref
    if type(own.selection) == "table" and own.selection.ignored == entry.spellID then own.selection = nil end
    return true
end

function Tracking:SetShared(entry, shared)
    local root = settings()
    if not root or self:IsShared(entry.spellID) == (shared == true) then return end
    local own = character(root, true)
    if not own then return false end
    if shared then
        if not valid(root.account[entry.spellID]) then
            local pref = duplicate(self:Preference(entry))
            if not valid(own[entry.spellID]) then
                local legacy = ns.db.excludedBuffs and ns.db.excludedBuffs[entry.spellID]
                if legacy ~= nil then pref = { enabled = legacy ~= true, order = 0, ignored = legacy == true }
                elseif self.Exclusive() and ns.db.trackingChoice ~= nil then
                    pref = { enabled = ns.db.trackingChoice == entry.spellID, order = 0 }
                end
            end
            root.account[entry.spellID] = pref
        end
        root.sharedTypes[entry.spellID] = true
    else
        own[entry.spellID] = duplicate(self:Preference(entry))
        root.sharedTypes[entry.spellID] = nil
    end
end
function Tracking:Reset()
    local root = settings()
    if not root then return end
    local own = character(root, true)
    if not own then return false end
    for key in pairs(own) do own[key] = nil end
    return true
end

-- Explicit newer choices win if shared and character preferences conflict.
-- With only defaults, one eligible tracker can be offered automatically;
-- several defaults require a choice, unless one is already active in game.
function Tracking:SelectedID(list)
    local selected, order, tied, active, activeCount = nil, -1, false, nil, 0
    for _, entry in ipairs(list or self:Available()) do
        local pref = self:Preference(entry)
        if pref.enabled then
            local rank = tonumber(pref.order) or 0
            if rank ~= rank or rank == math.huge then rank = 0 end
            if rank > order then selected, order, tied = entry.spellID, rank, false
            elseif rank == order then tied = true end
            if entry.active then active, activeCount = entry.spellID, activeCount + 1 end
        end
    end
    local root = settings()
    local own = root and character(root)
    local selection = own and own.selection
    if type(selection) == "table" and selection.id == false and (tonumber(selection.order) or 0) >= order then return nil end
    if not tied then return selected end
    if order == 0 and activeCount == 1 then return active end
end
function Tracking:Select(spellID, force)
    local root = settings()
    local own = root and character(root, true)
    if not own then
        if ns.HammerCore then ns.HammerCore.Print("Tracking preference not saved: your character is still loading.") end
        return false
    end
    local list = self:Available()
    local enable = force or self:SelectedID(list) ~= spellID
    for _, entry in ipairs(list) do
        if entry.spellID == spellID then
            self:SetEnabled(entry, enable)
            own.selection = { id = enable and spellID or false, order = root.serial }
            return true
        end
    end
    return false
end

-- The tracking actions the bar should show now.
function Tracking:Entries()
    local shown, ticked = {}, {}
    local available = self:Available()
    for _, entry in ipairs(available) do
        if not ns.IsBuffExcluded(entry) then ticked[#ticked + 1] = entry end
    end
    if Tracking.Exclusive() then
        local selected = self:SelectedID(available)
        for _, entry in ipairs(ticked) do
            -- An active different tracker is exactly when the selected one
            -- needs to be offered: clicking Minerals replaces active Herbs.
            if entry.active and entry.spellID == selected then return shown end
        end
        for _, entry in ipairs(ticked) do
            if entry.spellID == selected and offered(entry) then
                shown[1] = entry
                return shown
            end
        end
        return shown
    end
    for _, entry in ipairs(ticked) do
        if not entry.active and offered(entry) then shown[#shown + 1] = entry end
    end
    return shown
end

function Tracking:Summary()
    local parts = {}
    for _, entry in ipairs(self:Available()) do
        parts[#parts + 1] = entry.name .. (entry.active and " (on)" or "")
            .. (ns.IsBuffExcluded(entry) and " [off]" or "")
            .. (self:IsShared(entry.spellID) and " [shared]" or " [character]")
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end
