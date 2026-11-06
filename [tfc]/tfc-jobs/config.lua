JobsConfig = {
    ---Job every new character starts with, and the one people go back to when fired.
    DefaultJob = 'unemployed',

    ---Paychecks are paid on the clock every this many minutes (server time): 15 = HH:00, HH:15,
    ---HH:30, HH:45. Every loaded character gets their rank's pay into their bank, on or off duty,
    ---employed or not. Use a number that divides 60 (5, 10, 15, 20, 30, 60).
    PaycheckMinutes = 15,

    ---true = only pay duty jobs (police, EMS, clerk...) while on duty. false = pay everyone, always.
    PayOnDutyOnly = false,

    ---Bosses can set each rank's pay within the job's payRange (or this default).
    DefaultPayRange = { min = 0, max = 1000 },

    ---Job menu (police, EMS actions on the closest player): default key and reach in metres.
    JobMenu = { Key = 'F6', Distance = 3.0 },

    ---Boss Menu: chat command, how close a player must be to be hired (metres),
    ---how many ranks a job may have, and how many log entries to show.
    BossMenu = {
        Command = 'bossmenu',
        HireDistance = 5.0,
        MaxRanks = 20,
        LogEntries = 50,
    },

    ---Jobs. Grades start at 0 and go up; the highest number is the most senior.
    ---  label        shown on the HUD and in messages
    ---  noDuty       job has no duty toggle (always counts as working)
    ---  dutyCheck    resource whose CanGoOnDuty(src, job) export must allow clocking in
    ---  payRange     { min, max } a boss may set any rank's pay to (default: DefaultPayRange)
    ---  public       anyone can sign up at the Government Center (starts at rank 0)
    ---  description  shown on the Government Center job board
    ---  grades[n]    { label, pay (per paycheck), boss = true lets them use the Boss Menu }
    ---
    ---IMPORTANT: grades here only seed the database the first time a job is seen.
    ---After that, ranks are edited in the Boss Menu (admins) and stored in tfc_job_grades.
    ---Use the console command `resetranks <job>` to re-seed a job from this file.
    Jobs = {
        unemployed = {
            label = 'Unemployed',
            noDuty = true,
            grades = {
                [0] = { label = 'Unemployed', pay = 50 },
            },
        },

        police = {
            label = 'LSPD',
            payRange = { min = 200, max = 1200 },
            grades = {
                [0] = { label = 'Cadet', pay = 300 },
                [1] = { label = 'Officer', pay = 400 },
                [2] = { label = 'Sergeant', pay = 500 },
                [3] = { label = 'Lieutenant', pay = 600 },
                [4] = { label = 'Captain', pay = 700, boss = true },
                [5] = { label = 'Chief of Police', pay = 850, boss = true },
            },
        },

        ambulance = {
            label = 'EMS',
            payRange = { min = 200, max = 1200 },
            grades = {
                [0] = { label = 'Trainee', pay = 300 },
                [1] = { label = 'EMT', pay = 400 },
                [2] = { label = 'Paramedic', pay = 500 },
                [3] = { label = 'Doctor', pay = 650 },
                [4] = { label = 'Chief of Medicine', pay = 800, boss = true },
            },
        },

        mechanic = {
            label = 'Mechanic',
            public = true, -- players can sign up at the Government Center (tfc-government)
            description = 'Repair and tow vehicles. On duty you get NPC breakdown calls to repair or tow; bill players for your work.',
            payRange = { min = 100, max = 800 },
            grades = {
                [0] = { label = 'Apprentice', pay = 200 },
                [1] = { label = 'Mechanic', pay = 300 },
                [2] = { label = 'Lead Mechanic', pay = 400 },
                [3] = { label = 'Owner', pay = 500, boss = true },
            },
        },

        clerk = {
            label = 'Convenience Store Clerk',
            public = true,
            description = 'Run the counter at any 24/7 store that is not privately owned. Clock in at the store.',
            dutyCheck = 'tfc-civjobs', -- going on duty is only allowed at a store (checked by tfc-civjobs)
            payRange = { min = 100, max = 500 },
            grades = {
                [0] = { label = 'Clerk', pay = 150 },
                [1] = { label = 'Senior Clerk', pay = 200 },
                [2] = { label = 'Shift Supervisor', pay = 250, boss = true },
            },
        },

        garbage = {
            label = 'LS Sanitation',
            public = true,
            description = 'Drive a garbage truck route and empty dumpsters around the city. Clock in at the depot.',
            dutyCheck = 'tfc-civjobs',
            payRange = { min = 100, max = 500 },
            grades = {
                [0] = { label = 'Collector', pay = 150 },
                [1] = { label = 'Driver', pay = 200 },
                [2] = { label = 'Supervisor', pay = 250, boss = true },
            },
        },

        delivery = {
            label = 'GoPostal',
            public = true,
            description = 'Load the van at the depot and deliver packages to stores around the city. Clock in at the depot.',
            dutyCheck = 'tfc-civjobs',
            payRange = { min = 100, max = 500 },
            grades = {
                [0] = { label = 'Courier', pay = 150 },
                [1] = { label = 'Senior Courier', pay = 200 },
                [2] = { label = 'Route Manager', pay = 250, boss = true },
            },
        },

        taxi = {
            label = 'Downtown Cab Co.',
            public = true,
            description = 'Drive people around the city. On duty: F6 > Find a fare for NPC passengers; bill player fares.',
            payRange = { min = 100, max = 500 },
            grades = {
                [0] = { label = 'Driver', pay = 150 },
                [1] = { label = 'Senior Driver', pay = 225 },
                [2] = { label = 'Manager', pay = 300, boss = true },
            },
        },
    },
}
