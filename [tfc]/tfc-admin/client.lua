-- Admin client: the admin menu (NUI), teleports (/tpm, /tp, goto, bring, /back), spectate,
-- and being frozen. Noclip is in client/noclip.lua. The server checks every action.

local Cfg = AdminConfig
local NO_RESPONSE = { ok = false, error = 'no response from server, try again' }
local IMAGE_PATH = 'nui://tfc-inventory/html/images/'

local menuOpen = false
local lastPos = nil       -- for /back
local spectating = nil    -- { target, returnTo }

AdminClient = {}

local function notify(text, kind)
    TFC.UI.Notify({ title = 'Admin', description = text, type = kind or 'inform' })
end

function AdminClient.isAdmin()
    return LocalPlayer.state['tfc:admin'] == true
end

-- Teleports ----------------------------------------------------------------------------------------

local function moveEntity()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then return veh end
    return ped
end

---Find solid ground under x, y (loads the area first). Returns z or nil.
local function groundAt(x, y)
    local ent = moveEntity()
    for z = 1000.0, 0.0, -25.0 do
        SetEntityCoordsNoOffset(ent, x, y, z, false, false, false)
        RequestCollisionAtCoord(x, y, z)
        local t = GetGameTimer() + 150
        while GetGameTimer() < t do Wait(0) end
        local found, groundZ = GetGroundZFor_3dCoord(x, y, z, false)
        if found then return groundZ end
    end
    return nil
end

function AdminClient.teleport(c, opts)
    opts = opts or {}
    local ent = moveEntity()
    local here = GetEntityCoords(ent)
    lastPos = { x = here.x, y = here.y, z = here.z, w = GetEntityHeading(ent) }

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end
    FreezeEntityPosition(ent, true)

    local z = c.z
    if opts.findGround then
        z = groundAt(c.x, c.y)
        if not z then
            notify('Could not find the ground there; dropped you from above.', 'warning')
            z = 300.0
        end
    else
        RequestCollisionAtCoord(c.x, c.y, c.z)
    end

    SetEntityCoordsNoOffset(ent, c.x, c.y, z + (opts.findGround and 1.0 or 0.0), false, false, false)
    if c.w then SetEntityHeading(ent, c.w) end
    local t = GetGameTimer() + 1000
    while not HasCollisionLoadedAroundEntity(ent) and GetGameTimer() < t do Wait(0) end
    FreezeEntityPosition(ent, false)
    DoScreenFadeIn(400)
end

TFC.OnNet('tfc-admin:client:teleport', function(c, opts)
    AdminClient.teleport(c, opts)
end)

local function toWaypoint()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then return notify('Set a waypoint on the map first.', 'error') end
    local c = GetBlipInfoIdCoord(blip)
    AdminClient.teleport({ x = c.x, y = c.y, z = 0.0 }, { findGround = true })
end

TFC.OnNet('tfc-admin:client:tpm', toWaypoint)

local function goBack()
    if not lastPos then return notify('Nowhere to go back to.', 'error') end
    AdminClient.teleport(lastPos)
end

TFC.OnNet('tfc-admin:client:back', goBack)

-- Frozen / healed by an admin ------------------------------------------------------------------------

AddStateBagChangeHandler('tfc:frozen', nil, function(bagName, _, value)
    if bagName ~= ('player:%d'):format(GetPlayerServerId(PlayerId())) then return end
    FreezeEntityPosition(PlayerPedId(), value == true)
end)

TFC.OnNet('tfc-admin:client:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
end)

-- Spectate ---------------------------------------------------------------------------------------------

local function stopSpectate()
    if not spectating then return end
    local s = spectating
    spectating = nil
    local ped = PlayerPedId()
    NetworkSetInSpectatorMode(false, ped)
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end
    SetEntityCoordsNoOffset(ped, s.returnTo.x, s.returnTo.y, s.returnTo.z, false, false, false)
    SetEntityHeading(ped, s.returnTo.w)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    DoScreenFadeIn(400)
    notify('Stopped spectating.')
end

TFC.OnNet('tfc-admin:client:stopSpectate', stopSpectate)

