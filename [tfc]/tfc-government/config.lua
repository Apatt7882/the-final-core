-- Government Center (city info, public jobs, services) and the DMV (licenses).
-- Fees are paid into the 'government' account (tfc-banking).

GovConfig = {
    CityHall = {
        label = 'Government Center',
        coords = vector4(-545.06, -204.24, 38.22, 210.0),   -- Los Santos City Hall, Rockford Hills
        ped = 'a_f_y_business_02', scenario = 'WORLD_HUMAN_CLIPBOARD',
        blip = { sprite = 419, color = 0, scale = 0.8 },
    },
    Dmv = {
        label = 'DMV',
        coords = vector4(240.3, -1379.89, 33.74, 140.0),
        ped = 's_m_m_ciasec_01', scenario = 'WORLD_HUMAN_CLIPBOARD',
        blip = { sprite = 225, color = 3, scale = 0.75 },
    },
    InteractDistance = 2.0,

    IdCardFee = 50,          -- replacement ID card at the Government Center
    ReplacementFee = 250,    -- replacement license card (license must be valid)
    PassScore = 4,           -- quiz answers needed out of 5
    PayFrom = { 'bank', 'cash' },

    -- Licenses. quiz = name of a quiz in quizzes.lua (nil = no test, just pay).
    -- requires = another license you must hold first. card = which card it's printed on:
    --   'driver' (one Driver's License card listing all classes), 'weapon', or 'other'.
    Licenses = {
        { id = 'driver', label = "Driver's License", short = 'C', price = 500, card = 'driver',
          description = 'Cars, vans and pickups. No test needed.' },
        { id = 'motorcycle', label = 'Motorcycle Endorsement', short = 'M', price = 1000, card = 'driver', quiz = 'motorcycle', requires = 'driver',
          description = 'Motorcycles and scooters. 5-question test.' },
        { id = 'cdl', label = 'Commercial Driver License (CDL)', short = 'CDL', price = 1000, card = 'driver', quiz = 'cdl', requires = 'driver',
          description = 'Trucks, buses and heavy vehicles. 5-question test.' },
        { id = 'hazmat', label = 'Hazardous Materials Endorsement', short = 'HazMat', price = 1000, card = 'driver', quiz = 'hazmat', requires = 'cdl',
          description = 'Fuel and chemical loads. Needs a CDL. 5-question test.' },
        { id = 'weapon', label = 'Weapon Permit', price = 2500, card = 'weapon', quiz = 'weapon',
          description = 'Needed to buy firearms at Ammu-Nation. 5-question safety test.' },
        { id = 'hunting', label = 'Hunting License', price = 150, card = 'other',
          description = 'Hunt wildlife in season.' },
        { id = 'fishing', label = 'Fishing License', price = 100, card = 'other',
          description = 'Fish from shore or boat.' },
        { id = 'boat', label = 'Boating License', price = 750, card = 'other', quiz = 'boat',
          description = 'Operate boats and jet skis. 5-question test.' },
        { id = 'pilot', label = 'Pilot License', price = 5000, card = 'other', quiz = 'pilot',
          description = 'Fly helicopters and planes. 5-question test.' },
    },

    -- Who can suspend / revoke licenses (on duty), and the rank that can approve reinstatement.
    Authority = { jobs = { 'police' }, supervisorGrade = 2 },
    PoliceDistance = 5.0,
    Command = 'licenses',            -- police: check/suspend/revoke the closest player's licenses
    RequestsCommand = 'licenserequests', -- supervisors: reinstatement requests

    -- Government Center info. Edit freely.
    Info = {
        title = 'Welcome to Los Santos',
        intro = 'The Government Center is your first stop: find your way around, pick up a job and sort out your paperwork.',
        steps = {
            { title = "Get your driver's license", text = 'Visit the DMV. A basic license needs no test.', place = 'dmv' },
            { title = 'Set up your bank', text = 'Set a 4-digit ATM PIN at any bank teller so ATMs work.', place = 'bank' },
            { title = 'Find a job', text = 'Sign up for a public job on the Jobs tab. Everyone gets a paycheck every 15 minutes; a job pays more than unemployment.', tab = 'jobs' },
            { title = 'Meet the Accountant', text = 'Free advice on your money, debt and investing, right here.', action = 'accountant' },
        },
        places = {
            { id = 'dmv', label = 'DMV', coords = vector3(240.3, -1379.89, 33.74) },
            { id = 'bank', label = 'Fleeca Bank (Legion Square)', coords = vector3(149.9, -1040.46, 29.37) },
            { label = 'Pacific Standard Bank', coords = vector3(241.73, 220.71, 106.29) },
            { label = 'Pillbox Hill Medical', coords = vector3(298.6, -584.6, 43.26) },
            { label = 'Mission Row Police', coords = vector3(428.9, -984.5, 30.7) },
            { label = 'Ammu-Nation (Pillbox)', coords = vector3(23.0, -1105.67, 29.8) },
            { label = '24/7 Store (Strawberry)', coords = vector3(24.47, -1346.62, 29.5) },
        },
        faq = {
            { q = 'How do I get paid?', a = 'Every job pays a government paycheck at :00, :15, :30 and :45 while you are on duty (/duty). Type /job to see your pay.' },
            { q = 'What happens if I go down?', a = 'Press G to call EMS. If none are on duty you can respawn at the hospital for free after a minute; otherwise wait for EMS, or pay to respawn early.' },
            { q = 'How do bills work?', a = 'Bills from police, EMS and businesses show up with /bills or at any bank. Police and EMS bills can\'t be declined.' },
            { q = 'What is credit?', a = 'A $2,500 credit line used when your bank runs out. It charges 2% interest a week, so pay it back early at any bank.' },
            { q = 'My license was suspended. Now what?', a = 'Request reinstatement at the DMV. A police supervisor has to approve it; then buy a replacement card at the DMV.' },
        },
        rules = {
            'Respect other players and staff.',
            'Stay in character in public channels.',
            'No exploiting bugs: report them to staff.',
        },
    },
}
