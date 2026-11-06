InventoryConfig = {
    ---Player inventory size. Weights are in grams (1000 = 1 kg).
    ---`wallet` = extra slots on the left for cash and cards only (items with `wallet = true`).
    ---They count toward the weight and show up when the player is searched.
    Player = { slots = 40, wallet = 6, maxWeight = 30000 },

    ---Hotbar: keys 1-5 use the item in slots 1-5.
    HotbarSlots = 5,

    ---Default key to open the inventory (players can rebind it in GTA's key bindings).
    ---Tab is free because GTA's weapon wheel is turned off (Weapons.DisableWeaponWheel).
    OpenKey = 'TAB',

    ---Items every new character starts with: { name, count, metadata? }.
    ---Cash for new characters comes from tfc-accounts (cash default), not from here.
    StartingItems = {
        { 'phone', 1 },
        { 'bandage', 2 },
    },

    ---Weapons (phase 6c): turn off GTA's weapon wheel and weapon-select keys so weapons
    ---only come from the inventory, and remove any weapon not equipped from it.
    Weapons = {
        DisableWeaponWheel = true,
        RemoveOtherWeapons = true,
        ---Prefix of generated serial numbers.
        SerialPrefix = 'TFC',
    },

    ---Seconds between batched saves of changed inventories (always saved on logout too).
    SaveInterval = 30,

    ---Folder (inside html/) for item images named <item>.png. Items without an image
    ---show a lettered tile. You can point this at another resource, e.g.
    ---'nui://my-item-images/images/'.
    ImagePath = 'images/',

    ---Minimum milliseconds between item uses per player.
    UseCooldown = 750,

    -- Containers (phase 6b) -------------------------------------------------------------

    ---Give: drag an item onto "Give" to hand it to the closest player within this many metres.
    GiveDistance = 3.0,

    ---How close police must stay to a cuffed or downed player while searching them (metres).
    SearchDistance = 3.0,

    ---Ground drops: size of a drop, how close you must be to open it, how long an untouched
    ---drop lasts (minutes), and the prop shown on the ground (a marker is used if it can't load).
    Drop = { slots = 30, maxWeight = 100000, radius = 2.0, lifetime = 30, model = 'prop_paper_bag_small' },

    ---Vehicle storage. Saved by plate; empty storage is not stored, and storage nobody has
    ---touched for PurgeDays is deleted on server start.
    Vehicle = {
        trunkDistance = 2.0,     -- metres from the trunk to open it
        serverDistance = 7.0,    -- server check: metres from the vehicle's centre
        purgeDays = 7,
        glovebox = { slots = 5, maxWeight = 5000 },
        trunk = { slots = 20, maxWeight = 40000 },   -- default for classes not listed below
        ---Per GTA vehicle class. false = no trunk.
        trunkByClass = {
            [0]  = { slots = 15, maxWeight = 25000 },   -- compacts
            [2]  = { slots = 30, maxWeight = 60000 },   -- SUVs
            [6]  = { slots = 12, maxWeight = 20000 },   -- sports
            [7]  = { slots = 10, maxWeight = 15000 },   -- super
            [8]  = false,                               -- motorcycles
            [9]  = { slots = 25, maxWeight = 50000 },   -- off-road
            [10] = { slots = 40, maxWeight = 150000 },  -- industrial
            [12] = { slots = 40, maxWeight = 120000 },  -- vans
            [13] = false,                               -- bicycles
            [20] = { slots = 50, maxWeight = 200000 },  -- commercial
        },
        ---Classes with no glovebox.
        noGlovebox = { [8] = true, [13] = true },
    },
}
