-- Inventory server: loading/saving, player inventories, exports, the menu's callbacks,
-- item use and admin commands. Data rules live in server/engine.lua.
--
-- Exports (server). `target` is a player's server ID or an inventory id string.
--   AddItem(target, name, count, metadata?, slot?, reason?) -> ok, err
--   RemoveItem(target, name, count, metadata?, slot?, reason?) -> ok, err
--   GetItemCount(target, name, metadata?) -> integer      HasItem(target, name, count?) -> bool
--   CanCarry(target, name, count, metadata?) -> ok, err   Search(target, name) -> { slot, count, metadata }[]
--   SetMetadata(target, slot, metadata) -> ok, err        GetInventory(target) -> view
--   ClearInventory(target, keep?)                          RegisterItem(name, def)    GetItems()
-- Server hooks:
--   itemUsed(source, name, slot)                     a usable item was used
--   itemCountChanged(source, name, count, delta, reason)   a player's count of an item changed

local Cfg = InventoryConfig

---@type table<integer, string> source -> player inventory id
local playerInv = {}
---@type table<integer, boolean>
local loading = {}
---@type table<integer, integer> last use time
local lastUse = {}

local ready = false

local SCHEMA = [[
    CREATE TABLE IF NOT EXISTS `tfc_inventories` (
        `id`         VARCHAR(64) NOT NULL,
        `items`      LONGTEXT    NOT NULL,
        `updated_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]]

-- Persistence ------------------------------------------------------------------------------

local function isVehicle(inv)
    return inv.type == 'trunk' or inv.type == 'glovebox'
end

local function saveQuery(inv)
    -- Empty vehicle storage takes no space in the database.
    if isVehicle(inv) and next(inv.items) == nil then
        return { query = 'DELETE FROM tfc_inventories WHERE id = ?', values = { inv.id } }
    end
    return {
        query = 'INSERT INTO tfc_inventories (id, items) VALUES (?, ?) ON DUPLICATE KEY UPDATE items = VALUES(items)',
        values = { inv.id, Inv.Serialize(inv) },
    }
end

---Save every changed inventory in one transaction (drops live in memory only).
local function saveDirty(async)
    local queries = {}
    for _, inv in pairs(Inv.list) do
        if inv.dirty and inv.type ~= 'drop' then
            queries[#queries + 1] = saveQuery(inv)
            inv.dirty = false
        end
    end
    if #queries == 0 then return end
    if async then MySQL.transaction(queries) else MySQL.transaction.await(queries) end
end

local function saveOne(inv)
    if not inv.dirty or inv.type == 'drop' then return end
    MySQL.transaction.await({ saveQuery(inv) })
    inv.dirty = false
end

-- Player inventories ------------------------------------------------------------------------

---Load (or create) a player's inventory. Safe to call from anywhere; loads once.
---@return table|nil inv
local function ensure(src)
    src = tonumber(src) --[[@as integer]]
    local id = playerInv[src]
    if id and Inv.Get(id) then return Inv.Get(id) end
    if not ready then return nil end

    if loading[src] then
        local deadline = GetGameTimer() + 5000
        while loading[src] and GetGameTimer() < deadline do Wait(50) end
        return playerInv[src] and Inv.Get(playerInv[src]) or nil
    end

    local player = TFC.GetPlayer(src)
    if not player then return nil end
    local charId = player.characterId
    id = ('player:%d'):format(charId)

    loading[src] = true
    local ok, inv = pcall(function()
        local raw = MySQL.scalar.await('SELECT items FROM tfc_inventories WHERE id = ?', { id })
        local label = player:GetFullName()
        local created = Inv.Create(id, 'player', label, Cfg.Player.slots, Cfg.Player.maxWeight,
            Inv.Deserialize(raw, Cfg.Player.slots, id))

        if raw == nil then
            for _, it in ipairs(Cfg.StartingItems) do
                Inv.Add(created, it[1], it[2], it[3])
            end
            created.dirty = true
            saveOne(created)
        end
        return created
    end)
    loading[src] = nil

    if not ok then
        TFC.Log.Error('could not load inventory for player %d: %s', src, inv)
        return nil
    end

    -- Same character still loaded?
    local now = TFC.GetPlayer(src)
    if not now or now.characterId ~= charId then
        Inv.Remove(id)
        return nil
    end

    inv.owner = src
    playerInv[src] = id
    TriggerClientEvent('tfc-inventory:client:sync', src, Inv.View(inv), true)
    return inv
end

---A player's server ID or an inventory id -> inventory.
local function resolve(target)
    if type(target) == 'string' then return Inv.Get(target) end
    return ensure(target)
end

---Send an inventory to its owner and to everyone who has it open.
local function sync(inv)
    local view = Inv.View(inv)
    local sent = {}
    if inv.owner then
        TriggerClientEvent('tfc-inventory:client:sync', inv.owner, view, true)
        sent[inv.owner] = true
    end
    for viewer in pairs(inv.viewers or {}) do
        if not sent[viewer] then TriggerClientEvent('tfc-inventory:client:sync', viewer, view, false) end
    end
end

---Run `fn`, then announce count changes of the given item names for player inventories.
local function tracked(invs, names, reason, fn)
    local before = {}
    for _, inv in ipairs(invs) do
        if inv.owner then
            before[inv] = {}
            for name in pairs(names) do before[inv][name] = Inv.Count(inv, name) end
        end
    end

    local ok, err = fn()

    if ok then
        for _, inv in ipairs(invs) do
            sync(inv)
            if before[inv] then
                for name in pairs(names) do
                    local after = Inv.Count(inv, name)
                    local delta = after - before[inv][name]
                    if delta ~= 0 then
                        TFC.Emit('itemCountChanged', inv.owner, name, after, delta, reason or '')
                    end
                end
            end
        end
    end
    return ok, err
end

-- API ------------------------------------------------------------------------------------------

local function AddItem(target, name, count, metadata, slot, reason)
    local inv = resolve(target)
    if not inv then return false, 'inventory not found' end

    -- Weapons are added one at a time so each gets its own serial number.
    local def = Items[name]
    if def and def.weapon and InvSrv.weaponMeta then
        local n = Inv.ValidCount(count)
        if not n then return false, 'count must be a whole number above 0' end
        local fits, err = Inv.CanFit(inv, name, n, metadata, slot)
        if not fits then return false, err end
        return tracked({ inv }, { [name] = true }, reason, function()
            for i = 1, n do
                local ok, addErr = Inv.Add(inv, name, 1, InvSrv.weaponMeta(name, metadata), i == 1 and slot or nil)
                if not ok then return false, addErr end
            end
            return true
        end)
    end

    return tracked({ inv }, { [name] = true }, reason, function()
        return Inv.Add(inv, name, count, metadata, slot)
    end)
end

local function RemoveItem(target, name, count, metadata, slot, reason)
    local inv = resolve(target)
    if not inv then return false, 'inventory not found' end
    return tracked({ inv }, { [name] = true }, reason, function()
        return Inv.RemoveItem(inv, name, count, metadata, slot)
    end)
end

local function GetItemCount(target, name, metadata)
    local inv = resolve(target)
    return inv and Inv.Count(inv, name, metadata) or 0
end

local function HasItem(target, name, count)
    return GetItemCount(target, name) >= (count or 1)
end

local function CanCarry(target, name, count, metadata)
    local inv = resolve(target)
    if not inv then return false, 'inventory not found' end
    return Inv.CanFit(inv, name, count, metadata)
end

local function Search(target, name)
    local inv = resolve(target)
    return inv and Inv.Find(inv, name) or {}
end

local function SetMetadata(target, slot, metadata)
    local inv = resolve(target)
    if not inv then return false, 'inventory not found' end
    local ok, err = Inv.SetMetadata(inv, math.tointeger(tonumber(slot)), metadata)
    if ok then sync(inv) end
    return ok, err
end

local function GetInventory(target)
    local inv = resolve(target)
    return inv and Inv.View(inv) or nil
end

local function ClearInventory(target, keep)
    local inv = resolve(target)
    if not inv then return false, 'inventory not found' end
    local names = {}
    for _, item in pairs(inv.items) do names[item.name] = true end
    local keepSet = nil
    if type(keep) == 'table' then
        keepSet = {}
        for _, n in ipairs(keep) do keepSet[n] = true end
    end
    return tracked({ inv }, names, 'inventory cleared', function()
        Inv.Clear(inv, keepSet)
        return true
    end)
end

---Add or replace an item definition at runtime (e.g. from another module).
local function RegisterItem(name, def)
    if type(name) ~= 'string' or not name:match('^[%w_]+$') then return false, 'invalid item name' end
    if type(def) ~= 'table' or type(def.label) ~= 'string' then return false, 'item needs a label' end
    def.weight = tonumber(def.weight) or 0
    def.stack = def.stack ~= false
    Items[name] = def
    TriggerClientEvent('tfc-inventory:client:item', -1, name, def)
    return true
end

exports('AddItem', AddItem)
exports('RemoveItem', RemoveItem)
exports('GetItemCount', GetItemCount)
exports('HasItem', HasItem)
exports('CanCarry', CanCarry)
exports('Search', Search)
exports('SetMetadata', SetMetadata)
exports('GetInventory', GetInventory)
exports('ClearInventory', ClearInventory)
exports('RegisterItem', RegisterItem)
exports('GetItems', function() return Items end)

-- Shared with other server files of this resource.
InvSrv = {
    saveOne = saveOne,
    ensure = ensure,
    resolve = resolve,
    sync = sync,
    tracked = tracked,
    playerInv = playerInv,
    AddItem = AddItem,
    RemoveItem = RemoveItem,
}

---Take every item in `t.take` and give every item in `t.give`, all or nothing.
function InvSrv.transform(src, inv, t)
    for name, n in pairs(t.take) do
        if Inv.Count(inv, name) < n then
            return false, ('you need %dx %s'):format(n, Items[name].label)
        end
    end

    local names = {}
    for name in pairs(t.take) do names[name] = true end
    for name in pairs(t.give) do names[name] = true end

    return tracked({ inv }, names, 'combined', function()
        for name, n in pairs(t.take) do Inv.RemoveItem(inv, name, n) end
        for name, n in pairs(t.give) do
            local ok, err = Inv.Add(inv, name, n)
            if not ok then
                -- Undo: remove what was given, return what was taken.
                for gName, gN in pairs(t.give) do
                    if gName == name then break end
                    Inv.RemoveItem(inv, gName, gN)
                end
                for tName, tN in pairs(t.take) do Inv.Add(inv, tName, tN) end
                return false, err == 'too heavy' and 'you cannot carry the result' or 'no room for the result'
            end
        end
        return true
    end)
end

-- Menu callbacks ---------------------------------------------------------------------------------

---Cuffed (tfc-police) or downed (tfc-medical) players can't use their inventory.
---@return string|nil reason
function InvSrv.blocked(src)
    local state = Player(src).state
    if state['tfc:down'] then return 'you can\'t do that while you are down' end
    if state['tfc:cuffed'] then return 'you can\'t do that while cuffed' end
    return nil
end

---Inventories this player may touch right now. (6b adds the open secondary: ground, trunk...)
local function accessible(src)
    local set = {}
    local own = playerInv[src]
    if own then set[own] = true end
    if InvSrv.secondaryOf then
        local second = InvSrv.secondaryOf(src)
        if second then set[second] = true end
    end
    return set
end

TFC.Callback.Register('inventory:open', function(src, context)
    local why = InvSrv.blocked(src)
    if why then return { ok = false, error = why } end
    local inv = ensure(src)
    if not inv then return { ok = false, error = 'inventory not loaded yet' } end

    local secondary = nil
    if InvSrv.openSecondary then
        local second, err = InvSrv.openSecondary(src, type(context) == 'table' and context or {})
        if second then
            secondary = Inv.View(second)
        elseif err then
            TFC.UI.Notify(src, { title = 'Inventory', description = err, type = 'error' })
        end
    end
    return { ok = true, player = Inv.View(inv), secondary = secondary }
end, { rateLimit = 300 })

TFC.Callback.Register('inventory:close', function(src)
    if InvSrv.closeSecondary then InvSrv.closeSecondary(src) end
    return { ok = true }
end, { rateLimit = 100 })

TFC.Callback.Register('inventory:move', function(src, fromId, fromSlot, toId, toSlot, count)
    local why = InvSrv.blocked(src)
    if why then return { ok = false, error = why } end
    local allowed = accessible(src)
    if not allowed[fromId] or not allowed[toId] then return { ok = false, error = 'you cannot reach that' } end

    local from, to = Inv.Get(fromId), Inv.Get(toId)
    if not from or not to then return { ok = false, error = 'that inventory is gone' } end

    local names = {}
    local a, b = from.items[tonumber(fromSlot)], to.items[tonumber(toSlot)]
    if a then names[a.name] = true end
    if b then names[b.name] = true end

    local invs = from == to and { from } or { from, to }
    local reason = from == to and 'moved' or ('moved to %s'):format(to.label or to.type)
    local ok, err = tracked(invs, names, reason, function()
        return Inv.Move(from, fromSlot, to, toSlot, count)
    end)

    if ok and from ~= to and InvSrv.afterTransfer then InvSrv.afterTransfer(src, from, to) end
    return { ok = ok, error = err }
end, { rateLimit = 100 })

TFC.Callback.Register('inventory:use', function(src, slot)
    local why = InvSrv.blocked(src)
    if why then return { ok = false, error = why } end
    local now = GetGameTimer()
    if lastUse[src] and now - lastUse[src] < Cfg.UseCooldown then return { ok = false, error = 'slow down' } end
    lastUse[src] = now

    local inv = ensure(src)
    slot = math.tointeger(tonumber(slot))
    local item = inv and slot and inv.items[slot]
    if not item then return { ok = false, error = 'that slot is empty' } end

    local def = Items[item.name]
    if not def.usable then return { ok = false, error = ('%s cannot be used'):format(def.label) } end

    -- Weapons, ammo and the gun kit (server/weapons.lua).
    if InvSrv.handlesUse and InvSrv.handlesUse(item.name) then
        local result = InvSrv.useWeaponItem(src, slot, item)
        if result.ok then TFC.Emit('itemUsed', src, item.name, { slot = slot, name = item.name, count = item.count, metadata = Inv.Copy(item.metadata) }) end
        return result
    end

    -- Transform: turn some items into others (roll joints, break down a brick...).
    if def.transform then
        local ok, err = InvSrv.transform(src, inv, def.transform)
        if not ok then return { ok = false, error = err } end
        TFC.Emit('itemUsed', src, item.name, { slot = slot, name = item.name, count = item.count })
        return { ok = true, label = def.label }
    end

    local used = { slot = slot, name = item.name, count = item.count, metadata = Inv.Copy(item.metadata) }
    if (def.consume or 0) > 0 then
        local ok, err = RemoveItem(src, item.name, def.consume, nil, slot, 'used')
        if not ok then return { ok = false, error = err } end
    end

    if def.effect then TriggerClientEvent('tfc-inventory:client:effect', src, def.effect) end
    TFC.Emit('itemUsed', src, used.name, used)
    return { ok = true, close = def.close == true, label = def.label }
end, { rateLimit = 150 })

-- Lifecycle ------------------------------------------------------------------------------------

TFC.On('playerLoaded', function(src)
    CreateThread(function() ensure(src) end)
end)

TFC.On('playerUnloaded', function(src)
    if InvSrv.closeSecondary then InvSrv.closeSecondary(src) end
    local id = playerInv[src]
    playerInv[src] = nil
    lastUse[src] = nil
    local inv = id and Inv.Get(id)
    if inv then
        inv.owner = nil
        saveOne(inv)
        Inv.Remove(id)
    end
end)

CreateThread(function()
    while not exports['tfc-core']:IsDatabaseReady() do Wait(250) end
    MySQL.query.await(SCHEMA)
    ready = true
    InvSrv.ready = true

    local count = 0
    for _ in pairs(Items) do count = count + 1 end
    TFC.RegisterModule({ name = 'inventory', version = '0.3.1' }, function()
        TFC.Log.Info('inventory ready: %d items', count)
    end)

    for _, src in ipairs(TFC.GetPlayers()) do
        CreateThread(function() ensure(src) end)
    end

    while true do
        Wait(Cfg.SaveInterval * 1000)
        saveDirty(false)
    end
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function() saveDirty(false) end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then saveDirty(true) end
end)

-- Admin commands ----------------------------------------------------------------------------------

local function reply(src, ok, text)
    if src == 0 then TFC.Log.Info(text) else
        TFC.UI.Notify(src, { title = 'Inventory', description = text, type = ok and 'success' or 'error' })
    end
end

TFC.RegisterCommand('giveitem', {
    help = 'Admin: give an item to a player',
    permission = TFC.Permissions.Admin,
    params = {
        { name = 'id', help = 'Player server ID, or "me"' },
        { name = 'item', help = 'Item name, e.g. water, bandage, phone' },
        { name = 'count', help = 'How many (default 1)', optional = true },
    },
}, function(src, args)
    local target = TFC.ResolveTarget(src, args[1])
    if not target then return reply(src, false, ('no player with ID %s is online'):format(tostring(args[1]))) end
    local name, count = args[2], tonumber(args[3] or 1)
    local ok, err = AddItem(target, name, count, nil, nil, 'admin give')
    reply(src, ok, ok and ('Gave %dx %s to %s'):format(count, Items[name].label, GetPlayerName(target) or target) or err)
end)

TFC.RegisterCommand('removeitem', {
    help = 'Admin: remove an item from a player',
    permission = TFC.Permissions.Admin,
    params = {
        { name = 'id', help = 'Player server ID, or "me"' },
        { name = 'item', help = 'Item name' },
        { name = 'count', help = 'How many (default 1)', optional = true },
    },
}, function(src, args)
    local target = TFC.ResolveTarget(src, args[1])
    if not target then return reply(src, false, ('no player with ID %s is online'):format(tostring(args[1]))) end
    local name, count = args[2], tonumber(args[3] or 1)
    local ok, err = RemoveItem(target, name, count, nil, nil, 'admin remove')
    reply(src, ok, ok and ('Removed %dx %s from %s'):format(count, Items[name].label, GetPlayerName(target) or target) or err)
end)

TFC.RegisterCommand('clearinventory', {
    help = 'Admin: empty a player\'s inventory',
    permission = TFC.Permissions.Admin,
    params = { { name = 'id', help = 'Player server ID, or "me"' } },
}, function(src, args)
    local target = TFC.ResolveTarget(src, args[1])
    if not target then return reply(src, false, ('no player with ID %s is online'):format(tostring(args[1]))) end
    local ok, err = ClearInventory(target)
    reply(src, ok, ok and ('Cleared %s\'s inventory'):format(GetPlayerName(target) or target) or err)
end)
