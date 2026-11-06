-- Government Center: city info, public job board, ID cards, and the callbacks for the
-- Government Center, DMV and police license screens.

local Cfg = GovConfig
local fail, notify = GovSrv.fail, GovSrv.notify

local function int(v) return math.tointeger(tonumber(v)) end

-- Job board --------------------------------------------------------------------------------------

local function publicJobs(src)
    local list = {}
    local current = exports['tfc-jobs']:GetJob(src)
    for name, job in pairs(exports['tfc-jobs']:GetJobs() or {}) do
        if job.public then
            local g0 = job.grades and (job.grades[0] or job.grades['0'])
            local top = 0
            for g in pairs(job.grades or {}) do
                local n = int(g)
                if n and n > top then top = n end
            end
            list[#list + 1] = {
                name = name, label = job.label, description = job.description or '',
                startRank = g0 and g0.label or 'Employee', startPay = g0 and g0.pay or 0,
                ranks = top + 1, noDuty = job.noDuty == true,
                current = current and current.name == name or false,
            }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list, current
end

local function cityData(src)
    local jobs, current = publicJobs(src)
    local places = {}
    for _, p in ipairs(Cfg.Info.places) do
        places[#places + 1] = { id = p.id or false, label = p.label, x = p.coords.x, y = p.coords.y }
    end
    local recs = GovSrv.records(src)
    local licenses = {}
    for _, l in ipairs(Cfg.Licenses) do
        local r = recs[l.id]
        licenses[#licenses + 1] = { id = l.id, label = l.label, status = r and r.status or 'none', price = l.price, quiz = l.quiz ~= nil, description = l.description }
    end
    return {
        ok = true,
        info = { title = Cfg.Info.title, intro = Cfg.Info.intro, steps = Cfg.Info.steps, faq = Cfg.Info.faq, rules = Cfg.Info.rules },
        places = places,
        jobs = jobs,
        currentJob = current and { name = current.name, label = current.label, grade = current.gradeLabel or false } or false,
        licenses = licenses,
        idCardFee = Cfg.IdCardFee,
        hasIdCard = (#(exports['tfc-inventory']:Search(src, 'id_card') or {})) > 0,
        accountant = GetResourceState('tfc-finance') == 'started',
    }
end

local CityActions = {}

function CityActions.apply(src, d)
    local jobs = exports['tfc-jobs']:GetJobs() or {}
    local job = type(d.job) == 'string' and jobs[d.job]
    if not job or not job.public then return fail('you can\'t sign up for that job here') end
    local current = exports['tfc-jobs']:GetJob(src)
    if current and current.name == d.job then return fail('you already work there') end
    local ok, err = exports['tfc-jobs']:SetJob(src, d.job, 0)
    if not ok then return fail(err) end
    TFC.Log.Info('%s signed up as %s at the Government Center', TFC.GetPlayer(src):GetFullName(), job.label)
    return { ok = true, message = ('Welcome to %s! Go on duty with /duty to start earning.'):format(job.label) }
end

function CityActions.quit(src)
    local current = exports['tfc-jobs']:GetJob(src)
    if not current or current.name == 'unemployed' then return fail('you don\'t have a job') end
    local ok, err = exports['tfc-jobs']:SetJob(src, 'unemployed', 0)
    if not ok then return fail(err) end
    return { ok = true, message = ('You left %s.'):format(current.label) }
end

function CityActions.idcard(src)
    local p = TFC.GetPlayer(src)
    if (#(exports['tfc-inventory']:Search(src, 'id_card') or {})) > 0 then return fail('you already have an ID card') end
    if not GovSrv.pay(src, Cfg.IdCardFee, 'Government Center: ID card') then return fail(('you need $%d'):format(Cfg.IdCardFee)) end
    local meta = { name = p:GetFullName(), cid = p.cid }
    local dob = p:GetDob()
    if dob then meta.dob = dob end
    exports['tfc-inventory']:AddItem(src, 'id_card', 1, meta, nil, 'ID card issued')
    return { ok = true, message = 'Here is your new ID card.' }
end

-- Callbacks ---------------------------------------------------------------------------------------

TFC.Callback.Register('gov:open', function(src, place)
    if not TFC.GetPlayer(src) then return fail('no character loaded') end
    if place == 'cityhall' then
        if not GovSrv.near(src, Cfg.CityHall) then return fail('you are too far away') end
        local d = cityData(src)
        d.view = 'cityhall'
        return d
    elseif place == 'dmv' then
        if not GovSrv.near(src, Cfg.Dmv) then return fail('you are too far away') end
        local d = GovSrv.dmvData(src)
        d.view = 'dmv'
        return d
    end
    return fail('unknown')
end, { rateLimit = 500 })

TFC.Callback.Register('gov:city', function(src, action, d)
    if not GovSrv.near(src, Cfg.CityHall) then return fail('you walked away from the desk') end
    local fn = type(action) == 'string' and CityActions[action]
    if not fn then return fail('unknown action') end
    local r = fn(src, type(d) == 'table' and d or {})
    local data = cityData(src)
    data.view, data.ok, data.error, data.message = 'cityhall', r.ok, r.error, r.message
    return data
end, { rateLimit = 300 })

TFC.Callback.Register('gov:dmv', function(src, action, d)
    if not GovSrv.near(src, Cfg.Dmv) then return fail('you walked away from the counter') end
    local fn = type(action) == 'string' and GovSrv.DmvActions[action]
    if not fn then return fail('unknown action') end
    local r = fn(src, type(d) == 'table' and d or {})
    -- Quiz questions / results go back as they are; everything else returns fresh DMV data.
    if action == 'quiz' or action == 'submit' then return r end
    local data = GovSrv.dmvData(src)
    data.view, data.ok, data.error, data.message = 'dmv', r.ok, r.error, r.message
    return data
end, { rateLimit = 300 })

TFC.Callback.Register('gov:police', function(src, action, a, b, c)
    local r
    if action == 'view' then r = GovSrv.policeView(src, a)
    elseif action == 'set' then r = GovSrv.policeSet(src, a, b, c and c.action, c and c.reason)
    elseif action == 'requests' then r = GovSrv.requests(src)
    elseif action == 'decide' then r = GovSrv.decide(src, a, b == true)
    else r = fail('unknown action') end
    return r
end, { rateLimit = 300 })

-- Commands -----------------------------------------------------------------------------------------

local function closest(src, range)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local here = GetEntityCoords(ped)
    local best, bestDist = nil, range
    for _, other in ipairs(TFC.GetPlayers()) do
        if other ~= src then
            local op = GetPlayerPed(other)
            if op and op ~= 0 then
                local c = GetEntityCoords(op)
                local dx, dy, dz = c.x - here.x, c.y - here.y, c.z - here.z
                local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                if d < bestDist then best, bestDist = other, d end
            end
        end
    end
    return best
end

TFC.RegisterCommand(Cfg.Command, {
    help = 'Police: check, suspend or revoke a player\'s licenses',
    params = { { name = 'id', help = 'Player ID (default: closest player)', optional = true } },
}, function(src, args)
    if src == 0 then return end
    local target = args[1] and TFC.ResolveTarget(src, args[1]) or closest(src, Cfg.PoliceDistance)
    if not target then return notify(src, 'Nobody close enough.', 'error') end
    local r = GovSrv.policeView(src, target)
    if not r.ok then return notify(src, r.error, 'error') end
    TriggerClientEvent('tfc-government:client:police', src, r)
end)

TFC.RegisterCommand(Cfg.RequestsCommand, { help = 'Police supervisors: license reinstatement requests' }, function(src)
    if src == 0 then return end
    local r = GovSrv.requests(src)
    if not r.ok then return notify(src, r.error, 'error') end
    TriggerClientEvent('tfc-government:client:requests', src, r)
end)

-- Start ------------------------------------------------------------------------------------------------

CreateThread(function()
    while not exports['tfc-core']:IsDatabaseReady() do Wait(250) end
    GovSrv.createTables()
    TFC.RegisterModule({ name = 'government', version = '0.1.0' }, function()
        TFC.Log.Info('government ready: %d licenses', #Cfg.Licenses)
    end)
end)
