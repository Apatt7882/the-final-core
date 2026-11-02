-- Containers (phase 6b): ground drops, vehicle trunks and gloveboxes, and giving items.
-- Every action re-checks on the server that the player is still close enough.
--
--   drop:<n>        ground bag, in memory only; removed when empty or after Drop.lifetime minutes
--   trunk:<PLATE>   saved by plate; empty ones are deleted
--   glove:<PLATE>   saved by plate; only reachable from inside the vehicle
--   player:<id>     another player's inventory, while searching them (phase 7, tfc-police)

local Cfg = InventoryConfig

---@type table<integer, string> source -> open secondary inventory id
local open = {}
---@type table<integer, { veh: integer, door: boolean }|nil> vehicle info for an open trunk/glovebox
local openVehicle = {}
---@type table<integer, integer> source -> player they are searching
local openPlayer = {}
---@type table<integer, { target: integer, expires: integer }> searches another resource allowed
local searchGrant = {}

local nextDrop = 0

-- Position helpers -----------------------------------------------------------------------------

local function pedCoords(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function dist(a, b)
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z))
end

-- Drops ---------------------------------------------------------------------------------------

---@param inv table
local function announceDrop(inv)
    if inv.announced or next(inv.items) == nil then return end
    inv.announced = true
    TriggerClientEvent('tfc-inventory:client:drop', -1, inv.id, inv.coords)
end

local function removeDrop(inv)
    if inv.announced then TriggerClientEvent('tfc-inventory:client:dropRemoved', -1, inv.id) end
    for viewer in pairs(inv.viewers or {}) do
        if open[viewer] == inv.id then
            open[viewer] = nil
            TriggerClientEvent('tfc-inventory:client:secondaryClosed', viewer, inv.id)
        end
    end
    Inv.Remove(inv.id)
end

---Nearest drop within reach of the player, or nil.
local function nearestDrop(src)
    local here = pedCoords(src)
    if not here then return nil end
    local best, bestDist = nil, Cfg.Drop.radius
    for _, inv in pairs(Inv.list) do
        if inv.type == 'drop' then
            local d = dist(here, inv.coords)
            if d <= bestDist then best, bestDist = inv, d end
        end
    end
    return best
end

local function newDrop(src)
    local here = pedCoords(src)
    if not here then return nil end
    nextDrop = nextDrop + 1
    local inv = Inv.Create(('drop:%d'):format(nextDrop), 'drop', 'Ground', Cfg.Drop.slots, Cfg.Drop.maxWeight)
    inv.coords = { x = here.x, y = here.y, z = here.z - 0.95 }
    inv.touched = os.time()
    return inv
end

-- Vehicles -----------------------------------------------------------------------------------------

local function plateOf(veh)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return nil end
    plate = plate:gsub('^%s+', ''):gsub('%s+$', ''):upper()
    if plate == '' then return nil end
    return plate
end

---Validate a vehicle the client named, by network id.
local function vehicleFromNet(netId)
    netId = tonumber(netId)
    if not netId then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return nil end
    return veh
end

local function trunkSize(class)
    local size = Cfg.Vehicle.trunkByClass[tonumber(class) or -1]
    if size == false then return nil end
    return size or Cfg.Vehicle.trunk
end

---Load a vehicle inventory (from memory or the database).
local function vehicleInventory(kind, plate, size)
    local prefix = kind == 'trunk' and 'trunk' or 'glove'
    local id = ('%s:%s'):format(prefix, plate)
    local inv = Inv.Get(id)
    if inv then return inv end

    local raw = MySQL.scalar.await('SELECT items FROM tfc_inventories WHERE id = ?', { id })
    local label = ('%s (%s)'):format(kind == 'trunk' and 'Trunk' or 'Glovebox', plate)
    return Inv.Create(id, kind, label, size.slots, size.maxWeight, Inv.Deserialize(raw, size.slots, id))
end

-- Open / close -----------------------------------------------------------------------------------

local function attach(src, inv)
    inv.viewers = inv.viewers or {}
    inv.viewers[src] = true
    open[src] = inv.id
end

---Release a container the player had open. Unused vehicle storage is saved and unloaded;
---empty drops disappear.
function InvSrv.closeSecondary(src)
    local id = open[src]
    open[src] = nil
    local vehicle = openVehicle[src]
    openVehicle[src] = nil
    openPlayer[src] = nil
    if not id then return end

    local inv = Inv.Get(id)
    if not inv then return end
    if inv.viewers then inv.viewers[src] = nil end

    if inv.type == 'drop' then
        if next(inv.items) == nil then removeDrop(inv) end
    elseif (inv.type == 'trunk' or inv.type == 'glovebox') and next(inv.viewers or {}) == nil then
        InvSrv.saveOne(inv)
        Inv.Remove(id)
    end

    if vehicle and vehicle.door then
        TriggerClientEvent('tfc-inventory:client:trunkDoor', src, vehicle.net, false)
    end
