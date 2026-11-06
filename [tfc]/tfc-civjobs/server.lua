-- Civilian jobs server. Clerk: where each on-duty clerk works, the clock-in rule, auto clock-out.
--
-- Exports (server):
--   CanGoOnDuty(src, job) -> ok, err      called by tfc-jobs before anyone in a `dutyCheck` job clocks in
--   GetWorkplace(src) -> { type = 'store', id, label, x, y, z } | nil
-- Player state: 'tfc:workplace' = the same table (or nil) while on duty.

local C = CivJobsConfig.Clerk

local workplace = {}   -- src -> store view
local pending = {}     -- src -> store chosen by CanGoOnDuty, used when duty actually changes
local awaySince = {}   -- src -> os.time() they left the store

local function jobs() return exports['tfc-jobs'] end

local function isOwned(shopId)
    if GetResourceState('tfc-business') ~= 'started' then return false end
    local ok, b = pcall(function() return exports['tfc-business']:GetBusinessByShop(shopId) end)
    return ok and type(b) == 'table' and b.ownerCid ~= nil
end

---Stores a clerk can work at right now (not privately owned).
local function stores()
    local list = {}
    local ok, shops = pcall(function() return exports['tfc-shops']:GetShops() end)
    for _, s in ipairs(ok and shops or {}) do
        if C.ShopTypes[s.type] and not isOwned(s.id) then
            list[#list + 1] = { type = 'store', id = s.id, label = s.label, x = s.x, y = s.y, z = s.z }
        end
    end
    return list
end

local function distTo(src, s)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return math.huge end
    local p = GetEntityCoords(ped)
    return #(vector3(p.x, p.y, p.z) - vector3(s.x, s.y, s.z))
end

local function nearestStore(src)
    local best, bestD = nil, math.huge
    for _, s in ipairs(stores()) do
        local d = distTo(src, s)
        if d < bestD then best, bestD = s, d end
    end
    return best, bestD
end

local function notify(src, text, kind)
    TFC.UI.Notify(src, { title = 'Store clerk', description = text, type = kind or 'inform' })
end

local function setWorkplace(src, s)
    workplace[src], awaySince[src] = s, nil
    Player(src).state:set('tfc:workplace', s, true)
end

exports('CanGoOnDuty', function(src, job)
    if job ~= C.Job then return true end
    local s, d = nearestStore(src)
    if not s or d > C.ClockInDistance then
        return false, 'clock in at the counter of a 24/7 store that isn\'t privately owned'
    end
    pending[src] = s
    return true
end)

exports('GetWorkplace', function(src) return workplace[src] end)

TFC.On('dutyChanged', function(src, onDuty, job)
    if onDuty and job and job.name == C.Job and pending[src] then
        setWorkplace(src, pending[src])
        notify(src, ('Clocked in at %s. Stay near the store to keep your shift.'):format(pending[src].label), 'success')
    elseif not onDuty and workplace[src] then
        setWorkplace(src, nil)
    end
    pending[src] = nil
end)

TFC.On('jobChanged', function(src)
    if workplace[src] then setWorkplace(src, nil) end
end)

TFC.On('playerUnloaded', function(src)
    workplace[src], pending[src], awaySince[src] = nil, nil, nil
end)

-- F6 > Clock in / out
TFC.Callback.Register('civjobs:clock', function(src)
    local job = jobs():GetJob(src)
    if not job or job.name ~= C.Job then return { ok = false, error = 'you are not a store clerk' } end
    local ok, err = jobs():SetDuty(src, not job.onDuty)
    if not ok then return { ok = false, error = err } end
    return { ok = true, onDuty = not job.onDuty }
end, { rateLimit = 1000 })

-- Where clerks can work (for the client's "clock in here" hint).
TFC.Callback.Register('civjobs:stores', function()
    return stores()
end, { rateLimit = 2000 })

-- Clock out clerks who walked off, or whose store got bought.
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for src, s in pairs(workplace) do
            local gone = GetPlayerPed(src) == 0
            if not gone then
                if isOwned(s.id) then
                    jobs():SetDuty(src, false)
                    notify(src, ('%s is now privately owned. You were clocked out.'):format(s.label), 'error')
                elseif distTo(src, s) > C.LeaveDistance then
                    awaySince[src] = awaySince[src] or now
                    if now - awaySince[src] >= C.LeaveGraceSeconds then
                        jobs():SetDuty(src, false)
                        notify(src, ('You left %s and were clocked out.'):format(s.label), 'error')
                    elseif now - awaySince[src] < 5 then
                        notify(src, ('Head back to %s or you\'ll be clocked out in %d s.'):format(s.label, C.LeaveGraceSeconds), 'warning')
                    end
                else
                    awaySince[src] = nil
                end
            end
        end
    end
end)

CreateThread(function()
    TFC.RegisterModule({ name = 'civjobs', version = '0.1.0' }, function()
        TFC.Log.Info('civjobs ready: clerks can work at %d store(s)', #stores())
    end)
end)
