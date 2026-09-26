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

-- The tracking actions the bar should show now.
function Tracking:Entries()
    local shown, ticked = {}, {}
    for _, entry in ipairs(self:Available()) do
        if not ns.IsBuffExcluded(entry) then ticked[#ticked + 1] = entry end
    end
    if Tracking.Exclusive() then
        for _, entry in ipairs(ticked) do
            if entry.active then return shown end
        end
        for _, entry in ipairs(ticked) do
            if offered(entry) then
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
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end
