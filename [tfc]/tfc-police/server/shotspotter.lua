-- ShotSpotter (server). Clients report their own gunfire; after DelaySeconds every on-duty officer
-- gets an alert: a circle near the shots for DurationSeconds, semi or fully automatic, and with
-- CameraChance a short description of the shooter. Shots close together become one alert.

local Cfg = PoliceConfig.ShotSpotter
if not Cfg or not Cfg.Enabled then return end

local incidents = {}   -- open incidents still collecting shots
local nextId = 0

local function isOfficer(src)
    if GetResourceState('tfc-jobs') ~= 'started' then return false end
    local job = exports['tfc-jobs']:GetJob(src)
    if not job or job.onDuty ~= true then return false end
    for _, j in ipairs(PoliceConfig.Jobs) do if job.name == j then return true end end
    return false
end

local function officers()
    local list, seen = {}, {}
    for _, job in ipairs(PoliceConfig.Jobs) do
        for _, src in ipairs(exports['tfc-jobs']:GetPlayersWithJob(job, true) or {}) do
            if not seen[src] then seen[src] = true list[#list + 1] = src end
        end
    end
    return list
end

local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function ignored(pos)
    for _, z in ipairs(Cfg.IgnoreZones or {}) do
        if dist2d(pos, z.coords) <= z.radius then return true end
    end
    return false
end

---Plain-words description from what the shooter's game reported.
local function describe(d)
    if type(d) ~= 'table' then return nil end
    local who = d.male == true and 'Male' or d.male == false and 'Female' or 'Person'
    local wearing = {}
    if d.mask then wearing[#wearing + 1] = 'a mask' end
    if d.hat then wearing[#wearing + 1] = 'a hat or helmet' end
    if d.glasses then wearing[#wearing + 1] = 'glasses' end
    if d.bag then wearing[#wearing + 1] = 'a bag' end
    if d.shirtless then wearing[#wearing + 1] = 'no shirt' end
    local text = who
    if #wearing > 0 then
        local last = table.remove(wearing)
        text = text .. ', wearing ' .. (#wearing > 0 and (table.concat(wearing, ', ') .. ' and ' .. last) or last)
    end
    if type(d.vehicle) == 'string' and d.vehicle ~= '' then
        text = text .. ', in a ' .. ((type(d.color) == 'string' and d.color ~= '') and (d.color .. ' ') or '') .. d.vehicle
    else
        text = text .. ', on foot'
    end
    return (text:gsub('[<>]', ''))
end

local function send(inc)
    incidents[inc.id] = nil
    local angle, r = math.random() * math.pi * 2, math.random() * Cfg.Offset
    local alert = {
        id = inc.id,
        x = inc.pos.x + math.cos(angle) * r, y = inc.pos.y + math.sin(angle) * r, z = inc.pos.z,
        radius = Cfg.Radius, duration = Cfg.DurationSeconds,
        auto = inc.auto, shots = inc.reports, camera = inc.camera,
    }
    local list = officers()
    for _, src in ipairs(list) do TriggerClientEvent('tfc-police:client:shotspotter', src, alert) end
    TFC.Log.Info('[shotspotter] #%d %s near %.0f, %.0f sent to %d officer(s)%s', inc.id, inc.auto and 'full auto' or 'semi auto',
        inc.pos.x, inc.pos.y, #list, inc.camera and (' | camera: ' .. inc.camera) or '')
end

TFC.OnNet('tfc-police:server:shots', function(src, data)
    if type(data) ~= 'table' then return end
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if not x or not y or not z or not TFC.GetPlayer(src) then return end
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    -- The report must be where the player actually is.
    local here = GetEntityCoords(ped)
    local pos = vector3(x, y, z)
    if dist2d(here, pos) > 60.0 then return end
    if ignored(pos) then return end
    if Cfg.IgnoreOnDutyPolice and isOfficer(src) then return end

    local now = os.time()
    for _, inc in pairs(incidents) do
        if now - inc.started <= Cfg.MergeSeconds and dist2d(inc.pos, pos) <= Cfg.MergeDistance then
            inc.reports = inc.reports + 1
            inc.auto = inc.auto or data.auto == true
            if not inc.camera and inc.rollCamera then inc.camera = describe(data.look) end
            return
        end
    end

    nextId = nextId + 1
    local inc = {
        id = nextId, pos = pos, started = now, reports = 1, auto = data.auto == true,
        rollCamera = math.random() < Cfg.CameraChance,
    }
    if inc.rollCamera then inc.camera = describe(data.look) end
    incidents[inc.id] = inc
    SetTimeout(Cfg.DelaySeconds * 1000, function() send(inc) end)
end, { rateLimit = 3000 })
