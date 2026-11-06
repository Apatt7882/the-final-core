-- Convenience Store Clerk (server). Clock in at the counter of a 24/7 nobody owns; while you stay
-- in the store you get one task at a time: an NPC customer to ring up, boxes to put on the shelves,
-- or a spill to mop. Walk away from the store and you're clocked out.
-- Player state 'tfc:workplace' = { type = 'store', id, label, x, y, z, h } while on duty.
-- GlobalState['tfc:staffedStores'] = { ['<shop id>'] = true }: tfc-shops hides its NPC clerk there.

local C = CivJobsConfig.Clerk
local P = C.Points

local workplace = {}   -- src -> store
local pending = {}     -- src -> store chosen by canGoOnDuty
local awaySince = {}   -- src -> os.time() they left
local nextAt = {}      -- src -> { customer, restock, clean } os.time() each is due

local function isOwned(shopId)
    if GetResourceState('tfc-business') ~= 'started' then return false end
    local ok, b = pcall(function() return exports['tfc-business']:GetBusinessByShop(shopId) end)
    return ok and type(b) == 'table' and b.ownerCid ~= nil
end

-- What NPC customers can buy: each shop type's items with labels (looked up once).
local goods = nil
local function goodsFor(shopType)
    if not goods then
        goods = {}
        local okT, types = pcall(function() return exports['tfc-shops']:GetShopTypes() end)
        local okI, items = pcall(function() return exports['tfc-inventory']:GetItems() end)
        for name, t in pairs(okT and types or {}) do
            local list = {}
            for _, e in ipairs(t.items or {}) do
                local def = okI and items and items[e.name]
                list[#list + 1] = { label = def and def.label or e.name, price = e.price or 0 }
            end
            goods[name] = list
        end
    end
    return goods[shopType] or {}
end

---Stores a clerk can work at right now.
local function stores()
    local list = {}
    local ok, shops = pcall(function() return exports['tfc-shops']:GetShops() end)
    for _, s in ipairs(ok and shops or {}) do
        if C.ShopTypes[s.type] and not isOwned(s.id) then
            list[#list + 1] = { type = 'store', id = s.id, label = s.label, x = s.x, y = s.y, z = s.z, h = s.h or 0.0, shopType = s.type }
        end
    end
    return list
end

local function nearestStore(src)
    local p = Civ.pos(src)
    if not p then return nil, math.huge end
    local best, bestD = nil, math.huge
    for _, s in ipairs(stores()) do
        local d = Civ.dist2d(p, s)
        if d < bestD then best, bestD = s, d end
    end
    return best, bestD
end

local function point(store, rel)
    return Civ.offset(store.x, store.y, store.z, store.h, rel.forward, rel.right)
end

local function publishStaffed()
    local staffed = {}
    for _, s in pairs(workplace) do staffed[tostring(s.id)] = true end
    GlobalState:set('tfc:staffedStores', staffed, true)
end

local function setWorkplace(src, s)
    workplace[src], awaySince[src] = s, nil
    if s then
        local copy = { type = 'store', id = s.id, label = s.label, x = s.x, y = s.y, z = s.z, h = s.h }
        Player(src).state:set('tfc:workplace', copy, true)
        local now = os.time()
        nextAt[src] = { customer = now + 10, restock = now + Civ.rand(C.Restock.Every), clean = now + Civ.rand(C.Clean.Every) }
    else
        Player(src).state:set('tfc:workplace', nil, true)
        nextAt[src] = nil
    end
    publishStaffed()
end

local function notify(src, text, kind) Civ.notify(src, text, kind, 'Store clerk') end

local Job = { name = C.Job, label = 'Convenience Store Clerk', actions = {}, requests = {} }
Civ.Jobs[C.Job] = Job

function Job.canGoOnDuty(src)
    local s, d = nearestStore(src)
    if not s or d > C.ClockInDistance then
        return false, 'clock in at the counter of a 24/7 store that isn\'t privately owned'
    end
    pending[src] = s
    return true
end

function Job.dutyChanged(src, onDuty, job)
    if onDuty and job and job.name == C.Job and pending[src] then
        setWorkplace(src, pending[src])
        notify(src, ('Clocked in at %s. Customers will start coming in; stay near the counter.'):format(pending[src].label), 'success')
    end
    pending[src] = nil
end

function Job.stop(src)
    if workplace[src] then setWorkplace(src, nil) end
    pending[src] = nil
end

exports('GetWorkplace', function(src) return workplace[src] end)

-- Tasks ------------------------------------------------------------------------------------------------

local function customerTask(src, s)
    -- A few random things from the store's shelves.
    local pool = {}
    for _, it in ipairs(goodsFor(s.shopType)) do
        if it.price > 0 and it.price <= C.Customers.MaxItemPrice then pool[#pool + 1] = it end
    end
    for _, it in ipairs(C.Customers.Extra or {}) do pool[#pool + 1] = it end
    local items, total = {}, 0
    for _ = 1, Civ.rand(C.Customers.Items) do
        local it = pool[math.random(#pool)]
        if it then
            items[#items + 1] = it.label
            total = total + it.price
        end
    end
    if #items == 0 then items, total = { 'Snacks' }, 12 end
    local spawn, stand = point(s, P.customerSpawn), point(s, P.customerStand)
    Civ.issue(src, {
        job = C.Job, kind = 'customer', store = s.id, label = s.label,
        items = items, total = total, wait = C.Customers.WaitSeconds,
        spawn = spawn, stand = stand, heading = (s.h + 180.0) % 360.0,
        model = C.CustomerModels[math.random(#C.CustomerModels)],
        _expires = os.time() + C.Customers.WaitSeconds,
    })
end

local function restockTask(src, s)
    local shelves = {}
    for i, rel in ipairs(P.shelves) do shelves[i] = point(s, rel) end
    Civ.issue(src, {
        job = C.Job, kind = 'restock', store = s.id, boxes = C.Restock.Boxes, done = 0,
        stockroom = point(s, P.stockroom), shelves = shelves, carrying = false, shelf = 1,
    })
    notify(src, ('Shelves are running low: carry %d boxes from behind the counter to the shelves.'):format(C.Restock.Boxes))
end

local function cleanTask(src, s)
    local rel = P.spills[math.random(#P.spills)]
    Civ.issue(src, { job = C.Job, kind = 'clean', store = s.id, spot = point(s, rel) })
    notify(src, 'Someone spilled something. Grab the mop and clean it up.')
end

-- Ring up the customer: the client sends whether the skill check passed.
function Job.actions.serve(src, task, d)
    if task.kind ~= 'customer' then return Civ.fail('no customer') end
    local s = workplace[src]
    if not s or not Civ.near(src, s, 4.0) then return Civ.fail('get behind the counter') end
    if os.time() - task.issued < 5 then return Civ.fail('wait for them to reach the counter') end
    local cut = math.floor(task.total * C.Customers.SaleCut + 0.5)
    local tip = d.passed == true and Civ.rand(C.Customers.Tip) or 0
    Civ.clear(src)
    if tip > 0 then
        Civ.pay(src, cut + tip, ('Customer: $%d sale, $%d tip'):format(task.total, tip), 'Store clerk')
    else
        Civ.pay(src, cut, ('Customer: $%d sale (no tip, you fumbled the register)'):format(task.total), 'Store clerk')
    end
    return { ok = true, tip = tip }
end

function Job.actions.pickup(src, task)
    if task.kind ~= 'restock' then return Civ.fail('nothing to restock') end
    if task.carrying then return Civ.fail('you are already carrying a box') end
    if not Civ.near(src, task.stockroom, 3.0) then return Civ.fail('the boxes are behind the counter') end
    task.carrying = true
    task._pickedAt = os.time()
    Civ.update(src, task)
end

function Job.actions.stock(src, task)
    if task.kind ~= 'restock' or not task.carrying then return Civ.fail('pick up a box first') end
    local shelf = task.shelves[task.shelf]
    if not shelf or not Civ.near(src, shelf, 3.0) then return Civ.fail('take it to the marked shelf') end
    if os.time() - (task._pickedAt or 0) < 3 then return Civ.fail('slow down') end
    task.carrying = false
    task.done = task.done + 1
    task.shelf = (task.shelf % #task.shelves) + 1
    Civ.pay(src, C.Restock.PayPerBox, ('Restocked a shelf (%d/%d)'):format(task.done, task.boxes), 'Store clerk')
    if task.done >= task.boxes then
        Civ.clear(src, 'Shelves are full. Nice work.', 'success')
    else
        Civ.update(src, task)
    end
end

function Job.actions.mop(src, task)
    if task.kind ~= 'clean' then return Civ.fail('nothing to clean') end
    if not Civ.near(src, task.spot, 3.0) then return Civ.fail('go to the spill') end
    if os.time() - task.issued < 5 then return Civ.fail('slow down') end
    Civ.clear(src)
    Civ.pay(src, C.Clean.Pay, 'Cleaned up a spill', 'Store clerk')
end

-- Loop: clock out clerks who left, expire customers, hand out the next task ----------------------------------

function Job.start()
    local function tick()
        local now = os.time()
        for src, s in pairs(workplace) do
            if GetPlayerPed(src) ~= 0 then
                local p = Civ.pos(src)
                local d = p and Civ.dist2d(p, s) or math.huge
                local task = Civ.tasks[src]

                if isOwned(s.id) then
                    Civ.jobs():SetDuty(src, false)
                    notify(src, ('%s is now privately owned. You were clocked out.'):format(s.label), 'error')
                elseif d > C.LeaveDistance then
                    awaySince[src] = awaySince[src] or now
                    if now - awaySince[src] >= C.LeaveGraceSeconds then
                        Civ.jobs():SetDuty(src, false)
                        notify(src, ('You left %s and were clocked out.'):format(s.label), 'error')
                    elseif now - awaySince[src] < 5 then
                        notify(src, ('Head back to %s or you\'ll be clocked out in %d s.'):format(s.label, C.LeaveGraceSeconds), 'warning')
                    end
                else
                    awaySince[src] = nil
                    if task and task.kind == 'customer' and now >= task._expires then
                        Civ.clear(src, 'The customer got tired of waiting and left.', 'error')
                        task = nil
                    end
                    local due = nextAt[src]
                    if not task and due and d <= C.WorkDistance then
                        if now >= due.customer then
                            due.customer = now + Civ.rand(C.Customers.Every)
                            customerTask(src, s)
                        elseif now >= due.restock then
                            due.restock = now + Civ.rand(C.Restock.Every)
                            restockTask(src, s)
                        elseif now >= due.clean then
                            due.clean = now + Civ.rand(C.Clean.Every)
                            cleanTask(src, s)
                        end
                    end
                end
            end
        end
    end
    publishStaffed()
    while true do
        Wait(3000)
        local ok, err = pcall(tick)
        if not ok then TFC.Log.Error('clerk loop: %s', tostring(err)) end
    end
end

-- Where clerks can work (the client's "clock in here" hint).
TFC.Callback.Register('civjobs:stores', function()
    local out = {}
    for _, s in ipairs(stores()) do out[#out + 1] = { id = s.id, label = s.label, x = s.x, y = s.y, z = s.z } end
    return out
end, { rateLimit = 2000 })

-- F6 > Clock in / out (clerks clock in at the counter, so there's no depot).
TFC.Callback.Register('civjobs:clock', function(src)
    local job = Civ.jobs():GetJob(src)
    if not job or job.name ~= C.Job then return Civ.fail('you are not a store clerk') end
    local ok, err = Civ.jobs():SetDuty(src, not job.onDuty)
    if not ok then return Civ.fail(err) end
    return { ok = true, onDuty = not job.onDuty }
end, { rateLimit = 1000 })
