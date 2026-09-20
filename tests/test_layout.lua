local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local ns = {}
assert(loadfile("UI/Layout.lua"))("Buffsmith", ns)
local Layout = ns.Layout

-- Transcribed verbatim from the pre-refactor UI/Palette.lua Refresh loop so a
-- transcription slip in Layout.lua cannot pass unnoticed. Do not tidy this:
-- its value is being a faithful copy of the behaviour that shipped.
local function reference(items, opts)
    local mainSize = opts.mainSize
    local subSize = math.max(22, math.floor(mainSize * 0.76))
    local spacing = 6
    local vertical = opts.vertical == true
    local mainX, mainY = 2, -2
    local width, height = mainSize + 4, mainSize + 4
    local mains, subs = {}, {}
    for _, item in ipairs(items) do
        local x, y = mainX, mainY
        mains[#mains + 1] = { x = x, y = y, size = mainSize }
        if vertical then
            mainY = mainY - mainSize - spacing
            height = math.max(height, -mainY + 2)
        else
            mainX = mainX + mainSize + spacing
            width = math.max(width, mainX - spacing + 2)
        end
        local primaryX, primaryY = x, y
        local shown = 0
        for _ = 1, (item.subs or 0) do
            shown = shown + 1
            local sx, sy
            if vertical then
                sx, sy = math.floor((mainSize - subSize) / 2) + 2, mainY
                mainY = mainY - subSize - 4
                height = math.max(height, -mainY + 2)
            else
                sx = primaryX + math.floor((mainSize - subSize) / 2)
                sy = primaryY - mainSize - 4 - (shown - 1) * (subSize + 4)
                height = math.max(height, -sy + subSize + 4)
            end
            subs[#subs + 1] = { x = sx, y = sy, size = subSize }
        end
    end
    return {
        mains = mains, subs = subs,
        width = math.max(mainSize + 4, width),
        height = math.max(mainSize + 4, height),
    }
end

local function compare(items, opts, label)
    local got, want = Layout.Compute(items, opts), reference(items, opts)
    equal(got.width, want.width, label .. " width")
    equal(got.height, want.height, label .. " height")
    equal(#got.mains, #want.mains, label .. " main count")
    equal(#got.subs, #want.subs, label .. " sub count")
    for i, main in ipairs(want.mains) do
        equal(got.mains[i].x, main.x, label .. " main " .. i .. " x")
        equal(got.mains[i].y, main.y, label .. " main " .. i .. " y")
        equal(got.mains[i].size, main.size, label .. " main " .. i .. " size")
    end
    for i, sub in ipairs(want.subs) do
        equal(got.subs[i].x, sub.x, label .. " sub " .. i .. " x")
        equal(got.subs[i].y, sub.y, label .. " sub " .. i .. " y")
        equal(got.subs[i].size, sub.size, label .. " sub " .. i .. " size")
    end
end

-- Spot checks pinning the shipped numbers, independent of the reference copy.
local horizontal = Layout.Compute({ {}, {}, {} }, { mainSize = 40, vertical = false })
equal(horizontal.width, 136, "three 40px icons span 3*40 + 2*6 + 4")
equal(horizontal.height, 44, "a horizontal row without alternatives is one icon tall")
equal(horizontal.mains[2].x, 48, "the second icon clears the first plus spacing")
equal(horizontal.mains[2].y, -2, "a horizontal row keeps every icon on one line")

-- Vertical mode counts the trailing gap below the last icon, so a lone 40px
-- icon reports 50 rather than 44. Shipped behaviour; preserved deliberately.
local vertical = Layout.Compute({ {} }, { mainSize = 40, vertical = true })
equal(vertical.height, 50, "vertical height includes the trailing spacing")
equal(vertical.width, 44, "vertical width is one icon wide")

-- The coupling that makes the extraction worth testing: in vertical mode a
-- category's alternatives push every later primary further down.
local pushed = Layout.Compute({ { toggle = "food", subs = 2 }, {} }, { mainSize = 40, vertical = true })
equal(pushed.mains[2].y, -116, "alternatives displace the following primary")
equal(pushed.height, 164, "alternatives grow the bar")
equal(pushed.toggles.food, 1, "the toggle anchors to its own primary")
equal(pushed.subSize, 30, "40px icons take 30px alternatives")

-- Horizontal alternatives hang below their primary and never widen the bar.
local hanging = Layout.Compute({ { toggle = "food", subs = 2 }, {} }, { mainSize = 40, vertical = false })
equal(hanging.mains[2].x, 48, "alternatives do not displace the following primary")
equal(hanging.width, 90, "alternatives never widen the bar")
equal(hanging.subs[1].x, 7, "an alternative centres under its primary")
equal(hanging.subs[2].y, -80, "alternatives stack downward")

local empty = Layout.Compute({}, { mainSize = 40, vertical = true })
equal(#empty.mains, 0, "an empty bar places nothing")
equal(empty.width, 44, "an empty bar keeps the minimum width")
equal(empty.height, 44, "an empty bar keeps the minimum height")

equal(Layout.SubSize(24), 22, "small icons clamp alternatives to the 22px floor")
equal(Layout.SubSize(64), 48, "large icons scale alternatives by 0.76")

-- Fuzz every orientation, icon size and alternative count against the copy.
for _, isVertical in ipairs({ true, false }) do
    for mainSize = 24, 64, 2 do
        for subs = 0, 3 do
            for mains = 0, 4 do
                local items = {}
                for index = 1, mains do
                    items[index] = { toggle = index == mains and "food" or nil, subs = index == mains and subs or 0 }
                end
                compare(items, { mainSize = mainSize, vertical = isVertical },
                    ("%s size=%d mains=%d subs=%d"):format(isVertical and "vertical" or "horizontal", mainSize, mains, subs))
            end
        end
    end
end

print("layout tests passed")
