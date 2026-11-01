-- Core configuration. Values marked (phase N) are read once that phase ships.
-- Anything secret (webhooks, API keys) must NOT go here: this file is sent to clients.

---@class TFCConfig
TFC.Config = {
    ---Maximum characters per player. Hard cap is 10.
    MaxCharacters = 10,

    ---Seconds between batched saves of changed characters.
    SaveInterval = 300,

    ---Identifiers stored and linked to the user besides the license (the primary key).
    ---None are required to join.
    LinkedIdentifiers = { 'discord', 'fivem' },

    ---Development only: with no multichar module running, load the player's first
    ---character automatically (creating DevCharacter if they have none).
    ---Set to false once tfc-multichar is installed.
    AutoLoadCharacter = true,
    DevCharacter = { firstname = 'Dev', lastname = 'Tester' },

    ---Where characters with no saved position appear (LSIA arrivals).
    DefaultSpawn = { x = -1037.74, y = -2737.84, z = 20.17, w = 327.0 },

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
