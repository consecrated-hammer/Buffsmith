local addonName, ns = ...

-- Pure geometry for the icon bar, shared by the live secure bar and the
-- settings preview. No WoW API calls belong here: the preview must be able to
-- lay itself out without touching the secure buttons the live bar owns.
--
-- Callers resolve `expanded` and `maxAlternatives` into the item list first.
-- Alternatives are placed immediately after their primary, and in vertical
-- mode they advance the shared cursor, so a category's alternatives push every
-- later primary down. That coupling is deliberate and load-bearing.

ns.Layout = {}
local Layout = ns.Layout

local SPACING = 6
local SUB_GAP = 4
local MIN_SUB_SIZE = 22
local SUB_SCALE = 0.76
local INSET = 2

function Layout.SubSize(mainSize)
    return math.max(MIN_SUB_SIZE, math.floor(mainSize * SUB_SCALE))
end

-- items: ordered list of { toggle = <category or nil>, subs = <alternative count> }
-- opts:  { mainSize = <px>, vertical = <boolean> }
function Layout.Compute(items, opts)
    local mainSize = opts.mainSize
    local vertical = opts.vertical == true
    local subSize = Layout.SubSize(mainSize)
    local mainX, mainY = INSET, -INSET
    local width, height = mainSize + 4, mainSize + 4
    local mains, subs, toggles = {}, {}, {}

    for _, item in ipairs(items) do
        local x, y = mainX, mainY
        mains[#mains + 1] = { x = x, y = y, size = mainSize }
        if item.toggle then toggles[item.toggle] = #mains end

        if vertical then
            mainY = mainY - mainSize - SPACING
            height = math.max(height, -mainY + INSET)
        else
            mainX = mainX + mainSize + SPACING
            width = math.max(width, mainX - SPACING + INSET)
        end

        for shown = 1, (item.subs or 0) do
            local sx, sy
            if vertical then
                sx, sy = math.floor((mainSize - subSize) / 2) + INSET, mainY
                mainY = mainY - subSize - SUB_GAP
                height = math.max(height, -mainY + INSET)
            else
                sx = x + math.floor((mainSize - subSize) / 2)
                sy = y - mainSize - SUB_GAP - (shown - 1) * (subSize + SUB_GAP)
                height = math.max(height, -sy + subSize + SUB_GAP)
            end
            subs[#subs + 1] = { x = sx, y = sy, size = subSize }
        end
    end

    return {
        mains = mains,
        subs = subs,
        toggles = toggles,
        subSize = subSize,
        width = math.max(mainSize + 4, width),
        height = math.max(mainSize + 4, height),
    }
end
