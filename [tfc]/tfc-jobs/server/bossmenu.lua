-- Boss Menu and boss commands. Every rule is enforced here; the menu is never trusted.
--
-- Who can do what in a job:
--   boss of that job   view it; hire (nearby, below own rank), fire / promote / demote people
--                      below own rank, set rank pay (within the job's pay range)
--   admin (tfc.admin)  view every job; set anyone's rank; add, rename, remove ranks and
--                      set the boss flag. No hiring, firing or pay unless also a boss there.
--   admin AND boss     everything above for that job, with the admin's rank freedom.

local Cfg = JobsConfig.BossMenu

---@return { view: boolean, boss: boolean, admin: boolean, grade: integer|nil }
function JobsSrv.Access(src, name)
    local admin = TFC.IsAdmin(src)
    local state = JobsSrv.Load(src)
    local isBoss = false
    if state and state.name == name and name ~= JobsConfig.DefaultJob then
        local grade = JobsSrv.GradeOf(name, state.grade)
        isBoss = grade ~= nil and grade.boss == true
    end
    return {
        view = admin or isBoss,
        boss = isBoss,
        admin = admin,
        grade = isBoss and state.grade or nil,
        -- Holds the job's highest rank (a business owner).
        top = state ~= nil and state.name == name and state.grade == JobsSrv.MaxGrade(name),
    }
end

-- Savings (department / business account in tfc-banking) ---------------------------------------
-- Businesses: only the owner (highest rank). Departments (police, EMS...): whoever holds the
-- highest rank anyone currently has; if nobody is Chief, the next rank down. Admins can view.

local function banking()
    return GetResourceState('tfc-banking') == 'started' and exports['tfc-banking'] or nil
end

---@return 'full'|'view'|nil
function JobsSrv.SavingsAccess(src, name, access)
    if name == JobsConfig.DefaultJob or not banking() then return nil end
    local state = JobsSrv.Load(src)
    if state and state.name == name then
        if Jobs[name].kind == 'business' then
            if state.grade == JobsSrv.MaxGrade(name) then return 'full' end
        else
            local top = math.tointeger(tonumber((MySQL.scalar.await('SELECT MAX(grade) FROM tfc_character_jobs WHERE job = ?', { name }))))
            if top and state.grade >= top then return 'full' end
        end
    end
    if access and access.admin then return 'view' end
    return nil
end

local function savingsWho(name)
    return Jobs[name].kind == 'business' and 'the owner' or 'the highest-ranking member'
end

---An employee by cid (online or offline), only if they work in `name`.
local function employee(name, cid)
    if type(cid) ~= 'string' then return nil end
    local row = MySQL.single.await([[
        SELECT c.id AS charId, c.cid, c.firstname, c.lastname, j.job, j.grade
        FROM tfc_characters c JOIN tfc_character_jobs j ON j.character_id = c.id
        WHERE c.cid = ?
    ]], { cid })
    if not row or row.job ~= name then return nil end
    row.grade = math.tointeger(row.grade) or 0
    row.name = ('%s %s'):format(row.firstname, row.lastname)
    local online = TFC.GetPlayerByCid(cid)
    row.src = online and online.source or nil
    return row
end

local function distance(a, b)
    local pa, pb = GetEntityCoords(GetPlayerPed(tostring(a))), GetEntityCoords(GetPlayerPed(tostring(b)))
    return #(pa - pb)
end

---Loaded players within HireDistance of src who don't already work in `name`.
function JobsSrv.Nearby(src, name)
    local list = {}
    for target, state in pairs(JobsSrv.cache) do
        if target ~= src and state.name ~= name then
            local ok, d = pcall(distance, src, target)
            if ok and d <= Cfg.HireDistance then
                local player = TFC.GetPlayer(target)
                list[#list + 1] = {
                    id = target,
                    name = player and player:GetFullName() or GetPlayerName(target),
                    job = JobsSrv.Describe(state.name, state.grade),
                }
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function rankText(name, grade)
    local g = JobsSrv.GradeOf(name, grade)
    return g and g.label or ('rank %d'):format(grade)
end

local function tell(src, text, kind)
    if src then JobsSrv.Notify(src, text, kind) end
end

-- Actions -----------------------------------------------------------------------------------

local actions = {}

function actions.hire(src, name, access, data)
    if not access.boss then return false, 'only bosses of this job can hire' end
    local target = math.tointeger(tonumber(data.target))
    local grade = math.tointeger(tonumber(data.grade) or 0) or 0

    if not target or not JobsSrv.cache[target] then return false, 'that player is not available' end
    if target == src then return false, 'you cannot hire yourself' end
    local ok, d = pcall(distance, src, target)
    if not ok or d > Cfg.HireDistance then return false, 'they need to be standing next to you' end
    if JobsSrv.cache[target].name == name then return false, 'they already work here' end
    if not JobsSrv.GradeOf(name, grade) then return false, 'that rank does not exist' end
    if not access.admin and grade >= access.grade then return false, 'you can only hire below your own rank' end

    local okSet, err = JobsSrv.SetJob(target, name, grade)
    if not okSet then return false, err end

    JobsSrv.LogAction(name, src, 'hire', JobsSrv.cache[target].cid, ('as %s'):format(rankText(name, grade)))
    tell(target, ('You were hired as %s'):format(JobsSrv.Describe(name, grade)), 'success')
    return true
end

function actions.fire(src, name, access, data)
    if not access.boss then return false, 'only bosses of this job can fire' end
    local emp = employee(name, data.cid)
    if not emp then return false, 'that person does not work here' end
    if emp.src == src then return false, 'you cannot fire yourself' end
    if not access.admin and emp.grade >= access.grade then return false, 'you can only fire people below your rank' end

    local ok, err = JobsSrv.SetJobByCid(emp.cid, JobsConfig.DefaultJob, 0)
    if not ok then return false, err end

    JobsSrv.LogAction(name, src, 'fire', emp.cid, ('was %s'):format(rankText(name, emp.grade)))
    tell(emp.src, ('You were let go from %s'):format(Jobs[name].label), 'error')
    return true
end

---Set an employee's rank (promote / demote / any rank).
function actions.setgrade(src, name, access, data)
    local emp = employee(name, data.cid)
    if not emp then return false, 'that person does not work here' end

    local grade = math.tointeger(tonumber(data.grade))
    if not grade or not JobsSrv.GradeOf(name, grade) then return false, 'that rank does not exist' end
    if grade == emp.grade then return false, ('they are already %s'):format(rankText(name, grade)) end

    if not access.admin then
        if not access.boss then return false, 'only bosses of this job can change ranks' end
        if emp.src == src then return false, 'you cannot change your own rank' end
        if emp.grade >= access.grade then return false, 'you can only manage people below your rank' end
        if grade >= access.grade then return false, 'you can only promote up to one rank below yours' end
    end

    local ok, err = JobsSrv.SetJobByCid(emp.cid, name, grade)
    if not ok then return false, err end

    local verb = grade > emp.grade and 'promote' or 'demote'
    JobsSrv.LogAction(name, src, verb, emp.cid, ('%s -> %s'):format(rankText(name, emp.grade), rankText(name, grade)))
    tell(emp.src, ('You are now %s'):format(JobsSrv.Describe(name, grade)), grade > emp.grade and 'success' or 'inform')
    return true
end

function actions.setpay(src, name, access, data)
    if not access.boss then return false, 'only bosses of this job can change pay' end
    if Jobs[name].kind == 'business' and not access.top then return false, 'only the owner can change pay' end
    local grade = math.tointeger(tonumber(data.grade))
    local old = grade and JobsSrv.GradeOf(name, grade)
    if not old then return false, 'that rank does not exist' end
    local oldPay = old.pay

    local ok, err = JobsSrv.SetRankPay(name, grade, data.pay)
    if not ok then return false, err end
    JobsSrv.LogAction(name, src, 'setpay', nil, ('%s: $%d -> $%d'):format(old.label, oldPay, JobsSrv.GradeOf(name, grade).pay))
    return true
end

function actions.renamerank(src, name, access, data)
    if not access.admin then return false, 'only admins can edit ranks' end
    local grade = math.tointeger(tonumber(data.grade))
    local old = grade and JobsSrv.GradeOf(name, grade)
    if not old then return false, 'that rank does not exist' end
    local oldLabel = old.label

    local ok, err = JobsSrv.RenameRank(name, grade, data.label)
    if not ok then return false, err end
    JobsSrv.LogAction(name, src, 'renamerank', nil, ('%s -> %s'):format(oldLabel, JobsSrv.GradeOf(name, grade).label))
    return true
end

function actions.setboss(src, name, access, data)
    if not access.admin then return false, 'only admins can edit ranks' end
    local grade = math.tointeger(tonumber(data.grade))
    local ok, err = JobsSrv.SetRankBoss(name, grade, data.boss == true)
    if not ok then return false, err end
    JobsSrv.LogAction(name, src, 'setboss', nil, ('%s: boss %s'):format(rankText(name, grade), data.boss and 'on' or 'off'))
    return true
end

function actions.addrank(src, name, access, data)
    if not access.admin then return false, 'only admins can edit ranks' end
    local ok, result = JobsSrv.AddRank(name, data.label, data.pay or JobsSrv.PayRange(name).min, data.position)
    if not ok then return false, result end
    JobsSrv.LogAction(name, src, 'addrank', nil, ('%s at position %d'):format(rankText(name, result), result))
    return true
end

function actions.removerank(src, name, access, data)
    if not access.admin then return false, 'only admins can edit ranks' end
    local grade = math.tointeger(tonumber(data.grade))
    local label = grade and rankText(name, grade)
    local ok, err = JobsSrv.RemoveRank(name, grade)
    if not ok then return false, err end
    JobsSrv.LogAction(name, src, 'removerank', nil, label)
    return true
end

local function playerName(src)
    local p = TFC.GetPlayer(src)
    return p and p:GetFullName() or GetPlayerName(src) or tostring(src)
end

function actions.savings_deposit(src, name, access, data)
    if JobsSrv.SavingsAccess(src, name, access) ~= 'full' then return false, ('only %s can use the savings'):format(savingsWho(name)) end
    local n = math.tointeger(tonumber(data.amount))
    if not n or n < 1 then return false, 'enter an amount' end
    local reason = ('Deposit to %s savings'):format(Jobs[name].label)
    if not exports['tfc-accounts']:RemoveMoney(src, 'bank', n, reason) then return false, 'not enough in your bank' end
    if not banking():AddSociety(name, n, ('Deposit by %s'):format(playerName(src))) then
        exports['tfc-accounts']:AddMoney(src, 'bank', n, 'Refund: ' .. reason)
        return false, 'the deposit failed; you were refunded'
    end
    JobsSrv.LogAction(name, src, 'deposit', nil, ('$%d'):format(n))
    return true
end

function actions.savings_withdraw(src, name, access, data)
    if JobsSrv.SavingsAccess(src, name, access) ~= 'full' then return false, ('only %s can use the savings'):format(savingsWho(name)) end
    local n = math.tointeger(tonumber(data.amount))
    if not n or n < 1 then return false, 'enter an amount' end
    if not banking():RemoveSociety(name, n, ('Withdrawal by %s'):format(playerName(src))) then return false, 'not enough in the savings' end
    if not exports['tfc-accounts']:AddMoney(src, 'bank', n, ('Withdrawal from %s savings'):format(Jobs[name].label)) then
        banking():AddSociety(name, n, 'Refund: failed withdrawal')
        return false, 'the withdrawal failed'
    end
    JobsSrv.LogAction(name, src, 'withdraw', nil, ('$%d'):format(n))
    return true
end

---Run a Boss Menu action. Returns ok, err.
function JobsSrv.Action(src, name, action, data)
    if not Jobs[name] then return false, 'that job does not exist' end
    local fn = actions[action]
    if not fn then return false, 'unknown action' end

    local access = JobsSrv.Access(src, name)
    if not access.view then return false, 'you do not have access to this job' end
    return fn(src, name, access, type(data) == 'table' and data or {})
end

-- Menu data --------------------------------------------------------------------------------

local function jobList(src)
    local admin = TFC.IsAdmin(src)
    local state = JobsSrv.Load(src)
    local list = {}
    for name, job in pairs(Jobs) do
        if admin or JobsSrv.Access(src, name).boss then
            list[#list + 1] = { name = name, label = job.label }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list, state and state.name
end

local function savingsData(src, name, access)
    local level = JobsSrv.SavingsAccess(src, name, access)
    if not level then return nil end
    local b = banking()
    return { access = level, balance = b:GetSociety(name), history = b:GetSocietyHistory(name, 25), who = savingsWho(name) }
end

function JobsSrv.MenuData(src, name)
    local access = JobsSrv.Access(src, name)
    if not access.view then return { ok = false, error = 'you do not have access to this job' } end

    local employees = JobsSrv.GetEmployees(name)
    local counts, online, onDuty = {}, 0, 0
    for _, e in ipairs(employees) do
        counts[e.grade] = (counts[e.grade] or 0) + 1
        if e.online then online = online + 1 end
        if e.onDuty then onDuty = onDuty + 1 end
    end

    local ranks = {}
    for g = 0, JobsSrv.MaxGrade(name) do
        local def = Jobs[name].grades[g]
        if def then
            ranks[#ranks + 1] = { grade = g, label = def.label, pay = def.pay, boss = def.boss == true, count = counts[g] or 0 }
        end
    end

    local job = Jobs[name]
    local me = JobsSrv.cache[src]
    return {
        ok = true,
        me = me and me.cid or nil,
        job = { name = name, label = job.label, noDuty = job.noDuty == true, isDefault = name == JobsConfig.DefaultJob },
        access = { boss = access.boss, admin = access.admin, grade = access.grade },
        payRange = JobsSrv.PayRange(name),
        paycheckMinutes = JobsConfig.PaycheckMinutes,
        ranks = ranks,
        employees = employees,
        stats = { total = #employees, online = online, onDuty = onDuty, payroll = JobsSrv.GetPayroll(name) },
        log = JobsSrv.GetLog(name),
        maxRanks = Cfg.MaxRanks,
        savings = savingsData(src, name, access),
        business = job.kind == 'business',
        top = access.top,
    }
end

-- Callbacks (the menu's only way in) ------------------------------------------------------------

TFC.Callback.Register('jobs:boss:open', function(src)
    local list, current = jobList(src)
    if #list == 0 then return { ok = false, error = 'the Boss Menu is for bosses and admins' } end

    local start = list[1].name
    for _, j in ipairs(list) do
        if j.name == current then start = current end
    end
    local data = JobsSrv.MenuData(src, start)
    data.jobs = list
    return data
end, { rateLimit = 1000 })

TFC.Callback.Register('jobs:boss:get', function(src, name)
    return JobsSrv.MenuData(src, name)
end, { rateLimit = 300 })

TFC.Callback.Register('jobs:boss:nearby', function(src, name)
    local access = Jobs[name] and JobsSrv.Access(src, name)
    if not access or not access.boss then return { ok = false, error = 'only bosses of this job can hire' } end
    return { ok = true, players = JobsSrv.Nearby(src, name) }
end, { rateLimit = 500 })

TFC.Callback.Register('jobs:boss:action', function(src, name, action, data)
    local ok, err = JobsSrv.Action(src, name, action, data)
    local result = JobsSrv.MenuData(src, name)
    result.actionOk = ok
    result.actionError = err
    return result
end, { rateLimit = 400 })

-- Chat shortcuts for bosses (same rules as the menu) -------------------------------------------

local function bossJob(src)
    local state = JobsSrv.Load(src)
    if not state or not JobsSrv.Access(src, state.name).boss then
        JobsSrv.Notify(src, 'only bosses can do that', 'error')
        return nil
    end
    return state.name
end

local function targetCid(src, arg)
    local target = TFC.ResolveTarget(src, arg)
    local state = target and JobsSrv.cache[target]
    if not state then
        JobsSrv.Notify(src, ('no player with ID %s is online'):format(tostring(arg)), 'error')
        return nil
    end
    return state.cid, target, state
end

local function done(src, ok, err, text)
    JobsSrv.Notify(src, ok and text or err, ok and 'success' or 'error')
end

local TARGET = { name = 'id', help = 'Player server ID' }

TFC.RegisterCommand('hire', {
    help = 'Boss: hire the player next to you',
    params = { TARGET, { name = 'grade', help = 'Rank number (default 0)', optional = true } },
}, function(src, args)
    local name = bossJob(src); if not name then return end
    local target = TFC.ResolveTarget(src, args[1])
    local ok, err = JobsSrv.Action(src, name, 'hire', { target = target, grade = args[2] or 0 })
    done(src, ok, err, ('Hired %s'):format(target and GetPlayerName(target) or '?'))
end)

TFC.RegisterCommand('fire', { help = 'Boss: fire an employee', params = { TARGET } }, function(src, args)
    local name = bossJob(src); if not name then return end
    local cid, target = targetCid(src, args[1]); if not cid then return end
    local ok, err = JobsSrv.Action(src, name, 'fire', { cid = cid })
    done(src, ok, err, ('Fired %s'):format(GetPlayerName(target) or target))
end)

local function step(delta)
    return function(src, args)
        local name = bossJob(src); if not name then return end
        local cid, target, state = targetCid(src, args[1]); if not cid then return end
        if state.name ~= name then return JobsSrv.Notify(src, 'they do not work for you', 'error') end
        local ok, err = JobsSrv.Action(src, name, 'setgrade', { cid = cid, grade = state.grade + delta })
        done(src, ok, err, ('%s is now %s'):format(GetPlayerName(target) or target, rankText(name, state.grade)))
    end
end

TFC.RegisterCommand('promote', { help = 'Boss: promote an employee one rank', params = { TARGET } }, step(1))
TFC.RegisterCommand('demote', { help = 'Boss: demote an employee one rank', params = { TARGET } }, step(-1))
