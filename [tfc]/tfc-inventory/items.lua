-- Item definitions (shared, so the client knows labels and weights).
--   label        display name
--   weight       grams per unit
--   stack        true = units stack in one slot; false = each unit is its own slot (unique items)
--   maxStack     most units in one slot (stackable items; omit for no limit)
--   description  shown in the tooltip
--   usable       can be used from the inventory / hotbar
--   consume      units removed when used (0 = not removed)
--   effect       client effect when used:
--                  heal / armor = amount, sprint = { mult, seconds },
--                  screen = { name, seconds } (GTA screen effect), anim = { dict, clip, ms } or { scenario, ms }
--   transform    using it turns items into others: { take = { item = n, ... }, give = { item = n, ... } }
--   close        close the inventory when used
--   category     'general' (default), 'drug', 'weapon', 'ammo': groups items in the admin item browser
--
-- Weapons (`weapon = true`) and ammo are below; their rules are in server/weapons.lua.
-- Other resources can add items at runtime: exports['tfc-inventory']:RegisterItem(name, def)
-- and react to use with the server hook: TFC.On('itemUsed', function(src, name, slot) ... end)

Items = {
    -- General ---------------------------------------------------------------------------------
    cash = {
        label = 'Cash', weight = 0, stack = true,
        description = 'Paper money. Counts as your cash balance.',
    },
    phone = { label = 'Phone', weight = 190, stack = false, description = 'A smartphone.' },
    radio = { label = 'Radio', weight = 600, stack = false, description = 'A handheld two-way radio.' },
    id_card = { label = 'ID Card', weight = 10, stack = false, description = 'Government-issued identification.' },
    lockpick = {
        label = 'Lockpick', weight = 150, stack = true, maxStack = 10,
        description = 'For locks that are not yours.',
    },
    repair_kit = {
        label = 'Repair Kit', weight = 2500, stack = true, maxStack = 5,
        description = 'Basic tools to get a car running again.',
    },
    bandage = {
        label = 'Bandage', weight = 100, stack = true, maxStack = 20,
        description = 'Stops minor bleeding. Restores some health.',
        usable = true, consume = 1, close = true,
        effect = { heal = 25 },
    },
    weapon_kit = {
        label = 'Gun Cleaning Kit', weight = 800, stack = true, maxStack = 5,
        description = 'Clears a jam and restores the weapon in your hands to full condition.',
        usable = true, close = true, -- consumed by server/weapons.lua only if it worked
    },

    -- Drugs -------------------------------------------------------------------------------------
    weed_bag = {
        category = 'drug',
        label = 'Bag of Weed', weight = 30, stack = true, maxStack = 50,
        description = 'A dime bag. Use with rolling papers to roll two joints.',
        usable = true,
        transform = { take = { weed_bag = 1, rolling_papers = 1 }, give = { joint = 2 } },
    },
    rolling_papers = {
        category = 'drug',
        label = 'Rolling Papers', weight = 5, stack = true, maxStack = 50,
        description = 'For rolling joints.',
    },
    joint = {
        category = 'drug',
        label = 'Joint', weight = 3, stack = true, maxStack = 50,
        description = 'Takes the edge off. Slowly restores a little health.',
        usable = true, consume = 1, close = true,
        effect = { heal = 10, screen = { 'DrugsMichaelAliensFight', 30 }, anim = { scenario = 'WORLD_HUMAN_SMOKING_POT', ms = 6000 } },
    },
    coke_bag = {
        category = 'drug',
        label = 'Bag of Coke', weight = 10, stack = true, maxStack = 50,
        description = 'Brief burst of speed.',
        usable = true, consume = 1, close = true,
        effect = { sprint = { 1.2, 30 }, screen = { 'Rampage', 30 }, anim = { dict = 'switch@trevor@trev_smoking_meth', clip = 'trev_smoking_meth_loop', ms = 3000 } },
    },
    coke_brick = {
        category = 'drug',
        label = 'Brick of Coke', weight = 1000, stack = true, maxStack = 10,
        description = 'Packed for distribution. Use to break it down into 20 bags.',
        usable = true,
        transform = { take = { coke_brick = 1 }, give = { coke_bag = 20 } },
    },
    crack_rock = {
        category = 'drug',
        label = 'Crack Rock', weight = 5, stack = true, maxStack = 50,
        description = 'Short, sharp high. A little speed and a little health.',
        usable = true, consume = 1, close = true,
        effect = { heal = 5, sprint = { 1.15, 20 }, screen = { 'DrugsTrevorClownsFight', 20 }, anim = { dict = 'switch@trevor@trev_smoking_meth', clip = 'trev_smoking_meth_loop', ms = 3000 } },
    },
    meth_bag = {
        category = 'drug',
        label = 'Bag of Meth', weight = 10, stack = true, maxStack = 50,
        description = 'You feel unstoppable. Adds some armor.',
        usable = true, consume = 1, close = true,
        effect = { armor = 25, screen = { 'DMT_flight', 45 }, anim = { dict = 'switch@trevor@trev_smoking_meth', clip = 'trev_smoking_meth_loop', ms = 3000 } },
    },
    oxy = {
        category = 'drug',
        label = 'Oxy', weight = 2, stack = true, maxStack = 50,
        description = 'Prescription painkiller. Restores health.',
        usable = true, consume = 1, close = true,
        effect = { heal = 30, screen = { 'DrugsDrivingIn', 20 }, anim = { dict = 'mp_suicide', clip = 'pill', ms = 2500 } },
    },
    ecstasy = {
        category = 'drug',
        label = 'Ecstasy', weight = 2, stack = true, maxStack = 50,
        description = 'Everything is wonderful. Adds a little armor.',
        usable = true, consume = 1, close = true,
        effect = { armor = 10, screen = { 'DrugsMichaelAliensFight', 60 }, anim = { dict = 'mp_suicide', clip = 'pill', ms = 2500 } },
    },

    -- Ammo (use while holding a matching gun to reload) ------------------------------------------
    ammo_9mm = { label = '9mm Rounds', weight = 8, stack = true, maxStack = 250, usable = true, description = 'For most pistols and SMGs.' },
    ammo_45 = { label = '.45 ACP Rounds', weight = 15, stack = true, maxStack = 250, usable = true, description = 'For heavy pistols and revolvers.' },
    ammo_556 = { label = '5.56 Rounds', weight = 12, stack = true, maxStack = 250, usable = true, description = 'For carbines.' },
    ammo_762 = { label = '7.62 Rounds', weight = 16, stack = true, maxStack = 250, usable = true, description = 'For assault rifles.' },
    ammo_12g = { label = '12 Gauge Shells', weight = 40, stack = true, maxStack = 100, usable = true, description = 'For shotguns.' },
}

