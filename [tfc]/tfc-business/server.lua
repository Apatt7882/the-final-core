-- Businesses server. A business is a shop location (tfc-shops) + its own job (tfc-jobs) + a
-- savings account (tfc-banking, named after the job). Everything is decided here.
--
-- Exports (server): GetBusiness(id), GetBusinessByShop(shopId), GetBusinessByJob(job)
-- Server hooks: businessOwnerChanged(id, cid|nil), businessSale(id, total, toStaff, toSavings)

local Cfg = BusinessConfig

local businesses = {}   -- id -> business
local byShop = {}       -- shop id -> business id
local byJob = {}        -- job name -> business id

BizSrv = { businesses = businesses }

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `tfc_businesses` (
        `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `shop_id`    INT UNSIGNED NOT NULL,
        `job`        VARCHAR(32)  NULL,
        `label`      VARCHAR(48)  NOT NULL,
        `owner_cid`  VARCHAR(16)  NULL,
        `owner_name` VARCHAR(64)  NULL,
        `for_sale`   TINYINT(1)   NOT NULL DEFAULT 0,
        `price`      INT UNSIGNED NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uq_tfc_businesses_shop` (`shop_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_business_prices` (
        `business_id` INT UNSIGNED NOT NULL,
        `item`        VARCHAR(64)  NOT NULL,
        `price`       INT UNSIGNED NOT NULL,
        PRIMARY KEY (`business_id`, `item`),
        CONSTRAINT `fk_tfc_business_prices` FOREIGN KEY (`business_id`) REFERENCES `tfc_businesses` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_business_requests` (
        `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `business_id`  INT UNSIGNED NOT NULL,
        `character_id` INT UNSIGNED NOT NULL,
        `cid`          VARCHAR(16)  NOT NULL,
        `name`         VARCHAR(64)  NOT NULL,
        `price`        INT UNSIGNED NOT NULL,
        `status`       VARCHAR(12)  NOT NULL DEFAULT 'pending',
        `created_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `closed_at`    TIMESTAMP    NULL,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_business_requests` (`business_id`, `status`),
        CONSTRAINT `fk_tfc_business_requests` FOREIGN KEY (`business_id`) REFERENCES `tfc_businesses` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_business_sales` (
        `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        `business_id` INT UNSIGNED    NOT NULL,
        `item`        VARCHAR(64)     NOT NULL,
        `count`       INT UNSIGNED    NOT NULL,
        `total`       INT UNSIGNED    NOT NULL,
        `to_staff`    INT UNSIGNED    NOT NULL DEFAULT 0,
        `to_savings`  INT UNSIGNED    NOT NULL DEFAULT 0,
        `staff`       TINYINT UNSIGNED NOT NULL DEFAULT 0,
        `created_at`  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_business_sales` (`business_id`, `created_at`),
        CONSTRAINT `fk_tfc_business_sales` FOREIGN KEY (`business_id`) REFERENCES `tfc_businesses` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- Helpers ------------------------------------------------------------------------------------

local function shops() return exports['tfc-shops'] end
local function jobs() return exports['tfc-jobs'] end
local function bank() return exports['tfc-banking'] end
local function acc() return exports['tfc-accounts'] end

local function fail(err) return { ok = false, error = err } end

local function notify(src, text, kind)
    TFC.UI.Notify(src, { title = 'Business', description = text, type = kind or 'inform' })
end

local function name(src)
    local p = TFC.GetPlayer(src)
    return p and p:GetFullName() or GetPlayerName(src) or tostring(src)
end

local function clean(text, max)
    if type(text) ~= 'string' then return '' end
    return (text:gsub('<[^>]*>', ''):gsub('[%c<>]', ''):match('^%s*(.-)%s*$')):sub(1, max or 48)
end

local function int(v) return math.tointeger(tonumber(v)) end

local function topGrade(b)
    return jobs():GetTopGrade(b.job) or 0
end

---Push a business's state to tfc-shops (prices, owner, for sale) and the business job list to clients.
local function push(b)
    shops():SetStoreInfo(b.shopId, {
        business = b.id, job = b.job, owned = b.ownerCid ~= nil, ownerName = b.ownerName,
        forSale = b.forSale, price = b.price, prices = b.prices, shelf = Cfg.ShelfMax,
    })
end

local function publishJobs()
    local list = {}
    for job in pairs(byJob) do list[#list + 1] = job end
    GlobalState:set('tfc:businessJobs', list, true)
end

local function get(id)
    return businesses[int(id) or -1]
end

---The business a player works at, with their role there.
---@return table|nil business, 'owner'|'manager'|'staff'|nil role, table|nil job
local function membership(src)
    local job = jobs():GetJob(src)
    local id = job and byJob[job.name]
    if not id then return nil end
    local b = businesses[id]
    local role = 'staff'
    if job.grade == topGrade(b) then role = 'owner' elseif job.isBoss then role = 'manager' end
    return b, role, job
end

local function shopCoords(shopId)
    local s = shops():GetShop(shopId)
    return s and { x = s.x, y = s.y, z = s.z } or nil
end

local function distance(src, c)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not c then return math.huge end
    local p = GetEntityCoords(ped)
    local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Loading --------------------------------------------------------------------------------------

local function rowToBusiness(r)
    return {
        id = int(r.id), shopId = int(r.shop_id), job = r.job, label = r.label,
        ownerCid = r.owner_cid ~= '' and r.owner_cid or nil, ownerName = r.owner_name ~= '' and r.owner_name or nil,
        forSale = r.for_sale == 1 or r.for_sale == true, price = int(r.price) or 0, prices = {},
    }
end

local function jobDef(b)
    return { label = b.label, kind = 'business', ref = b.id, payRange = Cfg.PayRange, grades = Cfg.Ranks }
end

local function load()
    for _, q in ipairs(SCHEMA) do MySQL.query.await(q) end
    for _, r in ipairs(MySQL.query.await('SELECT * FROM tfc_businesses') or {}) do
        local b = rowToBusiness(r)
        businesses[b.id], byShop[b.shopId], byJob[b.job] = b, b.id, b.id
    end
    for _, r in ipairs(MySQL.query.await('SELECT business_id, item, price FROM tfc_business_prices') or {}) do
        local b = businesses[int(r.business_id)]
        if b then b.prices[r.item] = int(r.price) end
    end
    for _, b in pairs(businesses) do
        jobs():RegisterJob(b.job, jobDef(b)) -- makes sure the job exists (it's saved by tfc-jobs too)
        push(b)
    end
    publishJobs()
end

-- Owners ---------------------------------------------------------------------------------------

---Find a character by online server ID or by CID.
local function findCharacter(who)
    local src = int(who)
    if src and TFC.GetPlayer(src) then
        local p = TFC.GetPlayer(src)
        return { cid = p.cid, name = p:GetFullName(), src = src }
    end
    if type(who) == 'string' and who:match('^%w+$') then
        local row = MySQL.single.await('SELECT cid, firstname, lastname FROM tfc_characters WHERE cid = ?', { who:upper() })
        if row then
            local online = TFC.GetPlayerByCid(row.cid)
            return { cid = row.cid, name = ('%s %s'):format(row.firstname, row.lastname), src = online and online.source or nil }
        end
    end
    return nil
end

---@return boolean ok, string|nil err
local function setOwner(b, who, by)
    local c = findCharacter(who)
    if not c then return false, 'no character with that player ID or CID' end
    local wasOwned = b.ownerCid ~= nil

    -- The old owner leaves the business.
    if b.ownerCid and b.ownerCid ~= c.cid then
        jobs():SetJobByCid(b.ownerCid, 'unemployed', 0)
    end
    local ok, err = jobs():SetJobByCid(c.cid, b.job, topGrade(b))
    if not ok then return false, err end

    b.ownerCid, b.ownerName, b.forSale = c.cid, c.name, false
    MySQL.update.await('UPDATE tfc_businesses SET owner_cid = ?, owner_name = ?, for_sale = 0 WHERE id = ?', { c.cid, c.name, b.id })
    if not wasOwned then shops():ResetStoreStock(b.shopId, Cfg.StartingStock) end
    push(b)
    if c.src then notify(c.src, ('You now own %s.'):format(b.label), 'success') end
    TFC.Log.Info('business #%d (%s) owner set to %s (%s)%s', b.id, b.label, c.name, c.cid, by and (' by ' .. name(by)) or '')
    TFC.Emit('businessOwnerChanged', b.id, c.cid)
    return true
end

local function removeOwner(b, by)
    if not b.ownerCid then return false, 'it has no owner' end
    jobs():SetJobByCid(b.ownerCid, 'unemployed', 0)
    TFC.Log.Info('business #%d (%s) owner %s removed%s', b.id, b.label, b.ownerName or b.ownerCid, by and (' by ' .. name(by)) or '')
    b.ownerCid, b.ownerName = nil, nil
    MySQL.update.await('UPDATE tfc_businesses SET owner_cid = NULL, owner_name = NULL WHERE id = ?', { b.id })
    push(b)
    TFC.Emit('businessOwnerChanged', b.id, nil)
    return true
end

-- Sales split ------------------------------------------------------------------------------------

TFC.On('shopPurchase', function(buyer, shopId, item, count, total)
    local b = businesses[byShop[shopId] or -1]
    total = int(total) or 0
    if not b or not b.ownerCid or total <= 0 then return end

    local where = shopCoords(shopId)
    local staff = {}
    for _, s in ipairs(jobs():GetPlayersWithJob(b.job, true) or {}) do
        if s ~= buyer and distance(s, where) <= Cfg.WorkDistance then staff[#staff + 1] = s end
    end

    local each = 0
    if #staff == 1 or #staff == 2 then
        each = math.floor(total * Cfg.Split.share)
    elseif #staff > 2 then
        each = math.floor(total * Cfg.Split.pool / #staff)
    end

    local toStaff = 0
    if each > 0 then
        for _, s in ipairs(staff) do
            if acc():AddMoney(s, 'bank', each, ('Sales share: %s'):format(b.label)) then toStaff = toStaff + each end
        end
    end
    local toSavings = total - toStaff
    if toSavings > 0 then
        bank():AddSociety(b.job, toSavings, ('Sale: %dx %s'):format(count, item))
    end
    MySQL.insert('INSERT INTO tfc_business_sales (business_id, item, count, total, to_staff, to_savings, staff) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { b.id, item, count, total, toStaff, toSavings, #staff })
    TFC.Emit('businessSale', b.id, total, toStaff, toSavings)
end)

-- Business menu (owners and managers) ---------------------------------------------------------------

local function priceLimits(base)
    return math.ceil(base * Cfg.PriceRange.min), math.floor(base * Cfg.PriceRange.max)
end

local function wholesale(base)
    return math.max(1, math.ceil(base * Cfg.WholesaleRate))
end

local function menuData(src, b, role)
    local items = shops():GetStoreItems(b.shopId) or {}
    for _, it in ipairs(items) do
        it.wholesale = wholesale(it.basePrice)
        it.minPrice, it.maxPrice = priceLimits(it.basePrice)
    end
    local function sum(interval)
        local r = MySQL.single.await(('SELECT COALESCE(SUM(total), 0) AS total, COALESCE(SUM(to_staff), 0) AS staff, COUNT(*) AS n FROM tfc_business_sales WHERE business_id = ? AND created_at >= NOW() - INTERVAL %s'):format(interval), { b.id }) or {}
        return { total = int(r.total) or 0, staff = int(r.staff) or 0, count = int(r.n) or 0 }
    end
    local recent = MySQL.query.await('SELECT item, count, total, to_staff, to_savings, staff, UNIX_TIMESTAMP(created_at) AS at FROM tfc_business_sales WHERE business_id = ? ORDER BY id DESC LIMIT 25', { b.id }) or {}
    for _, r in ipairs(recent) do
        r.count, r.total, r.to_staff, r.to_savings, r.staff, r.at = int(r.count), int(r.total), int(r.to_staff), int(r.to_savings), int(r.staff), int(r.at)
    end
    local onDuty = #(jobs():GetPlayersWithJob(b.job, true) or {})
    return {
        ok = true,
        business = { id = b.id, label = b.label, ownerName = b.ownerName or false, role = role },
        items = items,
        today = sum('1 DAY'), week = sum('7 DAY'),
        recent = recent,
        savings = role == 'owner' and bank():GetSociety(b.job) or false,
        staffOnDuty = onDuty,
        shelf = Cfg.ShelfMax,
        wholesaleRate = Cfg.WholesaleRate,
    }
end

local function openFor(src)
    local b, role = membership(src)
    if not b then return nil, 'you don\'t work at a business' end
    if not b.ownerCid then return nil, 'this business has no owner yet' end
    if role == 'staff' then return nil, 'only managers and the owner can manage the store' end
    return b, role
end

TFC.Callback.Register('business:data', function(src)
    local b, role = openFor(src)
    if not b then return fail(role) end
    return menuData(src, b, role)
end, { rateLimit = 300 })

local Actions = {}

function Actions.restock(src, b, role, d)
    local items = shops():GetStoreItems(b.shopId) or {}
    local it
    for _, x in ipairs(items) do if x.name == d.item then it = x end end
    if not it then return fail('that isn\'t sold here') end
    local want = int(d.count)
    if not want or want < 1 then return fail('enter how many') end
    local n = math.min(want, Cfg.ShelfMax - (it.stock or 0))
    if n <= 0 then return fail('that shelf is full') end
    local cost = wholesale(it.basePrice) * n
    if not bank():RemoveSociety(b.job, cost, ('Restock: %dx %s by %s'):format(n, it.label, name(src))) then
        return fail(('not enough in the store savings ($%d needed)'):format(cost))
    end
    local added = shops():AddStock(b.shopId, it.name, n)
    if added < n then
        bank():AddSociety(b.job, wholesale(it.basePrice) * (n - added), 'Refund: restock')
        cost = wholesale(it.basePrice) * added
    end
    return { ok = true, message = ('Restocked %dx %s for $%d'):format(added, it.label, cost) }
end

function Actions.setPrice(src, b, role, d)
    if role ~= 'owner' then return fail('only the owner can set prices') end
    local items = shops():GetStoreItems(b.shopId) or {}
    local it
    for _, x in ipairs(items) do if x.name == d.item then it = x end end
    if not it then return fail('that isn\'t sold here') end
    local price = int(d.price)
    local lo, hi = priceLimits(it.basePrice)
    if not price or price < lo or price > hi then return fail(('price must be $%d to $%d'):format(lo, hi)) end
    MySQL.update.await('INSERT INTO tfc_business_prices (business_id, item, price) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE price = VALUES(price)',
        { b.id, it.name, price })
    b.prices[it.name] = price
    push(b)
    return { ok = true, message = ('%s now costs $%d'):format(it.label, price) }
end

TFC.Callback.Register('business:action', function(src, action, d)
    local b, role = openFor(src)
    if not b then return fail(role) end
    local fn = type(action) == 'string' and Actions[action]
    if not fn then return fail('unknown action') end
    local r = fn(src, b, role, type(d) == 'table' and d or {})
    local data = menuData(src, b, role)
    data.ok, data.error, data.message = r.ok, r.error, r.message
    return data
end, { rateLimit = 250 })

-- Purchase requests (players) ------------------------------------------------------------------------

TFC.Callback.Register('business:request', function(src, id)
    local b = get(id)
    local p = TFC.GetPlayer(src)
    if not b or not p then return fail('that store isn\'t for sale') end
    if not b.forSale then return fail('that store isn\'t for sale') end
    if b.ownerCid == p.cid then return fail('you already own it') end
    local existing = MySQL.scalar.await("SELECT COUNT(*) FROM tfc_business_requests WHERE business_id = ? AND character_id = ? AND status = 'pending'",
        { b.id, p.characterId })
    if (int(existing) or 0) > 0 then return fail('you already asked; an admin will get back to you') end
    MySQL.insert.await('INSERT INTO tfc_business_requests (business_id, character_id, cid, name, price) VALUES (?, ?, ?, ?, ?)',
        { b.id, p.characterId, p.cid, p:GetFullName(), b.price })
    for _, other in ipairs(TFC.GetPlayers()) do
        if TFC.IsAdmin(other) then notify(other, ('%s asked to buy %s for $%d. See /%s.'):format(p:GetFullName(), b.label, b.price, Cfg.AdminCommand)) end
    end
    TFC.Log.Info('%s requested to buy business #%d (%s) for $%d', p:GetFullName(), b.id, b.label, b.price)
    return { ok = true, message = ('Request sent. An admin will review your offer of $%d.'):format(b.price) }
end, { rateLimit = 2000 })

-- Admin panel -------------------------------------------------------------------------------------

local function adminData()
    local types = shops():GetShopTypes() or {}
    local list = {}
    for _, s in ipairs(shops():GetShops() or {}) do
        if Cfg.OwnableTypes[s.type] then
            local b = businesses[byShop[s.id] or -1]
            list[#list + 1] = {
                shopId = s.id, shopLabel = s.label, type = s.type, typeLabel = types[s.type] and types[s.type].label or s.type,
                business = b and {
                    id = b.id, label = b.label, job = b.job, ownerName = b.ownerName or false, ownerCid = b.ownerCid or false,
                    forSale = b.forSale, price = b.price, savings = bank():GetSociety(b.job),
                } or false,
            }
        end
    end
    table.sort(list, function(a, c) return a.shopId < c.shopId end)
    local requests = MySQL.query.await([[
        SELECT r.id, r.business_id, r.cid, r.name, r.price, UNIX_TIMESTAMP(r.created_at) AS at, b.label
        FROM tfc_business_requests r JOIN tfc_businesses b ON b.id = r.business_id
        WHERE r.status = 'pending' ORDER BY r.id
    ]]) or {}
    for _, r in ipairs(requests) do
        r.id, r.business_id, r.price, r.at = int(r.id), int(r.business_id), int(r.price), int(r.at)
        local online = TFC.GetPlayerByCid(r.cid)
        r.online = online ~= nil
    end
    return { ok = true, list = list, requests = requests }
end

local Admin = {}

function Admin.create(src, d)
    local shopId = int(d.shopId)
    local shop = shopId and shops():GetShop(shopId)
    if not shop or not Cfg.OwnableTypes[shop.type] then return fail('that shop can\'t be a business') end
    if byShop[shopId] then return fail('it\'s already a business') end
    local label = clean(d.label)
    if #label < 2 then return fail('give the business a name') end

    local id = int(MySQL.insert.await('INSERT INTO tfc_businesses (shop_id, label) VALUES (?, ?)', { shopId, label }))
    if not id then return fail('could not save') end
    local job = ('biz_%d'):format(id)
    MySQL.update.await('UPDATE tfc_businesses SET job = ? WHERE id = ?', { job, id })
    local b = { id = id, shopId = shopId, job = job, label = label, forSale = false, price = 0, prices = {} }
    local ok, err = jobs():RegisterJob(job, jobDef(b))
    if not ok then
        MySQL.update.await('DELETE FROM tfc_businesses WHERE id = ?', { id })
        return fail(err or 'could not create the job')
    end
    businesses[id], byShop[shopId], byJob[job] = b, id, id
    push(b)
    publishJobs()
    TFC.Log.Info('%s created business #%d (%s) at shop #%d', name(src), id, label, shopId)
    return { ok = true, message = ('Created %s'):format(label) }
end

function Admin.rename(src, d)
    local b = get(d.id)
    if not b then return fail('no such business') end
    local label = clean(d.label)
    if #label < 2 then return fail('give the business a name') end
    b.label = label
    MySQL.update.await('UPDATE tfc_businesses SET label = ? WHERE id = ?', { label, b.id })
    jobs():RegisterJob(b.job, jobDef(b))
    push(b)
    return { ok = true, message = ('Renamed to %s'):format(label) }
end

function Admin.setOwner(src, d)
    local b = get(d.id)
    if not b then return fail('no such business') end
    local ok, err = setOwner(b, d.who, src)
    if not ok then return fail(err) end
    -- Any open purchase requests are no longer relevant.
    MySQL.update.await("UPDATE tfc_business_requests SET status = 'closed', closed_at = CURRENT_TIMESTAMP WHERE business_id = ? AND status = 'pending'", { b.id })
    return { ok = true, message = ('%s now owns %s'):format(b.ownerName, b.label) }
end

function Admin.removeOwner(src, d)
    local b = get(d.id)
    if not b then return fail('no such business') end
    local ok, err = removeOwner(b, src)
    if not ok then return fail(err) end
    return { ok = true, message = 'Owner removed' }
end

function Admin.list(src, d)
    local b = get(d.id)
    if not b then return fail('no such business') end
    local price = int(d.price)
    if not price or price < 1 or price > 100000000 then return fail('set a price') end
    b.forSale, b.price = true, price
    MySQL.update.await('UPDATE tfc_businesses SET for_sale = 1, price = ? WHERE id = ?', { price, b.id })
    push(b)
    TFC.Log.Info('%s listed business #%d (%s) for $%d', name(src), b.id, b.label, price)
    return { ok = true, message = ('%s is for sale at $%d'):format(b.label, price) }
end

function Admin.unlist(src, d)
    local b = get(d.id)
    if not b then return fail('no such business') end
    b.forSale = false
    MySQL.update.await('UPDATE tfc_businesses SET for_sale = 0 WHERE id = ?', { b.id })
    MySQL.update.await("UPDATE tfc_business_requests SET status = 'closed', closed_at = CURRENT_TIMESTAMP WHERE business_id = ? AND status = 'pending'", { b.id })
    push(b)
    return { ok = true, message = ('%s is no longer for sale'):format(b.label) }
end

local function getRequest(id)
    local r = MySQL.single.await("SELECT id, business_id, cid, name, price FROM tfc_business_requests WHERE id = ? AND status = 'pending'", { int(id) or -1 })
    if r then r.business_id, r.price = int(r.business_id), int(r.price) end
    return r
end

function Admin.approve(src, d)
    local r = getRequest(d.request)
    if not r then return fail('that request was already handled') end
    local b = businesses[r.business_id]
    if not b or not b.forSale then return fail('that store is no longer for sale') end
    local buyer = TFC.GetPlayerByCid(r.cid)
    if not buyer then return fail(('%s must be in the city to pay'):format(r.name)) end

    local paid = acc():RemoveMoney(buyer.source, 'bank', r.price, ('Bought %s'):format(b.label))
    if not paid then
        notify(buyer.source, ('Your purchase of %s was approved, but your bank doesn\'t have $%d.'):format(b.label, r.price), 'error')
        return fail(('%s doesn\'t have $%d in the bank'):format(r.name, r.price))
    end
    local ok, err = setOwner(b, r.cid, src)
    if not ok then
        acc():AddMoney(buyer.source, 'bank', r.price, ('Refund: %s'):format(b.label))
        return fail(err)
    end
    MySQL.update.await("UPDATE tfc_business_requests SET status = 'approved', closed_at = CURRENT_TIMESTAMP WHERE id = ?", { r.id })
    MySQL.update.await("UPDATE tfc_business_requests SET status = 'closed', closed_at = CURRENT_TIMESTAMP WHERE business_id = ? AND status = 'pending'", { b.id })
    TFC.Log.Info('%s approved the sale of business #%d (%s) to %s for $%d', name(src), b.id, b.label, r.name, r.price)
    return { ok = true, message = ('Sold %s to %s for $%d'):format(b.label, r.name, r.price) }
end

function Admin.deny(src, d)
    local r = getRequest(d.request)
    if not r then return fail('that request was already handled') end
    MySQL.update.await("UPDATE tfc_business_requests SET status = 'denied', closed_at = CURRENT_TIMESTAMP WHERE id = ?", { r.id })
    local buyer = TFC.GetPlayerByCid(r.cid)
    local b = businesses[r.business_id]
    if buyer then notify(buyer.source, ('Your request to buy %s was declined.'):format(b and b.label or 'the store'), 'error') end
    return { ok = true, message = 'Request denied' }
end

TFC.Callback.Register('business:admin', function(src, action, d)
    if not TFC.IsAdmin(src) then return fail('admins only') end
    if action == 'data' then return adminData() end
    local fn = type(action) == 'string' and Admin[action]
    if not fn then return fail('unknown action') end
    local r = fn(src, type(d) == 'table' and d or {})
    local data = adminData()
    data.ok, data.error, data.message = r.ok, r.error, r.message
    return data
end, { rateLimit = 250 })

-- Commands -------------------------------------------------------------------------------------

TFC.RegisterCommand(Cfg.Command, { help = 'Manage your store (owners and managers)' }, function(src)
    if src == 0 then return end
    local b, why = openFor(src)
    if not b then return notify(src, why, 'error') end
    TriggerClientEvent('tfc-business:client:open', src, 'business')
end)

TFC.RegisterCommand(Cfg.AdminCommand, { help = 'Admin: businesses, owners, sales and requests', permission = TFC.Permissions.Admin }, function(src)
    if src == 0 then return end
    TriggerClientEvent('tfc-business:client:open', src, 'admin')
end)

exports('GetBusiness', function(id) return get(id) end)
exports('GetBusinessByShop', function(shopId) local id = byShop[int(shopId) or -1] return id and businesses[id] or nil end)
exports('GetBusinessByJob', function(job) local id = byJob[job] return id and businesses[id] or nil end)

BizSrv.setOwner, BizSrv.removeOwner, BizSrv.Admin, BizSrv.Actions = setOwner, removeOwner, Admin, Actions

-- Start ----------------------------------------------------------------------------------------

AddEventHandler('onResourceStart', function(resource)
    -- tfc-shops forgets store info when it restarts: tell it again.
    if resource == 'tfc-shops' and BizSrv.ready then
        SetTimeout(2000, function() for _, b in pairs(businesses) do push(b) end end)
    end
end)

CreateThread(function()
    while not exports['tfc-core']:IsDatabaseReady() do Wait(250) end
    while not exports['tfc-core']:IsModuleReady('jobs') or not exports['tfc-core']:IsModuleReady('shops') do Wait(250) end
    load()
    BizSrv.ready = true
    local n = 0
    for _ in pairs(businesses) do n = n + 1 end
    TFC.RegisterModule({ name = 'business', version = '0.1.0' }, function()
        TFC.Log.Info('business ready: %d business(es)', n)
    end)
end)
