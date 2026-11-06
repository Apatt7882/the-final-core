-- World client: follows the server's clock and weather (GlobalState['tfc:world']).
--
-- The clock: the client asks the server for the exact game time (on join, after every change and
-- once a minute) and counts forward from there with its own game timer. It never uses the PC's
-- clock, so a player whose Windows clock is off still sees the same time as everyone else.
-- The time is applied every frame so a script that sets the clock now and then can't win.
--
-- /worldcheck (F8 or chat) shows whether something else is changing the clock or weather.

local DAY = 24 * 60 * 60
local world = nil
local appliedWeather = nil
local appliedSnow = nil

-- Clock anchor from the server: { seconds, frozen, rate, timer }
local anchor = nil

local function resync()
    local r = TFC.Callback.Await('world:now')
    if type(r) == 'table' and tonumber(r.seconds) then
        anchor = { seconds = tonumber(r.seconds), frozen = r.frozen == true, rate = tonumber(r.rate) or 30, timer = GetGameTimer() }
    end
end

local function gameSeconds()
    if anchor.frozen then return math.floor(anchor.seconds) % DAY end
    return math.floor(anchor.seconds + (GetGameTimer() - anchor.timer) / 1000 * anchor.rate) % DAY
end

local function applySnow(on)
    if appliedSnow == on then return end
    appliedSnow = on
    ForceSnowPass(on)
    SetForceVehicleTrails(on)
    SetForcePedFootstepsTracks(on)
    if on then
        RequestScriptAudioBank('ICE_FOOTSTEPS', false)
        RequestScriptAudioBank('SNOW_FOOTSTEPS', false)
    else
        ReleaseNamedScriptAudioBank('ICE_FOOTSTEPS')
        ReleaseNamedScriptAudioBank('SNOW_FOOTSTEPS')
    end
end

local function applyWeather(instant)
    -- Holiday snow overrides the weather with GTA's Christmas weather.
    local weather = world.snow and 'XMAS' or world.weather
    if weather ~= appliedWeather then
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        if instant or not appliedWeather then
            SetWeatherTypeNowPersist(weather)
        else
            SetWeatherTypeOvertimePersist(weather, WorldConfig.TransitionSeconds + 0.0)
        end
        appliedWeather = weather
    end
    applySnow(world.snow == true)
    SetArtificialLightsState(world.blackout == true)
    SetArtificialLightsStateAffectsVehicles(false)
end

local function update(value, instant)
    if type(value) ~= 'table' or type(value.clock) ~= 'table' then return end
    world = value
    applyWeather(instant)
end

AddStateBagChangeHandler('tfc:world', 'global', function(_, _, value)
    update(value, false)
    CreateThread(resync)   -- time was changed or frozen: fetch the new clock now
end)

-- Spotting another script that changes the clock: we set the time every frame, so on the next
-- frame the game clock should be within a few game seconds of what we set. A big gap means
-- something else set it in between.
local foreign = { count = 0, last = nil, lastAt = 0 }

local function clockNow()
    return GetClockHours() * 3600 + GetClockMinutes() * 60 + GetClockSeconds()
end

local function fmt(s) return ('%02d:%02d'):format(s // 3600, (s % 3600) // 60) end

CreateThread(function()
    while not anchor do
        resync()
        if not anchor then Wait(2000) end
    end
    update(GlobalState['tfc:world'], true)

    local lastResync = GetGameTimer()
    local lastWeather = GetGameTimer()
    local lastSet = nil
    while true do
        local s = gameSeconds()
        if lastSet then
            local now = clockNow()
            local diff = math.abs(now - lastSet)
            diff = math.min(diff, DAY - diff)
            if diff > 120 then
                foreign.count = foreign.count + 1
                foreign.last = now
                foreign.lastAt = GetGameTimer()
            end
        end
        NetworkOverrideClockTime(s // 3600, (s % 3600) // 60, s % 60)
        lastSet = s

        local t = GetGameTimer()
        if t - lastResync > 60000 then
            lastResync = t
            CreateThread(resync)
        end
        -- Every 10 s re-apply weather and lights in case something else changed them.
        if world and t - lastWeather > 10000 then
            lastWeather = t
            local want = world.snow and 'XMAS' or world.weather
            if GetPrevWeatherTypeHashName() ~= GetHashKey(want) and GetNextWeatherTypeHashName() ~= GetHashKey(want) then
                appliedWeather = nil
            end
            applyWeather(appliedWeather == nil)
        end
        Wait(0)
    end
end)

-- /worldcheck: what's fighting over the clock? -------------------------------------------------

local SUSPECTS = { 'vmenu', 'sync', 'weather', 'time', 'clock', 'season' }

RegisterCommand('worldcheck', function()
    local lines = {}
    local function add(t) lines[#lines + 1] = t end
    add(('Server time %s, game clock %s%s'):format(anchor and fmt(gameSeconds()) or '?', fmt(clockNow()),
        anchor and anchor.frozen and ' (frozen)' or ''))
    add(('Clock changed by another script: %d time(s)%s'):format(foreign.count,
        foreign.last and (', last to %s, %d s ago'):format(fmt(foreign.last), (GetGameTimer() - foreign.lastAt) // 1000) or ''))
    for _, cv in ipairs({ 'vmenu_enable_time_sync', 'vmenu_enable_weather_sync', 'vmenu_enable_dynamic_weather', 'vmenu_freeze_time' }) do
        add(('%s = %s'):format(cv, GetConvar(cv, '(not set)')))
    end
    local found = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and name ~= GetCurrentResourceName() and GetResourceState(name) == 'started' then
            local low = name:lower()
            for _, word in ipairs(SUSPECTS) do
                if low:find(word, 1, true) then found[#found + 1] = name break end
            end
        end
    end
    add('Running resources that may set time/weather: ' .. (#found > 0 and table.concat(found, ', ') or 'none'))
    for _, l in ipairs(lines) do print('[tfc-world] ' .. l) end
    TFC.UI.Notify({ title = 'World check (details in F8)', description = table.concat(lines, '\n'), duration = 20000 })
end, false)

-- One warning if the clock keeps getting changed.
CreateThread(function()
    while foreign.count < 5 do Wait(15000) end
    local msg = 'Another resource keeps changing the game clock. Type /worldcheck to see which.'
    print('^3[tfc-world] ' .. msg .. '^7')
    if LocalPlayer.state['tfc:admin'] then
        TFC.UI.Notify({ title = 'World sync', description = msg, type = 'warning', duration = 15000 })
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetArtificialLightsState(false)
    if appliedSnow then applySnow(false) end
end)
