-- Inventory client: open/close, hotbar keys, item effects, and the bridge to the NUI page.
-- The server owns every item; the client only shows them and asks for changes.

local isOpen = false
local playerView = nil   -- latest copy of our own inventory (for the hotbar)
local NO_RESPONSE = { ok = false, error = 'no response from server, try again' }

local function itemDefs()
    local defs = {}
    for name, def in pairs(Items) do
        defs[name] = { label = def.label, weight = def.weight, description = def.description, usable = def.usable == true, stack = def.stack ~= false }
    end
    return defs
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function open()
    if isOpen or not TFC.PlayerData or IsPauseMenuActive() then return end
    local r = TFC.Callback.Await('inventory:open') or NO_RESPONSE
    if not r.ok then
        TFC.UI.Notify({ title = 'Inventory', description = r.error, type = 'error' })
        return
    end
    isOpen = true
    playerView = r.player
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        player = r.player,
        secondary = r.secondary,
        items = itemDefs(),
        imagePath = InventoryConfig.ImagePath,
        hotbar = InventoryConfig.HotbarSlots,
    })
end

local function use(slot)
    local r = TFC.Callback.Await('inventory:use', slot) or NO_RESPONSE
    if not r.ok then
        TFC.UI.Notify({ title = 'Inventory', description = r.error, type = 'error' })
    elseif r.close then
        close()
    end
    return r
end

-- Keys --------------------------------------------------------------------------------------

RegisterCommand('inventory', function()
    if isOpen then close() else open() end
end, false)
RegisterKeyMapping('inventory', 'Open inventory', 'keyboard', InventoryConfig.OpenKey)

for i = 1, InventoryConfig.HotbarSlots do
    RegisterCommand(('hotbar%d'):format(i), function()
        if isOpen or not TFC.PlayerData or IsPauseMenuActive() then return end
        SendNUIMessage({ action = 'hotbar', player = playerView, items = itemDefs(), imagePath = InventoryConfig.ImagePath, hotbar = InventoryConfig.HotbarSlots, used = i })
        use(i)
    end, false)
    RegisterKeyMapping(('hotbar%d'):format(i), ('Use hotbar slot %d'):format(i), 'keyboard', tostring(i))
end

-- Server -> client -------------------------------------------------------------------------------

TFC.OnNet('tfc-inventory:client:sync', function(view)
    if view and view.type == 'player' then playerView = view end
    if isOpen then SendNUIMessage({ action = 'update', inventory = view }) end
end)

TFC.OnNet('tfc-inventory:client:item', function(name, def)
    Items[name] = def
end)

-- Built-in item effects.
TFC.OnNet('tfc-inventory:client:effect', function(effect)
    local ped = PlayerPedId()
    if effect.heal then
        local max = GetEntityMaxHealth(ped)
        SetEntityHealth(ped, math.min(max, GetEntityHealth(ped) + effect.heal))
    end
end)

TFC.OnPlayerUnloaded(function()
    close()
    playerView = nil
end)

-- NUI -> client -> server ---------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('move', function(d, cb)
    cb(TFC.Callback.Await('inventory:move', d.fromId, d.fromSlot, d.toId, d.toSlot, d.count) or NO_RESPONSE)
end)

RegisterNUICallback('use', function(d, cb)
    cb(use(d.slot))
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then SetNuiFocus(false, false) end
end)
