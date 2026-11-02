InventoryConfig = {
    ---Player inventory size. Weights are in grams (1000 = 1 kg).
    Player = { slots = 40, maxWeight = 30000 },

    ---Hotbar: keys 1-5 use the item in slots 1-5.
    HotbarSlots = 5,

    ---Default key to open the inventory (players can rebind it in GTA's key bindings).
    OpenKey = 'F2',

    ---Items every new character starts with: { name, count, metadata? }.
    ---Cash for new characters comes from tfc-accounts (cash default), not from here.
    StartingItems = {
        { 'phone', 1 },
        { 'water', 2 },
        { 'sandwich', 2 },
    },

    ---Seconds between batched saves of changed inventories (always saved on logout too).
    SaveInterval = 30,

    ---Folder (inside html/) for item images named <item>.png. Items without an image
    ---show a lettered tile. You can point this at another resource, e.g.
    ---'nui://my-item-images/images/'.
    ImagePath = 'images/',

    ---Minimum milliseconds between item uses per player.
    UseCooldown = 750,
}
