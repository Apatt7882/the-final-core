-- Mechanic breakdown calls and taxi fares (client).

local M = CivJobsConfig.Mechanic
local T = CivJobsConfig.Taxi

-- Mechanic ------------------------------------------------------------------------------------------------

local MM = { job = M.Job }
Civ.modules.mechanic = MM

local broken = nil   -- { veh, owner, id, hooked }

local function cleanupBroken(keep)
    if not broken then return end
    if not keep then
        if broken.veh and DoesEntityExist(broken.veh) then
            DetachEntity(broken.veh, true, true)
            DeleteEntity(broken.veh)
        end
        if broken.owner and DoesEntityExist(broken.owner) then DeleteEntity(broken.owner) end
    end
    broken = nil
end

local function locateCall(t)
    CreateThread(function()
        local pos, heading = Civ.randomRoadSpot(t.range)
        if not pos then
            Civ.notify('No road spot found for the call; it was cancelled.', 'error', M.Label)
            TFC.Callback.Await('civjobs:cancel')
            return
        end
        Civ.act('located', { x = pos.x, y = pos.y, z = pos.z, h = heading })
    end)
end

local function spawnBroken(t)
    broken = { id = t.id }
    CreateThread(function()
        local model = Civ.loadModel(t.model)
        if not model then return end
        local veh = CreateVehicle(model, t.spot.x, t.spot.y, t.spot.z + 0.5, t.spot.h, true, false)
        SetModelAsNoLongerNeeded(model)
        SetVehicleOnGroundProperly(veh)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleEngineHealth(veh, 250.0)
        SetVehicleUndriveable(veh, true)
        SetVehicleDoorOpen(veh, 4, false, false)
        SetVehicleIndicatorLights(veh, 0, true)
        SetVehicleIndicatorLights(veh, 1, true)
        broken.veh = veh

        local pm = Civ.loadModel('a_m_m_skater_01')
        if pm then
            local p = GetOffsetFromEntityInWorldCoords(veh, 1.8, 2.5, 0.0)
            local owner = CreatePed(4, pm, p.x, p.y, p.z, t.spot.h, false, true)
            SetModelAsNoLongerNeeded(pm)
            SetBlockingOfNonTemporaryEvents(owner, true)
            TaskStartScenarioInPlace(owner, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
            broken.owner = owner
        end
    end)
end

function MM.onTask(t, old)
    if old and old.kind == 'call' and (not t or t.id ~= old.id) then
        Civ.clearBlips('m_')
        cleanupBroken(old.phase == 'drive' and old.mode == 'repair' and broken and broken.repaired)
    end
    if not t or t.kind ~= 'call' then return end
    Civ.clearBlips('m_')
    if t.phase == 'locate' then
        locateCall(t)
    elseif t.phase == 'drive' then
        Civ.blip('m_call', t.spot, { sprite = 446, color = 47, label = t.mode == 'tow' and 'Tow call' or 'Repair call', route = true })
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', false)
    elseif t.phase == 'deliver' then
        Civ.blip('m_yard', t.yard, { sprite = 446, color = 2, label = M.Label, route = true })
    end
end

function MM.describe(t)
    if t.kind ~= 'call' then return nil end
    if t.phase == 'locate' then return 'Getting the call details...' end
    if t.phase == 'drive' then
        return t.mode == 'tow' and 'Drive the flatbed to the broken-down car and load it.' or 'Drive to the broken-down car and repair it.'
    end
    if t.phase == 'deliver' then return ('Take the car back to %s and drop it off.'):format(M.Label) end
end

function MM.tick(here, t)
    if not t or t.kind ~= 'call' then return false end
    if t.phase == 'drive' then
        local d = Civ.dist2d(here, t.spot)
        if d < 150.0 and (not broken or broken.id ~= t.id) then spawnBroken(t) end
        if not broken or not broken.veh or not DoesEntityExist(broken.veh) then return d < 150.0 end
        local car = GetEntityCoords(broken.veh)
        if #(here - car) > 30.0 then return false end
        if IsPedInAnyVehicle(PlayerPedId(), false) then return true end
        if #(here - car) < 4.0 then
            if t.mode == 'repair' then
                Civ.offer('[E] Repair the vehicle', function()
                    TaskTurnPedToFaceEntity(PlayerPedId(), broken.veh, 800)
                    Wait(800)
                    if TFC.UI.Progress({ duration = 10000, label = 'Repairing', anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 } }) then
                        local r = Civ.act('repair')
                        if r.ok and broken and DoesEntityExist(broken.veh) then
                            local veh, owner = broken.veh, broken.owner
                            broken.repaired = true
                            SetVehicleFixed(veh)
                            SetVehicleUndriveable(veh, false)
                            SetVehicleDoorShut(veh, 4, false)
                            SetVehicleIndicatorLights(veh, 0, false)
                            SetVehicleIndicatorLights(veh, 1, false)
                            if owner and DoesEntityExist(owner) then
                                ClearPedTasks(owner)
                                TaskEnterVehicle(owner, veh, 10000, -1, 1.0, 1, 0)
                                SetTimeout(8000, function()
                                    if DoesEntityExist(owner) and DoesEntityExist(veh) then
                                        TaskVehicleDriveWander(owner, veh, 15.0, 786603)
                                    end
                                    SetTimeout(60000, function()
                                        if DoesEntityExist(veh) then SetEntityAsNoLongerNeeded(veh) end
                                        if DoesEntityExist(owner) then SetEntityAsNoLongerNeeded(owner) end
                                    end)
                                end)
                            end
                        end
                    end
                end)
            else
                local flatbed = Civ.myVehicle()
                if flatbed and #(GetEntityCoords(flatbed) - car) < 14.0 then
                    Civ.offer('[E] Load it onto the flatbed', function()
                        if TFC.UI.Progress({ duration = 5000, label = 'Securing the vehicle', anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 } }) then
                            local r = Civ.act('hooked')
                            if r.ok and broken and DoesEntityExist(broken.veh) then
                                AttachEntityToEntity(broken.veh, flatbed, GetEntityBoneIndexByName(flatbed, 'bodyshell'), 0.0, -2.35, 1.15, 0.0, 0.0, 0.0, false, false, true, false, 20, true)
                                broken.hooked = true
                                if broken.owner and DoesEntityExist(broken.owner) then DeleteEntity(broken.owner) end
                            end
                        end
                    end)
                else
                    Civ.offer('Bring your flatbed closer', function() Civ.notify('Park the flatbed next to the car first.', 'error', M.Label) end)
                end
            end
        end
        return true
    elseif t.phase == 'deliver' then
        if Civ.dist2d(here, t.yard) < 40.0 then
            Civ.ground(t.yard)
            Civ.marker(t.yard, { 76, 195, 138 }, 3.0)
            if Civ.dist2d(here, t.yard) < 20.0 then
                Civ.offer('[E] Drop off the vehicle', function()
                    local r = Civ.act('drop')
                    if r.ok then cleanupBroken(false) end
                end)
            end
            return true
        end
    end
    return false
