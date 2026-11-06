-- Banking server: bank/ATM sessions, cash in and out, transfers, history, credit, PINs,
-- weekly credit interest, and department/business ("society") accounts.
--
-- Exports (server):
--   GetSociety(name) -> balance             AddSociety(name, amount, reason) -> ok, balance
--   RemoveSociety(name, amount, reason) -> ok, balance
--   GetSocietyHistory(name, limit?) -> { amount, balance, reason, at }[]
-- Server hooks: societyChanged(name, balance, delta, reason)

local Cfg = BankingConfig
local ACC = 'tfc-accounts'

BankSrv = {}

---@type table<integer, { kind: string, label: string, x?: number, y?: number, z?: number, pinOk?: boolean }>
local sessions = {}
---@type table<integer, { fails: integer, lockedUntil: integer }>
local pinFails = {}

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `tfc_society_accounts` (
        `name`       VARCHAR(32) NOT NULL,
        `balance`    BIGINT      NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_society_transactions` (
        `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        `name`       VARCHAR(32)     NOT NULL,
        `amount`     BIGINT          NOT NULL,
        `balance`    BIGINT          NOT NULL,
        `reason`     VARCHAR(128)    NOT NULL DEFAULT '',
        `created_at` TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_society_transactions_name` (`name`, `created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- Helpers ------------------------------------------------------------------------------------

local function notify(src, text, kind)
    TFC.UI.Notify(src, { title = 'Bank', description = text, type = kind or 'inform' })
end

local function fail(err) return { ok = false, error = err } end

function BankSrv.fail(err) return fail(err) end
function BankSrv.notify(src, text, kind) notify(src, text, kind) end

local function amountOf(v, max)
    local n = math.tointeger(tonumber(v))
    if not n or n < 1 or n > (max or 1000000000) then return nil end
    return n
end
BankSrv.amountOf = amountOf

local function clean(text, max)
    if type(text) ~= 'string' then return '' end
    return (text:gsub('<[^>]*>', ''):gsub('[%c<>]', ''):match('^%s*(.-)%s*$')):sub(1, max or 100)
end
BankSrv.clean = clean

local function coords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function distTo(src, x, y, z)
    local c = coords(src)
    if not c then return math.huge end
    local dx, dy, dz = c.x - x, c.y - y, c.z - z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function acc() return exports[ACC] end

local function creditLimit()
    local types = acc():GetAccountTypes() or {}
    return types.credit and -(types.credit.min or 0) or 0
end

local function name(src)
    local p = TFC.GetPlayer(src)
    return p and p:GetFullName() or GetPlayerName(src) or tostring(src)
end
BankSrv.name = name

---Pay `amount` from bank, and what the bank can't cover from credit (up to its limit).
---@return boolean ok, string|nil paidFrom
function BankSrv.payFromBank(src, amount, reason)
    local a = acc()
    if a:RemoveMoney(src, 'bank', amount, reason) then return true, 'bank' end
    local have = math.max(0, math.tointeger((a:GetBalance(src, 'bank'))) or 0)
    local part = math.min(have, amount)
    local rest = amount - part
    if not a:RemoveMoney(src, 'credit', rest, reason) then return false end
    if part > 0 and not a:RemoveMoney(src, 'bank', part, reason) then
        a:AddMoney(src, 'credit', rest, 'Refund: ' .. reason)
        return false
    end
    return true, part > 0 and 'bank and credit' or 'credit'
end

-- Society (department / business) accounts ----------------------------------------------------

local function GetSociety(society)
    if type(society) ~= 'string' then return 0 end
    return math.tointeger((MySQL.scalar.await('SELECT balance FROM tfc_society_accounts WHERE name = ?', { society }))) or 0
end

---@return boolean ok, integer|string balanceOrError
local function changeSociety(society, delta, reason)
    if type(society) ~= 'string' or not society:match('^[%w_%-:]+$') or #society > 32 then return false, 'invalid account' end
    reason = clean(reason, 128)
    if delta > 0 then
        MySQL.update.await('INSERT INTO tfc_society_accounts (name, balance) VALUES (?, ?) ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)',
            { society, delta })
    else
        local n = MySQL.update.await('UPDATE tfc_society_accounts SET balance = balance + ? WHERE name = ? AND balance + ? >= 0',
            { delta, society, delta })
        if (n or 0) < 1 then return false, 'not enough money in the account' end
    end
    local balance = GetSociety(society)
    MySQL.insert('INSERT INTO tfc_society_transactions (name, amount, balance, reason) VALUES (?, ?, ?, ?)', { society, delta, balance, reason })
    TFC.Emit('societyChanged', society, balance, delta, reason)
    return true, balance
end

local function AddSociety(society, amount, reason)
    local n = amountOf(amount)
    if not n then return false, 'invalid amount' end
    return changeSociety(society, n, reason or '')
end

local function RemoveSociety(society, amount, reason)
    local n = amountOf(amount)
    if not n then return false, 'invalid amount' end
    return changeSociety(society, -n, reason or '')
end

---Newest first: { amount, balance, reason, at }
local function GetSocietyHistory(society, limit)
    local rows = MySQL.query.await('SELECT amount, balance, reason, UNIX_TIMESTAMP(created_at) AS at FROM tfc_society_transactions WHERE name = ? ORDER BY id DESC LIMIT ?',
        { society, math.min(100, math.tointeger(tonumber(limit)) or 20) }) or {}
    for _, r in ipairs(rows) do
        r.amount, r.balance, r.at = math.tointeger(r.amount), math.tointeger(r.balance), math.tointeger(r.at)
    end
    return rows
end

BankSrv.AddSociety = AddSociety

---Is the player standing at a bank teller?
exports('IsNearBank', function(src)
    for _, bank in ipairs(Cfg.Banks) do
        if distTo(src, bank.coords.x, bank.coords.y, bank.coords.z) <= Cfg.BankDistance + 3.0 then return true end
    end
    return false
end)

exports('GetCreditTerms', function()
    local last = GetResourceKvpInt('lastInterest') or 0
    return { rate = Cfg.CreditInterest.rate, everyDays = Cfg.CreditInterest.everyDays, limit = creditLimit(),
        nextAt = last > 0 and (last + Cfg.CreditInterest.everyDays * 86400) or nil }
end)
exports('GetSocietyHistory', GetSocietyHistory)
exports('GetSociety', GetSociety)
exports('AddSociety', AddSociety)
exports('RemoveSociety', RemoveSociety)

-- PIN ------------------------------------------------------------------------------------------

local function pinHash(src, pin)
    local p = TFC.GetPlayer(src)
    return tostring(GetHashKey(('tfc-pin:%s:%s'):format(p and p.cid or '?', pin)))
end

local function hasPin(src)
    local p = TFC.GetPlayer(src)
    return p ~= nil and (p:GetMetadata('bankPin')) ~= nil
end

local function validPin(pin)
    return type(pin) == 'string' and pin:match('^%d%d%d%d$') ~= nil
end

-- Sessions ---------------------------------------------------------------------------------------

---Re-check the player is still at the bank / ATM they opened.
---@param need 'bank'|'cash'|nil  'bank' = branch only; 'cash' = branch or unlocked ATM
local function checkSession(src, need)
    local s = sessions[src]
    if not s then return 'open the bank first' end
    if s.kind == 'bills' then
        if need then return 'you need to be at a bank' end
        return nil
    end
    local range = (s.kind == 'bank' and Cfg.BankDistance or Cfg.AtmDistance) + 3.0
    if distTo(src, s.x, s.y, s.z) > range then return 'you walked away from the ' .. (s.kind == 'bank' and 'bank' or 'ATM') end
    if s.kind == 'atm' and not s.pinOk then return 'enter your PIN first' end
    if need == 'bank' and s.kind ~= 'bank' then return 'only at a bank branch' end
    return nil
end

local function summary(src)
    local p = TFC.GetPlayer(src)
    local pending = 0
    if p then
        pending = math.tointeger((MySQL.scalar.await("SELECT COUNT(*) FROM tfc_bills WHERE character_id = ? AND status = 'pending'",
            { p.characterId }))) or 0
    end
    return { balances = acc():GetBalances(src) or {}, billsPending = pending }
end
BankSrv.summary = summary

local function history(src, page)
    local p = TFC.GetPlayer(src)
    if not p then return {} end
    page = math.max(1, math.tointeger(tonumber(page)) or 1)
    local rows = MySQL.query.await(
        'SELECT account, amount, balance, reason, UNIX_TIMESTAMP(created_at) AS at FROM tfc_transactions WHERE character_id = ? ORDER BY id DESC LIMIT ? OFFSET ?',
        { p.characterId, Cfg.HistoryPageSize + 1, (page - 1) * Cfg.HistoryPageSize }) or {}
    local more = #rows > Cfg.HistoryPageSize
    if more then rows[#rows] = nil end
    for _, r in ipairs(rows) do
        r.amount, r.balance, r.at = math.tointeger(r.amount), math.tointeger(r.balance), math.tointeger(r.at)
    end
    return { rows = rows, page = page, more = more }
end

local function interestInfo()
    local last = tonumber(GetResourceKvpInt('lastInterest')) or 0
    local nextAt = last > 0 and (last + Cfg.CreditInterest.everyDays * 86400) or nil
    return { rate = Cfg.CreditInterest.rate, everyDays = Cfg.CreditInterest.everyDays, nextAt = nextAt }
end

local function openData(src, s)
    local d = summary(src)
    d.ok = true
    d.kind = s.kind
    d.label = s.label
    d.name = name(src)
    d.hasPin = hasPin(src)
    d.creditLimit = creditLimit()
    d.interest = interestInfo()
    d.maxTransfer = Cfg.MaxTransfer
    d.finance = s.kind == 'bank' and GetResourceState('tfc-finance') == 'started'
    if s.kind ~= 'atm' then
        d.history = history(src, 1)
        d.bills = BankSrv.bills(src)
    end
    return d
end

TFC.Callback.Register('banking:open', function(src, kind, where)
    if not TFC.GetPlayer(src) then return fail('no character loaded') end
    if kind == 'bank' then
        local bank = Cfg.Banks[math.tointeger(tonumber(where)) or -1]
        if not bank then return fail('unknown bank') end
        if distTo(src, bank.coords.x, bank.coords.y, bank.coords.z) > Cfg.BankDistance + 2.0 then return fail('you are too far from the teller') end
        sessions[src] = { kind = 'bank', label = bank.label, x = bank.coords.x, y = bank.coords.y, z = bank.coords.z }
    elseif kind == 'atm' then
        if type(where) ~= 'table' or not tonumber(where.x) or not tonumber(where.y) or not tonumber(where.z) then return fail('no ATM') end
        if distTo(src, where.x, where.y, where.z) > Cfg.AtmDistance + 2.0 then return fail('you are too far from the ATM') end
        if not hasPin(src) then return fail('set up a PIN at any bank branch before using ATMs') end
        sessions[src] = { kind = 'atm', label = 'ATM', x = where.x + 0.0, y = where.y + 0.0, z = where.z + 0.0, pinOk = false }
    elseif kind == 'bills' then
        sessions[src] = { kind = 'bills', label = 'Bills' }
    else
        return fail('unknown')
    end
    return openData(src, sessions[src])
end, { rateLimit = 500 })

TFC.Callback.Register('banking:close', function(src)
    sessions[src] = nil
    return { ok = true }
end, { rateLimit = 100 })

-- Actions -------------------------------------------------------------------------------------------

local Actions = {}
BankSrv.Actions = Actions

function Actions.pin(src, d)
    local s = sessions[src]
    if not s or s.kind ~= 'atm' then return fail('no ATM open') end
    local lock = pinFails[src]
    if lock and lock.lockedUntil > os.time() then
        return fail(('too many wrong PINs; try again in %d min'):format(math.ceil((lock.lockedUntil - os.time()) / 60)))
    end
    if not validPin(d.pin) then return fail('enter 4 digits') end
    local p = TFC.GetPlayer(src)
    if (p:GetMetadata('bankPin')) ~= pinHash(src, d.pin) then
        lock = lock or { fails = 0, lockedUntil = 0 }
        lock.fails = lock.fails + 1
        pinFails[src] = lock
        if lock.fails >= Cfg.Pin.attempts then
            lock.fails = 0
            lock.lockedUntil = os.time() + Cfg.Pin.lockMinutes * 60
            sessions[src] = nil
            return fail(('wrong PIN. ATMs are locked for %d minutes'):format(Cfg.Pin.lockMinutes))
        end
        return fail(('wrong PIN (%d tries left)'):format(Cfg.Pin.attempts - lock.fails))
    end
    pinFails[src] = nil
    s.pinOk = true
    return { ok = true }
end

function Actions.setPin(src, d)
    local why = checkSession(src, 'bank')
    if why then return fail(why) end
    if not validPin(d.new) then return fail('the new PIN must be 4 digits') end
    local p = TFC.GetPlayer(src)
    if hasPin(src) and (p:GetMetadata('bankPin')) ~= pinHash(src, tostring(d.old or '')) then
        return fail('your current PIN is wrong')
    end
    p:SetMetadata('bankPin', pinHash(src, d.new))
    pinFails[src] = nil
    return { ok = true, message = 'PIN saved. You can now use any ATM.', hasPin = true }
end

function Actions.deposit(src, d)
    local why = checkSession(src, 'cash')
    if why then return fail(why) end
    local n = amountOf(d.amount)
    if not n then return fail('enter an amount') end
    local ok, err = acc():Transfer(src, 'cash', 'bank', n, 'Deposit')
    if not ok then return fail(err == 'not enough cash' and err or ('could not deposit: %s'):format(tostring(err))) end
    return { ok = true, message = ('Deposited $%d'):format(n) }
end

function Actions.withdraw(src, d)
    local why = checkSession(src, 'cash')
    if why then return fail(why) end
    local n = amountOf(d.amount)
    if not n then return fail('enter an amount') end
    local ok, err = acc():Transfer(src, 'bank', 'cash', n, 'Withdrawal')
    if not ok then
        err = tostring(err)
        return fail(err:find('not enough') and 'not enough in your bank' or err)
    end
    return { ok = true, message = ('Withdrew $%d'):format(n) }
end

function Actions.lookup(src, d)
    local why = checkSession(src, 'bank')
    if why then return fail(why) end
    local target = math.tointeger(tonumber(d.id))
    if not target or not TFC.GetPlayer(target) then return fail('no player with that ID is online') end
    if target == src then return fail('that\'s you') end
    return { ok = true, id = target, name = name(target) }
end

function Actions.transfer(src, d)
    local why = checkSession(src, 'bank')
    if why then return fail(why) end
    local target = math.tointeger(tonumber(d.id))
    if not target or not TFC.GetPlayer(target) then return fail('no player with that ID is online') end
    if target == src then return fail('you can\'t send money to yourself') end
    local n = amountOf(d.amount, Cfg.MaxTransfer)
    if not n then return fail(('amount must be $1 to $%d'):format(Cfg.MaxTransfer)) end
    local note = clean(d.note, 60)

    local fromReason = ('Transfer to %s%s'):format(name(target), note ~= '' and (': ' .. note) or '')
    local toReason = ('Transfer from %s%s'):format(name(src), note ~= '' and (': ' .. note) or '')
    local a = acc()
    local ok = a:RemoveMoney(src, 'bank', n, fromReason)
    if not ok then return fail('not enough in your bank') end
    if not a:AddMoney(target, 'bank', n, toReason) then
        a:AddMoney(src, 'bank', n, 'Refund: ' .. fromReason)
        return fail('the transfer failed; you were refunded')
    end
    notify(target, ('%s sent you $%d%s'):format(name(src), n, note ~= '' and (': ' .. note) or ''), 'success')
    TFC.Log.Info('%s (%d) sent $%d to %s (%d)', name(src), src, n, name(target), target)
    return { ok = true, message = ('Sent $%d to %s'):format(n, name(target)) }
end

function Actions.history(src, d)
    local why = checkSession(src, nil)
    if why then return fail(why) end
    local r = history(src, d.page)
    r.ok = true
    return r
end

function Actions.repay(src, d)
    local why = checkSession(src, 'bank')
    if why then return fail(why) end
    local owed = -(math.tointeger((acc():GetBalance(src, 'credit'))) or 0)
    if owed <= 0 then return fail('you don\'t owe anything') end
    local n
    if d.amount == 'all' then
        -- As much as the bank can cover.
        n = math.min(owed, math.max(0, math.tointeger((acc():GetBalance(src, 'bank'))) or 0))
        if n <= 0 then return fail('your bank is empty') end
    else
        n = amountOf(d.amount)
    end
    if not n then return fail('enter an amount') end
    n = math.min(n, owed)
    local ok, err = acc():RepayCredit(src, n)
    if not ok then return fail(err == 'not enough bank' and 'not enough in your bank' or tostring(err)) end
    return { ok = true, message = ('Repaid $%d of credit'):format(n) }
end

TFC.Callback.Register('banking:action', function(src, action, d)
    local fn = type(action) == 'string' and Actions[action]
    if not fn then return fail('unknown action') end
    local r = fn(src, type(d) == 'table' and d or {})
    local s = summary(src)
    r.balances, r.billsPending = s.balances, s.billsPending
    return r
end, { rateLimit = 200 })

-- Weekly credit interest ----------------------------------------------------------------------------

local function interestTick()
    local now = os.time()
    local last = GetResourceKvpInt('lastInterest')
    if not last or last == 0 then
        SetResourceKvpInt('lastInterest', now) -- first charge one period after install
        return
    end
    if now - last < Cfg.CreditInterest.everyDays * 86400 then return end
    SetResourceKvpInt('lastInterest', now)
    local n = acc():ApplyCreditInterest(Cfg.CreditInterest.rate,
        ('Credit interest (%g%%)'):format(Cfg.CreditInterest.rate * 100))
    TFC.Log.Info('credit interest charged to %d character(s)', n or 0)
end
BankSrv.interestTick = interestTick

-- Lifecycle -------------------------------------------------------------------------------------------

TFC.On('playerUnloaded', function(src)
    sessions[src] = nil
end)

-- Started from server/billing.lua (loaded last) so every part is defined first.
function BankSrv.start()
    while not exports['tfc-core']:IsDatabaseReady() do Wait(250) end
    for _, q in ipairs(SCHEMA) do MySQL.query.await(q) end
    BankSrv.createBillTable()
    TFC.RegisterModule({ name = 'banking', version = '0.1.0' }, function()
        TFC.Log.Info('banking ready: %d banks, credit interest %g%% every %d days', #Cfg.Banks,
            Cfg.CreditInterest.rate * 100, Cfg.CreditInterest.everyDays)
    end)
    while true do
        local ok, err = pcall(interestTick)
        if not ok then TFC.Log.Error('credit interest failed: %s', tostring(err)) end
        Wait(3600000)
    end
end
