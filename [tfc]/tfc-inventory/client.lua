-- Inventory client: open/close, hotbar keys, item effects, and the bridge to the NUI page.
-- The server owns every item; the client only shows them and asks for changes.

local isOpen = false
local playerView = nil   -- latest copy of our own inventory (for the hotbar)
local NO_RESPONSE = { ok = false, error = 'no response from server, try again' }

local function itemDefs()
    local defs = {}
    for name, def in pairs(Items) do
        defs[name] = { label = def.label, weight = def.weight, description = def.description, usable = def.usable == true, stack = def.stack ~= false, weapon = def.weapon == true, clip = def.clip, extClip = WeaponMods.Clips[name] }
    end
    return defs
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TFC.Callback.Await('inventory:close')
end

-- Where am I? In a vehicle -> glovebox; at the back of one -> trunk; otherwise the ground.
local function trunkPosition(veh)
    local bone = GetEntityBoneIndexByName(veh, 'boot')
    if bone ~= -1 then return GetWorldPositionOfEntityBone(veh, bone) end
    -- No boot bone: use the rear of the model.
    local min = GetModelDimensions(GetEntityModel(veh))
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, min.y, 0.0)
end

local function context()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        return { kind = 'glovebox', net = VehToNet(veh), class = GetVehicleClass(veh) }
    end

    local here = GetEntityCoords(ped)
    local best, bestDist = nil, InventoryConfig.Vehicle.trunkDistance
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(v) - here) < 10.0 and NetworkGetEntityIsNetworked(v) then
            local d = #(trunkPosition(v) - here)
            if d < bestDist then best, bestDist = v, d end
        end
    end
    if best then
        return { kind = 'trunk', net = VehToNet(best), class = GetVehicleClass(best) }
    end
    return { kind = 'ground' }
end

local function open(ctx)
    if isOpen or not TFC.PlayerData or IsPauseMenuActive() then return end
    local r = TFC.Callback.Await('inventory:open', ctx or context()) or NO_RESPONSE
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
        return r
    end
    if r.close then close() end
    if r.weapon then ClientWeapons.handle(r.weapon) end
    if r.weaponUpdate then ClientWeapons.update(r.weaponUpdate) end
    return r
end

-- Keys --------------------------------------------------------------------------------------

-- The command is named 'tfc_inventory' (not 'inventory') so the new default key (Tab) applies
-- to everyone: FiveM keeps old bindings per command name, and players who had F2 bound to the
-- old command would otherwise keep it.
RegisterCommand('tfc_inventory', function()
    if isOpen then close() else open() end
end, false)
RegisterKeyMapping('tfc_inventory', 'Open inventory', 'keyboard', InventoryConfig.OpenKey)

for i = 1, InventoryConfig.HotbarSlots do
    RegisterCommand(('hotbar%d'):format(i), function()
        if isOpen or not TFC.PlayerData or IsPauseMenuActive() then return end
        SendNUIMessage({ action = 'hotbar', player = playerView, items = itemDefs(), imagePath = InventoryConfig.ImagePath, hotbar = InventoryConfig.HotbarSlots, used = i })
        use(i)
    end, false)
    RegisterKeyMapping(('hotbar%d'):format(i), ('Use hotbar slot %d'):format(i), 'keyboard', tostring(i))
end

-- Server -> client -------------------------------------------------------------------------------

TFC.OnNet('tfc-inventory:client:sync', function(view, own)
    -- `own` is false when this is someone else's inventory we are searching.
    if view and view.type == 'player' and own ~= false then
        playerView = view
        ClientWeapons.onInventory(view)
    end
    if isOpen then SendNUIMessage({ action = 'update', inventory = view }) end
end)

-- Police search: open the other player's inventory next to ours.
TFC.OnNet('tfc-inventory:client:openSearch', function(target)
    if isOpen then close() end
    open({ kind = 'player', target = target })
end)

-- Cuffed or downed: close the window and put the weapon away.
TFC.OnNet('tfc-inventory:client:forceClose', function()
    close()
    ClientWeapons.forceHolster()
end)

TFC.OnNet('tfc-inventory:client:secondaryClosed', function(id)
    if isOpen then SendNUIMessage({ action = 'secondaryClosed', id = id }) end
end)

TFC.OnNet('tfc-inventory:client:trunkDoor', function(net, openDoor)
    if not NetworkDoesNetworkIdExist(net) then return end
    local veh = NetToVeh(net)
    if veh == 0 then return end
    if openDoor then SetVehicleDoorOpen(veh, 5, false, false) else SetVehicleDoorShut(veh, 5, false) end
end)

TFC.OnNet('tfc-inventory:client:item', function(name, def)
    Items[name] = def
end)

-- Built-in item effects -----------------------------------------------------------------------

local activeScreen = nil
local screenEnds = 0
local sprintEnds = 0

