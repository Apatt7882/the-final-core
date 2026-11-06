-- Stock market (fictional companies, prices move every few minutes) and the City Accountant
-- (advice from the player's real finances). Open at the Accountant in the Government Center,
-- or "Investing & advice" in any bank. /stocks shows the market anywhere (view only).
--
-- Optional real AI answers: put your Claude API key in server.cfg with `set` (NOT setr, which
-- would send it to every player):
--   set tfc_ai_key "sk-ant-..."
--   set tfc_ai_model "claude-haiku-5-5"     # optional; see docs.claude.com for model names
-- Without a key the Accountant still gives full built-in advice; only "Ask a question" is hidden.

FinanceConfig = {
    Accountant = {
        label = 'City Accountant',
        coords = vector4(-541.9, -207.2, 38.22, 210.0),   -- inside the Government Center
        ped = 'a_m_m_business_01', scenario = 'WORLD_HUMAN_CLIPBOARD',
    },
    InteractDistance = 2.0,
    ViewCommand = 'stocks',

    Market = {
        tickSeconds = 300,      -- prices move every 5 minutes
        historyHours = 168,     -- keep a week of history for charts
        fee = 0.01,             -- 1% per trade (min $1)
        minFee = 1,
        maxSharesPerTrade = 10000,
        eventChance = 0.10,     -- chance per tick that a news event hits one company
    },

    -- vol = how much the price swings each tick; drift = small long-run trend per tick.
    Stocks = {
        { symbol = 'LFI', name = 'Lifeinvader', sector = 'Tech', price = 120, vol = 0.030, drift = 0.0006 },
        { symbol = 'MZB', name = 'Maze Bank', sector = 'Finance', price = 85, vol = 0.015, drift = 0.0004 },
        { symbol = 'FLC', name = 'Fleeca', sector = 'Finance', price = 42, vol = 0.018, drift = 0.0003 },
        { symbol = 'AMU', name = 'Ammu-Nation', sector = 'Retail', price = 64, vol = 0.022, drift = 0.0004 },
        { symbol = 'BEAN', name = 'Bean Machine', sector = 'Food', price = 28, vol = 0.020, drift = 0.0005 },
        { symbol = 'GLB', name = 'Globe Oil', sector = 'Energy', price = 96, vol = 0.025, drift = 0.0002 },
        { symbol = 'VAP', name = 'Vapid Motors', sector = 'Autos', price = 55, vol = 0.028, drift = 0.0003 },
        { symbol = 'MWS', name = 'Merryweather', sector = 'Defense', price = 140, vol = 0.035, drift = 0.0004 },
    },

    News = {
        up = {
            '{name} beats earnings expectations',
            '{name} announces a major new contract',
            'Analysts upgrade {name} to "buy"',
            '{name} unveils a popular new product',
        },
        down = {
            '{name} misses earnings expectations',
            '{name} hit by a lawsuit',
            'Analysts downgrade {name}',
            '{name} recalls a faulty product',
        },
    },

    Advisor = {
        CashWarning = 2000,       -- warn when carrying more cash than this
        EmergencyFund = 2000,     -- suggest keeping at least this in the bank
        InvestFrom = 10000,       -- suggest investing once the bank is above this (and no debt)
    },

    AI = {
        Model = 'claude-haiku-5-5',  -- overridden by the tfc_ai_model convar
        MaxTokens = 350,
        CooldownSeconds = 20,
        DailyLimit = 30,             -- questions per player per day
    },
}