-- Weapons ------------------------------------------------------------------------------------------
--   hash       GTA weapon name
--   ammo       ammo item it uses (omit for melee / no ammo)
--   clip       rounds per reload
--   wear       durability lost per shot (100 = new; at 0 it jams)
--   serial     false = no serial number (melee, tools)
--   infinite   tool that never runs out (extinguisher, jerry can)

local Weapons = {
    -- Melee
    knife       = { label = 'Knife', hash = 'WEAPON_KNIFE', weight = 300, serial = false },
    switchblade = { label = 'Switchblade', hash = 'WEAPON_SWITCHBLADE', weight = 200, serial = false },
    bat         = { label = 'Baseball Bat', hash = 'WEAPON_BAT', weight = 900, serial = false },
    crowbar     = { label = 'Crowbar', hash = 'WEAPON_CROWBAR', weight = 1500, serial = false },
    hammer      = { label = 'Hammer', hash = 'WEAPON_HAMMER', weight = 700, serial = false },
    golfclub    = { label = 'Golf Club', hash = 'WEAPON_GOLFCLUB', weight = 400, serial = false },
    knuckles    = { label = 'Brass Knuckles', hash = 'WEAPON_KNUCKLE', weight = 200, serial = false },
    nightstick  = { label = 'Nightstick', hash = 'WEAPON_NIGHTSTICK', weight = 600, serial = false },
    flashlight  = { label = 'Flashlight', hash = 'WEAPON_FLASHLIGHT', weight = 400, serial = false },

    -- Pistols
    pistol        = { label = 'Pistol', hash = 'WEAPON_PISTOL', weight = 900, ammo = 'ammo_9mm', clip = 12, wear = 0.1 },
    combatpistol  = { label = 'Combat Pistol', hash = 'WEAPON_COMBATPISTOL', weight = 950, ammo = 'ammo_9mm', clip = 12, wear = 0.1 },
    snspistol     = { label = 'SNS Pistol', hash = 'WEAPON_SNSPISTOL', weight = 600, ammo = 'ammo_9mm', clip = 6, wear = 0.15 },
    vintagepistol = { label = 'Vintage Pistol', hash = 'WEAPON_VINTAGEPISTOL', weight = 850, ammo = 'ammo_9mm', clip = 7, wear = 0.12 },
    heavypistol   = { label = 'Heavy Pistol', hash = 'WEAPON_HEAVYPISTOL', weight = 1100, ammo = 'ammo_45', clip = 18, wear = 0.1 },
    pistol50      = { label = 'Pistol .50', hash = 'WEAPON_PISTOL50', weight = 1300, ammo = 'ammo_45', clip = 9, wear = 0.12 },
    revolver      = { label = 'Revolver', hash = 'WEAPON_REVOLVER', weight = 1400, ammo = 'ammo_45', clip = 6, wear = 0.08 },
    stungun       = { label = 'Taser', hash = 'WEAPON_STUNGUN', weight = 500, wear = 0.2 },

    -- SMGs
    microsmg      = { label = 'Micro SMG', hash = 'WEAPON_MICROSMG', weight = 1800, ammo = 'ammo_9mm', clip = 16, wear = 0.06 },
    machinepistol = { label = 'Machine Pistol', hash = 'WEAPON_MACHINEPISTOL', weight = 1500, ammo = 'ammo_9mm', clip = 12, wear = 0.07 },
    smg           = { label = 'SMG', hash = 'WEAPON_SMG', weight = 2600, ammo = 'ammo_9mm', clip = 30, wear = 0.05 },
    combatpdw     = { label = 'Combat PDW', hash = 'WEAPON_COMBATPDW', weight = 2800, ammo = 'ammo_9mm', clip = 30, wear = 0.05 },

    -- Rifles and shotguns
    carbinerifle  = { label = 'Carbine Rifle', hash = 'WEAPON_CARBINERIFLE', weight = 3400, ammo = 'ammo_556', clip = 30, wear = 0.04 },
    assaultrifle  = { label = 'Assault Rifle', hash = 'WEAPON_ASSAULTRIFLE', weight = 3600, ammo = 'ammo_762', clip = 30, wear = 0.04 },
    compactrifle  = { label = 'Compact Rifle', hash = 'WEAPON_COMPACTRIFLE', weight = 3000, ammo = 'ammo_762', clip = 30, wear = 0.05 },
    pumpshotgun   = { label = 'Pump Shotgun', hash = 'WEAPON_PUMPSHOTGUN', weight = 3200, ammo = 'ammo_12g', clip = 8, wear = 0.08 },
    sawnoff       = { label = 'Sawed-Off Shotgun', hash = 'WEAPON_SAWNOFFSHOTGUN', weight = 2500, ammo = 'ammo_12g', clip = 8, wear = 0.1 },

    -- Tools
    extinguisher  = { label = 'Fire Extinguisher', hash = 'WEAPON_FIREEXTINGUISHER', weight = 4000, serial = false, infinite = true },
    jerrycan      = { label = 'Jerry Can', hash = 'WEAPON_PETROLCAN', weight = 5000, serial = false, infinite = true },
}

for name, w in pairs(Weapons) do
    w.weapon = true
    w.stack = false
    w.usable = true
    if w.serial == nil then w.serial = true end
    w.description = w.description or (w.ammo and ('Uses %s.'):format(Items[w.ammo].label) or nil)
    Items[name] = w
end