local function playAnim(anim)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    if anim.scenario then
        TaskStartScenarioInPlace(ped, anim.scenario, 0, true)
        Wait(anim.ms or 5000)
        ClearPedTasks(ped)
        return
    end
    RequestAnimDict(anim.dict)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < t do Wait(0) end
    if not HasAnimDictLoaded(anim.dict) then return end
    TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, anim.ms or 3000, 49, 0.0, false, false, false)
    Wait(anim.ms or 3000)
    StopAnimTask(ped, anim.dict, anim.clip, 1.0)
    RemoveAnimDict(anim.dict)
end

TFC.OnNet('tfc-inventory:client:effect', function(effect)
    CreateThread(function()
        if effect.anim then playAnim(effect.anim) end

        local ped = PlayerPedId()
        if effect.heal then
            local max = GetEntityMaxHealth(ped)
            SetEntityHealth(ped, math.min(max, GetEntityHealth(ped) + effect.heal))
        end
        if effect.armor then
            SetPedArmour(ped, math.min(100, GetPedArmour(ped) + effect.armor))
        end

        if effect.sprint then
            local mult, seconds = effect.sprint[1], effect.sprint[2]
            SetRunSprintMultiplierForPlayer(PlayerId(), math.min(mult, 1.49))
            sprintEnds = GetGameTimer() + seconds * 1000
            CreateThread(function()
                Wait(seconds * 1000)
                if GetGameTimer() >= sprintEnds then SetRunSprintMultiplierForPlayer(PlayerId(), 1.0) end
            end)
        end

        if effect.screen then
            local name, seconds = effect.screen[1], effect.screen[2]
            if activeScreen and activeScreen ~= name then AnimpostfxStop(activeScreen) end
            activeScreen = name
            AnimpostfxPlay(name, 0, true)
            screenEnds = GetGameTimer() + seconds * 1000
            CreateThread(function()
                Wait(seconds * 1000)
                if activeScreen == name and GetGameTimer() >= screenEnds then
                    AnimpostfxStop(name)
                    activeScreen = nil
                end
            end)
        end
    end)
end)

TFC.OnPlayerUnloaded(function()
    close()
    playerView = nil
    if activeScreen then AnimpostfxStop(activeScreen) activeScreen = nil end
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
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

RegisterNUICallback('give', function(d, cb)
    cb(TFC.Callback.Await('inventory:give', d.slot, d.count) or NO_RESPONSE)
end)

-- Ground drops: a bag prop near the player for every drop within 50 m ------------------------------

local drops = {}    -- id -> { coords, object }

TFC.OnNet('tfc-inventory:client:drop', function(id, coords)
    drops[id] = { coords = vector3(coords.x, coords.y, coords.z) }
end)

TFC.OnNet('tfc-inventory:client:dropRemoved', function(id)
    local d = drops[id]
    if d and d.object and DoesEntityExist(d.object) then DeleteEntity(d.object) end
    drops[id] = nil
end)

local dropModel = joaat(InventoryConfig.Drop.model)
local useMarker = not IsModelInCdimage(dropModel)

CreateThread(function()
    while true do
        local here = GetEntityCoords(PlayerPedId())
        local nearAny = false

        for _, d in pairs(drops) do
            local dist = #(d.coords - here)
            if dist < 50.0 then
                nearAny = true
                if not useMarker and not d.object then
                    RequestModel(dropModel)
                    local t = GetGameTimer() + 3000
                    while not HasModelLoaded(dropModel) and GetGameTimer() < t do Wait(0) end
                    if HasModelLoaded(dropModel) then
                        d.object = CreateObject(dropModel, d.coords.x, d.coords.y, d.coords.z, false, false, false)
                        PlaceObjectOnGroundProperly(d.object)
                        FreezeEntityPosition(d.object, true)
                        SetEntityCollision(d.object, false, false)
                        SetModelAsNoLongerNeeded(dropModel)
                    else
                        useMarker = true
                    end
                end
            elseif d.object then
                DeleteEntity(d.object)
                d.object = nil
            end
        end

        if useMarker and nearAny then
            -- Draw markers every frame for a second, then re-check distances.
            local untilTime = GetGameTimer() + 1000
            while GetGameTimer() < untilTime do
                for _, d in pairs(drops) do
                    if #(d.coords - here) < 25.0 then
                        DrawMarker(2, d.coords.x, d.coords.y, d.coords.z + 0.3, 0, 0, 0, 0, 180.0, 0, 0.25, 0.25, 0.2, 232, 163, 61, 180, false, true, 2, false, nil, nil, false)
                    end
                end
                Wait(0)
            end
        else
            Wait(1000)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, d in pairs(drops) do
        if d.object and DoesEntityExist(d.object) then DeleteEntity(d.object) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then SetNuiFocus(false, false) end
end)