TFC.OnNet('tfc-admin:client:spectate', function(target, c)
    if spectating then stopSpectate() end
    if AdminNoclip and AdminNoclip.active() then AdminNoclip.set(false) end

    local ped = PlayerPedId()
    local here = GetEntityCoords(ped)
    spectating = { target = target, returnTo = { x = here.x, y = here.y, z = here.z, w = GetEntityHeading(ped) } }

    -- Hide ourselves near them (under the map) so their ped streams in for us.
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z - 30.0, false, false, false)

    CreateThread(function()
        local started = GetGameTimer()
        local watching = false
        while spectating and spectating.target == target do
            local player = GetPlayerFromServerId(target)
            local targetPed = player ~= -1 and GetPlayerPed(player) or 0
            if targetPed ~= 0 and DoesEntityExist(targetPed) then
                if not watching then
                    NetworkSetInSpectatorMode(true, targetPed)
                    watching = true
                    notify(('Spectating %d. Press Backspace or /spectate to stop.'):format(target))
                end
                local tc = GetEntityCoords(targetPed)
                SetEntityCoordsNoOffset(PlayerPedId(), tc.x, tc.y, tc.z - 30.0, false, false, false)
            else
                -- Not streamed in (far away / teleported): ask the server where they are.
                watching = false
                local pos = TFC.Callback.Await('admin:targetCoords', target)
                if not pos then
                    notify('They left.', 'error')
                    break
                end
                SetEntityCoordsNoOffset(PlayerPedId(), pos.x, pos.y, pos.z - 30.0, false, false, false)
                if GetGameTimer() - started > 15000 and not watching then
                    notify('Could not load their position.', 'error')
                    break
                end
            end
            for _ = 1, 50 do
                if IsControlJustPressed(0, 177) then -- Backspace / Esc (cancel)
                    stopSpectate()
                    return
                end
                Wait(0)
            end
        end
        if spectating and spectating.target == target then stopSpectate() end
    end)
end)

-- Menu -------------------------------------------------------------------------------------------------

---@param tab string 'players' | 'items'
---@param explicit boolean true when asked for by command (show errors); false for the key
local function openMenu(tab, explicit)
    if menuOpen then
        -- Pressing the key again closes it (and un-sticks a menu that never finished opening).
        menuOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
        return
    end

    -- The server decides who is an admin; the client flag is only a hint, so never rely on it here.
    local r = TFC.Callback.Await('admin:data')
    if not r then
        print('^1[tfc-admin] no answer from the server for admin:data (is tfc-admin started on the server?)^7')
        return notify('No response from the server.', 'error')
    end
    if not r.ok then
        if explicit then notify(r.error, 'error') end
        return
    end
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', tab = tab or 'players', data = r, imagePath = IMAGE_PATH })
end

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

TFC.OnNet('tfc-admin:client:openMenu', function(tab) openMenu(tab, true) end)

RegisterCommand('tfc_admin', function() openMenu('players', false) end, false)
RegisterKeyMapping('tfc_admin', 'Admin menu (admins only)', 'keyboard', Cfg.MenuKey)

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb({})
end)

RegisterNUICallback('refresh', function(_, cb)
    cb(TFC.Callback.Await('admin:data') or NO_RESPONSE)
end)

RegisterNUICallback('action', function(d, cb)
    local r = TFC.Callback.Await('admin:action', d.action, d.target, d.data or {}) or NO_RESPONSE
    if r.close then closeMenu() end
    cb(r)
end)

-- World tab: talks to tfc-world's server directly (it checks admin itself).
RegisterNUICallback('world', function(d, cb)
    if GetResourceState('tfc-world') ~= 'started' then return cb({ ok = false, error = 'tfc-world is not running' }) end
    if d.action == 'state' then return cb(TFC.Callback.Await('world:state') or NO_RESPONSE) end
    cb(TFC.Callback.Await('world:set', d.action, d.a, d.b) or NO_RESPONSE)
end)

RegisterNUICallback('self', function(d, cb)
    if d.action == 'noclip' then
        closeMenu()
        AdminNoclip.toggle()
    elseif d.action == 'tpm' then
        closeMenu()
        ExecuteCommand('tpm')
    elseif d.action == 'back' then
        closeMenu()
        goBack()
    end
    cb({ ok = true })
end)

-- Cleanup ------------------------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if menuOpen then SetNuiFocus(false, false) end
    if spectating then
        NetworkSetInSpectatorMode(false, PlayerPedId())
        SetEntityVisible(PlayerPedId(), true, false)
        SetEntityCollision(PlayerPedId(), true, true)
        FreezeEntityPosition(PlayerPedId(), false)
    end
end)
