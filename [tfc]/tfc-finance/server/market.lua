-- Stock market: fictional companies whose prices move every few minutes (random swings,
-- a pull back toward their usual price, and the odd news event). Players buy and sell shares
-- from their bank at a bank teller or the City Accountant.
--
-- Exports (server): GetQuote(symbol) -> { price, change }, GetPortfolio(src)

local Cfg = FinanceConfig
local M = Cfg.Market

FinSrv = {}

local stocks = {}       -- symbol -> { symbol, name, sector, base, vol, drift, price, history = { { at, price } } }
local order = {}        -- symbols in config order
local news = {}         -- newest first: { at, symbol, text, change }

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `tfc_stock_prices` (
        `symbol` VARCHAR(8) NOT NULL, `price` DECIMAL(12,2) NOT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`symbol`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_stock_history` (
        `symbol` VARCHAR(8) NOT NULL, `price` DECIMAL(12,2) NOT NULL,
        `at` INT UNSIGNED NOT NULL,
        KEY `idx_tfc_stock_history` (`symbol`, `at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_stock_news` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `symbol` VARCHAR(8) NOT NULL,
        `text` VARCHAR(160) NOT NULL, `change` DECIMAL(6,4) NOT NULL, `at` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_stock_holdings` (
        `character_id` INT UNSIGNED NOT NULL, `symbol` VARCHAR(8) NOT NULL,
        `shares` INT UNSIGNED NOT NULL, `cost` BIGINT NOT NULL,
        PRIMARY KEY (`character_id`, `symbol`),
        CONSTRAINT `fk_tfc_stock_holdings_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_stock_trades` (
        `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `character_id` INT UNSIGNED NOT NULL,
        `symbol` VARCHAR(8) NOT NULL, `side` VARCHAR(4) NOT NULL, `shares` INT UNSIGNED NOT NULL,
        `price` DECIMAL(12,2) NOT NULL, `fee` INT UNSIGNED NOT NULL, `total` BIGINT NOT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `idx_tfc_stock_trades` (`character_id`, `created_at`),
        CONSTRAINT `fk_tfc_stock_trades_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

local function int(v) return math.tointeger(tonumber(v)) end
local function round2(n) return math.floor(n * 100 + 0.5) / 100 end
local function fail(err) return { ok = false, error = err } end
FinSrv.fail = fail

-- Price movement --------------------------------------------------------------------------------

---Standard normal random number (Box-Muller).
local function gaussian()
    local u1, u2 = math.random(), math.random()
    if u1 < 1e-9 then u1 = 1e-9 end
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

local function priceAgo(s, seconds)
    local cutoff = os.time() - seconds
    local best = s.history[1] and s.history[1].price or s.price
    for _, h in ipairs(s.history) do
        if h.at <= cutoff then best = h.price else break end
    end
    return best
end

local function change24h(s)
    local before = priceAgo(s, 86400)
    return before > 0 and (s.price - before) / before or 0
end

local function tick()
    local now = os.time()
    for _, sym in ipairs(order) do
        local s = stocks[sym]
        -- Random swing + slow drift + a gentle pull back toward the usual price.
        local pull = (s.base - s.price) / s.base * 0.01
        local r = s.drift + pull + s.vol * gaussian()
        s.price = math.max(1, round2(s.price * (1 + r)))
    end

    if math.random() < M.eventChance then
        local s = stocks[order[math.random(#order)]]
        local up = math.random() < 0.5
        local size = 0.05 + math.random() * 0.10
        local list = up and Cfg.News.up or Cfg.News.down
        local text = list[math.random(#list)]:gsub('{name}', s.name)
        local change = up and size or -size
        s.price = math.max(1, round2(s.price * (1 + change)))
        table.insert(news, 1, { at = now, symbol = s.symbol, text = text, change = change })
        while #news > 20 do table.remove(news) end
        MySQL.insert('INSERT INTO tfc_stock_news (symbol, text, `change`, at) VALUES (?, ?, ?, ?)', { s.symbol, text, change, now })
    end

    local cutoff = now - M.historyHours * 3600
    local queries = {}
    for _, sym in ipairs(order) do
        local s = stocks[sym]
        s.history[#s.history + 1] = { at = now, price = s.price }
        while s.history[1] and s.history[1].at < cutoff do table.remove(s.history, 1) end
        queries[#queries + 1] = { query = 'INSERT INTO tfc_stock_prices (symbol, price) VALUES (?, ?) ON DUPLICATE KEY UPDATE price = VALUES(price)', values = { sym, s.price } }
        queries[#queries + 1] = { query = 'INSERT INTO tfc_stock_history (symbol, price, at) VALUES (?, ?, ?)', values = { sym, s.price, now } }
    end
    queries[#queries + 1] = { query = 'DELETE FROM tfc_stock_history WHERE at < ?', values = { cutoff } }
    MySQL.transaction(queries)
end
FinSrv.tick = tick

local function load()
    for _, q in ipairs(SCHEMA) do MySQL.query.await(q) end
    local saved = {}
    for _, r in ipairs(MySQL.query.await('SELECT symbol, price FROM tfc_stock_prices') or {}) do saved[r.symbol] = tonumber(r.price) end
    local cutoff = os.time() - M.historyHours * 3600
    for _, def in ipairs(Cfg.Stocks) do
        local s = { symbol = def.symbol, name = def.name, sector = def.sector, base = def.price, vol = def.vol, drift = def.drift,
            price = saved[def.symbol] or def.price, history = {} }
        for _, h in ipairs(MySQL.query.await('SELECT price, at FROM tfc_stock_history WHERE symbol = ? AND at >= ? ORDER BY at', { def.symbol, cutoff }) or {}) do
            s.history[#s.history + 1] = { at = int(h.at), price = tonumber(h.price) }
        end
        if #s.history == 0 then s.history[1] = { at = os.time(), price = s.price } end
        stocks[def.symbol] = s
        order[#order + 1] = def.symbol
    end
    for _, n in ipairs(MySQL.query.await('SELECT symbol, text, `change`, at FROM tfc_stock_news ORDER BY id DESC LIMIT 20') or {}) do
        news[#news + 1] = { symbol = n.symbol, text = n.text, change = tonumber(n.change), at = int(n.at) }
    end
end

-- Market data for the window ----------------------------------------------------------------------

---Up to `points` evenly spread prices from the last `seconds` (for sparklines and charts).
local function series(s, seconds, points)
    local cutoff = os.time() - seconds
    local list = {}
    for _, h in ipairs(s.history) do
        if h.at >= cutoff then list[#list + 1] = h end
    end
    if #list <= points then
        local out = {}
        for i, h in ipairs(list) do out[i] = h.price end
        return out
    end
    local out = {}
    for i = 1, points do
        out[i] = list[math.floor((i - 1) * (#list - 1) / (points - 1)) + 1].price
    end
    return out
end

function FinSrv.market()
    local list = {}
    for _, sym in ipairs(order) do
        local s = stocks[sym]
        list[#list + 1] = {
            symbol = sym, name = s.name, sector = s.sector, price = s.price, change = change24h(s),
            spark = series(s, 86400, 48), week = series(s, 7 * 86400, 120),
        }
    end
    return { stocks = list, news = news, fee = M.fee, minFee = M.minFee, tickSeconds = M.tickSeconds }
end

function FinSrv.portfolio(src)
    local p = TFC.GetPlayer(src)
    if not p then return { holdings = {}, value = 0, cost = 0, trades = {} } end
    local holdings, value, cost = {}, 0, 0
    for _, r in ipairs(MySQL.query.await('SELECT symbol, shares, cost FROM tfc_stock_holdings WHERE character_id = ? AND shares > 0', { p.characterId }) or {}) do
        local s = stocks[r.symbol]
        if s then
            local shares, c = int(r.shares), int(r.cost)
            local v = math.floor(s.price * shares)
            holdings[#holdings + 1] = { symbol = r.symbol, name = s.name, shares = shares, cost = c, avg = shares > 0 and c / shares or 0, price = s.price, value = v }
            value, cost = value + v, cost + c
        end
    end
    table.sort(holdings, function(a, b) return a.value > b.value end)
    local trades = MySQL.query.await('SELECT symbol, side, shares, price, fee, total, UNIX_TIMESTAMP(created_at) AS at FROM tfc_stock_trades WHERE character_id = ? ORDER BY id DESC LIMIT 15', { p.characterId }) or {}
    for _, t in ipairs(trades) do t.shares, t.price, t.fee, t.total, t.at = int(t.shares), tonumber(t.price), int(t.fee), int(t.total), int(t.at) end
    return { holdings = holdings, value = value, cost = cost, trades = trades }
end

-- Trading -----------------------------------------------------------------------------------------

local function canTrade(src)
    if GetResourceState('tfc-banking') == 'started' and exports['tfc-banking']:IsNearBank(src) then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local p, c = GetEntityCoords(ped), Cfg.Accountant.coords
    local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= Cfg.InteractDistance + 4.0
end
FinSrv.canTrade = canTrade

local function fee(amount)
    return math.max(M.minFee, math.ceil(amount * M.fee))
end

function FinSrv.buy(src, symbol, shares)
    if not canTrade(src) then return fail('trade at a bank or with the City Accountant') end
    local s = stocks[symbol]
    shares = int(shares)
    if not s then return fail('unknown company') end
    if not shares or shares < 1 or shares > M.maxSharesPerTrade then return fail(('buy 1 to %d shares'):format(M.maxSharesPerTrade)) end
    local p = TFC.GetPlayer(src)
    local price = s.price
    local cost = math.ceil(price * shares)
    local f = fee(cost)
    local total = cost + f
    if not exports['tfc-accounts']:RemoveMoney(src, 'bank', total, ('Stocks: bought %d %s @ $%.2f'):format(shares, symbol, price)) then
        return fail(('you need $%d in your bank (incl. $%d fee)'):format(total, f))
    end
    MySQL.update.await('INSERT INTO tfc_stock_holdings (character_id, symbol, shares, cost) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE shares = shares + VALUES(shares), cost = cost + VALUES(cost)',
        { p.characterId, symbol, shares, cost })
    MySQL.insert('INSERT INTO tfc_stock_trades (character_id, symbol, side, shares, price, fee, total) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { p.characterId, symbol, 'buy', shares, price, f, total })
    return { ok = true, message = ('Bought %d %s for $%d (incl. $%d fee)'):format(shares, symbol, total, f) }
end

function FinSrv.sell(src, symbol, shares)
    if not canTrade(src) then return fail('trade at a bank or with the City Accountant') end
    local s = stocks[symbol]
    shares = int(shares)
    if not s then return fail('unknown company') end
    if not shares or shares < 1 then return fail('enter how many shares') end
    local p = TFC.GetPlayer(src)
    local row = MySQL.single.await('SELECT shares, cost FROM tfc_stock_holdings WHERE character_id = ? AND symbol = ?', { p.characterId, symbol })
    local owned, costBasis = row and int(row.shares) or 0, row and int(row.cost) or 0
    if owned < shares then return fail(owned == 0 and 'you don\'t own any' or ('you only own %d'):format(owned)) end

    -- Take the shares first (conditional, so they can't be sold twice), then pay.
    local costPart = owned > 0 and math.floor(costBasis * shares / owned) or 0
    local n = MySQL.update.await('UPDATE tfc_stock_holdings SET shares = shares - ?, cost = cost - ? WHERE character_id = ? AND symbol = ? AND shares >= ?',
        { shares, costPart, p.characterId, symbol, shares })
    if (n or 0) < 1 then return fail('that sale failed, try again') end

    local price = s.price
    local gross = math.floor(price * shares)
    local f = fee(gross)
    local net = math.max(0, gross - f)
    if net > 0 then exports['tfc-accounts']:AddMoney(src, 'bank', net, ('Stocks: sold %d %s @ $%.2f'):format(shares, symbol, price)) end
    MySQL.update('DELETE FROM tfc_stock_holdings WHERE character_id = ? AND symbol = ? AND shares = 0', { p.characterId, symbol })
    MySQL.insert('INSERT INTO tfc_stock_trades (character_id, symbol, side, shares, price, fee, total) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { p.characterId, symbol, 'sell', shares, price, f, net })
    local profit = net - costPart
    return { ok = true, message = ('Sold %d %s for $%d (%s$%d %s)'):format(shares, symbol, net, profit < 0 and '-' or '+', math.abs(profit), profit < 0 and 'loss' or 'profit') }
end

exports('GetQuote', function(symbol)
    local s = stocks[symbol]
    return s and { price = s.price, change = change24h(s) } or nil
end)
exports('GetPortfolio', function(src) return FinSrv.portfolio(src) end)

FinSrv.stocks = stocks

function FinSrv.start()
    while not exports['tfc-core']:IsDatabaseReady() do Wait(250) end
    load()
    FinSrv.ready = true
    TFC.RegisterModule({ name = 'finance', version = '0.1.0' }, function()
        local c = Cfg.Accountant.coords
        TFC.Log.Info('finance ready: %d stocks, AI accountant %s, Accountant at %.2f, %.2f, %.2f', #order,
            FinSrv.aiEnabled() and 'on' or 'off (no tfc_ai_key)', c.x, c.y, c.z)
    end)
    while true do
        Wait(M.tickSeconds * 1000)
        local ok, err = pcall(tick)
        if not ok then TFC.Log.Error('market tick failed: %s', tostring(err)) end
    end
end
