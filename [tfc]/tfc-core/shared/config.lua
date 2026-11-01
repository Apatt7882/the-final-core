-- Core configuration. Values marked (phase N) are read once that phase ships.
-- Anything secret (webhooks, API keys) must NOT go here: this file is sent to clients.

---@class TFCConfig
TFC.Config = {
    ---Maximum characters per player (phase 3). Hard cap is 10.
    MaxCharacters = 10,

    ---Seconds between batched saves of changed player data (phase 2).
    SaveInterval = 300,

    ---Accounts every character starts with (phase 4). Modules can register more.
    DefaultAccounts = {
        cash = 500,
        bank = 5000,
        credit = 0,
    },
}

-- Debug logging and callback timeouts are convars so every resource can read them:
--   setr tfc_debug 1                 -- verbose logs on server and clients
--   setr tfc_callback_timeout 10000  -- ms before a callback gives up
