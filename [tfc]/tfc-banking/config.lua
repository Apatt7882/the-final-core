-- Banking: bank branches (full bank), ATMs (cash and balance, PIN needed), transfers to online
-- players, bills from jobs, credit with weekly interest, and department/business accounts
-- that bills and fines are paid into.

BankingConfig = {
    -- Bank tellers. Walk up and press E for the full bank.
    Banks = {
        { label = 'Fleeca Bank', coords = vector3(149.9, -1040.46, 29.37) },
        { label = 'Fleeca Bank', coords = vector3(314.23, -278.83, 54.17) },
        { label = 'Fleeca Bank', coords = vector3(-350.8, -49.57, 49.04) },
        { label = 'Fleeca Bank', coords = vector3(-1213.0, -330.39, 37.79) },
        { label = 'Fleeca Bank', coords = vector3(-2962.71, 483.0, 15.7) },
        { label = 'Fleeca Bank', coords = vector3(1175.07, 2706.41, 38.09) },
        { label = 'Pacific Standard', coords = vector3(241.73, 220.71, 106.29) },
        { label = 'Blaine County Savings', coords = vector3(-113.22, 6470.03, 31.63) },
    },
    BankDistance = 2.5,
    Blip = { sprite = 108, color = 2, scale = 0.7 },

    -- Every ATM prop in the world works. ATMs: withdraw, deposit and balance only.
    AtmModels = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' },
    AtmDistance = 1.5,

    -- ATM PIN (set at a bank branch). Wrong PIN this many times locks ATMs for a while.
    Pin = { attempts = 3, lockMinutes = 5 },

    MaxTransfer = 1000000,

    -- Weekly interest on negative credit balances (never past the credit limit).
    CreditInterest = { rate = 0.02, everyDays = 7 },

    HistoryPageSize = 25,

    Billing = {
        Command = 'bill',           -- /bill id amount reason (job members on duty)
        ListCommand = 'bills',      -- /bills: see and pay your bills anywhere
        MaxAmount = 50000,
        -- Jobs that can send bills. mandatory = the bill can't be declined.
        -- Money from paid bills goes into the job's department account.
        Jobs = {
            police = { mandatory = true },
            ambulance = { mandatory = true },
            mechanic = {},
            taxi = {},
        },
    },
}
