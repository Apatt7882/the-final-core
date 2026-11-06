-- Civilian jobs server: the shared parts. Each job (server/*.lua) registers itself in Civ.Jobs.
--
-- A player has at most one task at a time (Civ.tasks[src]). The client shows it and asks to do
-- things with it ('civjobs:act'); the job checks the player is really where they should be (and has
-- taken long enough) before paying anything. Bonuses go to the bank with tfc-accounts.
--
-- Exports (server):
--   CanGoOnDuty(src, job) -> ok, err      tfc-jobs asks before anyone in a `dutyCheck` job clocks in
--   GetWorkplace(src) -> { type = 'store', id, label, x, y, z } | nil   (clerks)
--   GetTask(src) -> the player's current task view | nil

Civ = { Jobs = {}, tasks = {}, vehicles = {} }

local nextId = 0

-- Helpers ------------------------------------------------------------------------------------------

function Civ.jobs() return exports['tfc-jobs'] end

---The player's job if they're on duty in it (or nil).
function Civ.working(src, jobName)
    if GetResourceState('tfc-jobs') ~= 'started' then return nil end
    local job = Civ.jobs():GetJob(src)
    if not job or job.onDuty ~= true then return nil end
    if jobName and job.name ~= jobName then return nil end
    return job
end

function Civ.pos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function Civ.dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

---Is the player within `r` metres (2D) of `c`?
function Civ.near(src, c, r)
    local p = Civ.pos(src)
    return p ~= nil and Civ.dist2d(p, c) <= r
end

function Civ.notify(src, text, kind, title)
    TFC.UI.Notify(src, { title = title or 'Work', description = text, type = kind or 'inform' })
end

function Civ.fail(err) return { ok = false, error = err } end

function Civ.rand(range) return math.random(range[1], range[2]) end

---Pay a task bonus into the bank.
function Civ.pay(src, amount, reason, title)
    amount = math.floor(amount + 0.5)
    if amount <= 0 then return false end
    if GetResourceState('tfc-accounts') ~= 'started' then return false end
    local ok = exports['tfc-accounts']:AddMoney(src, 'bank', amount, reason)
    if ok then Civ.notify(src, ('+$%d · %s'):format(amount, reason), 'success', title) end
    return ok
end

---A point `forward`/`right` metres from (x, y) facing `heading` (GTA headings: 0 = north, counter-clockwise).
function Civ.offset(x, y, z, heading, forward, right)
    local h = math.rad(heading)
    local fx, fy = -math.sin(h), math.cos(h)
    local rx, ry = math.cos(h), math.sin(h)
    return { x = x + fx * forward + rx * right, y = y + fy * forward + ry * right, z = z }
end

-- Tasks ------------------------------------------------------------------------------------------------

---What the client gets: everything except fields starting with "_".
local function view(task)
    local out = {}
    for k, v in pairs(task) do
        if type(k) ~= 'string' or k:sub(1, 1) ~= '_' then out[k] = v end
    end
    return out
end

function Civ.issue(src, task)
    nextId = nextId + 1
    task.id = nextId
    task.issued = os.time()
    Civ.tasks[src] = task
    TriggerClientEvent('tfc-civjobs:client:task', src, view(task))
    return task
end

---Send the task again after changing it.
function Civ.update(src, task)
    if Civ.tasks[src] ~= task then return end
    TriggerClientEvent('tfc-civjobs:client:task', src, view(task))
end

function Civ.clear(src, text, kind)
    if not Civ.tasks[src] then return end
    Civ.tasks[src] = nil
    TriggerClientEvent('tfc-civjobs:client:task', src, false)
    if text then Civ.notify(src, text, kind) end
end

exports('GetTask', function(src) local t = Civ.tasks[src] return t and view(t) or nil end)

TFC.Callback.Register('civjobs:act', function(src, taskId, action, data)
    local task = Civ.tasks[src]
    if not task or task.id ~= taskId then return Civ.fail('that job is over') end
    local job = Civ.Jobs[task.job]
    local fn = job and job.actions and job.actions[action]
    if type(fn) ~= 'function' then return Civ.fail('unknown action') end
    if not Civ.working(src, job.name) then return Civ.fail('you are not on duty') end
    local r = fn(src, task, type(data) == 'table' and data or {})
    return r or { ok = true }
end, { rateLimit = 400 })

-- Requests not tied to a task: start a route, find a fare...
TFC.Callback.Register('civjobs:request', function(src, jobName, what, data)
    local job = Civ.Jobs[jobName]
    local fn = job and job.requests and job.requests[what]
    if type(fn) ~= 'function' then return Civ.fail('unknown request') end
    if not Civ.working(src, job.name) then return Civ.fail('clock in first') end
    return fn(src, type(data) == 'table' and data or {}) or { ok = true }
end, { rateLimit = 800 })

-- Give up the current task (route, call, fare). Customers and restocks can't be skipped.
TFC.Callback.Register('civjobs:cancel', function(src)
    local task = Civ.tasks[src]
    if not task then return Civ.fail('you have nothing to cancel') end
    if task.job == CivJobsConfig.Clerk.Job then return Civ.fail('the store needs you; finish it') end
    Civ.clear(src, 'Task cancelled. No bonus for this one.')
    local job = Civ.Jobs[task.job]
    if job and job.cancelled then job.cancelled(src) end
    return { ok = true }
end, { rateLimit = 1000 })

-- Clock in / out at a depot (the depot menu).
TFC.Callback.Register('civjobs:duty', function(src, jobName, on)
    local job = Civ.Jobs[jobName]
    if not job then return Civ.fail('unknown job') end
    local mine = Civ.jobs():GetJob(src)
    if not mine or mine.name ~= jobName then return Civ.fail(('you don\'t work for %s'):format(job.label or jobName)) end
    local ok, err = Civ.jobs():SetDuty(src, on == true)
    if not ok then return Civ.fail(err) end
    return { ok = true, onDuty = on == true }
end, { rateLimit = 800 })

-- Work vehicles --------------------------------------------------------------------------------------
-- The client spawns the vehicle (on the nearest road) after the server says yes, then registers it.

function Civ.vehicleOf(src)
    local v = Civ.vehicles[src]
    if not v then return nil end
    local ent = NetworkGetEntityFromNetworkId(v.netId)
    if ent == 0 or not DoesEntityExist(ent) then
        Civ.vehicles[src] = nil
        return nil
    end
    return ent, v
end

---Is the player's work vehicle within `r` metres of them?
function Civ.vehicleNear(src, r)
    local ent = Civ.vehicleOf(src)
    local p = Civ.pos(src)
    if not ent or not p then return false end
    return Civ.dist2d(GetEntityCoords(ent), p) <= r
end

function Civ.deleteVehicle(src)
    local ent = Civ.vehicleOf(src)
    if ent then DeleteEntity(ent) end
    Civ.vehicles[src] = nil
end

TFC.Callback.Register('civjobs:vehicle', function(src, jobName, action, netId)
    local job = Civ.Jobs[jobName]
    if not job or not job.vehicle then return Civ.fail('this job has no vehicle') end
    if not Civ.working(src, job.name) then return Civ.fail('clock in first') end
    local spot = job.vehicle.depot

    if action == 'request' then
        if not Civ.near(src, spot, 40.0) then return Civ.fail('get the vehicle at the depot') end
        Civ.deleteVehicle(src)
        Civ.vehicles[src] = { pending = true, job = jobName }
        return { ok = true, model = job.vehicle.model, spot = job.vehicle.spot, plate = job.vehicle.plate }

    elseif action == 'spawned' then
        local v = Civ.vehicles[src]
        if not v or not v.pending then return Civ.fail('no vehicle was requested') end
        local ent = NetworkGetEntityFromNetworkId(math.tointeger(tonumber(netId)) or 0)
        if ent == 0 or not DoesEntityExist(ent) or GetEntityModel(ent) ~= joaat(job.vehicle.model) then
            Civ.vehicles[src] = nil
            return Civ.fail('that is not the work vehicle')
        end
        Civ.vehicles[src] = { netId = netId, job = jobName }
        return { ok = true }

    elseif action == 'return' then
        local ent = Civ.vehicleOf(src)
        if not ent then return Civ.fail('you have no work vehicle out') end
        if not Civ.near(src, spot, 40.0) or Civ.dist2d(GetEntityCoords(ent), spot) > 50.0 then
            return Civ.fail('bring the vehicle back to the depot first')
        end
        Civ.deleteVehicle(src)
        return { ok = true }
    end
    return Civ.fail('unknown action')
end, { rateLimit = 800 })

-- Duty and lifecycle --------------------------------------------------------------------------------------

exports('CanGoOnDuty', function(src, jobName)
    for _, job in pairs(Civ.Jobs) do
        if job.name == jobName and job.canGoOnDuty then return job.canGoOnDuty(src) end
    end
    return true
end)

local function stopWork(src)
    Civ.clear(src)
    Civ.deleteVehicle(src)
    for _, job in pairs(Civ.Jobs) do
        if job.stop then job.stop(src) end
    end
end

TFC.On('dutyChanged', function(src, onDuty, job)
    for _, j in pairs(Civ.Jobs) do
        if j.dutyChanged then j.dutyChanged(src, onDuty, job) end
    end
    if not onDuty then stopWork(src) end
end)

TFC.On('jobChanged', function(src)
    stopWork(src)
end)

TFC.On('playerUnloaded', function(src)
    stopWork(src)
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then stopWork(src) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(Civ.vehicles) do Civ.deleteVehicle(src) end
end)

-- Tells each job module to start its loops once everything is loaded (see server/start.lua).
function Civ.start()
    for _, job in pairs(Civ.Jobs) do
        if job.start then CreateThread(job.start) end
    end
    local names = {}
    for key in pairs(Civ.Jobs) do names[#names + 1] = key end
    table.sort(names)
    TFC.RegisterModule({ name = 'civjobs', version = '0.2.0' }, function()
        TFC.Log.Info('civjobs ready: %s', table.concat(names, ', '))
    end)
end
