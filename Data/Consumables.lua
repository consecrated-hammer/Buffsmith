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
    weapon = {
        label = "Weapon enhancement", icon = 134712,
        subtypes = {
            [ITEM_SUBCLASS_CONSUMABLE_ITEM_ENHANCEMENT or "Item Enhancement"] = true,
            ["Weapon Enhancement"] = true,
            ["Weapon Enchantment"] = true,
        },
    },
}
