-- Jobs: one job + grade per character (saved immediately), a duty toggle (not saved:
-- everyone starts off duty), and government paychecks per on-duty minute.
--
-- Public state bag on every loaded player, read by tfc-hud and anyone else:
--   tfc:job = { name, label, grade, gradeLabel, onDuty, isBoss }
--
-- Exports (server):
--   GetJob(src) -> table|nil                 SetJob(src, job, grade) -> ok, err
--   SetJobByCid(cid, job, grade) -> ok, err  (works offline)
--   SetDuty(src, onDuty) -> ok, err          ToggleDuty(src) -> ok, errOrOnDuty
--   IsOnDuty(src) -> bool                    HasJob(src, job, minGrade?) -> bool
--   GetPlayersWithJob(job, onDutyOnly?) -> integer[]
--   GetJobs() -> config table
-- Server hooks: jobChanged(source, job, oldJob), dutyChanged(source, onDuty, job)

local Jobs = JobsConfig.Jobs

---@class TFCJobState
---@field charId integer
---@field name string
---@field grade integer
---@field onDuty boolean
---@field minutes integer on-duty minutes towards the next paycheck

---@type table<integer, TFCJobState>
local cache = {}
local tablesReady = false
local Load

-- Config checks ----------------------------------------------------------------------

local function maxGrade(job)
    local max = 0
    for g in pairs(job.grades) do
        if g > max then max = g end
    end
    return max
end

do
    if not Jobs[JobsConfig.DefaultJob] then
        error(('DefaultJob "%s" is not defined in Jobs'):format(JobsConfig.DefaultJob))
    end
    for name, job in pairs(Jobs) do
        if not job.grades or not job.grades[0] then
            error(('job "%s" needs a grade 0'):format(name))
        end
    end
end

-- Helpers ------------------------------------------------------------------------------

---@param name string
---@param grade integer
local function gradeOf(name, grade)
    local job = Jobs[name]
    return job and job.grades[grade]
end

---The public view of a player's job (also the state bag value).
---@param state TFCJobState
local function view(state)
    local job = Jobs[state.name]
    local grade = job.grades[state.grade]

    -- nil = this job has no duty; true/false = on/off duty. (Not `a and b or nil`:
    -- that turns false into nil.)
    local onDuty = nil
    if not job.noDuty then onDuty = state.onDuty == true end

    local gradeLabel = nil
    if state.name ~= JobsConfig.DefaultJob then gradeLabel = grade.label end

    return {
        name = state.name,
        label = job.label,
        grade = state.grade,
        gradeLabel = gradeLabel,
        onDuty = onDuty,
        isBoss = grade.boss == true,
        pay = grade.pay or 0,
    }
end

local function publish(src)
    local state = cache[src]
    local player = TFC.GetPlayer(src)
    if not state or not player then return end
    player:SetState('job', view(state))
end

local function notify(src, text, kind)
    if src == 0 then
        TFC.Log.Info(text)
    else
        TFC.UI.Notify(src, { title = 'Jobs', description = text, type = kind or 'inform' })
    end
end

local function describe(name, grade)
    local job = Jobs[name]
    if name == JobsConfig.DefaultJob then return job.label end
    return ('%s %s'):format(job.label, job.grades[grade].label)
end

-- Storage -------------------------------------------------------------------------------

