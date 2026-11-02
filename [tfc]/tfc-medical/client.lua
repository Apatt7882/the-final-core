-- Medical client: going down instead of dying, the downed screen, revive / heal effects,
-- EMS distress blips, and the EMS job-menu actions (revive, treat).

local Cfg = MedicalConfig

local isDown = false
local downStart = 0          -- GetGameTimer() when we went down (server's clock, adjusted)
local emsOnDuty = 0
local distressReadyAt = 0
local busy = false

local function notify(text, kind)
    TFC.UI.Notify({ title = 'Medical', description = text, type = kind or 'inform' })
end

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(dict)
end

-- Downed --------------------------------------------------------------------------------------

local DOWN_ANIM = { dict = 'dead', clip = 'dead_a' }
local CAR_ANIM = { dict = 'veh@low@front_ps@idle_duck', clip = 'sit' }

local function playDownAnim(ped)
    local anim = IsPedInAnyVehicle(ped, false) and CAR_ANIM or DOWN_ANIM
    if IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then return end
    if not loadDict(anim.dict) then return end
    TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
end

local function overlay(data)
    SendNUIMessage(data)
end

local function elapsed()
    return math.max(0, (GetGameTimer() - downStart) // 1000)
end

local function option()
    return Cfg.RespawnOption(elapsed(), emsOnDuty)
end

---Sync with the server's view: seconds down and EMS on duty.
local function applyStatus(st)
    if type(st) ~= 'table' then return end
    downStart = GetGameTimer() - (tonumber(st.elapsed) or 0) * 1000
    emsOnDuty = tonumber(st.ems) or 0
end

---Bring the player back from GTA's death, frozen in a downed pose.
local function enterDown(st)
    if isDown then return end
    isDown = true
    applyStatus(st or { elapsed = 0, ems = 0 })

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local seat = nil
    if veh ~= 0 then
        for s = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
            if GetPedInVehicleSeat(veh, s) == ped then seat = s break end
        end
    end

    -- Wait for the death ragdoll to settle a moment, then resurrect in place.
    Wait(1500)
    local c = GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
    ped = PlayerPedId()
    if veh ~= 0 and seat and DoesEntityExist(veh) then SetPedIntoVehicle(ped, veh, seat) end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    ClearPedBloodDamage(ped)
    playDownAnim(ped)

    overlay({ action = 'down', ems = emsOnDuty, option = option() })
end

local function leaveDown()
    if not isDown then return end
    isDown = false
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    SetPedCanRagdoll(ped, true)
    if not IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end
    overlay({ action = 'up' })
end

-- spawnmanager's auto-respawn would fight with going down: turn it off.
CreateThread(function()
    if GetResourceState('spawnmanager') == 'started' then
        pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
    end
end)

-- Watch for death.
CreateThread(function()
    while true do
        Wait(250)
        if TFC.PlayerData and not isDown then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
                local r = TFC.Callback.Await('medical:down')
                enterDown(r and r.ok and r or nil)
            end
        end
    end
end)

-- While down: keep the pose, block controls, handle [E] respawn and [G] call EMS.
CreateThread(function()
    local lastSecond = -1
    while true do
        if isDown then
            local ped = PlayerPedId()
            DisableAllControlActions(0)
            for _, c in ipairs({ 1, 2, 245, 249, 199, 200 }) do EnableControlAction(0, c, true) end
            -- 1/2 look, 245 chat, 249 push-to-talk, 199/200 pause.

            if not IsEntityAttached(ped) then playDownAnim(ped) end
            if GetEntityHealth(ped) < 150 then SetEntityHealth(ped, GetEntityMaxHealth(ped)) end

            local now = elapsed()
            local opt = option()
            if now ~= lastSecond then
                lastSecond = now
                overlay({ action = 'tick', ems = emsOnDuty, option = opt })
            end

            if IsDisabledControlJustPressed(0, 47) and GetGameTimer() >= distressReadyAt then -- G
                distressReadyAt = GetGameTimer() + 2000
                CreateThread(function()
                    local r = TFC.Callback.Await('medical:distress')
                    if r then notify(r.ok and r.message or r.error, r.ok and 'success' or 'error') end
                end)
            end

            if opt.now and IsDisabledControlJustPressed(0, 38) and not busy then -- E
                busy = true
                CreateThread(function()
                    local r = TFC.Callback.Await('medical:respawn')
                    if r and not r.ok then notify(r.error, 'error') end
                    busy = false
                end)
            end
            Wait(0)
        else
            lastSecond = -1
            Wait(500)
        end
    end
end)

-- Server -> client ---------------------------------------------------------------------------------

TFC.OnNet('tfc-medical:client:forceDown', function(st)
    if isDown then return end
    -- Put them down as if they'd died here (reconnected while down).
    CreateThread(function() enterDown(st) end)
end)

TFC.OnNet('tfc-medical:client:status', function(st)
    if isDown then applyStatus(st) end
end)

TFC.OnNet('tfc-medical:client:revive', function(data)
    local ped = PlayerPedId()
    if data.coords then
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(0) end
    end
    leaveDown()
    ped = PlayerPedId()
    if IsEntityDead(ped) then
        local c = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
    end
    if data.coords then
        SetEntityCoords(ped, data.coords.x, data.coords.y, data.coords.z - 1.0, false, false, false, false)
        SetEntityHeading(ped, data.coords.w or 0.0)
    end
    local max = GetEntityMaxHealth(ped)
    SetEntityHealth(ped, data.health == 'full' and max or math.min(max, data.health))
    ClearPedBloodDamage(ped)
    if data.coords then
        Wait(500)
        DoScreenFadeIn(800)
    end
end)

TFC.OnNet('tfc-medical:client:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
end)

-- Distress calls for EMS: a flashing blip for a while, and a waypoint.
TFC.OnNet('tfc-medical:client:distress', function(d)
    notify(('Distress call: %s (%d). Waypoint set.'):format(d.name, d.id), 'warning')
    local blip = AddBlipForCoord(d.x, d.y, d.z)
    SetBlipSprite(blip, 153)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.0)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Distress: ' .. d.name)
    EndTextCommandSetBlipName(blip)
    SetNewWaypoint(d.x, d.y)
    SetTimeout(Cfg.DistressBlipSeconds * 1000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

-- EMS job menu actions ------------------------------------------------------------------------------

local function emsAction(cbName, label, seconds, anim, target)
    if busy or not target then return end
    busy = true
    local done = TFC.UI.Progress({ duration = seconds * 1000, label = label, anim = anim })
    if done then
        local r = TFC.Callback.Await(cbName, target)
        if r then notify(r.ok and r.message or r.error, r.ok and 'success' or 'error') end
    end
    busy = false
end

AddEventHandler('tfc-medical:client:actionRevive', function(args)
    local target = args and args.target
    if target and not Player(target).state['tfc:down'] then return notify('They are not down.', 'error') end
    emsAction('medical:revive', 'Performing CPR', Cfg.ReviveSeconds, { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 }, target)
end)

AddEventHandler('tfc-medical:client:actionHeal', function(args)
    emsAction('medical:heal', 'Treating wounds', Cfg.HealSeconds, { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 1 }, args and args.target)
end)

local function registerActions()
    if GetResourceState('tfc-jobs') ~= 'started' then return end
    local jobs = exports['tfc-jobs']
    jobs:AddJobAction({ id = 'ems_revive', jobs = Cfg.EmsJobs, label = 'Revive', description = 'CPR on the closest downed player', icon = 'heart-pulse', event = 'tfc-medical:client:actionRevive' })
    jobs:AddJobAction({ id = 'ems_heal', jobs = Cfg.EmsJobs, label = 'Treat wounds', description = 'Heal the closest player to full', icon = 'kit-medical', event = 'tfc-medical:client:actionHeal' })
end

CreateThread(registerActions)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'tfc-jobs' then registerActions() end
end)

-- Cleanup ------------------------------------------------------------------------------------------

TFC.OnPlayerUnloaded(function()
    leaveDown()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isDown then
        SetEntityInvincible(PlayerPedId(), false)
    end
end)
