-- World client: follows the server's clock and weather (GlobalState['tfc:world']).
-- The time is worked out locally from the server's clock anchor, so it stays smooth
-- without the server sending anything every second.

local DAY = 24 * 60 * 60
local world = nil
local appliedWeather = nil
local appliedSnow = nil

local function gameSeconds()
    local c = world.clock
    if c.frozen then return math.floor(c.seconds) % DAY end
    -- GetCloudTimeAsInt is the network's Unix time, the same clock the server's os.time uses.
    return math.floor(c.seconds + (GetCloudTimeAsInt() - c.at) * c.rate) % DAY
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
end)

-- Another script that also sets the clock (usually vMenu's time sync) makes the time jump back
-- and forth. Spot it: just before we set the clock, it should already be within a few game
-- minutes of what we set a second ago.
local conflicts = 0
local warned = false

local function checkConflict(expected)
    local now = GetClockHours() * 3600 + GetClockMinutes() * 60 + GetClockSeconds()
    local diff = math.abs(now - expected)
    diff = math.min(diff, DAY - diff)
    if diff > 300 then conflicts = conflicts + 1 else conflicts = 0 end
    if conflicts >= 3 and not warned then
        warned = true
        local msg = 'Another resource keeps changing the game clock (usually vMenu time sync). '
            .. 'Set "setr vmenu_enable_time_sync false" and "setr vmenu_enable_weather_sync false" in server.cfg.'
        print('^3[tfc-world] ' .. msg .. '^7')
        if LocalPlayer.state['tfc:admin'] then
            TFC.UI.Notify({ title = 'World sync', description = msg, type = 'warning', duration = 15000 })
        end
    end
end

CreateThread(function()
    update(GlobalState['tfc:world'], true)
    local tick = 0
    local lastSet = nil
    while true do
        if world then
            local s = gameSeconds()
            if lastSet and not world.clock.frozen then checkConflict(s) end
            NetworkOverrideClockTime(s // 3600, (s % 3600) // 60, s % 60)
            lastSet = s

            -- Every 10 s re-apply weather and lights in case something else changed them.
            tick = tick + 1
            if tick >= 10 then
                tick = 0
                local want = world.snow and 'XMAS' or world.weather
                if GetPrevWeatherTypeHashName() ~= GetHashKey(want) and GetNextWeatherTypeHashName() ~= GetHashKey(want) then
                    appliedWeather = nil
                end
                applyWeather(appliedWeather == nil)
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetArtificialLightsState(false)
    if appliedSnow then applySnow(false) end
end)
