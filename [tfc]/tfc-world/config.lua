-- World sync: everyone sees the same time and weather. The server keeps the clock; admins
-- change things from the World tab in the admin menu (F10). Settings survive restarts.
--
-- If vMenu is running, turn off its own sync in server.cfg or the two will fight:
--   setr vmenu_enable_time_sync false
--   setr vmenu_enable_weather_sync false

WorldConfig = {
    -- Real seconds per in-game minute. 2 = GTA's normal pace (a full day every 48 minutes).
    SecondsPerGameMinute = 2,

    -- Used the very first time (afterwards the last state is restored after a restart).
    StartTime = { hour = 8, minute = 0 },
    StartWeather = 'CLEAR',

    -- Seconds a weather change takes to blend in.
    TransitionSeconds = 15,

    -- Weather the admin menu offers: id = GTA weather type.
    Weathers = {
        { id = 'EXTRASUNNY', label = 'Extra sunny' },
        { id = 'CLEAR', label = 'Clear' },
        { id = 'CLOUDS', label = 'Clouds' },
        { id = 'OVERCAST', label = 'Overcast' },
        { id = 'SMOG', label = 'Smog' },
        { id = 'FOGGY', label = 'Foggy' },
        { id = 'CLEARING', label = 'Clearing' },
        { id = 'RAIN', label = 'Rain' },
        { id = 'THUNDER', label = 'Thunder' },
        { id = 'SNOWLIGHT', label = 'Light snow' },
        { id = 'SNOW', label = 'Snow' },
        { id = 'BLIZZARD', label = 'Blizzard' },
        { id = 'XMAS', label = 'Christmas' },
    },
}
