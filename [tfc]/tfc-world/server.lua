-- World server: the one true clock and weather, published to every client.
--
-- GlobalState['tfc:world'] = {
--     clock = { at = <unix seconds>, seconds = <game seconds since midnight at `at`>, frozen = bool, rate = <game s per real s> },
--     weather = 'CLEAR', blackout = bool, snow = bool,
-- }
-- Clients work out the current time themselves from `clock`, so nothing is sent every second.
--
-- Exports (server): GetTime() -> { hour, minute }, SetTime(h, m), FreezeTime(bool),
--   GetWeather(), SetWeather(type), SetBlackout(bool), SetSnow(bool), GetState(),
--   GetAop(), SetAop(text), GetPriority('city'|'county'), SetPriority(zone, status, minutes?, byName?)

local Cfg = WorldConfig
local DAY = 24 * 60 * 60
local RATE = 60 / Cfg.SecondsPerGameMinute    -- game seconds per real second

local valid = {}
for _, w in ipairs(Cfg.Weathers) do valid[w.id] = true end

local state = nil

-- Clock -----------------------------------------------------------------------------------------

---Game seconds since midnight right now.
local function gameSeconds()
    local c = state.clock
    if c.frozen then return c.seconds % DAY end
    return math.floor(c.seconds + (os.time() - c.at) * c.rate) % DAY
end

