-- Garbage and delivery routes (server). Both: clock in at the depot, take the work vehicle, start a
-- route from the depot menu, work the stops, bring the vehicle back for the route bonus.

local function pick(list, n)
    local pool, out = {}, {}
    for i = 1, #list do pool[i] = i end
    for _ = 1, math.min(n, #pool) do
        out[#out + 1] = table.remove(pool, math.random(#pool))
    end
    return out
end

local function depotDuty(cfg)
    return function(src)
        if not Civ.near(src, cfg.Depot, cfg.ClockInDistance) then
            return false, ('clock in at the %s depot'):format(cfg.Label)
        end
        return true
    end
end

-- Garbage --------------------------------------------------------------------------------------------
-- Route: ZonesPerRoute areas. In each, the client finds dumpsters nearby and sends their positions;
-- you grab a bag at each and throw it in the back of the truck.

local G = CivJobsConfig.Garbage
local Garbage = {
    name = G.Job, label = G.Label, actions = {}, requests = {},
    vehicle = { model = G.Vehicle, depot = G.Depot, spot = G.VehicleSpot, plate = 'LSSAN' },
    canGoOnDuty = depotDuty(G),
}
Civ.Jobs[G.Job] = Garbage

local function gNotify(src, text, kind) Civ.notify(src, text, kind, G.Label) end

local function zoneView(task)
    local z = G.Zones[task._zones[task.zoneIndex]]
    task.zone = { label = z.label, x = z.x, y = z.y, radius = G.ZoneRadius }
end

function Garbage.requests.route(src)
    if Civ.tasks[src] then return Civ.fail('finish your current route first') end
    if not Civ.vehicleOf(src) then return Civ.fail('take a garbage truck first') end
    local task = {
        job = G.Job, kind = 'garbage', phase = 'drive', zoneIndex = 1, zones = G.ZonesPerRoute,
        bags = 0, perZone = G.BagsPerZone, stops = false, carrying = false,
        _zones = pick(G.Zones, G.ZonesPerRoute), _stops = nil,
    }
    zoneView(task)
    Civ.issue(src, task)
    gNotify(src, ('Route started: head to %s and empty %d dumpsters.'):format(task.zone.label, G.BagsPerZone), 'success')
end

-- The client is in the zone and found dumpsters: { { x, y, z }, ... }
function Garbage.actions.stops(src, task, d)
    if task.kind ~= 'garbage' or task.phase ~= 'drive' then return Civ.fail('not now') end
    local z = task.zone
    if not Civ.near(src, z, G.ZoneRadius + 50.0) then return Civ.fail(('drive to %s first'):format(z.label)) end
    local stops = {}
    for _, s in ipairs(type(d.stops) == 'table' and d.stops or {}) do
        local x, y, zz = tonumber(s.x), tonumber(s.y), tonumber(s.z)
        if x and y and zz and Civ.dist2d({ x = x, y = y }, z) <= G.ZoneRadius + 100.0 then
            stops[#stops + 1] = { x = x, y = y, z = zz, done = false }
        end
        if #stops >= G.BagsPerZone then break end
    end
    if #stops == 0 then return Civ.fail('no dumpsters found here') end
    task.stops, task.phase, task.left = stops, 'collect', #stops
    Civ.update(src, task)
end

function Garbage.actions.grab(src, task, d)
    if task.kind ~= 'garbage' or task.phase ~= 'collect' then return Civ.fail('not now') end
    if task.carrying then return Civ.fail('throw the bag you have in the truck first') end
    local i = math.tointeger(tonumber(d.stop))
    local stop = i and task.stops[i]
    if not stop or stop.done then return Civ.fail('that one is done') end
    if not Civ.near(src, stop, 4.0) then return Civ.fail('get closer to the dumpster') end
    task.carrying = i
    Civ.update(src, task)
end

function Garbage.actions.toss(src, task)
    if task.kind ~= 'garbage' or not task.carrying then return Civ.fail('grab a bag first') end
    if not Civ.vehicleNear(src, 7.0) then return Civ.fail('throw it in the back of your truck') end
    local now = os.time()
    if task._lastBag and now - task._lastBag < 4 then return Civ.fail('slow down') end
    task._lastBag = now
    task.stops[task.carrying].done = true
    task.carrying = false
    task.bags = task.bags + 1
    task.left = task.left - 1
    Civ.pay(src, G.PayPerBag, ('Garbage bag (%s)'):format(task.zone.label), G.Label)

    if task.left <= 0 then
        if task.zoneIndex < #task._zones then
            task.zoneIndex = task.zoneIndex + 1
            task.phase, task.stops = 'drive', false
            zoneView(task)
            gNotify(src, ('%s is clean. Next: %s.'):format(G.Zones[task._zones[task.zoneIndex - 1]].label, task.zone.label), 'success')
        else
            task.phase, task.stops, task.zone = 'return', false, false
            task.depot = { x = G.Depot.x, y = G.Depot.y, z = G.Depot.z }
            gNotify(src, 'Route done. Take the truck back to the depot for your route bonus.', 'success')
        end
    end
    Civ.update(src, task)
end

function Garbage.actions.finish(src, task)
    if task.kind ~= 'garbage' or task.phase ~= 'return' then return Civ.fail('the route isn\'t done yet') end
    if not Civ.near(src, G.Depot, 40.0) or not Civ.vehicleNear(src, 25.0) then return Civ.fail('bring the truck back to the depot') end
    Civ.clear(src)
    Civ.pay(src, G.RouteBonus, 'Garbage route finished', G.Label)
end

-- Delivery -------------------------------------------------------------------------------------------
-- Route: StopsPerRoute stores. At each, take a package from the back of the van to the counter.

local D = CivJobsConfig.Delivery
local Delivery = {
    name = D.Job, label = D.Label, actions = {}, requests = {},
    vehicle = { model = D.Vehicle, depot = D.Depot, spot = D.VehicleSpot, plate = 'GOPOST' },
    canGoOnDuty = depotDuty(D),
}
Civ.Jobs[D.Job] = Delivery

local function dNotify(src, text, kind) Civ.notify(src, text, kind, D.Label) end

local function destinations()
    local list = {}
    local ok, shops = pcall(function() return exports['tfc-shops']:GetShops() end)
    for _, s in ipairs(ok and shops or {}) do
        if D.DeliverTo[s.type] then list[#list + 1] = { x = s.x, y = s.y, z = s.z, label = s.label } end
    end
    return list
end

function Delivery.requests.route(src)
    if Civ.tasks[src] then return Civ.fail('finish your current route first') end
    if not Civ.vehicleOf(src) then return Civ.fail('take a van first') end
    local all = destinations()
    if #all == 0 then return Civ.fail('no stores to deliver to') end
    local stops = {}
    for _, i in ipairs(pick(all, D.StopsPerRoute)) do stops[#stops + 1] = all[i] end
    Civ.issue(src, { job = D.Job, kind = 'delivery', phase = 'deliver', stops = stops, stop = 1, carrying = false })
    dNotify(src, ('Route started: %d packages. First stop: %s.'):format(#stops, stops[1].label), 'success')
end

function Delivery.actions.grab(src, task)
    if task.kind ~= 'delivery' or task.phase ~= 'deliver' then return Civ.fail('not now') end
    if task.carrying then return Civ.fail('you already have a package') end
    if not Civ.vehicleNear(src, 7.0) then return Civ.fail('packages are in the back of your van') end
    local stop = task.stops[task.stop]
    if not Civ.near(src, stop, 80.0) then return Civ.fail(('drive to %s first'):format(stop.label)) end
    task.carrying = true
    Civ.update(src, task)
end

function Delivery.actions.deliver(src, task)
    if task.kind ~= 'delivery' or not task.carrying then return Civ.fail('get the package from the van') end
    local stop = task.stops[task.stop]
    if not Civ.near(src, stop, 4.0) then return Civ.fail('take it to the counter') end
    task.carrying = false
    Civ.pay(src, D.PayPerPackage, ('Package delivered to %s'):format(stop.label), D.Label)
    if task.stop < #task.stops then
        task.stop = task.stop + 1
        dNotify(src, ('Next stop: %s.'):format(task.stops[task.stop].label))
    else
        task.phase = 'return'
        task.depot = { x = D.Depot.x, y = D.Depot.y, z = D.Depot.z }
        dNotify(src, 'All delivered. Take the van back to the depot for your route bonus.', 'success')
    end
    Civ.update(src, task)
end

function Delivery.actions.finish(src, task)
    if task.kind ~= 'delivery' or task.phase ~= 'return' then return Civ.fail('the route isn\'t done yet') end
    if not Civ.near(src, D.Depot, 40.0) or not Civ.vehicleNear(src, 25.0) then return Civ.fail('bring the van back to the depot') end
    Civ.clear(src)
    Civ.pay(src, D.RouteBonus, 'Delivery route finished', D.Label)
end
