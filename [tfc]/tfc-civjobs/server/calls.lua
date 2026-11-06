-- Mechanic breakdown calls and taxi fares (server). Both are spots on the road the client picks
-- (nearest road node a set distance away) and the server checks: distance, time and position.

-- Mechanic ---------------------------------------------------------------------------------------------

local M = CivJobsConfig.Mechanic
local Mechanic = {
    name = M.Job, label = M.Label, actions = {}, requests = {},
    vehicle = { model = M.Vehicle, depot = M.Yard, spot = M.VehicleSpot, plate = 'HAYES' },
}
Civ.Jobs[M.Job] = Mechanic

local nextCall = {}   -- src -> os.time() of their next call

local function mNotify(src, text, kind) Civ.notify(src, text, kind, M.Label) end

function Mechanic.dutyChanged(src, onDuty, job)
    if onDuty and job and job.name == M.Job then
        nextCall[src] = os.time() + 20
        mNotify(src, 'On duty. Breakdown calls will come in; take the flatbed from the yard to do tows too.', 'success')
    end
end

function Mechanic.stop(src) nextCall[src] = nil end

local function newCall(src)
    local tow = Civ.vehicleOf(src) ~= nil and math.random() < M.TowChance
    Civ.issue(src, {
        job = M.Job, kind = 'call', mode = tow and 'tow' or 'repair', phase = 'locate',
        model = M.BrokenModels[math.random(#M.BrokenModels)], range = M.CallDistance,
    })
end

function Mechanic.start()
    while true do
        Wait(5000)
        local now = os.time()
        for src, at in pairs(nextCall) do
            if now >= at and not Civ.tasks[src] and Civ.working(src, M.Job) then
                nextCall[src] = now + Civ.rand(M.CallEvery)
                newCall(src)
            end
        end
    end
end

-- The client found a road spot for the broken-down car.
function Mechanic.actions.located(src, task, d)
    if task.kind ~= 'call' or task.phase ~= 'locate' then return Civ.fail('not now') end
    local x, y, z, h = tonumber(d.x), tonumber(d.y), tonumber(d.z), tonumber(d.h) or 0.0
    local p = Civ.pos(src)
    if not x or not p then return Civ.fail('bad spot') end
    local dist = Civ.dist2d(p, { x = x, y = y })
    if dist < M.CallDistance[1] * 0.5 or dist > M.CallDistance[2] * 1.5 then return Civ.fail('bad spot') end
    task.spot = { x = x, y = y, z = z, h = h }
    task.phase = 'drive'
    task._locatedAt = os.time()
    task._minTime = math.floor(dist / 45)   -- no one gets there faster than ~160 km/h
    Civ.update(src, task)
    mNotify(src, task.mode == 'tow' and 'Breakdown call: tow it back to the yard. Location on your GPS.'
        or 'Breakdown call: repair it on the spot. Location on your GPS.', 'inform')
end

function Mechanic.cancelled(src)
    if nextCall[src] then nextCall[src] = os.time() + Civ.rand(M.CallEvery) end
end

function Mechanic.actions.repair(src, task)
    if task.kind ~= 'call' or task.mode ~= 'repair' or task.phase ~= 'drive' then return Civ.fail('not now') end
    if not Civ.near(src, task.spot, 8.0) then return Civ.fail('get to the vehicle') end
    if os.time() - task._locatedAt < task._minTime + 8 then return Civ.fail('slow down') end
    Civ.clear(src)
    nextCall[src] = os.time() + Civ.rand(M.CallEvery)
    Civ.pay(src, M.RepairPay, 'Roadside repair', M.Label)
end

function Mechanic.actions.hooked(src, task)
    if task.kind ~= 'call' or task.mode ~= 'tow' or task.phase ~= 'drive' then return Civ.fail('not now') end
    if not Civ.near(src, task.spot, 15.0) or not Civ.vehicleNear(src, 15.0) then return Civ.fail('bring the flatbed to the vehicle') end
    if os.time() - task._locatedAt < task._minTime then return Civ.fail('slow down') end
    task.phase = 'deliver'
    task.yard = { x = M.Yard.x, y = M.Yard.y, z = M.Yard.z }
    task._hookedAt = os.time()
    task._hookedDist = Civ.dist2d(task.spot, M.Yard)
    Civ.update(src, task)
end

function Mechanic.actions.drop(src, task)
    if task.kind ~= 'call' or task.phase ~= 'deliver' then return Civ.fail('not now') end
    if not Civ.near(src, M.Yard, 30.0) or not Civ.vehicleNear(src, 20.0) then return Civ.fail('bring it to the yard') end
    if os.time() - task._hookedAt < math.floor(task._hookedDist / 45) then return Civ.fail('slow down') end
    Civ.clear(src)
    nextCall[src] = os.time() + Civ.rand(M.CallEvery)
    Civ.pay(src, M.TowPay, 'Tow to the yard', M.Label)
end

-- Taxi ----------------------------------------------------------------------------------------------------

local T = CivJobsConfig.Taxi
local Taxi = {
    name = T.Job, label = T.Label, actions = {}, requests = {},
    vehicle = { model = T.Vehicle, depot = T.Depot, spot = T.VehicleSpot, plate = 'DTCAB' },
}
Civ.Jobs[T.Job] = Taxi

local taxiModels = {}
for _, m in ipairs(T.TaxiModels) do taxiModels[joaat(m)] = true end

local function tNotify(src, text, kind) Civ.notify(src, text, kind, T.Label) end

---Is the player driving a taxi?
local function inTaxi(src)
    local ped = GetPlayerPed(src)
    local veh = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    return veh ~= 0 and taxiModels[GetEntityModel(veh)] == true
end

function Taxi.requests.fare(src)
    if Civ.tasks[src] then return Civ.fail('you already have a fare') end
    if not inTaxi(src) then return Civ.fail('get in a taxi first') end
    Civ.issue(src, {
        job = T.Job, kind = 'fare', phase = 'locate', range = T.PickupDistance, trip = T.TripDistance,
        model = T.PassengerModels[math.random(#T.PassengerModels)],
    })
end

function Taxi.actions.located(src, task, d)
    if task.kind ~= 'fare' or task.phase ~= 'locate' then return Civ.fail('not now') end
    local x, y, z = tonumber(d.x), tonumber(d.y), tonumber(d.z)
    local p = Civ.pos(src)
    if not x or not p then return Civ.fail('bad spot') end
    local dist = Civ.dist2d(p, { x = x, y = y })
    if dist < T.PickupDistance[1] * 0.5 or dist > T.PickupDistance[2] * 1.5 then return Civ.fail('bad spot') end
    task.pickup = { x = x, y = y, z = z }
    task.phase = 'pickup'
    Civ.update(src, task)
    tNotify(src, 'Fare waiting. Pickup on your GPS.')
end

-- The passenger got in; the client picked where they want to go.
function Taxi.actions.picked(src, task, d)
    if task.kind ~= 'fare' or task.phase ~= 'pickup' then return Civ.fail('not now') end
    if not inTaxi(src) then return Civ.fail('you need to be in the taxi') end
    if not Civ.near(src, task.pickup, 25.0) then return Civ.fail('pick them up first') end
    local x, y, z = tonumber(d.x), tonumber(d.y), tonumber(d.z)
    if not x then return Civ.fail('bad destination') end
    local dist = Civ.dist2d(task.pickup, { x = x, y = y })
    if dist < T.TripDistance[1] * 0.5 or dist > T.TripDistance[2] * 1.5 then return Civ.fail('bad destination') end
    task.dest = { x = x, y = y, z = z, label = type(d.label) == 'string' and d.label:sub(1, 60) or nil }
    task.phase = 'ride'
    task._pickedAt = os.time()
    task._dist = dist
    Civ.update(src, task)
end

function Taxi.actions.dropped(src, task)
    if task.kind ~= 'fare' or task.phase ~= 'ride' then return Civ.fail('not now') end
    if not inTaxi(src) then return Civ.fail('you need to be in the taxi') end
    if not Civ.near(src, task.dest, 30.0) then return Civ.fail('that\'s not where they asked to go') end
    if os.time() - task._pickedAt < math.floor(task._dist / 45) then return Civ.fail('slow down') end
    local fare = T.FareBase + T.FarePerKm * task._dist / 1000
    local tip = math.floor(fare * Civ.rand(T.TipPercent) / 100 + 0.5)
    Civ.clear(src)
    Civ.pay(src, fare + tip, ('Fare %.1f km%s'):format(task._dist / 1000, tip > 0 and (', $%d tip'):format(tip) or ''), T.Label)
end

function Taxi.actions.cancel(src, task)
    if task.kind ~= 'fare' then return Civ.fail('no fare') end
    Civ.clear(src, 'Fare cancelled.')
end
