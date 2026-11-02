-- Medical server: who is down, reviving, healing, hospital respawn and EMS distress calls.
--
-- Exports (server): IsDown(src) -> bool, Revive(src, full?) -> ok, Heal(src) -> ok
-- State bag (public): 'tfc:down' = true while a player is down.
-- Server hooks: playerDowned(source), playerRevived(source, by)   (by = reviver's source, 0 = system)

local Cfg = MedicalConfig

---@type table<integer, { at: integer }> source -> when they went down
local down = {}
---@type table<integer, integer> source -> last distress call (os.time)
local lastDistress = {}

local function notify(src, text, kind)
    TFC.UI.Notify(src, { title = 'Medical', description = text, type = kind or 'inform' })
end

local function coords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function distance(a, b)
    local ca, cb = coords(a), coords(b)
    if not ca or not cb then return math.huge end
    local dx, dy, dz = ca.x - cb.x, ca.y - cb.y, ca.z - cb.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function isEms(src)
    if GetResourceState('tfc-jobs') ~= 'started' then return false end
    local job = exports['tfc-jobs']:GetJob(src)
    if not job or not job.onDuty then return false end
    for _, name in ipairs(Cfg.EmsJobs) do
        if job.name == name then return true end
    end
    return false
end

local function displayName(src)
    local player = TFC.GetPlayer(src)
    return player and player:GetFullName() or GetPlayerName(src) or tostring(src)
end

-- Down / up --------------------------------------------------------------------------------

local function setDown(src, value)
    Player(src).state:set('tfc:down', value or nil, true)
    local player = TFC.GetPlayer(src)
    if player then player:SetMetadata('isDown', value == true) end
end

local function markDown(src)
    if down[src] then return end
    down[src] = { at = os.time() }
    setDown(src, true)
    if GetResourceState('tfc-inventory') == 'started' then exports['tfc-inventory']:ForceClose(src) end
    TFC.Emit('playerDowned', src)
end

local function IsDown(src)
    return down[tonumber(src)] ~= nil
end

---@param full? boolean full health (admin) instead of ReviveHealth (EMS)
---@param by? integer who revived them (0 = system)
---@param hospital? table vector4 to move them to
local function Revive(src, full, by, hospital)
    src = tonumber(src) --[[@as integer]]
    if not TFC.GetPlayer(src) then return false end
    local wasDown = down[src] ~= nil
    down[src] = nil
    setDown(src, false)
    TriggerClientEvent('tfc-medical:client:revive', src, {
        health = full and 'full' or Cfg.ReviveHealth,
        coords = hospital and { x = hospital.x, y = hospital.y, z = hospital.z, w = hospital.w } or nil,
    })
    if wasDown then TFC.Emit('playerRevived', src, by or 0) end
    return true
end

local function Heal(src)
    src = tonumber(src) --[[@as integer]]
    if not TFC.GetPlayer(src) then return false end
    if down[src] then return Revive(src, true, 0) end
    TriggerClientEvent('tfc-medical:client:heal', src)
    return true
end

exports('IsDown', IsDown)
exports('Revive', function(src, full) return Revive(src, full, 0) end)
exports('Heal', Heal)

-- Client reports -----------------------------------------------------------------------------

local function countEms()
    local n = 0
    for _, other in ipairs(TFC.GetPlayers()) do
        if isEms(other) then n = n + 1 end
    end
    return n
end

---Seconds down and EMS on duty, for the downed screen.
local function status(src)
    local state = down[src]
    return { elapsed = state and (os.time() - state.at) or 0, ems = countEms() }
end

local function announce(src)
    local ems = countEms()
    if ems == 0 then
        notify(src, ('No EMS on duty. You can respawn at the hospital for free in %d seconds.'):format(Cfg.Respawn.noEmsSeconds), 'warning')
    else
        notify(src, ('%d EMS on duty. Press G to call them.'):format(ems), 'warning')
    end
end

TFC.Callback.Register('medical:down', function(src)
    if not TFC.GetPlayer(src) then return { ok = false } end
    local fresh = down[src] == nil
    markDown(src)
    if fresh then announce(src) end
    local st = status(src)
    st.ok = true
    return st
end, { rateLimit = 1000 })

-- Keep downed players' screens up to date as EMS clock in and out.
CreateThread(function()
    while true do
        Wait(5000)
        if next(down) then
            local ems = countEms()
            for src, state in pairs(down) do
                TriggerClientEvent('tfc-medical:client:status', src, { elapsed = os.time() - state.at, ems = ems })
            end
        end
    end
end)

local function nearestHospital(src)
    local here = coords(src)
    local best, bestDist = Cfg.Hospitals[1], math.huge
    if here then
        for _, h in ipairs(Cfg.Hospitals) do
            local dx, dy = h.coords.x - here.x, h.coords.y - here.y
            local d = dx * dx + dy * dy
            if d < bestDist then best, bestDist = h, d end
        end
    end
    return best
end

TFC.Callback.Register('medical:respawn', function(src)
    local state = down[src]
    if not state then return { ok = false, error = 'you are not down' } end
    local elapsed = os.time() - state.at
    local opt = Cfg.RespawnOption(elapsed, countEms())
    if not opt.now then
        local wait = opt.paidIn or opt.freeIn or 0
        return { ok = false, error = ('you can respawn in %d:%02d'):format(wait // 60, wait % 60) }
    end

    local hospital = nearestHospital(src)
    if opt.fee > 0 then
        local paid = GetResourceState('tfc-accounts') == 'started'
            and exports['tfc-accounts']:Charge(src, opt.fee, 'Hospital bill (early): ' .. hospital.label, Cfg.RespawnFeeFrom)
        if not paid then
            local wait = opt.freeIn or 0
            return { ok = false, error = ('you can\'t afford the $%d bill. Free respawn in %d:%02d'):format(opt.fee, wait // 60, wait % 60) }
        end
    end

    Revive(src, true, 0, hospital.coords)
    if opt.fee > 0 then
        notify(src, ('Treated at %s. Bill: $%d'):format(hospital.label, opt.fee))
    else
        notify(src, ('Treated at %s. No charge.'):format(hospital.label))
    end
    TFC.Log.Info('%s respawned at %s ($%d)', displayName(src), hospital.label, opt.fee)
    return { ok = true }
end, { rateLimit = 2000 })

TFC.Callback.Register('medical:distress', function(src)
    if not down[src] then return { ok = false, error = 'you are not down' } end
    local now = os.time()
    if lastDistress[src] and now - lastDistress[src] < Cfg.DistressCooldown then
        return { ok = false, error = ('wait %d s before calling again'):format(Cfg.DistressCooldown - (now - lastDistress[src])) }
    end
    lastDistress[src] = now

    local here = coords(src)
    local sent = 0
    for _, ems in ipairs(TFC.GetPlayers()) do
        if ems ~= src and isEms(ems) then
            TriggerClientEvent('tfc-medical:client:distress', ems, {
                id = src, name = displayName(src),
                x = here and here.x or 0.0, y = here and here.y or 0.0, z = here and here.z or 0.0,
            })
            sent = sent + 1
        end
    end
    if sent == 0 then
        return { ok = true, message = 'No EMS on duty. You can respawn at the hospital when the timer runs out.' }
    end
    return { ok = true, message = ('EMS alerted (%d on duty).'):format(sent) }
end, { rateLimit = 1000 })

-- EMS actions --------------------------------------------------------------------------------

---Shared by the job menu and the commands.
---@return table result { ok, error?, message? }
local function emsRevive(src, target)
    target = math.tointeger(tonumber(target))
    if not isEms(src) then return { ok = false, error = 'you need to be EMS on duty' } end
    if not target or target == src or not TFC.GetPlayer(target) then return { ok = false, error = 'nobody to revive' } end
    if not down[target] then return { ok = false, error = 'they are not down' } end
    if distance(src, target) > Cfg.ReviveDistance + 1.0 then return { ok = false, error = 'they are too far away' } end
    Revive(target, false, src)
    notify(target, 'You were revived by EMS.', 'success')
    TFC.Log.Info('%s revived %s', displayName(src), displayName(target))
    return { ok = true, message = ('Revived %s'):format(displayName(target)) }
end

local function emsHeal(src, target)
    target = math.tointeger(tonumber(target))
    if not isEms(src) then return { ok = false, error = 'you need to be EMS on duty' } end
    if not target or target == src or not TFC.GetPlayer(target) then return { ok = false, error = 'nobody to treat' } end
    if down[target] then return { ok = false, error = 'they are down: revive them first' } end
    if distance(src, target) > Cfg.ReviveDistance + 1.0 then return { ok = false, error = 'they are too far away' } end
    Heal(target)
    notify(target, 'EMS treated your wounds.', 'success')
    return { ok = true, message = ('Treated %s'):format(displayName(target)) }
end

TFC.Callback.Register('medical:revive', emsRevive, { rateLimit = 1000 })
TFC.Callback.Register('medical:heal', emsHeal, { rateLimit = 1000 })

-- Commands -----------------------------------------------------------------------------------

---Closest loaded player to src within range (optionally only downed ones).
local function closest(src, range, downOnly)
    local best, bestDist = nil, range
    for _, other in ipairs(TFC.GetPlayers()) do
        if other ~= src and (not downOnly or down[other]) then
            local d = distance(src, other)
            if d < bestDist then best, bestDist = other, d end
        end
    end
    return best
end

local function commandTarget(src, arg, downOnly)
    if arg then return TFC.ResolveTarget(src, arg) end
    return closest(src, Cfg.ReviveDistance, downOnly)
end

TFC.RegisterCommand('revive', {
    help = 'Revive a downed player (EMS on duty: nearby; admins: anyone)',
    params = { { name = 'id', help = 'Player ID or "me" (default: closest downed player)', optional = true } },
}, function(src, args)
    if src == 0 then
        local target = TFC.ResolveTarget(0, args[1])
        if target then Revive(target, true, 0) end
        return
    end

    if TFC.IsAdmin(src) then
        local target = args[1] and TFC.ResolveTarget(src, args[1]) or (down[src] and src) or closest(src, 10.0, true) or src
        if not target then return notify(src, 'No such player.', 'error') end
        Revive(target, true, src)
        TFC.Log.Info('admin %s revived %s', displayName(src), displayName(target))
        return notify(src, ('Revived %s'):format(displayName(target)), 'success')
    end

    local target = commandTarget(src, args[1], true)
    if not target then return notify(src, 'Nobody downed close by.', 'error') end
    local r = emsRevive(src, target)
    notify(src, r.ok and r.message or r.error, r.ok and 'success' or 'error')
end)

TFC.RegisterCommand('heal', {
    help = 'Heal a player (EMS on duty: nearby; admins: anyone)',
    params = { { name = 'id', help = 'Player ID or "me" (default: closest player)', optional = true } },
}, function(src, args)
    if src == 0 then
        local target = TFC.ResolveTarget(0, args[1])
        if target then Heal(target) end
        return
    end

    if TFC.IsAdmin(src) then
        local target = args[1] and TFC.ResolveTarget(src, args[1]) or src
        if not target then return notify(src, 'No such player.', 'error') end
        Heal(target)
        return notify(src, ('Healed %s'):format(displayName(target)), 'success')
    end

    local target = commandTarget(src, args[1], false)
    if not target then return notify(src, 'Nobody close by.', 'error') end
    local r = emsHeal(src, target)
    notify(src, r.ok and r.message or r.error, r.ok and 'success' or 'error')
end)

-- Lifecycle ----------------------------------------------------------------------------------

TFC.On('playerLoaded', function(src)
    local player = TFC.GetPlayer(src)
    if not player then return end
    if Cfg.StayDownOnReconnect and player:GetMetadata('isDown') then
        CreateThread(function()
            Wait(4000) -- let the client spawn first
            if not TFC.GetPlayer(src) then return end
            markDown(src)
            announce(src)
            TriggerClientEvent('tfc-medical:client:forceDown', src, status(src))
        end)
    end
end)

TFC.On('playerUnloaded', function(src)
    down[src] = nil
    lastDistress[src] = nil
    Player(src).state:set('tfc:down', nil, true)
end)

CreateThread(function()
    TFC.RegisterModule({ name = 'medical', version = '0.1.0' }, function()
        local R = Cfg.Respawn
        TFC.Log.Info('medical ready: respawn $%d after %d s or free after %d s (%d s with no EMS)', R.earlyFee, R.earlySeconds, R.freeSeconds, R.noEmsSeconds)
    end)
end)
