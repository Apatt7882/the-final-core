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
}
