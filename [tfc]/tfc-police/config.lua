-- Police tools. Officers use them from the job menu (F6) or with chat commands; every action
-- is checked on the server (job, on duty, distance, cuffed/down).

PoliceConfig = {
    Jobs = { 'police' },          -- jobs that count as police (must be on duty)

    CuffDistance = 2.5,           -- metres between officer and suspect
    ActionDistance = 3.0,         -- escort, search, fine, jail
    VehicleDistance = 6.0,        -- seat / unseat: officer to vehicle

    MaxFine = 25000,
    FineFrom = { 'bank', 'credit' },  -- taken from these in order; credit can go to its limit

    MaxJailMinutes = 120,
    Jail = {
        -- Bolingbroke Penitentiary. Inmates are put back if they go further than `radius`.
        spawn = vector4(1691.6, 2565.9, 45.56, 180.0),
        center = vector3(1691.6, 2565.9, 45.56),
        radius = 180.0,
        -- Where they walk out when released.
        release = vector4(1846.0, 2585.8, 45.67, 270.0),
    },

    -- ShotSpotter: gunfire shows up for on-duty police after a delay, as a circle on the map
    -- (roughly where, not exactly) with semi-automatic / fully automatic, and sometimes a camera
    -- description. Suppressed guns, tasers and melee don't set it off.
    ShotSpotter = {
        Enabled = true,
        DelaySeconds = 15,          -- time between the shots and the alert
        DurationSeconds = 90,       -- how long the alert stays on the map
        CameraChance = 0.25,        -- chance a camera describes the shooter
        Radius = 90.0,              -- size of the circle on the map (metres)
        Offset = 45.0,              -- the circle's centre is up to this far from the real spot
        MergeDistance = 150.0,      -- more shots this close within MergeSeconds join the same alert
        MergeSeconds = 60,
        IgnoreOnDutyPolice = true,  -- on-duty police shooting don't trigger it
        Command = 'shotspotter',    -- sets a waypoint to the latest alert
        -- No alerts here (shooting ranges...).
        IgnoreZones = {
            { coords = vector3(13.5, -1097.5, 29.8), radius = 25.0 },    -- Ammu-Nation range, Pillbox Hill
            { coords = vector3(821.5, -2163.5, 29.6), radius = 25.0 },   -- Ammu-Nation range, Cypress Flats
        },
    },
}