end

---Open the right container for where the player is. context comes from the client:
---  { kind = 'glovebox', net, class } | { kind = 'trunk', net, class } | { kind = 'ground' }
---@return table|nil inv, string|nil err
function InvSrv.openSecondary(src, context)
    InvSrv.closeSecondary(src)
    local ped = GetPlayerPed(tostring(src))
    local here = pedCoords(src)
    if not here then return nil end

    if context.kind == 'glovebox' then
        local veh = vehicleFromNet(context.net)
        if not veh or GetVehiclePedIsIn(ped, false) ~= veh then return nil, 'you need to be in the vehicle' end
        if Cfg.Vehicle.noGlovebox[tonumber(context.class) or -1] then return nil end
        local plate = plateOf(veh)
        if not plate then return nil end
        local inv = vehicleInventory('glovebox', plate, Cfg.Vehicle.glovebox)
        attach(src, inv)
        openVehicle[src] = { veh = veh, net = context.net }
        return inv
    end

    if context.kind == 'player' then
        local target = math.tointeger(tonumber(context.target))
        local grant = searchGrant[src]
        searchGrant[src] = nil -- one use
        if not target or not grant or grant.target ~= target or grant.expires < os.time() then
            return nil, 'you can\'t search them'
        end
        local there = pedCoords(target)
        if not there or dist(here, there) > Cfg.SearchDistance then return nil, 'they are too far away' end
        if not InvSrv.searchable(target) then return nil, 'they need to be cuffed or down' end
        local inv = InvSrv.ensure(target)
        if not inv then return nil, 'their inventory is not loaded' end
        attach(src, inv)
        openPlayer[src] = target
        return inv
    end

    if context.kind == 'trunk' then
        local veh = vehicleFromNet(context.net)
        if not veh then return nil end
        if GetVehiclePedIsIn(ped, false) ~= 0 then return nil, 'get out of the vehicle to use the trunk' end
        if dist(here, GetEntityCoords(veh)) > Cfg.Vehicle.serverDistance then return nil, 'you are too far from the trunk' end
        local size = trunkSize(context.class)
        if not size then return nil, 'this vehicle has no trunk' end
        local plate = plateOf(veh)
        if not plate then return nil end
        local inv = vehicleInventory('trunk', plate, size)
        attach(src, inv)
        openVehicle[src] = { veh = veh, net = context.net, door = true }
        TriggerClientEvent('tfc-inventory:client:trunkDoor', src, context.net, true)
        return inv
    end

    -- Ground: the nearest drop, or a fresh empty one that only appears once something is put in it.
    local inv = nearestDrop(src) or newDrop(src)
    if not inv then return nil end
    attach(src, inv)
    return inv
end

---The container a player may touch right now (re-checks distance on every call).
function InvSrv.secondaryOf(src)
    local id = open[src]
    local inv = id and Inv.Get(id)
    if not inv then return nil end
    local here = pedCoords(src)
    if not here then return nil end

    if inv.type == 'player' then
        local target = openPlayer[src]
        local there = target and pedCoords(target)
        if not there or dist(here, there) > Cfg.SearchDistance + 1.0 or not InvSrv.searchable(target) then return nil end
    elseif inv.type == 'drop' then
        if dist(here, inv.coords) > Cfg.Drop.radius + 1.0 then return nil end
    elseif inv.type == 'trunk' or inv.type == 'glovebox' then
        local v = openVehicle[src]
        if not v or not DoesEntityExist(v.veh) then return nil end
        if inv.type == 'glovebox' then
            if GetVehiclePedIsIn(GetPlayerPed(tostring(src)), false) ~= v.veh then return nil end
        elseif dist(here, GetEntityCoords(v.veh)) > Cfg.Vehicle.serverDistance then
            return nil
        end
    end
    return id
end

---After items move between two inventories: show new drops, remove emptied ones.
function InvSrv.afterTransfer(_, from, to)
    for _, inv in ipairs({ from, to }) do
        if inv.type == 'drop' then
            inv.touched = os.time()
            if next(inv.items) == nil then
                if next(inv.viewers or {}) == nil then removeDrop(inv) end
            else
                announceDrop(inv)
            end
        end
    end
end

-- Searching another player ---------------------------------------------------------------------------

---Only cuffed or downed players can be searched.
function InvSrv.searchable(target)
    local state = Player(target).state
    return state['tfc:cuffed'] == true or state['tfc:down'] == true
end