local SCHEMA = [[
    CREATE TABLE IF NOT EXISTS `tfc_character_jobs` (
        `character_id` INT UNSIGNED     NOT NULL,
        `job`          VARCHAR(32)      NOT NULL,
        `grade`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
        `updated_at`   TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`character_id`),
        KEY `idx_tfc_character_jobs_job` (`job`),
        CONSTRAINT `fk_tfc_character_jobs_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]]

local function save(charId, name, grade)
    MySQL.query.await([[
        INSERT INTO tfc_character_jobs (character_id, job, grade) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE job = VALUES(job), grade = VALUES(grade)
    ]], { charId, name, grade })
end

---Load a player's job into the cache (creating the default if they have none).
Load = function(src)
    src = tonumber(src) --[[@as integer]]
    if cache[src] then return cache[src] end
    if not tablesReady then return nil end

    local player = TFC.GetPlayer(src)
    if not player then return nil end
    local charId = player.characterId

    local row = MySQL.single.await('SELECT job, grade FROM tfc_character_jobs WHERE character_id = ?', { charId })
    local name, grade = JobsConfig.DefaultJob, 0

    if row then
        name, grade = row.job, math.tointeger(row.grade) or 0
        -- A job removed from the config, or a grade that no longer exists, falls back safely.
        if not Jobs[name] then
            TFC.Log.Warn('character %d had unknown job "%s"; reset to %s', charId, name, JobsConfig.DefaultJob)
            name, grade = JobsConfig.DefaultJob, 0
            save(charId, name, grade)
        elseif not gradeOf(name, grade) then
            grade = math.min(grade, maxGrade(Jobs[name]))
            if not gradeOf(name, grade) then grade = 0 end
            save(charId, name, grade)
        end
    else
        save(charId, name, grade)
    end

    -- Still the same character after the query?
    local now = TFC.GetPlayer(src)
    if not now or now.characterId ~= charId then return nil end

    cache[src] = { charId = charId, name = name, grade = grade, onDuty = false, minutes = 0 }
    publish(src)
    return cache[src]
end

-- API ------------------------------------------------------------------------------------

local function GetJob(src)
    local state = Load(src)
    return state and view(state) or nil
end

---@return boolean ok
---@return string|nil err
local function SetJob(src, name, grade)
    src = tonumber(src) --[[@as integer]]
    grade = math.tointeger(tonumber(grade) or 0)
    if not Jobs[name] then return false, ('job "%s" does not exist'):format(tostring(name)) end
    if not grade or not gradeOf(name, grade) then
        return false, ('%s has grades 0-%d'):format(Jobs[name].label, maxGrade(Jobs[name]))
    end

    local state = Load(src)
    if not state then return false, 'player has no loaded character' end

    local old = view(state)
    save(state.charId, name, grade)

    local changedJob = state.name ~= name
    state.name, state.grade = name, grade
    if changedJob then
        state.onDuty = false
        state.minutes = 0
    end

    publish(src)
    TFC.Emit('jobChanged', src, view(state), old)
    return true
end

---Change the job of a character who may be offline.
local function SetJobByCid(cid, name, grade)
    local online = TFC.GetPlayerByCid(cid)
    if online then return SetJob(online.source, name, grade) end

    grade = math.tointeger(tonumber(grade) or 0)
    if not Jobs[name] then return false, ('job "%s" does not exist'):format(tostring(name)) end
    if not grade or not gradeOf(name, grade) then return false, 'that grade does not exist' end

    local charId = MySQL.scalar.await('SELECT id FROM tfc_characters WHERE cid = ?', { cid })
    if not charId then return false, ('no character with cid %s'):format(tostring(cid)) end

    save(charId, name, grade)
    return true
end

local function SetDuty(src, onDuty)
    src = tonumber(src) --[[@as integer]]
    local state = Load(src)
    if not state then return false, 'player has no loaded character' end
    if Jobs[state.name].noDuty then return false, ('%s has no duty'):format(Jobs[state.name].label) end

    onDuty = onDuty == true
    if state.onDuty == onDuty then return true end

    state.onDuty = onDuty
    publish(src)
    TFC.Emit('dutyChanged', src, onDuty, view(state))
    return true
end

local function ToggleDuty(src)
    local state = Load(src)
    if not state then return false, 'player has no loaded character' end
    local ok, err = SetDuty(src, not state.onDuty)
    if not ok then return false, err end
    return true, state.onDuty
end

local function IsOnDuty(src)
    local state = Load(src)
    return state ~= nil and state.onDuty == true
end

local function HasJob(src, name, minGrade)
    local state = Load(src)
    return state ~= nil and state.name == name and state.grade >= (minGrade or 0)
end

local function GetPlayersWithJob(name, onDutyOnly)
    local list = {}
    for src, state in pairs(cache) do
        if state.name == name and (not onDutyOnly or state.onDuty) then
            list[#list + 1] = src
        end
    end
    return list
end

exports('GetJob', GetJob)
exports('SetJob', SetJob)
exports('SetJobByCid', SetJobByCid)
exports('SetDuty', SetDuty)
exports('ToggleDuty', ToggleDuty)
exports('IsOnDuty', IsOnDuty)
exports('HasJob', HasJob)
exports('GetPlayersWithJob', GetPlayersWithJob)
exports('GetJobs', function() return Jobs end)

-- Lifecycle --------------------------------------------------------------------------------

CreateThread(function()
    while not exports['tfc-core']:IsDatabaseReady() do Wait(250) end
    MySQL.query.await(SCHEMA)
    tablesReady = true

    local count = 0
    for _ in pairs(Jobs) do count = count + 1 end
    TFC.RegisterModule({ name = 'jobs', version = '0.1.0' }, function()
        TFC.Log.Info('jobs ready: %d jobs, paycheck every %d min', count, JobsConfig.PaycheckMinutes)
    end)

    for _, src in ipairs(TFC.GetPlayers()) do
        CreateThread(function() Load(src) end)
    end
end)

TFC.On('playerLoaded', function(src)
    CreateThread(function() Load(src) end)
end)

TFC.On('playerUnloaded', function(src)
    cache[src] = nil
end)

-- Paychecks: count working minutes per player; pay when they reach PaycheckMinutes.
CreateThread(function()
    while true do
        Wait(60000)
        local accounts = GetResourceState('tfc-accounts') == 'started'

        for src, state in pairs(cache) do
            local job = Jobs[state.name]
            local working = job.noDuty or state.onDuty or JobsConfig.PayOffDuty
            if working then
                state.minutes = state.minutes + 1
                if state.minutes >= JobsConfig.PaycheckMinutes then
                    state.minutes = 0
                    local pay = job.grades[state.grade].pay or 0
                    if accounts and pay > 0 then
                        local reason = ('Paycheck: %s'):format(describe(state.name, state.grade))
                        exports['tfc-accounts']:AddMoney(src, 'bank', pay, reason)
                    end
                end
            end
        end
    end
end)

-- Commands --------------------------------------------------------------------------------

TFC.RegisterCommand('duty', { help = 'Go on or off duty' }, function(src)
    if src == 0 then return end
    local ok, result = ToggleDuty(src)
    if not ok then return notify(src, result, 'error') end
    local job = GetJob(src)
    notify(src, ('%s: %s duty'):format(job.label, result and 'on' or 'off'), result and 'success' or 'inform')
end)

TFC.RegisterCommand('job', { help = 'Show your job, rank and pay' }, function(src)
    if src == 0 then return end
    local job = GetJob(src)
    if not job then return end
    local text = describe(job.name, job.grade)
    if job.onDuty ~= nil then text = text .. (job.onDuty and ' (on duty)' or ' (off duty)') end
    text = text .. (' | $%d every %d min'):format(job.pay, JobsConfig.PaycheckMinutes)
    notify(src, text)
end)

TFC.RegisterCommand('setjob', {
    help = 'Admin: set a player\'s job',
    restricted = true,
    params = {
        { name = 'id', help = 'Player server ID, or "me"' },
        { name = 'job', help = 'Job name, e.g. police, ambulance, unemployed' },
        { name = 'grade', help = 'Rank number, 0 = lowest', optional = true },
    },
}, function(src, args)
    local target = TFC.ResolveTarget(src, args[1])
    if not target then return notify(src, ('no player with ID %s is online'):format(tostring(args[1])), 'error') end

    local ok, err = SetJob(target, args[2], args[3] or 0)
    if not ok then return notify(src, err, 'error') end

    local job = GetJob(target)
    notify(src, ('%s is now %s'):format(GetPlayerName(target) or target, describe(job.name, job.grade)), 'success')
    if target ~= src then notify(target, ('You are now %s'):format(describe(job.name, job.grade)), 'success') end
end)

-- Boss commands: manage people in your own job, only below your own rank.

---@return TFCJobState|nil boss, integer|nil target, TFCJobState|nil targetState
local function bossCheck(src, arg, needSameJob)
    if src == 0 then return nil end
    local boss = Load(src)
    local bossGrade = boss and gradeOf(boss.name, boss.grade)
    if not bossGrade or not bossGrade.boss then
        notify(src, 'only bosses can do that', 'error')
        return nil
    end

    local target = TFC.ResolveTarget(src, arg)
    if not target then
        notify(src, ('no player with ID %s is online'):format(tostring(arg)), 'error')
        return nil
    end
    if target == src then
        notify(src, 'you cannot manage yourself', 'error')
        return nil
    end

    local targetState = Load(target)
    if not targetState then
        notify(src, 'that player has no character loaded', 'error')
        return nil
    end
    if needSameJob and targetState.name ~= boss.name then
        notify(src, ('%s does not work for %s'):format(GetPlayerName(target) or target, Jobs[boss.name].label), 'error')
        return nil
    end
    if needSameJob and targetState.grade >= boss.grade then
        notify(src, 'you can only manage people below your rank', 'error')
        return nil
    end
    return boss, target, targetState
end

local TARGET = { name = 'id', help = 'Player server ID' }

TFC.RegisterCommand('hire', {
    help = 'Boss: hire a player into your job',
    params = { TARGET, { name = 'grade', help = 'Rank number (default 0)', optional = true } },
}, function(src, args)
    local boss, target, targetState = bossCheck(src, args[1], false)
    if not boss then return end
    if targetState.name == boss.name then return notify(src, 'they already work here; use /promote', 'error') end

    local grade = math.tointeger(tonumber(args[2] or 0)) or 0
    if grade >= boss.grade then return notify(src, 'you can only hire below your own rank', 'error') end

    local ok, err = SetJob(target, boss.name, grade)
    if not ok then return notify(src, err, 'error') end
    notify(src, ('Hired %s as %s'):format(GetPlayerName(target) or target, describe(boss.name, grade)), 'success')
    notify(target, ('You were hired as %s'):format(describe(boss.name, grade)), 'success')
end)

TFC.RegisterCommand('fire', {
    help = 'Boss: fire a player from your job',
    params = { TARGET },
}, function(src, args)
    local boss, target = bossCheck(src, args[1], true)
    if not boss then return end

    SetJob(target, JobsConfig.DefaultJob, 0)
    notify(src, ('Fired %s'):format(GetPlayerName(target) or target), 'success')
    notify(target, ('You were let go from %s'):format(Jobs[boss.name].label), 'error')
end)

local function changeRank(delta)
    return function(src, args)
        local boss, target, targetState = bossCheck(src, args[1], true)
        if not boss then return end

        local grade = targetState.grade + delta
        if grade >= boss.grade then return notify(src, 'you can only promote up to one rank below yours', 'error') end
        if not gradeOf(boss.name, grade) then return notify(src, 'there is no rank there', 'error') end

        SetJob(target, boss.name, grade)
        local text = describe(boss.name, grade)
        notify(src, ('%s is now %s'):format(GetPlayerName(target) or target, text), 'success')
        notify(target, ('You are now %s'):format(text), delta > 0 and 'success' or 'inform')
    end
end

TFC.RegisterCommand('promote', { help = 'Boss: promote an employee one rank', params = { TARGET } }, changeRank(1))
TFC.RegisterCommand('demote', { help = 'Boss: demote an employee one rank', params = { TARGET } }, changeRank(-1))
