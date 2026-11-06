-- Civilian jobs client: the shared parts. Job files (client/*.lua) add themselves to Civ.modules.
-- The server owns the task; this side draws markers and blips, spawns the NPCs and props, and asks
-- the server when the player does something.

Civ = { task = false, modules = {}, vehicle = nil, vehicleJob = nil }

local Cfg = CivJobsConfig
local NO_RESPONSE = { ok = false, error = 'no response, try again' }

-- Helpers ------------------------------------------------------------------------------------------------

function Civ.notify(text, kind, title)
    TFC.UI.Notify({ title = title or 'Work', description = text, type = kind or 'inform' })
end

function Civ.job()
    return LocalPlayer.state['tfc:job']
end

function Civ.onDuty(name)
    local j = Civ.job()
    return j ~= nil and j.name == name and j.onDuty == true
end

function Civ.loadModel(name)
    local model = type(name) == 'number' and name or joaat(name)
    if not IsModelInCdimage(model) then return nil end
    RequestModel(model)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(0) end
    return HasModelLoaded(model) and model or nil
end

function Civ.loadDict(dict)
    RequestAnimDict(dict)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(dict)
end

---Ground height at (x, y), or `z` if it can't be found (not streamed in yet).
function Civ.groundZ(x, y, z)
    local found, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + 2.0, false)
    if found then return gz end
    return z - 1.0
end

---Nearest road spot (for vehicles) to a point.
function Civ.roadSpot(x, y, z)
    local ok, pos, heading = GetClosestVehicleNodeWithHeading(x + 0.0, y + 0.0, z + 0.0, 1, 3.0, 0)
    if ok then return pos, heading end
    return vector3(x, y, z), 0.0
end

---A road spot between min and max metres away from the player, in a random direction.
function Civ.randomRoadSpot(range)
    local p = GetEntityCoords(PlayerPedId())
    for _ = 1, 10 do
        local a = math.random() * math.pi * 2
        local d = range[1] + math.random() * (range[2] - range[1])
        local pos, heading = Civ.roadSpot(p.x + math.cos(a) * d, p.y + math.sin(a) * d, p.z)
        local real = #(vector2(pos.x, pos.y) - vector2(p.x, p.y))
        if real >= range[1] * 0.6 and real <= range[2] * 1.3 then return pos, heading end
    end
    return nil
end

function Civ.streetName(c)
    local s1 = GetStreetNameAtCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
    local street = GetStreetNameFromHashKey(s1)
    local zone = GetLabelText(GetNameOfZone(c.x + 0.0, c.y + 0.0, c.z + 0.0))
    if zone == 'NULL' then zone = '' end
    if street ~= '' and zone ~= '' then return street .. ', ' .. zone end
    return street ~= '' and street or zone
end

function Civ.dist(a, b)
    return #(vector3(a.x, a.y, a.z or 0.0) - vector3(b.x, b.y, b.z or 0.0))
end

function Civ.dist2d(a, b)
    return #(vector2(a.x, a.y) - vector2(b.x, b.y))
end

function Civ.me() return GetEntityCoords(PlayerPedId()) end

---Ask the server to do something with the current task. Shows the error if it says no.
function Civ.act(action, data)
    if not Civ.task then return NO_RESPONSE end
    local r = TFC.Callback.Await('civjobs:act', Civ.task.id, action, data or {}) or NO_RESPONSE
    if not r.ok and r.error then Civ.notify(r.error, 'error') end
    return r
end

function Civ.request(job, what, data)
    local r = TFC.Callback.Await('civjobs:request', job, what, data or {}) or NO_RESPONSE
    if not r.ok and r.error then Civ.notify(r.error, 'error') end
    return r
end

-- Markers, blips and the [E] prompt ----------------------------------------------------------------------------

---Draw a ground marker at c (call every frame).
function Civ.marker(c, rgb, size)
    local z = c.gz or c.z
    rgb = rgb or { 232, 163, 61 }
    size = size or 0.8
    DrawMarker(1, c.x + 0.0, c.y + 0.0, z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, 0.4, rgb[1], rgb[2], rgb[3], 120, false, false, 2, false, nil, nil, false)
end

---Give a point a ground height once (markers sit on the floor).
function Civ.ground(c)
    if c.gz == nil and c.x then c.gz = Civ.groundZ(c.x, c.y, c.z or 50.0) end
    return c
end

local blips = {}

function Civ.blip(key, c, opts)
    Civ.clearBlip(key)
    opts = opts or {}
    local b = AddBlipForCoord(c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0)
    SetBlipSprite(b, opts.sprite or 1)
    SetBlipColour(b, opts.color or 5)
    SetBlipScale(b, opts.scale or 0.85)
    if opts.route then
        SetBlipRoute(b, true)
        SetBlipRouteColour(b, opts.color or 5)
    end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(opts.label or 'Work')
    EndTextCommandSetBlipName(b)
    blips[key] = b
    return b
end

function Civ.radiusBlip(key, c, radius, color)
    Civ.clearBlip(key)
    local b = AddBlipForRadius(c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0, radius + 0.0)
    SetBlipColour(b, color or 5)
    SetBlipAlpha(b, 90)
    blips[key] = b
end

function Civ.clearBlip(key)
    if blips[key] and DoesBlipExist(blips[key]) then RemoveBlip(blips[key]) end
    blips[key] = nil
end

function Civ.clearBlips(prefix)
    for key in pairs(blips) do
        if not prefix or key:sub(1, #prefix) == prefix then Civ.clearBlip(key) end
    end
end

-- One prompt at a time: modules call Civ.offer() every frame; the first one wins.
local wanted = nil
local busy = false

function Civ.offer(text, fn)
    if wanted or busy then return end
    wanted = { text = text, fn = fn }
end

function Civ.busy() return busy end

---Run something that waits (progress bar, server call) without double presses.
function Civ.run(fn)
    if busy then return end
    busy = true
    TFC.UI.HidePrompt()
    CreateThread(function()
        local ok, err = pcall(fn)
        if not ok then print('^1[tfc-civjobs] ' .. tostring(err) .. '^7') end
        busy = false
    end)
end

-- Carrying things ---------------------------------------------------------------------------------------------

local CARRY = {
    box = { prop = 'hei_prop_heist_box', bone = 60309, pos = { 0.025, 0.08, 0.255 }, rot = { -145.0, 290.0, 0.0 }, dict = 'anim@heists@box_carry@', clip = 'idle' },
    package = { prop = 'prop_cs_cardbox_01', bone = 60309, pos = { 0.025, 0.08, 0.255 }, rot = { -145.0, 290.0, 0.0 }, dict = 'anim@heists@box_carry@', clip = 'idle' },
    bag = { prop = 'prop_cs_rub_binbag_01', bone = 57005, pos = { 0.12, 0.0, -0.05 }, rot = { 220.0, 120.0, 0.0 }, dict = 'missfbi4prepp1', clip = '_bag_walk_garbage_man' },
}
local carried = nil

function Civ.carry(kind)
    if carried and carried.kind == kind then return end
    Civ.stopCarry()
    local c = CARRY[kind]
    local model = Civ.loadModel(c.prop)
    if not model then return end
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local obj = CreateObject(model, p.x, p.y, p.z + 0.2, true, true, false)
    SetModelAsNoLongerNeeded(model)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, c.bone), c.pos[1], c.pos[2], c.pos[3], c.rot[1], c.rot[2], c.rot[3], true, true, false, true, 1, true)
    if Civ.loadDict(c.dict) then TaskPlayAnim(ped, c.dict, c.clip, 8.0, -8.0, -1, 49, 0.0, false, false, false) end
    carried = { kind = kind, obj = obj, dict = c.dict, clip = c.clip }
end

function Civ.stopCarry()
    if not carried then return end
    if DoesEntityExist(carried.obj) then DeleteEntity(carried.obj) end
    StopAnimTask(PlayerPedId(), carried.dict, carried.clip, 1.0)
    carried = nil
end

function Civ.carrying() return carried and carried.kind or nil end

-- Keep the carry animation going (it stops when the player jumps, ragdolls...).
CreateThread(function()
    while true do
        if carried then
            local ped = PlayerPedId()
            if not IsEntityPlayingAnim(ped, carried.dict, carried.clip, 3) and not IsPedRagdoll(ped) then
                TaskPlayAnim(ped, carried.dict, carried.clip, 8.0, -8.0, -1, 49, 0.0, false, false, false)
            end
            DisableControlAction(0, 21, true)   -- no sprinting with a box
            DisableControlAction(0, 22, true)   -- or jumping
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- Work vehicle ----------------------------------------------------------------------------------------------------

---The work vehicle's rear (where bags and packages go).
function Civ.vehicleRear(veh)
    local min = GetModelDimensions(GetEntityModel(veh))
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, min.y - 0.6, 0.0)
end

function Civ.myVehicle()
    if Civ.vehicle and DoesEntityExist(Civ.vehicle) then return Civ.vehicle end
    Civ.vehicle = nil
    return nil
end

function Civ.takeVehicle(jobName)
    local r = TFC.Callback.Await('civjobs:vehicle', jobName, 'request') or NO_RESPONSE
    if not r.ok then return Civ.notify(r.error, 'error') end
    local model = Civ.loadModel(r.model)
    if not model then return Civ.notify('That vehicle model is missing.', 'error') end
    local pos, heading = Civ.roadSpot(r.spot.x, r.spot.y, r.spot.z)
    local veh = CreateVehicle(model, pos.x, pos.y, pos.z + 0.5, heading, true, false)
    SetModelAsNoLongerNeeded(model)
    if not veh or veh == 0 then return Civ.notify('Could not get the vehicle out. Try again.', 'error') end
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleNumberPlateText(veh, ('%s%02d'):format(r.plate or 'WORK', math.random(0, 99)))
    SetVehicleEngineOn(veh, true, true, false)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdCanMigrate(netId, true)
    local ok = TFC.Callback.Await('civjobs:vehicle', jobName, 'spawned', netId) or NO_RESPONSE
    if not ok.ok then
        DeleteEntity(veh)
        return Civ.notify(ok.error, 'error')
    end
    Civ.vehicle, Civ.vehicleJob = veh, jobName
    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    Civ.notify('Your work vehicle is ready. Bring it back here when you\'re done.', 'success')
end

function Civ.returnVehicle(jobName)
    local r = TFC.Callback.Await('civjobs:vehicle', jobName, 'return') or NO_RESPONSE
    if not r.ok then return Civ.notify(r.error, 'error') end
    Civ.vehicle, Civ.vehicleJob = nil, nil
    Civ.notify('Vehicle returned.', 'success')
end

-- Depots: blip, ped and a menu (clock in/out, vehicle, start route) ------------------------------------------------

local DEPOTS = {
    { job = Cfg.Garbage.Job, label = Cfg.Garbage.Label, coords = Cfg.Garbage.Depot, ped = Cfg.Garbage.DepotPed, blip = Cfg.Garbage.Blip, route = true },
    { job = Cfg.Delivery.Job, label = Cfg.Delivery.Label, coords = Cfg.Delivery.Depot, ped = Cfg.Delivery.DepotPed, blip = Cfg.Delivery.Blip, route = true },
    { job = Cfg.Mechanic.Job, label = Cfg.Mechanic.Label, coords = Cfg.Mechanic.Yard, blip = Cfg.Mechanic.Blip },
    { job = Cfg.Taxi.Job, label = Cfg.Taxi.Label, coords = Cfg.Taxi.Depot, blip = Cfg.Taxi.Blip },
}

for _, d in ipairs(DEPOTS) do
    local b = AddBlipForCoord(d.coords.x, d.coords.y, d.coords.z)
    SetBlipSprite(b, d.blip.sprite)
    SetBlipColour(b, d.blip.color)
    SetBlipScale(b, 0.75)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(d.label)
    EndTextCommandSetBlipName(b)
    d.point = { x = d.coords.x, y = d.coords.y, z = d.coords.z }
end

local function depotMenu(d)
    local job = Civ.job()
    if not job or job.name ~= d.job then
        return Civ.notify(('You don\'t work for %s. Sign up at the Government Center.'):format(d.label), 'error', d.label)
    end
    local function duty(on)
        local r = TFC.Callback.Await('civjobs:duty', d.job, on) or NO_RESPONSE
        if not r.ok then Civ.notify(r.error, 'error', d.label) end
    end
    if not job.onDuty then return Civ.run(function() duty(true) end) end

    local options = {}
    local veh = Civ.myVehicle()
    local task = Civ.task
    if task and task.job == d.job and task.phase == 'return' then
        options[#options + 1] = { title = 'Finish route', description = 'Collect your route bonus', icon = 'flag-checkered', event = 'tfc-civjobs:client:depot', args = { job = d.job, what = 'finish' } }
    end
    if d.route and not task then
        options[#options + 1] = { title = 'Start a route', description = veh and 'Get your stops' or 'Take a vehicle first', icon = 'route', disabled = not veh, event = 'tfc-civjobs:client:depot', args = { job = d.job, what = 'route' } }
    end
    if veh then
        options[#options + 1] = { title = 'Return vehicle', icon = 'square-parking', event = 'tfc-civjobs:client:depot', args = { job = d.job, what = 'return' } }
    else
        options[#options + 1] = { title = 'Take a work vehicle', icon = 'truck', event = 'tfc-civjobs:client:depot', args = { job = d.job, what = 'vehicle' } }
    end
    options[#options + 1] = { title = 'Clock out', icon = 'right-from-bracket', event = 'tfc-civjobs:client:depot', args = { job = d.job, what = 'off' } }

    if not TFC.UI.Menu({ id = 'tfc_civjobs_depot', title = d.label, options = options }) then
        -- No menu library: do the most useful thing.
        local first = options[1].args
        TriggerEvent('tfc-civjobs:client:depot', first)
    end
end

AddEventHandler('tfc-civjobs:client:depot', function(a)
    if type(a) ~= 'table' then return end
    Civ.run(function()
        if a.what == 'vehicle' then Civ.takeVehicle(a.job)
        elseif a.what == 'return' then Civ.returnVehicle(a.job)
        elseif a.what == 'route' then Civ.request(a.job, 'route')
        elseif a.what == 'finish' then Civ.act('finish')
        elseif a.what == 'off' then
            local r = TFC.Callback.Await('civjobs:duty', a.job, false) or NO_RESPONSE
            if not r.ok then Civ.notify(r.error, 'error') end
        end
    end)
end)

local depotPeds = {}

local function depotTick(here)
    for i, d in ipairs(DEPOTS) do
        local dist = Civ.dist2d(here, d.point)
        if d.ped then
            if dist < 60.0 and not depotPeds[i] then
                local model = Civ.loadModel(d.ped)
                if model then
                    local z = Civ.groundZ(d.coords.x, d.coords.y, d.coords.z)
                    local ped = CreatePed(4, model, d.coords.x, d.coords.y, z, d.coords.w, false, true)
                    SetModelAsNoLongerNeeded(model)
                    SetEntityInvincible(ped, true)
                    FreezeEntityPosition(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
                    depotPeds[i] = ped
                end
            elseif dist >= 60.0 and depotPeds[i] then
                if DoesEntityExist(depotPeds[i]) then DeleteEntity(depotPeds[i]) end
                depotPeds[i] = nil
            end
        end
        if dist < 20.0 then
            Civ.ground(d.point)
            if not d.ped then Civ.marker(d.point, { 232, 163, 61 }, 1.2) end
            if dist < 2.5 and not IsPedInAnyVehicle(PlayerPedId(), false) then
                Civ.offer('[E] ' .. d.label, function() depotMenu(d) end)
            end
        end
    end
end

-- Task updates from the server -----------------------------------------------------------------------------------

TFC.OnNet('tfc-civjobs:client:task', function(task)
    local old = Civ.task
    Civ.task = task or false
    for _, m in pairs(Civ.modules) do
        if m.onTask then
            local ok, err = pcall(m.onTask, Civ.task, old)
            if not ok then print('^1[tfc-civjobs] ' .. tostring(err) .. '^7') end
        end
    end
    if not Civ.task then Civ.stopCarry() end
end)

---What the player is doing right now, in words.
function Civ.describe()
    local t = Civ.task
    if not t then return nil end
    for _, m in pairs(Civ.modules) do
        if m.describe then
            local text = m.describe(t)
            if text then return text end
        end
    end
    return nil
end

-- Main loop ----------------------------------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local sleep = 500
        if TFC.PlayerData then
            local here = Civ.me()
            wanted = nil
            depotTick(here)
            local job = Civ.job()
            for _, m in pairs(Civ.modules) do
                if m.tick and (Civ.task or (job and m.job == job.name)) then
                    local ok, active = pcall(m.tick, here, Civ.task)
                    if not ok then print('^1[tfc-civjobs] ' .. tostring(active) .. '^7')
                    elseif active then sleep = 0 end
                end
            end
            for _, d in ipairs(DEPOTS) do
                if Civ.dist2d(here, d.point) < 20.0 then sleep = 0 end
            end
            if wanted and not busy then
                TFC.UI.ShowPrompt(wanted.text)
                if IsControlJustReleased(0, Cfg.TaskKey) then
                    local fn = wanted.fn
                    Civ.run(fn)
                end
            elseif not busy then
                TFC.UI.HidePrompt()
            end
        end
        Wait(sleep)
    end
end)

-- F6 actions and commands -----------------------------------------------------------------------------------------------

local ALL = { Cfg.Clerk.Job, Cfg.Garbage.Job, Cfg.Delivery.Job, Cfg.Mechanic.Job, Cfg.Taxi.Job }

local function addActions()
    local jobs = exports['tfc-jobs']
    jobs:AddJobAction({ id = 'civ_task', jobs = ALL, label = 'Current task', description = 'What you should be doing',
        icon = 'clipboard-list', event = 'tfc-civjobs:client:taskInfo', target = false, duty = false })
    jobs:AddJobAction({ id = 'civ_cancel', jobs = { Cfg.Garbage.Job, Cfg.Delivery.Job, Cfg.Mechanic.Job, Cfg.Taxi.Job }, label = 'Cancel task',
        description = 'Give up the current route, call or fare (no bonus)', icon = 'xmark', event = 'tfc-civjobs:client:cancel', target = false })
    for _, m in pairs(Civ.modules) do
        if m.actions then m.actions(jobs) end
    end
end

CreateThread(function()
    while GetResourceState('tfc-jobs') ~= 'started' do Wait(500) end
    Wait(500)
    addActions()
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'tfc-jobs' then addActions() end
end)

AddEventHandler('tfc-civjobs:client:taskInfo', function()
    local text = Civ.describe()
    Civ.notify(text or 'No task right now.', 'inform', 'Current task')
end)

AddEventHandler('tfc-civjobs:client:cancel', function()
    Civ.run(function()
        local r = TFC.Callback.Await('civjobs:cancel') or NO_RESPONSE
        if not r.ok then Civ.notify(r.error, 'error') end
    end)
end)

RegisterCommand('task', function() TriggerEvent('tfc-civjobs:client:taskInfo') end, false)

TFC.OnPlayerUnloaded(function()
    Civ.stopCarry()
    Civ.vehicle = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Civ.stopCarry()
    Civ.clearBlips()
    for _, ped in pairs(depotPeds) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    TFC.UI.HidePrompt()
end)
