-- Civilian jobs: things to do on shift even with nobody else online. Every finished task pays a
-- bonus into the bank on top of the normal 15-minute paycheck.
--
--   Clerk      clock in at any 24/7 that isn't privately owned: serve NPC customers, restock, mop
--   Garbage    clock in at the depot, take a truck, empty dumpsters in the areas you're sent to
--   Delivery   clock in at the depot, take a van, deliver packages to stores
--   Mechanic   on duty: NPC breakdown calls, repair on the spot or tow to the yard (needs the flatbed)
--   Taxi       on duty in a taxi: F6 > Find a fare, pick up an NPC and drive them where they ask
--
-- Places marked "(tune)" are starting points: stand where you want it, /coords, paste it here.
-- Peds and markers are put on the ground automatically, and work vehicles appear on the nearest road.

CivJobsConfig = {
    TaskKey = 38,            -- E
    MarkerDistance = 25.0,   -- task markers are drawn this close

    Clerk = {
        Job = 'clerk',
        ShopTypes = { general = true },  -- tfc-shops types a clerk can work at
        ClockInDistance = 10.0,          -- metres from the counter to clock in
        LeaveDistance = 60.0,            -- metres from the store before you get clocked out
        LeaveGraceSeconds = 30,
        HintDistance = 20.0,
        WorkDistance = 30.0,             -- tasks only come while you're this close to the counter

        -- NPC customers walk up to the counter; ring them up (a quick skill check) before they give up.
        Customers = {
            Every = { 40, 90 }, WaitSeconds = 90, Items = { 1, 4 }, MaxItemPrice = 100, Tip = { 5, 25 }, SaleCut = 0.10,
            -- Everyday things NPCs buy besides the store's own items (not real inventory items).
            Extra = {
                { label = 'Snacks', price = 6 }, { label = 'Soda', price = 3 }, { label = 'Coffee', price = 4 },
                { label = 'Cigarettes', price = 12 }, { label = 'Lottery ticket', price = 5 }, { label = 'Energy drink', price = 5 },
                { label = 'Sandwich', price = 8 }, { label = 'Gas', price = 45 }, { label = 'Phone card', price = 20 },
            },
        },
        -- Boxes from behind the counter to the shelves, paid per box.
        Restock = { Every = { 150, 300 }, Boxes = 3, PayPerBox = 40 },
        -- A spill to mop.
        Clean = { Every = { 180, 360 }, Pay = 35 },

        -- Spots inside the store, relative to where the store's clerk stands (the shop ped):
        -- forward = towards the customers, right = to the clerk's right. Every 24/7 has the same
        -- interior, so one set works for all of them. (tune)
        Points = {
            customerSpawn = { forward = 6.0, right = -1.0 },
            customerStand = { forward = 1.2, right = 0.0 },
            stockroom = { forward = 0.0, right = -1.6 },
            shelves = {
                { forward = 4.0, right = -3.0 },
                { forward = 5.0, right = 2.0 },
                { forward = 7.0, right = -1.0 },
            },
            spills = {
                { forward = 3.0, right = -1.5 },
                { forward = 4.5, right = 1.5 },
                { forward = 6.5, right = 0.0 },
                { forward = 2.5, right = 2.5 },
            },
        },
        CustomerModels = { 'a_m_y_hipster_01', 'a_f_y_hipster_02', 'a_m_m_business_01', 'a_f_m_bevhills_02', 'a_m_y_skater_01', 'a_f_y_tourist_01', 'a_m_m_tourist_01', 'a_m_y_genstreet_01' },
    },

    Garbage = {
        Job = 'garbage',
        Label = 'LS Sanitation',
        Depot = vector4(-313.84, -1522.82, 27.56, 250.0),   -- (tune)
        DepotPed = 's_m_y_garbage',
        VehicleSpot = vector4(-341.13, -1567.68, 24.97, 59.5), -- truck appears on the road nearest this (tune)
        Vehicle = 'trash',
        Blip = { sprite = 318, color = 25 },
        ClockInDistance = 15.0,
        ZonesPerRoute = 2,
        BagsPerZone = 6,
        PayPerBag = 35,
        RouteBonus = 150,
        ZoneRadius = 180.0,
        -- Areas a route can send you to (x, y). Dumpsters there are found automatically.
        Zones = {
            { label = 'Strawberry', x = 150.0, y = -1500.0 },
            { label = 'Davis', x = 40.0, y = -1750.0 },
            { label = 'Mission Row', x = 420.0, y = -1000.0 },
            { label = 'Pillbox Hill', x = 100.0, y = -800.0 },
            { label = 'Textile City', x = 400.0, y = -750.0 },
            { label = 'Little Seoul', x = -680.0, y = -900.0 },
            { label = 'Vespucci Canals', x = -1050.0, y = -1000.0 },
            { label = 'Del Perro', x = -1500.0, y = -500.0 },
            { label = 'La Mesa', x = 850.0, y = -1050.0 },
            { label = 'Mirror Park', x = 1100.0, y = -550.0 },
            { label = 'Downtown Vinewood', x = 300.0, y = 150.0 },
        },
        DumpsterModels = {
            'prop_dumpster_01a', 'prop_dumpster_02a', 'prop_dumpster_02b', 'prop_dumpster_3a', 'prop_dumpster_4a', 'prop_dumpster_4b',
            'prop_bin_05a', 'prop_bin_07a', 'prop_bin_08a', 'prop_bin_14a', 'prop_cs_dumpster_01a',
        },
    },

    Delivery = {
        Job = 'delivery',
        Label = 'GoPostal',
        Depot = vector4(69.0, 121.0, 79.2, 160.0),          -- GoPostal, Downtown Vinewood (tune)
        DepotPed = 's_m_m_postal_01',
        VehicleSpot = vector4(62.0, 105.0, 79.0, 160.0),     -- (tune)
        Vehicle = 'boxville2',
        Blip = { sprite = 478, color = 5 },
        ClockInDistance = 15.0,
        StopsPerRoute = 4,
        PayPerPackage = 60,
        RouteBonus = 150,
        -- Packages go to stores of these tfc-shops types (their counter peds sign for them).
        DeliverTo = { general = true, ammunation = true, pawn = true },
    },

    Mechanic = {
        Job = 'mechanic',
        Label = 'Hayes Autos',
        Yard = vector4(471.39, -1311.03, 29.21, 114.5),      -- tow drop-off and flatbed pickup (tune)
        VehicleSpot = vector4(480.0, -1320.0, 29.2, 300.0),  -- (tune)
        Vehicle = 'flatbed',
        Blip = { sprite = 446, color = 47 },
        CallEvery = { 90, 180 },     -- seconds between calls while on duty and free
        TowChance = 0.4,             -- share of calls that need a tow (only while you have the flatbed out)
        RepairPay = 120,
        TowPay = 250,
        CallDistance = { 300.0, 1500.0 },
        BrokenModels = { 'asea', 'premier', 'stanier', 'primo', 'emperor', 'ingot', 'tailgater', 'washington', 'dilettante', 'blista', 'panto', 'rhapsody' },
    },

    Taxi = {
        Job = 'taxi',
        Label = 'Downtown Cab Co.',
        Depot = vector4(903.3, -170.5, 74.07, 238.0),        -- (tune)
        VehicleSpot = vector4(915.0, -163.0, 74.5, 195.0),   -- (tune)
        Vehicle = 'taxi',
        Blip = { sprite = 198, color = 5 },
        TaxiModels = { 'taxi' },                -- vehicles that count as a taxi for NPC fares
        PickupDistance = { 200.0, 700.0 },
        TripDistance = { 700.0, 3000.0 },
        FareBase = 20,
        FarePerKm = 70,
        TipPercent = { 0, 15 },
        PassengerModels = { 'a_m_y_business_01', 'a_f_y_business_02', 'a_m_m_bevhills_01', 'a_f_y_vinewood_01', 'a_m_y_hipster_02', 'a_f_m_tourist_01', 'a_m_m_genfat_01', 'a_f_y_eastsa_03' },
    },
}
