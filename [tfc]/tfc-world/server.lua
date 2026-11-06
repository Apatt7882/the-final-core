-- World server: the one true clock and weather, published to every client.
--
-- GlobalState['tfc:world'] = {
--     clock = { at = <unix seconds>, seconds = <game seconds since midnight at `at`>, frozen = bool, rate = <game s per real s> },
--     weather = 'CLEAR', blackout = bool, snow = bool,
-- }
-- Clients work out the current time themselves from `clock`, so nothing is sent every second.
--
-- Exports (server): GetTime() -> { hour, minute }, SetTime(h, m), FreezeTime(bool),
--   GetWeather(), SetWeather(type), SetBlackout(bool), SetSnow(bool), GetState()

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
    else
        state = {
            clock = { at = os.time(), seconds = (Cfg.StartTime.hour * 60 + Cfg.StartTime.minute) * 60, frozen = false, rate = RATE },
            weather = Cfg.StartWeather,
            blackout = false,
            snow = false,
        }
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
local function GetState()
    local t = GetTime()
    return {
        hour = t.hour, minute = t.minute, frozen = state.clock.frozen,
        weather = state.weather, blackout = state.blackout, snow = state.snow,
        weathers = Cfg.Weathers,
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

-- vMenu's own sync fights with this one (the clock and weather flip back and forth).
CreateThread(function()
    Wait(2000)
    for _, convar in ipairs({ 'vmenu_enable_time_sync', 'vmenu_enable_weather_sync' }) do
        if GetConvar(convar, 'false') == 'true' then
            TFC.Log.Warn('%s is on: vMenu will fight tfc-world. Add "setr %s false" to server.cfg.', convar, convar)
        end
    end
end)

CreateThread(function()
    TFC.RegisterModule({ name = 'world', version = '0.2.0' }, function()
        local t = GetTime()
        TFC.Log.Info('world ready: %02d:%02d%s, %s%s%s', t.hour, t.minute, state.clock.frozen and ' (frozen)' or '',
            state.weather, state.blackout and ', blackout' or '', state.snow and ', snow' or '')
    end)
end)
