-- Shops. Shop TYPES (what is sold, prices, payment, hours, job locks) live here.
-- Shop LOCATIONS live in the database and are managed in game with /shops (admins).
-- `Locations` below is only used to fill the database the first time the resource starts.

ShopsConfig = {
    -- Which clock opening hours use: 'game' (the GTA clock players see; read from tfc-world when
    -- it's running) or 'real' (the server's real time).
    Clock = 'game',

    InteractDistance = 2.0,  -- how close to stand to the shopkeeper to press E
    PedDistance = 60.0,      -- shopkeepers spawn when you are this close
    MaxQuantity = 50,        -- most of one item per purchase / sale
    Command = 'shops',       -- admin shop manager

    -- Payment labels shown in the shop.
    PaymentLabels = { cash = 'Cash', bank = 'Bank', credit = 'Card (credit)' },
}

--[[ Shop types
    label     name shown in the prompt and the shop window
    ped       shopkeeper model; scenario = what they do while standing
    blip      { sprite, color, scale } or false for no map blip (admins can override per shop)
    payment   accounts the player can pay with: 'cash', 'bank', 'credit'. Order = default first
    hours     { open, close } in hours (0-23); may wrap past midnight, e.g. { 20, 5 }. nil = always open
    job       { name = 'police', grade = 0, duty = true } -> only that job (at least that rank, on duty)
    items     what the shop sells: { name, price, stock?, grade?, license? }
                license = a license (tfc-government) the buyer must hold, e.g. 'weapon'
                stock = limited, restocks up to this amount; nil = unlimited
                grade = minimum job rank for this item (job-locked shops)
    restock   { minutes, amount } how limited stock refills
    buys      what the shop buys from players: { name, price }
    sellTo    account players are paid into when selling (default 'cash')
    scratched true = guns bought here have scratched-off serial numbers
]]

ShopsConfig.Types = {
    general = {
        label = '24/7 Store',
        ped = 'mp_m_shopkeeper_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        blip = { sprite = 52, color = 2, scale = 0.7 },
        payment = { 'cash', 'bank', 'credit' },
        items = {
            { name = 'phone', price = 250 },
            { name = 'radio', price = 400 },
            { name = 'bandage', price = 25 },
            { name = 'rolling_papers', price = 5 },
            { name = 'repair_kit', price = 350 },
            { name = 'flashlight', price = 60 },
            { name = 'jerrycan', price = 120 },
        },
    },

    ammunation = {
        label = 'Ammu-Nation',
        ped = 's_m_y_ammucity_01', scenario = 'WORLD_HUMAN_COP_IDLES',
        blip = { sprite = 110, color = 1, scale = 0.7 },
        payment = { 'bank', 'cash', 'credit' },
        items = {
            { name = 'knife', price = 150 },
            { name = 'bat', price = 90 },
            { name = 'golfclub', price = 120 },
            { name = 'snspistol', price = 1800, license = 'weapon' },
            { name = 'pistol', price = 2500, license = 'weapon' },
            { name = 'vintagepistol', price = 3200, license = 'weapon' },
            { name = 'pumpshotgun', price = 6500, license = 'weapon' },
            { name = 'ammo_9mm', price = 3 },
            { name = 'ammo_12g', price = 8 },
            { name = 'weapon_kit', price = 200 },
            -- Weapon mods: hold the gun and use the mod to fit it (/removemods takes them off).
            { name = 'mod_flashlight', price = 300 },
            { name = 'mod_grip', price = 600 },
            { name = 'mod_scope', price = 1200 },
            { name = 'mod_extclip', price = 900, license = 'weapon' },
            { name = 'mod_suppressor', price = 4000, license = 'weapon' },
        },
        buys = {
            { name = 'snspistol', price = 600 },
            { name = 'pistol', price = 800 },
            { name = 'vintagepistol', price = 1000 },
            { name = 'pumpshotgun', price = 2000 },
        },
        sellTo = 'bank',
    },

    pawn = {
        label = 'Pawn Shop',
        ped = 'a_m_m_business_01', scenario = 'WORLD_HUMAN_CLIPBOARD',
        blip = { sprite = 52, color = 5, scale = 0.7 },
        payment = { 'cash' },
        hours = { 8, 22 },
        items = {
            { name = 'lockpick', price = 120, stock = 10 },
            { name = 'crowbar', price = 150, stock = 5 },
        },
        restock = { minutes = 60, amount = 2 },
        buys = {
            { name = 'phone', price = 80 },
            { name = 'radio', price = 120 },
            { name = 'repair_kit', price = 100 },
            { name = 'weapon_kit', price = 60 },
            { name = 'lockpick', price = 30 },
            { name = 'hammer', price = 20 },
            { name = 'golfclub', price = 30 },
        },
    },

    drugdealer = {
        label = 'Dealer',
        ped = 's_m_y_dealer_01', scenario = 'WORLD_HUMAN_DRUG_DEALER',
        blip = false,
        payment = { 'cash' },
        hours = { 20, 5 },
        items = {
            { name = 'rolling_papers', price = 10 },
            { name = 'weed_bag', price = 60, stock = 40 },
            { name = 'lockpick', price = 150, stock = 10 },
        },
        restock = { minutes = 30, amount = 5 },
        buys = {
            { name = 'weed_bag', price = 35 },
            { name = 'joint', price = 15 },
            { name = 'coke_bag', price = 120 },
            { name = 'coke_brick', price = 3500 },
            { name = 'crack_rock', price = 45 },
            { name = 'meth_bag', price = 110 },
            { name = 'oxy', price = 40 },
            { name = 'ecstasy', price = 50 },
        },
    },

    armsdealer = {
        label = 'Arms Dealer',
        ped = 'g_m_m_armboss_01', scenario = 'WORLD_HUMAN_SMOKING',
        blip = false,
        payment = { 'cash' },
        hours = { 22, 4 },
        scratched = true,
        items = {
            { name = 'switchblade', price = 300, stock = 10 },
            { name = 'knuckles', price = 250, stock = 10 },
            { name = 'pistol', price = 6000, stock = 3 },
            { name = 'machinepistol', price = 15000, stock = 2 },
            { name = 'sawnoff', price = 12000, stock = 2 },
            { name = 'ammo_9mm', price = 6, stock = 500 },
            { name = 'ammo_12g', price = 12, stock = 200 },
            { name = 'weapon_kit', price = 400, stock = 5 },
            { name = 'mod_extclip', price = 1800, stock = 4 },
            { name = 'mod_suppressor', price = 7500, stock = 2 },
        },
        restock = { minutes = 60, amount = 1 },
    },

    police_armory = {
        label = 'Police Armory',
        ped = 's_m_y_cop_01', scenario = 'WORLD_HUMAN_COP_IDLES',
        blip = false,
        payment = { 'bank' },
        job = { name = 'police', grade = 0, duty = true },
        items = {
            { name = 'nightstick', price = 0 },
            { name = 'flashlight', price = 0 },
            { name = 'stungun', price = 0 },
            { name = 'radio', price = 0 },
            { name = 'bandage', price = 0 },
            { name = 'combatpistol', price = 0, grade = 1 },
            { name = 'ammo_9mm', price = 0, grade = 1 },
            { name = 'pumpshotgun', price = 0, grade = 2 },
            { name = 'ammo_12g', price = 0, grade = 2 },
            { name = 'carbinerifle', price = 0, grade = 3 },
            { name = 'ammo_556', price = 0, grade = 3 },
            { name = 'weapon_kit', price = 0 },
        },
    },

    ems_supply = {
        label = 'EMS Supply',
        ped = 's_m_m_paramedic_01', scenario = 'WORLD_HUMAN_CLIPBOARD',
        blip = false,
        payment = { 'bank' },
        job = { name = 'ambulance', grade = 0, duty = true },
        items = {
            { name = 'bandage', price = 0 },
            { name = 'radio', price = 0 },
            { name = 'flashlight', price = 0 },
            { name = 'extinguisher', price = 0 },
        },
    },
}

