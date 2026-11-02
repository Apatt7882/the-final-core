-- Shops server: locations (database), limited stock, buying and selling.
-- Every rule is checked here; the client only shows the shop and asks.
--
-- Exports (server):
--   GetShops() -> list of shops as clients see them      GetShop(id) -> shop|nil
--   RestockShop(id) -> ok                                  fill every limited item to its maximum
-- Server hooks:
--   shopPurchase(source, shopId, item, count, total, payment)
--   shopSale(source, shopId, item, count, total, account)

local Cfg = ShopsConfig
local Types = Cfg.Types

ShopsSrv = {}

---@type table<integer, { id: integer, type: string, label: string|nil, x: number, y: number, z: number, h: number, ped: string|nil, blip: integer|nil }>
local shops = {}
---@type table<integer, table<string, integer>> shop id -> item -> stock left
local stock = {}
---@type table<integer, integer> shop id -> os.time() of the last restock
local lastRestock = {}
---@type table<string, table> item definitions from tfc-inventory
local itemDefs = {}

ShopsSrv.shops, ShopsSrv.stock = shops, stock

local SCHEMA_SHOPS = [[
    CREATE TABLE IF NOT EXISTS `tfc_shops` (
        `id`         INT UNSIGNED     NOT NULL AUTO_INCREMENT,
        `type`       VARCHAR(32)      NOT NULL,
        `label`      VARCHAR(48)      NULL,
        `x`          FLOAT            NOT NULL,
        `y`          FLOAT            NOT NULL,
        `z`          FLOAT            NOT NULL,
        `h`          FLOAT            NOT NULL DEFAULT 0,
        `ped`        VARCHAR(64)      NULL,
        `blip`       TINYINT UNSIGNED NULL,
        `created_by` VARCHAR(64)      NULL,
        `created_at` TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]]

local SCHEMA_STOCK = [[
    CREATE TABLE IF NOT EXISTS `tfc_shop_stock` (
        `shop_id` INT UNSIGNED NOT NULL,
        `item`    VARCHAR(64)  NOT NULL,
        `stock`   INT UNSIGNED NOT NULL,
        PRIMARY KEY (`shop_id`, `item`),
        CONSTRAINT `fk_tfc_shop_stock_shop` FOREIGN KEY (`shop_id`) REFERENCES `tfc_shops` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]]

local INV, ACC, JOBS = 'tfc-inventory', 'tfc-accounts', 'tfc-jobs'

-- Helpers ------------------------------------------------------------------------------------

local function findEntry(list, name)
    for _, e in ipairs(list or {}) do
        if e.name == name then return e end
    end
    return nil
end

local function contains(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

local function itemLabel(name)
    local def = itemDefs[name]
    return def and def.label or name
end

function ShopsSrv.RefreshItems()
    if GetResourceState(INV) == 'started' then
        itemDefs = exports[INV]:GetItems() or {}
    end
end

---Is a shop with these hours open at this hour? Hours may wrap past midnight ({ 20, 5 }).
local function isOpenAt(hours, hour)
    if not hours then return true end
    local open, close = hours[1], hours[2]
    if open == close then return true end
    if open < close then return hour >= open and hour < close end
    return hour >= open or hour < close
end
ShopsSrv.IsOpenAt = isOpenAt

local function currentHour(clientHour)
    if Cfg.Clock == 'real' then return tonumber(os.date('%H')) end
    local h = math.tointeger(tonumber(clientHour))
    if h and h >= 0 and h <= 23 then return h end
    return nil
end

local function playerJob(src)
    if GetResourceState(JOBS) ~= 'started' then return nil end
    return exports[JOBS]:GetJob(src)
end

local function distanceTo(src, shop)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return math.huge end
    local c = GetEntityCoords(ped)
    local dx, dy, dz = c.x - shop.x, c.y - shop.y, c.z - shop.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Can this player use this shop right now?
---@return boolean ok, string|nil err, table|nil job
local function checkAccess(src, shop, clientHour)
    local def = Types[shop.type]
    if not def then return false, 'this shop is closed' end
    if distanceTo(src, shop) > Cfg.InteractDistance + 3.0 then return false, 'you are too far from the shop' end

    local job = playerJob(src)
    if def.job then
        if not job or job.name ~= def.job.name or (job.grade or 0) < (def.job.grade or 0) then
            return false, 'employees only'
        end
        if def.job.duty and not job.onDuty then return false, 'you need to be on duty' end
    end

    if def.hours then
        local hour = currentHour(clientHour)
        if not hour or not isOpenAt(def.hours, hour) then
            return false, ('closed right now, open %02d:00 to %02d:00'):format(def.hours[1], def.hours[2])
        end
    end
    return true, nil, job
end

-- Shops as clients see them ------------------------------------------------------------------

local DEFAULT_BLIP = { sprite = 52, color = 0, scale = 0.7 }

local function blipFor(shop, def)
    if shop.blip == 0 then return false end
    if shop.blip == 1 then return def.blip or DEFAULT_BLIP end
    return def.blip or false
end

local function publicShop(shop)
    local def = Types[shop.type]
    if not def then return nil end
    return {
        id = shop.id,
        type = shop.type,
        label = shop.label or def.label,
        x = shop.x, y = shop.y, z = shop.z, h = shop.h,
        ped = shop.ped or def.ped,
        scenario = def.scenario,
        blip = blipFor(shop, def),
        hours = def.hours,
        job = def.job and def.job.name or false,
    }
end

function ShopsSrv.List()
    local list = {}
    for _, shop in pairs(shops) do
        local view = publicShop(shop)
        if view then list[#list + 1] = view end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function ShopsSrv.Broadcast()
    TriggerClientEvent('tfc-shops:client:shops', -1, ShopsSrv.List())
end

-- Stock --------------------------------------------------------------------------------------

local function saveStock(id, name)
    local n = stock[id] and stock[id][name]
    if n == nil then return end
    MySQL.update('INSERT INTO tfc_shop_stock (shop_id, item, stock) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE stock = VALUES(stock)', { id, name, n })
end

---Set up stock for one shop; `stored` = saved counts (item -> n) if any.
function ShopsSrv.InitStock(shop, stored)
    local def = Types[shop.type]
    stock[shop.id] = {}
    lastRestock[shop.id] = os.time()
    if not def then return end
    for _, e in ipairs(def.items or {}) do
        if e.stock then
            local n = stored and stored[e.name]
            if n == nil then n = e.stock end
            stock[shop.id][e.name] = math.max(0, math.min(e.stock, n))
        end
    end
end

function ShopsSrv.ForgetStock(id)
    stock[id], lastRestock[id] = nil, nil
end

local function RestockShop(id)
    local shop = shops[tonumber(id)]
    local def = shop and Types[shop.type]
    if not def then return false end
    local any = false
    for _, e in ipairs(def.items or {}) do
        if e.stock and stock[shop.id] then
            stock[shop.id][e.name] = e.stock
            saveStock(shop.id, e.name)
            any = true
        end
    end
    lastRestock[shop.id] = os.time()
    return any
end
ShopsSrv.Restock = RestockShop

local function restockTick()
    local now = os.time()
    for id, shop in pairs(shops) do
        local def = Types[shop.type]
        local r = def and def.restock
        if r and stock[id] and now - (lastRestock[id] or now) >= r.minutes * 60 then
            lastRestock[id] = now
            for _, e in ipairs(def.items or {}) do
                local cur = stock[id][e.name]
                if e.stock and cur and cur < e.stock then
                    stock[id][e.name] = math.min(e.stock, cur + r.amount)
                    saveStock(id, e.name)
                end
            end
        end
    end
end
ShopsSrv.RestockTick = restockTick

-- What the shop window shows -----------------------------------------------------------------

local function balancesOf(src)
    if GetResourceState(ACC) ~= 'started' then return {} end
    return exports[ACC]:GetBalances(src) or {}
end

local function shopData(src, shop, job)
    local def = Types[shop.type]
    local items, buys, payment = {}, {}, {}

    for _, e in ipairs(def.items or {}) do
        local d = itemDefs[e.name] or {}
        local locked = false
        if e.grade and (not job or (job.grade or 0) < e.grade) then locked = true end
        items[#items + 1] = {
            name = e.name, label = itemLabel(e.name), description = d.description or '',
            weight = d.weight or 0, price = e.price, max = e.stock or false,
            stock = (e.stock and stock[shop.id] and stock[shop.id][e.name]) or false,
            locked = locked, grade = e.grade or false,
        }
    end

    for _, e in ipairs(def.buys or {}) do
        buys[#buys + 1] = {
            name = e.name, label = itemLabel(e.name), price = e.price,
            have = exports[INV]:GetItemCount(src, e.name) or 0,
        }
    end

    for _, p in ipairs(def.payment or { 'cash' }) do
        payment[#payment + 1] = { id = p, label = Cfg.PaymentLabels[p] or p }
    end

    local sellTo = def.sellTo or 'cash'
    return {
        id = shop.id,
        type = shop.type,
        label = shop.label or def.label,
        items = items,
        buys = buys,
        payment = payment,
        sellTo = { id = sellTo, label = Cfg.PaymentLabels[sellTo] or sellTo },
        balances = balancesOf(src),
        maxQuantity = Cfg.MaxQuantity,
    }
end

-- Buying and selling -------------------------------------------------------------------------

local SERIAL_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local function scratchedSerial()
    local t = {}
    for i = 1, 6 do
        local n = math.random(1, #SERIAL_CHARS)
        t[i] = SERIAL_CHARS:sub(n, n)
    end
    return 'SCRATCHED-' .. table.concat(t)
end

local function validCount(count)
    local n = math.tointeger(tonumber(count))
    if not n or n < 1 or n > Cfg.MaxQuantity then return nil end
    return n
end

local function fail(err) return { ok = false, error = err } end

local function getShop(id)
    return shops[math.tointeger(tonumber(id)) or -1]
end

function ShopsSrv.Buy(src, id, name, count, payment, hour)
    local shop = getShop(id)
    if not shop then return fail('this shop no longer exists') end
    local ok, err, job = checkAccess(src, shop, hour)
    if not ok then return fail(err) end

    local def = Types[shop.type]
    local entry = findEntry(def.items, name)
    if not entry then return fail('that is not sold here') end
    if entry.grade and (not job or (job.grade or 0) < entry.grade) then return fail('your rank cannot take that') end

    local n = validCount(count)
    if not n then return fail(('pick an amount from 1 to %d'):format(Cfg.MaxQuantity)) end

    local total = entry.price * n
    if total > 0 and not contains(def.payment, payment) then return fail('this shop does not take that payment') end

    -- Reserve limited stock before anything waits, so two buyers can't take the last one.
    local limited = entry.stock ~= nil
    if limited then
        local left = stock[shop.id] and stock[shop.id][name] or 0
        if left < n then return fail(left == 0 and 'sold out' or ('only %d left'):format(left)) end
        stock[shop.id][name] = left - n
    end
    local function giveBackStock(k)
        if limited and k > 0 and stock[shop.id] then
            stock[shop.id][name] = math.min(entry.stock, stock[shop.id][name] + k)
        end
    end

    local fits = exports[INV]:CanCarry(src, name, n)
    if not fits then
        giveBackStock(n)
        return fail('you can\'t carry that much')
    end

    local label = shop.label or def.label
    local reason = ('%s: %dx %s'):format(label, n, itemLabel(name))

    if total > 0 then
        local paid, payErr = exports[ACC]:RemoveMoney(src, payment, total, reason)
        if not paid then
            giveBackStock(n)
            return fail(payErr or 'payment failed')
        end
    end

    -- Hand over the goods. Scratched guns go one by one so each has its own serial.
    local delivered = 0
    local isWeapon = itemDefs[name] and itemDefs[name].weapon
    if isWeapon and def.scratched then
        for _ = 1, n do
            if not exports[INV]:AddItem(src, name, 1, { serial = scratchedSerial() }, nil, reason) then break end
            delivered = delivered + 1
        end
    elseif exports[INV]:AddItem(src, name, n, nil, nil, reason) then
        delivered = n
    end

    -- Anything we couldn't hand over is refunded and goes back on the shelf.
    if delivered < n then
        giveBackStock(n - delivered)
        local refund = entry.price * (n - delivered)
        if refund > 0 then exports[ACC]:AddMoney(src, payment, refund, 'Refund: ' .. reason) end
    end
    if limited then saveStock(shop.id, name) end
    if delivered == 0 then return fail('you can\'t carry that much') end

    TFC.Emit('shopPurchase', src, shop.id, name, delivered, entry.price * delivered, payment)
    local msg = total > 0 and ('Bought %dx %s for $%d'):format(delivered, itemLabel(name), entry.price * delivered)
        or ('Took %dx %s'):format(delivered, itemLabel(name))
    return { ok = true, message = msg, shop = shopData(src, shop, job) }
end

function ShopsSrv.Sell(src, id, name, count, hour)
    local shop = getShop(id)
    if not shop then return fail('this shop no longer exists') end
    local ok, err, job = checkAccess(src, shop, hour)
    if not ok then return fail(err) end

    local def = Types[shop.type]
    local entry = findEntry(def.buys, name)
    if not entry then return fail('they don\'t buy that here') end

    local n = validCount(count)
    if not n then return fail(('pick an amount from 1 to %d'):format(Cfg.MaxQuantity)) end

    local have = exports[INV]:GetItemCount(src, name) or 0
    if have < n then return fail(have == 0 and 'you don\'t have any' or ('you only have %d'):format(have)) end

    local label = shop.label or def.label
    local reason = ('%s: sold %dx %s'):format(label, n, itemLabel(name))
    local total = entry.price * n
    local account = def.sellTo or 'cash'

    if not exports[INV]:RemoveItem(src, name, n, nil, nil, reason) then return fail('could not take the items') end
    if total > 0 then
        local paid, payErr = exports[ACC]:AddMoney(src, account, total, reason)
        if not paid then
            exports[INV]:AddItem(src, name, n, nil, nil, 'Returned: ' .. reason)
            return fail(payErr or 'payment failed')
        end
    end

    -- If the shop also sells this item with limited stock, what you sold goes on its shelf.
    local sold = findEntry(def.items, name)
    if sold and sold.stock and stock[shop.id] and stock[shop.id][name] then
        stock[shop.id][name] = math.min(sold.stock, stock[shop.id][name] + n)
        saveStock(shop.id, name)
    end

    TFC.Emit('shopSale', src, shop.id, name, n, total, account)
    return { ok = true, message = ('Sold %dx %s for $%d'):format(n, itemLabel(name), total), shop = shopData(src, shop, job) }
end

-- Callbacks ----------------------------------------------------------------------------------

TFC.Callback.Register('shops:list', function()
    return { shops = ShopsSrv.List() }
end, { rateLimit = 1000 })

TFC.Callback.Register('shops:open', function(src, id, hour)
    local shop = getShop(id)
    if not shop then return fail('this shop no longer exists') end
    local ok, err, job = checkAccess(src, shop, hour)
    if not ok then return fail(err) end
    if not next(itemDefs) then ShopsSrv.RefreshItems() end
    return { ok = true, shop = shopData(src, shop, job) }
end, { rateLimit = 500 })

TFC.Callback.Register('shops:buy', function(src, id, name, count, payment, hour)
    return ShopsSrv.Buy(src, id, name, count, payment, hour)
end, { rateLimit = 250 })

TFC.Callback.Register('shops:sell', function(src, id, name, count, hour)
    return ShopsSrv.Sell(src, id, name, count, hour)
end, { rateLimit = 250 })

-- Loading ------------------------------------------------------------------------------------

local function rowToShop(row)
    return {
        id = math.tointeger(row.id),
        type = row.type,
        label = (row.label ~= nil and row.label ~= '') and row.label or nil,
        x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h) or 0.0,
        ped = (row.ped ~= nil and row.ped ~= '') and row.ped or nil,
        blip = math.tointeger(row.blip),
    }
end
ShopsSrv.RowToShop = rowToShop

local function seed()
    local queries = {}
    for _, loc in ipairs(Cfg.Locations or {}) do
        if Types[loc.type] then
            local c = loc.coords
            queries[#queries + 1] = {
                query = 'INSERT INTO tfc_shops (type, x, y, z, h, created_by) VALUES (?, ?, ?, ?, ?, ?)',
                values = { loc.type, c.x, c.y, c.z, c.w or 0.0, 'config' },
            }
        end
    end
    if #queries > 0 then MySQL.transaction.await(queries) end
    TFC.Log.Info('added %d shops from config (first start)', #queries)
end

local function checkConfig()
    for typeName, def in pairs(Types) do
        for _, list in ipairs({ def.items or {}, def.buys or {} }) do
            for i = #list, 1, -1 do
                if not itemDefs[list[i].name] then
                    TFC.Log.Warn('shop type %s: unknown item "%s" removed', typeName, tostring(list[i].name))
                    table.remove(list, i)
                end
            end
        end
    end
end

local function load()
    local existed = (tonumber((MySQL.scalar.await(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'tfc_shops'"))) or 0) > 0
    MySQL.query.await(SCHEMA_SHOPS)
    MySQL.query.await(SCHEMA_STOCK)
    if not existed then seed() end

    local stored = {}
    for _, row in ipairs(MySQL.query.await('SELECT shop_id, item, stock FROM tfc_shop_stock') or {}) do
        local id = math.tointeger(row.shop_id)
        stored[id] = stored[id] or {}
        stored[id][row.item] = math.tointeger(row.stock)
    end

    local count, unknown = 0, 0
    for _, row in ipairs(MySQL.query.await('SELECT id, type, label, x, y, z, h, ped, blip FROM tfc_shops') or {}) do
        local shop = rowToShop(row)
        shops[shop.id] = shop
        ShopsSrv.InitStock(shop, stored[shop.id])
        if Types[shop.type] then count = count + 1 else unknown = unknown + 1 end
    end
    if unknown > 0 then
        TFC.Log.Warn('%d shop(s) use a type that is not in config.lua; they are hidden until fixed in /%s', unknown, Cfg.Command)
    end
    return count
end

AddEventHandler('onResourceStart', function(resource)
    if resource == INV then ShopsSrv.RefreshItems() end
end)

CreateThread(function()
    while not exports['tfc-core']:IsDatabaseReady() do Wait(250) end
    ShopsSrv.RefreshItems()
    checkConfig()
    local count = load()
    ShopsSrv.ready = true

    TFC.RegisterModule({ name = 'shops', version = '0.1.0' }, function()
        TFC.Log.Info('shops ready: %d shops', count)
    end)
    ShopsSrv.Broadcast()

    while true do
        Wait(60000)
        local okTick, tickErr = pcall(restockTick)
        if not okTick then TFC.Log.Error('restock failed: %s', tostring(tickErr)) end
    end
end)

exports('GetShops', ShopsSrv.List)
exports('GetShop', function(id)
    local shop = getShop(id)
    return shop and publicShop(shop) or nil
end)
exports('RestockShop', RestockShop)

ShopsSrv.PublicShop = publicShop
ShopsSrv.CheckAccess = checkAccess
