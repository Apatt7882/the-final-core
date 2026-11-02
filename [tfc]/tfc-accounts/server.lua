-- Accounts: every change is one conditional UPDATE, so a balance can never pass its
-- min/max even with simultaneous requests. Balances are cached per loaded player for reads.
--
-- Exports (all return ok, errorOrNewBalance unless noted):
--   GetBalance(src, account) -> number|nil          GetBalances(src) -> table|nil
--   AddMoney(src, account, amount, reason)          RemoveMoney(src, account, amount, reason)
--   SetBalance(src, account, amount, reason)        Transfer(src, from, to, amount, reason)
--   Charge(src, amount, reason, order?) -> ok, accountUsedOrError
--   RepayCredit(src, amount) (bank -> credit)       RegisterAccount(name, def)
-- Server hook: moneyChanged(source, account, balance, delta, reason)

local Accounts = AccountsConfig.Accounts
local BIG = 9007199254740991 -- 2^53 - 1, "no max"

---@type table<integer, { charId: integer, balances: table<string, integer> }>
local cache = {}
---@type table<integer, boolean>
local loadingNow = {}

local tablesReady = false
local Load -- defined below; used by the startup thread

-- Schema -------------------------------------------------------------------------

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `tfc_accounts` (
        `character_id` INT UNSIGNED NOT NULL,
        `name`         VARCHAR(32)  NOT NULL,
        `balance`      BIGINT       NOT NULL DEFAULT 0,
        `updated_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`character_id`, `name`),
        CONSTRAINT `fk_tfc_accounts_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_transactions` (
        `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        `character_id` INT UNSIGNED    NOT NULL,
        `account`      VARCHAR(32)     NOT NULL,
        `amount`       BIGINT          NOT NULL,
        `balance`      BIGINT          NOT NULL,
        `reason`       VARCHAR(128)    NOT NULL DEFAULT '',
        `created_at`   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_transactions_character` (`character_id`, `created_at`),
        CONSTRAINT `fk_tfc_transactions_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

CreateThread(function()
    -- Our tables reference tfc_characters, so wait for the core's schema first.
    while not exports['tfc-core']:IsDatabaseReady() do Wait(250) end
    for _, statement in ipairs(SCHEMA) do
        MySQL.query.await(statement)
    end
    tablesReady = true

    TFC.RegisterModule({ name = 'accounts', version = '0.1.2' }, function()
        TFC.Log.Info('accounts ready: %s', table.concat((function()
            local names = {}
            for name in pairs(Accounts) do names[#names + 1] = name end
            table.sort(names)
            return names
        end)(), ', '))
    end)

    -- Players already loaded (e.g. this resource restarted mid-session).
    for _, src in ipairs(TFC.GetPlayers()) do
        CreateThread(function() Load(src) end)
    end
end)

-- Helpers ---------------------------------------------------------------------------

---@param amount any
---@return integer|nil
local function validAmount(amount)
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount <= 0 or amount > AccountsConfig.MaxAmount then return nil end
    if math.floor(amount) ~= amount then return nil end
    return math.tointeger(amount)
end

local function bounds(account)
    local def = Accounts[account]
    return def.min or 0, def.max or BIG
end

---@param n integer
local function formatMoney(n)
    local s = ('%d'):format(math.abs(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (n < 0 and '-$' or '$') .. s
end

local function syncClient(src, entry)
    TriggerClientEvent('tfc-accounts:client:sync', src, entry.balances)
end

---Load (or create) a player's account rows into the cache.
---@param src integer
---@return table|nil entry
Load = function(src)
    src = tonumber(src) --[[@as integer]]
    if cache[src] then return cache[src] end
    if not tablesReady then return nil end

    -- Another coroutine is already loading this player: wait for it.
    if loadingNow[src] then
        local deadline = GetGameTimer() + 5000
        while loadingNow[src] and GetGameTimer() < deadline do Wait(50) end
        return cache[src]
    end

    local player = TFC.GetPlayer(src)
    if not player then return nil end
    local charId = player.characterId

    loadingNow[src] = true
    local ok, err = pcall(function()
        local inserts = {}
        for name, def in pairs(Accounts) do
            inserts[#inserts + 1] = {
                query = 'INSERT IGNORE INTO tfc_accounts (character_id, name, balance) VALUES (?, ?, ?)',
                values = { charId, name, def.default or 0 },
            }
        end
        MySQL.transaction.await(inserts)

        local balances = {}
        for _, row in ipairs(MySQL.query.await('SELECT name, balance FROM tfc_accounts WHERE character_id = ?', { charId }) or {}) do
            if Accounts[row.name] then balances[row.name] = math.tointeger(row.balance) or row.balance end
        end

        -- Still the same character? (they may have switched or left while we queried)
        local now = TFC.GetPlayer(src)
        if now and now.characterId == charId then
            cache[src] = { charId = charId, balances = balances }
        end
    end)
    loadingNow[src] = nil

    if not ok then
        TFC.Log.Error('could not load accounts for player %d: %s', src, err)
        return nil
    end

    if cache[src] then syncClient(src, cache[src]) end
    return cache[src]
end

---@param entry table
---@param src integer
---@param account string
---@param delta integer
---@param reason string
local function applied(src, entry, account, delta, reason)
    local balance = entry.balances[account] + delta
    entry.balances[account] = balance

    if AccountsConfig.LogTransactions then
        MySQL.insert('INSERT INTO tfc_transactions (character_id, account, amount, balance, reason) VALUES (?, ?, ?, ?, ?)',
            { entry.charId, account, delta, balance, reason })
    end

    TriggerClientEvent('tfc-accounts:client:changed', src, account, balance, delta, reason)
    TFC.Emit('moneyChanged', src, account, balance, delta, reason)
    return balance
end

---Atomically change a balance by delta, respecting min/max. The core of every operation.
---@return boolean ok
---@return string|integer errOrBalance
local function change(src, account, delta, reason)
    src = tonumber(src) --[[@as integer]]
    if not Accounts[account] then return false, ('unknown account "%s"'):format(tostring(account)) end

    local entry = Load(src)
    if not entry then return false, 'player has no loaded character' end

    local min, max = bounds(account)
    local affected = MySQL.update.await(
        'UPDATE tfc_accounts SET balance = balance + ? WHERE character_id = ? AND name = ? AND balance + ? >= ? AND balance + ? <= ?',
        { delta, entry.charId, account, delta, min, delta, max })

    if (affected or 0) < 1 then
        if delta < 0 then return false, ('not enough %s'):format(Accounts[account].label:lower()) end
        return false, ('%s limit reached'):format(Accounts[account].label:lower())
    end

    -- The player may have switched character while we waited; don't touch the new cache.
    if cache[src] ~= entry then return true, entry.balances[account] + delta end

    return true, applied(src, entry, account, delta, reason)
end

local function cleanReason(reason)
    reason = type(reason) == 'string' and reason or ''
    return reason:sub(1, 128)
end

-- API -------------------------------------------------------------------------------

---@return integer|nil
local function GetBalance(src, account)
    local entry = Load(src)
    return entry and entry.balances[account] or nil
end

---@return table<string, integer>|nil
local function GetBalances(src)
    local entry = Load(src)
    if not entry then return nil end
    local copy = {}
    for k, v in pairs(entry.balances) do copy[k] = v end
    return copy
end

local function AddMoney(src, account, amount, reason)
    local n = validAmount(amount)
    if not n then return false, 'amount must be a whole number above 0' end
    return change(src, account, n, cleanReason(reason))
end

local function RemoveMoney(src, account, amount, reason)
    local n = validAmount(amount)
    if not n then return false, 'amount must be a whole number above 0' end
    return change(src, account, -n, cleanReason(reason))
end

local function SetBalance(src, account, amount, reason)
    amount = tonumber(amount)
    if not amount or math.floor(amount) ~= amount then return false, 'amount must be a whole number' end
    local current = GetBalance(src, account)
    if not current then return false, 'unknown account or no loaded character' end

    local delta = math.tointeger(amount) - current
    if delta == 0 then return true, current end
    return change(src, account, delta, cleanReason(reason or 'set by admin'))
end

---Move money between two of this player's own accounts.
local function Transfer(src, from, to, amount, reason)
    if from == to then return false, 'choose two different accounts' end
    if not Accounts[from] or not Accounts[to] then return false, 'unknown account' end

    local n = validAmount(amount)
    if not n then return false, 'amount must be a whole number above 0' end
    reason = cleanReason(reason or ('transfer %s -> %s'):format(from, to))

    local ok, err = change(src, from, -n, reason)
    if not ok then return false, err end

    local ok2, err2 = change(src, to, n, reason)
    if not ok2 then
        change(src, from, n, 'refund: ' .. reason)
        return false, err2
    end
    return true, err2
end

---Pay from the first account that can cover the whole amount.
---@return boolean ok
---@return string accountOrError
local function Charge(src, amount, reason, order)
    local n = validAmount(amount)
    if not n then return false, 'amount must be a whole number above 0' end

    for _, account in ipairs(order or AccountsConfig.ChargeOrder) do
        if Accounts[account] and change(src, account, -n, cleanReason(reason)) then
            return true, account
        end
    end
    return false, 'not enough money'
end

---Pay down a negative credit balance from the bank.
local function RepayCredit(src, amount)
    local owed = GetBalance(src, 'credit')
    if not owed then return false, 'no credit account' end
    if owed >= 0 then return false, 'nothing to repay' end

    local n = validAmount(amount) or -owed
    n = math.min(n, -owed)
    return Transfer(src, 'bank', 'credit', n, 'credit repayment')
end

---Add an account type at runtime (e.g. from another module). Loaded players get it on next load.
---@param name string
---@param def { label: string, default?: integer, min?: integer, max?: integer }
local function RegisterAccount(name, def)
    if type(name) ~= 'string' or not name:match('^[%w_]+$') or #name > 32 then return false, 'invalid account name' end
    if type(def) ~= 'table' or type(def.label) ~= 'string' then return false, 'account needs a label' end
    Accounts[name] = { label = def.label, default = def.default or 0, min = def.min or 0, max = def.max }
    return true
end

exports('GetBalance', GetBalance)
exports('GetBalances', GetBalances)
exports('AddMoney', AddMoney)
exports('RemoveMoney', RemoveMoney)
exports('SetBalance', SetBalance)
exports('Transfer', Transfer)
exports('Charge', Charge)
exports('RepayCredit', RepayCredit)
exports('RegisterAccount', RegisterAccount)
exports('GetAccountTypes', function() return Accounts end)

-- Lifecycle --------------------------------------------------------------------------

TFC.On('playerLoaded', function(src)
    CreateThread(function() Load(src) end)
end)

TFC.On('playerUnloaded', function(src)
    cache[src] = nil
end)

-- Commands --------------------------------------------------------------------------------

local ACCOUNT_HELP = 'cash, bank or credit'

local function reply(src, ok, msg)
    if src == 0 then
        TFC.Log.Info(msg)
    else
        TFC.UI.Notify(src, { title = 'Money', description = msg, type = ok and 'success' or 'error' })
    end
end

TFC.RegisterCommand('money', { help = 'Show your cash, bank and credit balances' }, function(src)
    if src == 0 then return end
    local b = GetBalances(src)
    if not b then return end
    local parts = {}
    for _, name in ipairs({ 'cash', 'bank', 'credit' }) do
        if b[name] then parts[#parts + 1] = ('%s %s'):format(Accounts[name].label, formatMoney(b[name])) end
    end
    TFC.UI.Notify(src, { title = 'Balances', description = table.concat(parts, '  |  '), type = 'inform' })
end)

TFC.RegisterCommand('repaycredit', {
    help = 'Pay back credit from your bank account',
    params = { { name = 'amount', help = 'Whole dollars; leave empty to repay everything', optional = true } },
}, function(src, args)
    if src == 0 then return end
    local ok, result = RepayCredit(src, args[1])
    if not ok then TFC.UI.Notify(src, { title = 'Credit', description = result, type = 'error' }) end
end)

---@param verb 'give'|'take'|'set'
local function adminMoney(verb)
    return function(src, args)
        local target = TFC.ResolveTarget(src, args[1])
        if not target then return reply(src, false, ('no player with ID %s is online'):format(tostring(args[1]))) end

        local account, amount = args[2], args[3]
        if not Accounts[account] then return reply(src, false, ('account must be %s'):format(ACCOUNT_HELP)) end

        local reason = table.concat(args, ' ', 4)
        if reason == '' then reason = 'admin ' .. verb end

        local fn = verb == 'give' and AddMoney or verb == 'take' and RemoveMoney or SetBalance
        local ok, result = fn(target, account, amount, reason)
        if ok then
            reply(src, true, ('%s %s: now %s'):format(GetPlayerName(target) or target, Accounts[account].label:lower(), formatMoney(result)))
        else
            reply(src, false, ('failed: %s'):format(result))
        end
    end
end

local function adminParams(amountHelp)
    return {
        { name = 'id', help = 'Player server ID, or "me"' },
        { name = 'account', help = ACCOUNT_HELP },
        { name = 'amount', help = amountHelp },
        { name = 'reason', help = 'Note for the transaction log', optional = true },
    }
end

TFC.RegisterCommand('givemoney', {
    help = 'Admin: add money to a player',
    permission = TFC.Permissions.Admin,
    params = adminParams('Whole dollars to add'),
}, adminMoney('give'))

TFC.RegisterCommand('takemoney', {
    help = 'Admin: remove money from a player',
    permission = TFC.Permissions.Admin,
    params = adminParams('Whole dollars to remove'),
}, adminMoney('take'))

TFC.RegisterCommand('setmoney', {
    help = 'Admin: set a balance exactly',
    permission = TFC.Permissions.Admin,
    params = adminParams('New balance (credit can be negative)'),
}, adminMoney('set'))