-- First start only: these are copied into the database. After that, use /shops in game.
-- x, y, z, heading of the shopkeeper.
ShopsConfig.Locations = {
    { type = 'general', coords = vector4(24.47, -1346.62, 29.5, 271.66) },
    { type = 'general', coords = vector4(-3039.54, 584.38, 7.91, 17.27) },
    { type = 'general', coords = vector4(-3242.97, 1000.01, 12.83, 357.57) },
    { type = 'general', coords = vector4(1728.07, 6416.63, 35.04, 247.55) },
    { type = 'general', coords = vector4(1959.82, 3740.48, 32.34, 301.57) },
    { type = 'general', coords = vector4(549.13, 2670.85, 42.16, 99.39) },
    { type = 'general', coords = vector4(2677.47, 3279.76, 55.24, 335.08) },
    { type = 'general', coords = vector4(2556.66, 380.84, 108.62, 356.67) },
    { type = 'general', coords = vector4(372.66, 326.98, 103.57, 253.73) },

    { type = 'ammunation', coords = vector4(-661.96, -933.53, 21.83, 177.05) },
    { type = 'ammunation', coords = vector4(809.68, -2159.13, 29.62, 1.43) },
    { type = 'ammunation', coords = vector4(1692.67, 3761.38, 34.71, 227.65) },
    { type = 'ammunation', coords = vector4(-331.23, 6085.37, 31.45, 228.02) },
    { type = 'ammunation', coords = vector4(253.63, -51.02, 69.94, 72.91) },
    { type = 'ammunation', coords = vector4(23.0, -1105.67, 29.8, 162.91) },
    { type = 'ammunation', coords = vector4(2567.48, 292.59, 108.73, 349.68) },
    { type = 'ammunation', coords = vector4(-1118.59, 2700.05, 18.55, 221.89) },
    { type = 'ammunation', coords = vector4(841.92, -1035.32, 28.19, 1.56) },
}
