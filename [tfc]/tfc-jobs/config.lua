JobsConfig = {
    ---Job every new character starts with, and the one people go back to when fired.
    DefaultJob = 'unemployed',

    ---Minutes of (on-duty) time between paychecks. Paid into the bank by the government.
    PaycheckMinutes = 15,

    ---Pay people in duty jobs while they're off duty? Usually false.
    PayOffDuty = false,

    ---Jobs. Grades start at 0 and go up; the highest number is the most senior.
    ---  label        shown on the HUD and in messages
    ---  noDuty       job has no duty toggle (always counts as working)
    ---  grades[n]    { label, pay (per paycheck), boss = true lets them hire/fire/promote }
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
            grades = {
                [0] = { label = 'Apprentice', pay = 200 },
                [1] = { label = 'Mechanic', pay = 300 },
                [2] = { label = 'Lead Mechanic', pay = 400 },
                [3] = { label = 'Owner', pay = 500, boss = true },
            },
        },

        taxi = {
            label = 'Downtown Cab Co.',
            grades = {
                [0] = { label = 'Driver', pay = 150 },
                [1] = { label = 'Senior Driver', pay = 225 },
                [2] = { label = 'Manager', pay = 300, boss = true },
            },
        },
    },
}
