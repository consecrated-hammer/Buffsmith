local addonName, ns = ...

-- Consumable classification uses client-provided localized item type strings.
ns.CONSUMABLE_CATEGORIES = {
    food = {
        label = "Food", icon = 134062,
        subtypes = { [ITEM_SUBCLASS_CONSUMABLE_FOOD_AND_DRINK or "Food & Drink"] = true },
    },
    scroll = {
        label = "Scroll", icon = 134943,
        subtypes = { [ITEM_SUBCLASS_CONSUMABLE_SCROLL or "Scroll"] = true },
    },
    flask = {
        label = "Flask", icon = 236884,
        subtypes = { [ITEM_SUBCLASS_CONSUMABLE_FLASK or "Flask"] = true },
    },
    -- Elixirs, and drinks or other consumables whose "Use:" line gives a
    -- timed stat buff that isn't Well Fed (Keg of Thunderbrew, for one).
    other = {
        label = "Other buffs", icon = 134821,
        subtypes = { [ITEM_SUBCLASS_CONSUMABLE_ELIXIR or "Elixir"] = true },
    },
    weapon = {
        label = "Weapon enhancement", icon = 134712,
        subtypes = {
            [ITEM_SUBCLASS_CONSUMABLE_ITEM_ENHANCEMENT or "Item Enhancement"] = true,
            ["Weapon Enhancement"] = true,
            ["Weapon Enchantment"] = true,
        },
    },
}

-- The order categories appear on the bar, the trigger and the settings page.
ns.CONSUMABLE_ORDER = { "food", "scroll", "flask", "other", "weapon" }