---Called by another resource (e.g. tfc-police) after its own checks: opens `target`'s
---inventory next to `viewer`'s. The inventory still re-checks distance and cuffs/down.
exports('OpenSearch', function(viewer, target)
    viewer, target = math.tointeger(tonumber(viewer)), math.tointeger(tonumber(target))
    if not viewer or not target or viewer == target then return false, 'invalid player' end
    if not InvSrv.searchable(target) then return false, 'they need to be cuffed or down' end
    searchGrant[viewer] = { target = target, expires = os.time() + 15 }
    TriggerClientEvent('tfc-inventory:client:openSearch', viewer, target)
    return true
end)

---Close every inventory window a player has open (e.g. they were just cuffed).
exports('ForceClose', function(src)
    InvSrv.closeSecondary(src)
    TriggerClientEvent('tfc-inventory:client:forceClose', src)
end)

-- Give ---------------------------------------------------------------------------------------------

---Closest loaded player within GiveDistance (other than src).
local function closestPlayer(src)
    local here = pedCoords(src)
    if not here then return nil end
    local best, bestDist = nil, Cfg.GiveDistance
    for target in pairs(InvSrv.playerInv) do
        if target ~= src then
            local there = pedCoords(target)
            if there then
                local d = dist(here, there)
                if d <= bestDist then best, bestDist = target, d end
            end
        end
    end
    return best
end

TFC.Callback.Register('inventory:give', function(src, slot, count)
    local why = InvSrv.blocked(src)
    if why then return { ok = false, error = why } end
    local from = InvSrv.ensure(src)
    slot = math.tointeger(tonumber(slot))
    local item = from and slot and from.items[slot]
    if not item then return { ok = false, error = 'that slot is empty' } end

    local target = closestPlayer(src)
    if not target then return { ok = false, error = 'nobody is close enough' } end
    local to = InvSrv.ensure(target)
    if not to then return { ok = false, error = 'they cannot take items right now' } end

    count = Inv.ValidCount(count) or item.count
    if count > item.count then count = item.count end
    local name, metadata = item.name, Inv.Copy(item.metadata)

    local fits, why = Inv.CanFit(to, name, count, metadata)
    if not fits then return { ok = false, error = why == 'too heavy' and 'they cannot carry that much' or 'they have no room' } end

    local giver = TFC.GetPlayer(src)
    local taker = TFC.GetPlayer(target)
    local giverName = giver and giver:GetFullName() or GetPlayerName(src)
    local takerName = taker and taker:GetFullName() or GetPlayerName(target)

    local ok, err = InvSrv.tracked({ from, to }, { [name] = true }, ('handed over: %s to %s'):format(giverName, takerName), function()
        local removed, rErr = Inv.RemoveItem(from, name, count, metadata, slot)
        if not removed then return false, rErr end
        local added, aErr = Inv.Add(to, name, count, metadata)
        if not added then
            Inv.Add(from, name, count, metadata) -- put it back
            return false, aErr
        end
        return true
    end)
    if not ok then return { ok = false, error = err } end

    local label = Items[name].label
    local what = name == 'cash' and ('$%d'):format(count) or ('%dx %s'):format(count, label)
    TFC.UI.Notify(target, { title = 'Inventory', description = ('%s gave you %s'):format(giverName, what), type = 'success' })
    TFC.UI.Notify(src, { title = 'Inventory', description = ('You gave %s %s'):format(takerName, what), type = 'success' })
    return { ok = true }
end, { rateLimit = 500 })

-- Lifecycle ------------------------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    InvSrv.closeSecondary(tonumber(source))
end)

-- New players see the drops that already exist.
TFC.On('playerLoaded', function(src)
    for _, inv in pairs(Inv.list) do
        if inv.type == 'drop' and inv.announced then
            TriggerClientEvent('tfc-inventory:client:drop', src, inv.id, inv.coords)
        end
    end
end)

CreateThread(function()
    while not InvSrv.ready do Wait(250) end

    -- Forget vehicle storage nobody has touched in a while (unowned NPC cars, mostly).
    local purged = MySQL.update.await([[
        DELETE FROM tfc_inventories
        WHERE (id LIKE 'trunk:%' OR id LIKE 'glove:%') AND updated_at < NOW() - INTERVAL ? DAY
    ]], { Cfg.Vehicle.purgeDays })
    if (purged or 0) > 0 then TFC.Log.Info('removed %d unused vehicle storages', purged) end

    -- Expire old drops.
    while true do
        Wait(60000)
        local cutoff = os.time() - Cfg.Drop.lifetime * 60
        for _, inv in pairs(Inv.list) do
            if inv.type == 'drop' and (inv.touched or 0) < cutoff and next(inv.viewers or {}) == nil then
                removeDrop(inv)
            end
        end
    end
end)
