-- Item definitions (shared, so the client knows labels and weights).
--   label        display name
--   weight       grams per unit
--   stack        true = units stack in one slot; false = each unit is its own slot (unique items)
--   maxStack     most units in one slot (stackable items; omit for no limit)
--   description  shown in the tooltip
--   usable       can be used from the inventory / hotbar
--   consume      units removed when used (0 = not removed)
--   effect       built-in client effect when used: { heal = 25 } (more in later phases)
--   close        close the inventory when used
--
-- Other resources can add items at runtime: exports['tfc-inventory']:RegisterItem(name, def)
-- and react to use with the server hook: TFC.On('itemUsed', function(src, name, slot) ... end)

Items = {
    cash = {
        label = 'Cash',
        weight = 0,
        stack = true,
        description = 'Paper money. Counts as your cash balance.',
    },

    phone = {
        label = 'Phone',
        weight = 190,
        stack = false,
        description = 'A smartphone.',
    },

    water = {
        label = 'Water',
        weight = 500,
        stack = true,
        maxStack = 10,
        description = 'A bottle of water.',
        usable = true,
        consume = 1,
    },

    sandwich = {
        label = 'Sandwich',
        weight = 250,
        stack = true,
        maxStack = 10,
        description = 'A wrapped deli sandwich.',
        usable = true,
        consume = 1,
    },

    bandage = {
        label = 'Bandage',
        weight = 100,
        stack = true,
        maxStack = 20,
        description = 'Stops minor bleeding. Restores some health.',
        usable = true,
        consume = 1,
        effect = { heal = 25 },
        close = true,
    },

    lockpick = {
        label = 'Lockpick',
        weight = 150,
        stack = true,
        maxStack = 10,
        description = 'For locks that are not yours.',
    },

    radio = {
        label = 'Radio',
        weight = 600,
        stack = false,
        description = 'A handheld two-way radio.',
    },

    id_card = {
        label = 'ID Card',
        weight = 10,
        stack = false,
        description = 'Government-issued identification.',
    },

    repair_kit = {
        label = 'Repair Kit',
        weight = 2500,
        stack = true,
        maxStack = 5,
        description = 'Basic tools to get a car running again.',
    },
}