local function GetTime()
    local s = gameSeconds()
    return { hour = s // 3600, minute = (s % 3600) // 60 }
end

-- Saving and publishing -------------------------------------------------------------------------

local function publish()
    GlobalState:set('tfc:world', state, true)
    SetResourceKvp('state', json.encode(state))
end

local function load()
    local raw = GetResourceKvpString('state')
    local saved = raw and json.decode(raw)
    if type(saved) == 'table' and type(saved.clock) == 'table' then
        state = saved
        -- Carry on from where the clock was when the server stopped (not from the downtime).
        state.clock.seconds = math.floor(tonumber(state.clock.seconds) or 0) % DAY
        state.clock.at = os.time()
        state.clock.rate = RATE
        if not valid[state.weather] then state.weather = Cfg.StartWeather end
        state.blackout = state.blackout == true
        state.snow = state.snow == true
        state.clock.frozen = state.clock.frozen == true
        state.aop = type(state.aop) == 'string' and state.aop ~= '' and state.aop or Cfg.Aop.Default
        state.prio = type(state.prio) == 'table' and state.prio or nil
    else
        state = {
            clock = { at = os.time(), seconds = (Cfg.StartTime.hour * 60 + Cfg.StartTime.minute) * 60, frozen = false, rate = RATE },
            weather = Cfg.StartWeather,
            blackout = false,
            snow = false,
            aop = Cfg.Aop.Default,
        }
    end
    state.prio = state.prio or {}
    for _, zone in ipairs({ 'city', 'county' }) do
        if type(state.prio[zone]) ~= 'table' then state.prio[zone] = { status = 'available' } end
    end
end

-- Remember the running clock every minute so a crash loses at most a minute of game time.
CreateThread(function()
    while true do
        Wait(60000)
        if state then
            local copy = json.decode(json.encode(state))
            copy.clock.seconds = gameSeconds()
            copy.clock.at = os.time()
            SetResourceKvp('state', json.encode(copy))
        end
    end
end)

-- Changes ----------------------------------------------------------------------------------------

local function SetTime(hour, minute)
    hour, minute = math.tointeger(tonumber(hour)), math.tointeger(tonumber(minute or 0))
    if not hour or hour < 0 or hour > 23 or not minute or minute < 0 or minute > 59 then return false, 'time must be 00:00 to 23:59' end
    state.clock.seconds = (hour * 60 + minute) * 60
    state.clock.at = os.time()
    publish()
    return true
end

local function FreezeTime(frozen)
    local now = gameSeconds()
    state.clock.seconds = now
    state.clock.at = os.time()
    state.clock.frozen = frozen == true
    publish()
    return true
end

local function SetWeather(weather)
    weather = type(weather) == 'string' and weather:upper() or ''
    if not valid[weather] then return false, 'unknown weather' end
    state.weather = weather
    publish()
    return true
end

local function SetBlackout(on)
    state.blackout = on == true
    publish()
    return true
end

local function SetSnow(on)
    state.snow = on == true
    publish()
    return true
end

exports('GetTime', GetTime)
exports('SetTime', SetTime)
exports('FreezeTime', FreezeTime)
exports('GetWeather', function() return state.weather end)
exports('SetWeather', SetWeather)
exports('SetBlackout', SetBlackout)
exports('SetSnow', SetSnow)
-- AOP and priority --------------------------------------------------------------------------------
-- GlobalState['tfc:aop'] = { aop, city = { status, label, detail }, county = { ... } } for the HUD.

local P = Cfg.Priority
local ZONES = { city = 'City', county = 'County' }
local STATUS = { available = 'Available', active = 'In progress', cooldown = 'Cooldown', hold = 'On hold' }

local function prioView(p)
    local v = { status = p.status, label = STATUS[p.status] or p.status }
    if p.status == 'active' and p.by then v.detail = p.by
    elseif p.status == 'cooldown' and p.untilT then v.detail = ('%d min'):format(math.max(1, math.ceil((p.untilT - os.time()) / 60)))
    elseif p.status == 'hold' and p.by then v.detail = p.by end
    return v
end

local lastAop = nil
local function publishAop()
    local v = { aop = state.aop, city = prioView(state.prio.city), county = prioView(state.prio.county) }
    local enc = json.encode(v)
    if enc == lastAop then return end
    lastAop = enc
    GlobalState:set('tfc:aop', v, true)
end

local function announce(text, kind)
    TFC.UI.Notify(-1, { title = 'Priority', description = text, type = kind or 'inform', duration = 7000 })
end

local function SetAop(text)
    text = type(text) == 'string' and text:gsub('[%c<>]', ''):match('^%s*(.-)%s*$') or ''
    if #text < 2 or #text > 60 then return false, 'AOP must be 2 to 60 characters' end
    state.aop = text
    publish()
    publishAop()
    TFC.UI.Notify(-1, { title = 'Area of play', description = ('AOP is now %s.'):format(text), type = 'inform', duration = 8000 })
    return true
end

---@param zone 'city'|'county'
---@param status 'available'|'active'|'cooldown'|'hold'
local function SetPriority(zone, status, minutes, byName)
    if not ZONES[zone] then return false, 'zone must be city or county' end
    if not STATUS[status] then return false, 'status must be available, active, cooldown or hold' end
    local p = { status = status, by = byName }
    if status == 'cooldown' then
        minutes = math.tointeger(tonumber(minutes) or P.CooldownMinutes) or P.CooldownMinutes
        if minutes < 1 or minutes > 180 then return false, 'cooldown must be 1 to 180 minutes' end
        p.untilT = os.time() + minutes * 60
    end
    state.prio[zone] = p
    publish()
    publishAop()
    local name = ZONES[zone]
    if status == 'active' then announce(('%s priority is now in progress%s.'):format(name, byName and (' (' .. byName .. ')') or ''), 'warning')
    elseif status == 'cooldown' then announce(('%s priority is on cooldown for %d minutes.'):format(name, minutes), 'inform')
    elseif status == 'hold' then announce(('%s priority is on hold.'):format(name), 'inform')
    else announce(('%s priority is available.'):format(name), 'success') end
    return true
end

-- Cooldowns run out by themselves; the HUD's minutes count down.
CreateThread(function()
    while true do
        Wait(15000)
        if state then
            for zone, p in pairs(state.prio) do
                if p.status == 'cooldown' and p.untilT and os.time() >= p.untilT then
                    SetPriority(zone, 'available')
                end
            end
            publishAop()
        end
    end
end)

exports('GetAop', function() return state.aop end)
exports('SetAop', SetAop)
exports('GetPriority', function(zone) return state.prio[zone] and prioView(state.prio[zone]) or nil end)
exports('SetPriority', SetPriority)

local function charName(src)
    local p = TFC.GetPlayer(src)
    return p and p:GetFullName() or GetPlayerName(src) or 'Unknown'
end

local function canCommand(src)
    if TFC.IsAdmin(src) then return true end
    if GetResourceState('tfc-jobs') ~= 'started' then return false end
    local job = exports['tfc-jobs']:GetJob(src)
    if not job or job.onDuty ~= true then return false end
    for _, j in ipairs(P.CommandJobs) do if j == job.name then return true end end
    return false
end

for zone, command in pairs(P.Commands) do
    TFC.RegisterCommand(command, {
        help = ('%s priority: start, stop, cooldown [minutes], hold or reset'):format(ZONES[zone]),
        params = { { name = 'action', help = 'start | stop | cooldown | hold | reset' }, { name = 'minutes', help = 'for cooldown (optional)', optional = true } },
    }, function(src, args)
        if src == 0 then src = nil end
        local action = (args[1] or ''):lower()
        local function reply(text, kind)
            if src then TFC.UI.Notify(src, { title = 'Priority', description = text, type = kind or 'error' }) else print(text) end
        end
        local map = { start = 'active', stop = 'cooldown', cooldown = 'cooldown', hold = 'hold', reset = 'available' }
        local status = map[action]
        if not status then return reply(('Use /%s start | stop | cooldown [minutes] | hold | reset'):format(command)) end

        local full = not src or canCommand(src)
        if not full then
            local current = state.prio[zone].status
            if not (action == 'start' and P.AnyoneCanStart and current == 'available') then
                return reply(action == 'start' and ('%s priority is not available right now.'):format(ZONES[zone])
                    or 'Only staff or on-duty police can do that.')
            end
        end
        if action == 'start' and state.prio[zone].status == 'active' then return reply(('%s priority is already in progress.'):format(ZONES[zone])) end

        local ok, err = SetPriority(zone, status, action == 'cooldown' and args[2] or nil, src and charName(src) or 'Console')
        if not ok then return reply(err) end
        TFC.Log.Info('[world] %s set %s priority to %s', src and ('%s (%d)'):format(charName(src), src) or 'console', zone, status)
    end)
end

local function GetState()
    local t = GetTime()
    return {
        hour = t.hour, minute = t.minute, frozen = state.clock.frozen,
        weather = state.weather, blackout = state.blackout, snow = state.snow,
        weathers = Cfg.Weathers,
        aop = state.aop, aopPresets = Cfg.Aop.Presets, cooldownMinutes = Cfg.Priority.CooldownMinutes,
        prio = { city = prioView(state.prio.city), county = prioView(state.prio.county) },
    }
end
exports('GetState', GetState)

-- Admin callbacks (used by the World tab in tfc-admin) -----------------------------------------------

local function adminName(src)
    local p = TFC.GetPlayer(src)
    return ('%s (%d)'):format(p and p:GetFullName() or GetPlayerName(src) or '?', src)
end

TFC.Callback.Register('world:set', function(src, action, a, b)
    if not TFC.IsAdmin(src) then return { ok = false, error = 'admins only' } end
    local ok, err
    if action == 'time' then ok, err = SetTime(a, b)
    elseif action == 'freeze' then ok, err = FreezeTime(a == true)
    elseif action == 'weather' then ok, err = SetWeather(a)
    elseif action == 'blackout' then ok, err = SetBlackout(a == true)
    elseif action == 'snow' then ok, err = SetSnow(a == true)
    elseif action == 'aop' then ok, err = SetAop(a)
    elseif action == 'prio' then
        local d = type(b) == 'table' and b or {}
        ok, err = SetPriority(a, d.status, d.minutes, charName(src))
    else return { ok = false, error = 'unknown action' } end

    if ok then
        TFC.Log.Info('[world] %s set %s to %s%s', adminName(src), action, tostring(a), b ~= nil and (':' .. tostring(b)) or '')
    end
    local r = GetState()
    r.ok, r.error = ok == true, err
    return r
end, { rateLimit = 250 })

-- Every client asks for the clock itself (on join, after changes and every minute) and counts
-- from there with its own game timer, so it never depends on the player's PC clock.
TFC.Callback.Register('world:now', function()
    return { seconds = gameSeconds(), frozen = state.clock.frozen == true, rate = state.clock.rate }
end, { rateLimit = 1000 })

TFC.Callback.Register('world:state', function(src)
    if not TFC.IsAdmin(src) then return { ok = false, error = 'admins only' } end
    local r = GetState()
    r.ok = true
    return r
end, { rateLimit = 250 })

-- Start ----------------------------------------------------------------------------------------------

load()
publish()
publishAop()

-- vMenu's own sync fights with this one (the clock and weather flip back and forth).
CreateThread(function()
    Wait(2000)
    for _, convar in ipairs({ 'vmenu_enable_time_sync', 'vmenu_enable_weather_sync' }) do
        local value = GetConvar(convar, 'false')
        if value:lower() == 'true' then
            -- The server really has it set to true: some .cfg that runs AFTER the "false" line sets it
            -- again (usually vMenu's permissions.cfg). tfc-world still wins, but vMenu keeps sending its time.
            TFC.Log.Warn('%s is "%s" on the server. Some .cfg run after your "setr %s false" turns it back on '
                .. '(check vMenu\'s permissions.cfg and every exec). tfc-world overrides it, but it should be false.', convar, value, convar)
        end
    end
end)

CreateThread(function()
    TFC.RegisterModule({ name = 'world', version = '0.3.0' }, function()
        local t = GetTime()
        TFC.Log.Info('world ready: %02d:%02d%s, %s%s%s', t.hour, t.minute, state.clock.frozen and ' (frozen)' or '',
            state.weather, state.blackout and ', blackout' or '', state.snow and ', snow' or '')
    end)
end)
