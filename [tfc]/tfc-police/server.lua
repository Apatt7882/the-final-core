-- Police server: every police action is decided here.
--
-- State bags (public): 'tfc:cuffed' = true, 'tfc:escortedBy' = officer's server ID, 'tfc:jailed' = true
-- Exports (server): IsCuffed(src), IsJailed(src), Jail(src, minutes, reason?), Release(src)
-- Server hooks: playerCuffed(source, officer, cuffed), playerFined(source, officer, amount, reason),
--               playerJailed(source, officer, minutes, reason), playerReleased(source)

local Cfg = PoliceConfig

---@type table<integer, integer> suspect -> officer escorting them
local escorts = {}
---@type table<integer, integer> source -> os.time() their sentence ends
local jailed = {}

local SCHEMA = [[
    CREATE TABLE IF NOT EXISTS `tfc_police_records` (
        `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `type`         VARCHAR(16)  NOT NULL,
        `target_cid`   VARCHAR(16)  NOT NULL,
        `target_name`  VARCHAR(64)  NOT NULL,
        `officer_cid`  VARCHAR(16)  NULL,
        `officer_name` VARCHAR(64)  NULL,
        `amount`       INT          NULL,
        `minutes`      INT          NULL,
        `reason`       VARCHAR(128) NOT NULL DEFAULT '',
        `created_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_police_records_target` (`target_cid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]]

-- Helpers ------------------------------------------------------------------------------------

local function notify(src, text, kind)
    TFC.UI.Notify(src, { title = 'Police', description = text, type = kind or 'inform' })
end

local function fail(err) return { ok = false, error = err } end

local function coords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function name(src)
    local p = TFC.GetPlayer(src)
    return p and p:GetFullName() or GetPlayerName(src) or tostring(src)
end

local function isOfficer(src)
    local job = exports['tfc-jobs']:GetJob(src)
    if not job or not job.onDuty then return false end
    for _, j in ipairs(Cfg.Jobs) do
        if job.name == j then return true end
    end
    return false
end

local function state(src) return Player(src).state end
local function isCuffed(src) return state(src)['tfc:cuffed'] == true end
local function isDown(src) return state(src)['tfc:down'] == true end

local function cleanReason(r)
    if type(r) ~= 'string' then return '' end
    return r:gsub('<[^>]*>', ''):gsub('[%c<>]', ''):match('^%s*(.-)%s*$'):sub(1, 120)
end

---Common checks for an officer acting on a suspect.
---@return integer|nil target, string|nil err
local function check(src, target, range)
    target = math.tointeger(tonumber(target))
    if not isOfficer(src) then return nil, 'you need to be police on duty' end
    if not target or target == src or not TFC.GetPlayer(target) then return nil, 'nobody there' end
    if dist(coords(src), coords(target)) > range + 1.0 then return nil, 'they are too far away' end
    return target
end

-- Escort -------------------------------------------------------------------------------------

local function stopEscort(target)
    if not escorts[target] then return end
    escorts[target] = nil
    state(target):set('tfc:escortedBy', nil, true)
end

-- Cuffs --------------------------------------------------------------------------------------

local function setCuffed(target, value, officer)
    state(target):set('tfc:cuffed', value or nil, true)
    if not value then stopEscort(target) end
    if value and GetResourceState('tfc-inventory') == 'started' then exports['tfc-inventory']:ForceClose(target) end
    TFC.Emit('playerCuffed', target, officer or 0, value == true)
end

local Actions = {}

function Actions.cuff(src, target)
    local t, err = check(src, target, Cfg.CuffDistance)
    if not t then return fail(err) end
    if jailed[t] then return fail('they are in jail') end
    if isCuffed(t) then
        setCuffed(t, false, src)
        notify(t, 'You were uncuffed.')
        return { ok = true, message = ('Uncuffed %s'):format(name(t)), cuffed = false }
    end
    setCuffed(t, true, src)
    TriggerClientEvent('tfc-police:client:cuffedAnim', t)
    notify(t, 'You were handcuffed.', 'warning')
    TFC.Log.Info('%s cuffed %s', name(src), name(t))
    return { ok = true, message = ('Cuffed %s'):format(name(t)), cuffed = true }
end

function Actions.escort(src, target)
    local t, err = check(src, target, Cfg.ActionDistance)
    if not t then return fail(err) end
    if escorts[t] then
        stopEscort(t)
        return { ok = true, message = ('Let go of %s'):format(name(t)) }
    end
    if not isCuffed(t) and not isDown(t) then return fail('they need to be cuffed or down') end
    if GetVehiclePedIsIn(GetPlayerPed(t), false) ~= 0 then return fail('take them out of the vehicle first') end
    -- One officer escorts one person at a time.
    for suspect, officer in pairs(escorts) do
        if officer == src then stopEscort(suspect) end
    end
    escorts[t] = src
    state(t):set('tfc:escortedBy', src, true)
    return { ok = true, message = ('Escorting %s'):format(name(t)) }
end

local function closestVehicle(src)
    local here = coords(src)
    local best, bestDist = nil, Cfg.VehicleDistance
    for _, veh in ipairs(GetAllVehicles()) do
        local d = dist(here, GetEntityCoords(veh))
        if d < bestDist then best, bestDist = veh, d end
    end
    return best
end

function Actions.seat(src, target)
    local t, err = check(src, target, Cfg.VehicleDistance)
    if not t then return fail(err) end
    if not isCuffed(t) and not isDown(t) then return fail('they need to be cuffed or down') end
    local veh = closestVehicle(src)
    if not veh then return fail('no vehicle close enough') end
    stopEscort(t)
    TriggerClientEvent('tfc-police:client:seat', t, NetworkGetNetworkIdFromEntity(veh))
    return { ok = true, message = ('Put %s in the vehicle'):format(name(t)) }
end

function Actions.unseat(src, target)
    local t, err = check(src, target, Cfg.VehicleDistance)
    if not t then return fail(err) end
    local veh = GetVehiclePedIsIn(GetPlayerPed(t), false)
    if veh == 0 then return fail('they are not in a vehicle') end
    TriggerClientEvent('tfc-police:client:unseat', t)
    return { ok = true, message = ('Took %s out'):format(name(t)) }
end

function Actions.search(src, target)
    local t, err = check(src, target, Cfg.ActionDistance)
    if not t then return fail(err) end
    if not isCuffed(t) and not isDown(t) then return fail('they need to be cuffed or down') end
    if GetResourceState('tfc-inventory') ~= 'started' then return fail('inventory is not running') end
    local ok, why = exports['tfc-inventory']:OpenSearch(src, t)
    if not ok then return fail(why or 'could not search them') end
    notify(t, 'You are being searched.', 'warning')
    return { ok = true }
end

local function record(kind, target, officer, amount, minutes, reason)
    local tp, op = TFC.GetPlayer(target), officer and officer > 0 and TFC.GetPlayer(officer) or nil
    MySQL.insert('INSERT INTO tfc_police_records (type, target_cid, target_name, officer_cid, officer_name, amount, minutes, reason) VALUES (?, ?, ?, NULLIF(?, \'\'), NULLIF(?, \'\'), NULLIF(?, -1), NULLIF(?, -1), ?)', {
        kind, tp and tp.cid or '?', name(target), op and op.cid or '', op and name(officer) or '',
        amount or -1, minutes or -1, reason or '',
    })
end

---Take a fine: all from the first account if it can, otherwise everything the first account
---has and the rest from the second (e.g. bank, then credit up to its limit).
---@return boolean ok, string|nil paidFrom
local function payFine(target, amount, reason)
    local acc = exports['tfc-accounts']
    local first, second = Cfg.FineFrom[1], Cfg.FineFrom[2]
    if acc:RemoveMoney(target, first, amount, reason) then return true, first end
    if not second then return false end

    local have = math.max(0, math.tointeger((acc:GetBalance(target, first))) or 0)
    local part = math.min(have, amount)
    local rest = amount - part
    if not acc:RemoveMoney(target, second, rest, reason) then return false end
    if part > 0 and not acc:RemoveMoney(target, first, part, reason) then
        acc:AddMoney(target, second, rest, 'Refund: ' .. reason)
        return false
    end
    return true, part > 0 and ('%s and %s'):format(first, second) or second
end

function Actions.fine(src, target, amount, reason)
    local t, err = check(src, target, Cfg.ActionDistance + 2.0)
    if not t then return fail(err) end
    amount = math.tointeger(tonumber(amount))
    if not amount or amount < 1 or amount > Cfg.MaxFine then return fail(('fine must be $1 to $%d'):format(Cfg.MaxFine)) end
    reason = cleanReason(reason)
    if #reason < 3 then return fail('give a reason') end

    local paid, account = payFine(t, amount, 'Fine: ' .. reason)
    if not paid then return fail(('%s can\'t pay $%d (bank and credit limit reached)'):format(name(t), amount)) end

    record('fine', t, src, amount, nil, reason)
    -- Fines go into the police department's account (tfc-banking).
    if GetResourceState('tfc-banking') == 'started' then
        local job = exports['tfc-jobs']:GetJob(src)
        exports['tfc-banking']:AddSociety(job and job.name or 'police', amount, ('Fine: %s (%s)'):format(name(t), reason))
    end
    TFC.Emit('playerFined', t, src, amount, reason)
    notify(t, ('You were fined $%d: %s (paid from %s)'):format(amount, reason, account), 'warning')
    TFC.Log.Info('%s fined %s $%d: %s', name(src), name(t), amount, reason)
    return { ok = true, message = ('Fined %s $%d'):format(name(t), amount) }
end

-- Jail ---------------------------------------------------------------------------------------

local function saveSentence(src)
    local p = TFC.GetPlayer(src)
    if not p then return end
    local left = jailed[src] and math.max(0, jailed[src] - os.time()) or 0
    p:SetMetadata('jail', left > 0 and left or nil)
end

local function Jail(target, minutes, reason, officer)
    target = math.tointeger(tonumber(target))
    if not target or not TFC.GetPlayer(target) then return false end
    jailed[target] = os.time() + minutes * 60
    if isCuffed(target) then setCuffed(target, false, officer) end
    stopEscort(target)
    state(target):set('tfc:jailed', true, true)
    saveSentence(target)
    local s = Cfg.Jail.spawn
    TriggerClientEvent('tfc-police:client:jail', target, minutes * 60, { x = s.x, y = s.y, z = s.z, w = s.w })
    TFC.Emit('playerJailed', target, officer or 0, minutes, reason or '')
    return true
end

local function Release(target)
    target = math.tointeger(tonumber(target))
    if not target or not jailed[target] then return false end
    jailed[target] = nil
    state(target):set('tfc:jailed', nil, true)
    saveSentence(target)
    local r = Cfg.Jail.release
    TriggerClientEvent('tfc-police:client:release', target, { x = r.x, y = r.y, z = r.z, w = r.w })
    notify(target, 'You have been released.', 'success')
    TFC.Emit('playerReleased', target)
    return true
end

function Actions.jail(src, target, minutes, reason)
    local t, err = check(src, target, Cfg.ActionDistance + 2.0)
    if not t then return fail(err) end
    if not isCuffed(t) then return fail('cuff them first') end
    if jailed[t] then return fail('they are already in jail') end
    minutes = math.tointeger(tonumber(minutes))
    if not minutes or minutes < 1 or minutes > Cfg.MaxJailMinutes then return fail(('jail time must be 1 to %d minutes'):format(Cfg.MaxJailMinutes)) end
    reason = cleanReason(reason)
    if #reason < 3 then return fail('give a reason') end

    Jail(t, minutes, reason, src)
    record('jail', t, src, nil, minutes, reason)
    notify(t, ('You were sentenced to %d minutes: %s'):format(minutes, reason), 'error')
    TFC.Log.Info('%s jailed %s for %d min: %s', name(src), name(t), minutes, reason)
    return { ok = true, message = ('Jailed %s for %d min'):format(name(t), minutes) }
end

function Actions.unjail(src, target)
    target = math.tointeger(tonumber(target))
    if not isOfficer(src) and not TFC.IsAdmin(src) then return fail('you need to be police on duty') end
    if not target or not jailed[target] then return fail('they are not in jail') end
    Release(target)
    record('release', target, src, nil, nil, 'released early')
    TFC.Log.Info('%s released %s from jail', name(src), name(target))
    return { ok = true, message = ('Released %s'):format(name(target)) }
end

exports('IsCuffed', function(src) return isCuffed(tonumber(src)) end)
exports('IsJailed', function(src) return jailed[tonumber(src)] ~= nil end)
exports('Jail', function(src, minutes, reason) return Jail(src, math.tointeger(tonumber(minutes)) or 1, reason, 0) end)
exports('Release', Release)

TFC.Callback.Register('police:action', function(src, action, target, a, b)
    local fn = type(action) == 'string' and Actions[action]
    if not fn then return fail('unknown action') end
    return fn(src, target, a, b)
end, { rateLimit = 500 })

-- Commands -----------------------------------------------------------------------------------

---A command's target: the ID given, or the closest loaded player within range.
local function targetFor(src, arg, range)
    if arg then return TFC.ResolveTarget(src, arg) end
    local here = coords(src)
    local best, bestDist = nil, range + 1.0
    for _, other in ipairs(TFC.GetPlayers()) do
        if other ~= src then
            local d = dist(here, coords(other))
            if d < bestDist then best, bestDist = other, d end
        end
    end
    return best
end

local function reply(src, r)
    if r.ok and r.message then notify(src, r.message, 'success') elseif not r.ok then notify(src, r.error, 'error') end
end

local ID_OPTIONAL = { { name = 'id', help = 'Player ID (default: closest player)', optional = true } }

for cmd, def in pairs({
    cuff = { help = 'Police: cuff or uncuff the closest player', range = Cfg.CuffDistance },
    escort = { help = 'Police: start or stop escorting a cuffed/downed player', range = Cfg.ActionDistance },
    seat = { help = 'Police: put a cuffed/downed player in the closest vehicle', range = Cfg.VehicleDistance },
    unseat = { help = 'Police: take a player out of their vehicle', range = Cfg.VehicleDistance },
    search = { help = 'Police: search a cuffed/downed player', range = Cfg.ActionDistance },
}) do
    TFC.RegisterCommand(cmd, { help = def.help, params = ID_OPTIONAL }, function(src, args)
        if src == 0 then return end
        local target = targetFor(src, args[1], def.range)
        if not target then return notify(src, 'Nobody close enough.', 'error') end
        reply(src, Actions[cmd](src, target))
    end)
end

TFC.RegisterCommand('fine', {
    help = 'Police: fine a nearby player',
    params = {
        { name = 'id', help = 'Player ID' },
        { name = 'amount', help = 'Dollars' },
        { name = 'reason', help = 'What for' },
    },
}, function(src, args)
    if src == 0 then return end
    local target = TFC.ResolveTarget(src, args[1])
    if not target then return notify(src, 'No such player.', 'error') end
    reply(src, Actions.fine(src, target, args[2], table.concat(args, ' ', 3)))
end)

TFC.RegisterCommand('jail', {
    help = 'Police: send a cuffed, nearby player to jail',
    params = {
        { name = 'id', help = 'Player ID' },
        { name = 'minutes', help = ('1-%d'):format(Cfg.MaxJailMinutes) },
        { name = 'reason', help = 'What for' },
    },
}, function(src, args)
    local target = TFC.ResolveTarget(src, args[1])
    if not target then
        if src == 0 then return print('no such player') end
        return notify(src, 'No such player.', 'error')
    end
    if src == 0 then
        Jail(target, math.tointeger(tonumber(args[2])) or 5, table.concat(args, ' ', 3), 0)
        return
    end
    reply(src, Actions.jail(src, target, args[2], table.concat(args, ' ', 3)))
end)

TFC.RegisterCommand('unjail', {
    help = 'Police / admin: release a player from jail',
    params = { { name = 'id', help = 'Player ID' } },
}, function(src, args)
    local target = TFC.ResolveTarget(src, args[1])
    if src == 0 then
        if target then Release(target) end
        return
    end
    if not target then return notify(src, 'No such player.', 'error') end
    reply(src, Actions.unjail(src, target))
end)

TFC.RegisterCommand('jailtime', { help = 'How long is left on your sentence' }, function(src)
    if src == 0 then return end
    local ends = jailed[src]
    if not ends then return notify(src, 'You are not in jail.') end
    notify(src, ('%d min %d s left.'):format((ends - os.time()) // 60, (ends - os.time()) % 60))
end)

-- Timers and lifecycle ------------------------------------------------------------------------

CreateThread(function()
    local saveTick = 0
    while true do
        Wait(5000)
        saveTick = saveTick + 1
        local now = os.time()
        for src, ends in pairs(jailed) do
            if now >= ends then
                local ok, err = pcall(Release, src)
                if not ok then TFC.Log.Error('release failed: %s', tostring(err)) end
            elseif saveTick % 12 == 0 then
                pcall(saveSentence, src) -- once a minute
            end
        end
        -- Escorts end if the officer left or went off duty.
        for suspect, officer in pairs(escorts) do
            if not TFC.GetPlayer(officer) or not TFC.GetPlayer(suspect) or not isOfficer(officer) then
                stopEscort(suspect)
            end
        end
    end
end)

TFC.On('playerLoaded', function(src)
    local p = TFC.GetPlayer(src)
    local left = p and math.tointeger((p:GetMetadata('jail')))
    if left and left > 0 then
        CreateThread(function()
            Wait(4000) -- let the client spawn first
            if not TFC.GetPlayer(src) then return end
            jailed[src] = os.time() + left
            state(src):set('tfc:jailed', true, true)
            local s = Cfg.Jail.spawn
            TriggerClientEvent('tfc-police:client:jail', src, left, { x = s.x, y = s.y, z = s.z, w = s.w })
            notify(src, ('You still have %d min to serve.'):format(math.ceil(left / 60)), 'warning')
        end)
    end
end)

TFC.On('playerUnloaded', function(src)
    if jailed[src] then pcall(saveSentence, src) end
    jailed[src] = nil
    stopEscort(src)
    for suspect, officer in pairs(escorts) do
        if officer == src then stopEscort(suspect) end
    end
    local st = state(src)
    st:set('tfc:cuffed', nil, true)
    st:set('tfc:jailed', nil, true)
end)

CreateThread(function()
    while not exports['tfc-core']:IsDatabaseReady() do Wait(250) end
    MySQL.query.await(SCHEMA)
    TFC.RegisterModule({ name = 'police', version = '0.1.0' }, function()
        TFC.Log.Info('police ready')
    end)
end)