end

-- Taxi ----------------------------------------------------------------------------------------------------

local TM = { job = T.Job }
Civ.modules.taxi = TM

local taxiModels = {}
for _, m in ipairs(T.TaxiModels) do taxiModels[joaat(m)] = true end

local fare = nil   -- { id, ped, inside }

local function myTaxi()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 and taxiModels[GetEntityModel(veh)] and GetPedInVehicleSeat(veh, -1) == PlayerPedId() then return veh end
    return nil
end

local function releasePassenger()
    if not fare or not fare.ped or not DoesEntityExist(fare.ped) then fare = nil return end
    local ped = fare.ped
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then TaskLeaveVehicle(ped, veh, 0) end
    SetTimeout(3000, function()
        if DoesEntityExist(ped) then
            TaskWanderStandard(ped, 10.0, 10)
            SetTimeout(30000, function() if DoesEntityExist(ped) then DeleteEntity(ped) end end)
        end
    end)
    fare = nil
end

local function spawnPassenger(t)
    fare = { id = t.id }
    CreateThread(function()
        local model = Civ.loadModel(t.model)
        if not model then return end
        local ok, pos = GetSafeCoordForPed(t.pickup.x, t.pickup.y, t.pickup.z, true, 16)
        if not ok then pos = vector3(t.pickup.x, t.pickup.y, t.pickup.z) end
        local ped = CreatePed(4, model, pos.x, pos.y, pos.z, 0.0, true, true)
        SetModelAsNoLongerNeeded(model)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityAsMissionEntity(ped, true, true)
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
        fare.ped = ped
    end)
