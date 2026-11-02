JobsConfig = {
    ---Job every new character starts with, and the one people go back to when fired.
    DefaultJob = 'unemployed',

    ---Minutes of (on-duty) time between paychecks. Paid into the bank by the government.
    PaycheckMinutes = 15,

    ---Pay people in duty jobs while they're off duty? Usually false.
    PayOffDuty = false,

    ---Bosses can set each rank's pay within the job's payRange (or this default).
    DefaultPayRange = { min = 0, max = 1000 },

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
    ---  payRange     { min, max } a boss may set any rank's pay to (default: DefaultPayRange)
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
            payRange = { min = 100, max = 800 },
            grades = {
                [0] = { label = 'Apprentice', pay = 200 },
                [1] = { label = 'Mechanic', pay = 300 },
                [2] = { label = 'Lead Mechanic', pay = 400 },
                [3] = { label = 'Owner', pay = 500, boss = true },
            },
        },

        taxi = {
            label = 'Downtown Cab Co.',
            payRange = { min = 100, max = 500 },
            grades = {
                [0] = { label = 'Driver', pay = 150 },
                [1] = { label = 'Senior Driver', pay = 225 },
                [2] = { label = 'Manager', pay = 300, boss = true },
            },
        },
    },
}