end

function TM.onTask(t, old)
    if old and old.kind == 'fare' and (not t or t.id ~= old.id) then
        Civ.clearBlips('t_')
        releasePassenger()
    end
    if not t or t.kind ~= 'fare' then return end
    Civ.clearBlips('t_')
    if t.phase == 'locate' then
        CreateThread(function()
            local pos = Civ.randomRoadSpot(t.range)
            if not pos then
                Civ.notify('No fares around here right now.', 'error', T.Label)
                TFC.Callback.Await('civjobs:cancel')
                return
            end
            Civ.act('located', { x = pos.x, y = pos.y, z = pos.z })
        end)
    elseif t.phase == 'pickup' then
        Civ.blip('t_pickup', t.pickup, { sprite = 280, color = 5, label = 'Fare pickup', route = true })
    elseif t.phase == 'ride' then
        Civ.blip('t_dest', t.dest, { sprite = 38, color = 5, label = 'Fare destination', route = true })
        Civ.notify(('Take them to %s.'):format(t.dest.label or 'the marked spot'), 'inform', T.Label)
    end
end

function TM.describe(t)
    if t.kind ~= 'fare' then return nil end
    if t.phase == 'locate' then return 'Finding a fare...' end
    if t.phase == 'pickup' then return 'Pick up the passenger (on your GPS). Stop next to them.' end
    if t.phase == 'ride' then return ('Drive your passenger to %s.'):format(t.dest.label or 'the marked spot') end
end

local picking = false

function TM.tick(here, t)
    if not t or t.kind ~= 'fare' then return false end
    local veh = myTaxi()
    if t.phase == 'pickup' then
        local d = Civ.dist2d(here, t.pickup)
        if d < 120.0 and (not fare or fare.id ~= t.id) then spawnPassenger(t) end
        if not fare or not fare.ped or not DoesEntityExist(fare.ped) or not veh then return d < 120.0 end
        local pp = GetEntityCoords(fare.ped)
        if #(here - pp) < 12.0 and GetEntitySpeed(veh) < 2.0 and not picking then
            picking = true
            CreateThread(function()
                local ped = fare.ped
                ClearPedTasks(ped)
                local seat = IsVehicleSeatFree(veh, 2) and 2 or (IsVehicleSeatFree(veh, 1) and 1 or 0)
                TaskEnterVehicle(ped, veh, 15000, seat, 1.0, 1, 0)
                local until_ = GetGameTimer() + 15000
                while GetGameTimer() < until_ and DoesEntityExist(ped) and not IsPedInVehicle(ped, veh, false) do Wait(250) end
                if DoesEntityExist(ped) and IsPedInVehicle(ped, veh, false) then
                    local dest, label
                    for _ = 1, 5 do
                        dest = Civ.randomRoadSpot(t.trip)
                        if dest then break end
                    end
                    if dest then
                        label = Civ.streetName(dest)
                        Civ.act('picked', { x = dest.x, y = dest.y, z = dest.z, label = label })
                    end
                end
                picking = false
            end)
        end
        return true
    elseif t.phase == 'ride' then
        local d = Civ.dist2d(here, t.dest)
        if d < 60.0 then
            Civ.ground(t.dest)
            Civ.marker(t.dest, { 232, 163, 61 }, 3.0)
            if veh and d < 20.0 and GetEntitySpeed(veh) < 1.5 and not picking then
                picking = true
                CreateThread(function()
                    local r = Civ.act('dropped')
                    if r.ok then releasePassenger() end
                    Wait(r.ok and 1000 or 5000)
                    picking = false
                end)
            end
            return true
        end
    end
    return false
end

function TM.actions(jobs)
    jobs:AddJobAction({
        id = 'taxi_fare', jobs = { T.Job }, label = 'Find a fare',
        description = 'Get an NPC passenger (you need to be driving a taxi)', icon = 'taxi',
        event = 'tfc-civjobs:client:findFare', target = false,
    })
end

AddEventHandler('tfc-civjobs:client:findFare', function()
    Civ.run(function() Civ.request(T.Job, 'fare') end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupBroken(false)
    if fare and fare.ped and DoesEntityExist(fare.ped) then DeleteEntity(fare.ped) end
end)
