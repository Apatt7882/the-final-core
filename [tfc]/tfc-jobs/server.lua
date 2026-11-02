-- Jobs core: one job + grade per character (saved immediately), a duty toggle (not saved:
-- everyone starts off duty), and government paychecks per on-duty minute.
-- Ranks come from the database (server/ranks.lua); stats and the Boss Menu live in server/.
--
-- Public state bag on every loaded player, read by tfc-hud and anyone else:
--   tfc:job = { name, label, grade, gradeLabel, onDuty, isBoss, pay }
--
-- Exports (server):
--   GetJob(src) -> table|nil                 SetJob(src, job, grade) -> ok, err
--   SetJobByCid(cid, job, grade) -> ok, err  (works offline)
--   SetDuty(src, onDuty) -> ok, err          ToggleDuty(src) -> ok, errOrOnDuty
--   IsOnDuty(src) -> bool                    HasJob(src, job, minGrade?) -> bool
--   GetPlayersWithJob(job, onDutyOnly?) -> integer[]
--   GetJobs() -> jobs with their current ranks
-- Server hooks: jobChanged(source, job, oldJob), dutyChanged(source, onDuty, job)

---Shared by every server file in this resource. Jobs[name].grades is replaced from the
---database at start (server/ranks.lua).
Jobs = JobsConfig.Jobs
JobsSrv = { cache = {}, ready = false }

---@class TFCJobState
---@field charId integer
---@field cid string
---@field name string
---@field grade integer
---@field onDuty boolean
---@field minutes integer on-duty minutes towards the next paycheck

---@type table<integer, TFCJobState>
local cache = JobsSrv.cache

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

function JobsSrv.MaxGrade(name)
    local max = 0
    for g in pairs(Jobs[name].grades) do
        if g > max then max = g end
    end
    return max
end

function JobsSrv.GradeOf(name, grade)
    local job = Jobs[name]
    return job and job.grades[grade]
end

function JobsSrv.PayRange(name)
    return Jobs[name].payRange or JobsConfig.DefaultPayRange
end

function JobsSrv.Describe(name, grade)
    local job = Jobs[name]
    if name == JobsConfig.DefaultJob or not job.grades[grade] then return job.label end
    return ('%s %s'):format(job.label, job.grades[grade].label)
end

function JobsSrv.Notify(src, text, kind)
    if src == 0 then
        TFC.Log.Info(text)
    else
        TFC.UI.Notify(src, { title = 'Jobs', description = text, type = kind or 'inform' })
    end
end

---The public view of a player's job (also the state bag value).
---@param state TFCJobState
function JobsSrv.View(state)
    local job = Jobs[state.name]
    local grade = job.grades[state.grade] or job.grades[0]

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

function JobsSrv.Publish(src)
    local state = cache[src]
    local player = TFC.GetPlayer(src)
    if not state or not player then return end
    player:SetState('job', JobsSrv.View(state))
end

---Re-send the state bag of everyone online in a job (after its ranks change).
function JobsSrv.PublishJob(name)
    for src, state in pairs(cache) do
        if state.name == name then JobsSrv.Publish(src) end
    end
end

-- Storage -------------------------------------------------------------------------------

function JobsSrv.Save(charId, name, grade)
    MySQL.query.await([[
        INSERT INTO tfc_character_jobs (character_id, job, grade) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE job = VALUES(job), grade = VALUES(grade)
    ]], { charId, name, grade })
end

---Load a player's job into the cache (creating the default if they have none).
function JobsSrv.Load(src)
    src = tonumber(src) --[[@as integer]]
    if cache[src] then return cache[src] end
    if not JobsSrv.ready then return nil end

    local player = TFC.GetPlayer(src)
    if not player then return nil end
    local charId, cid = player.characterId, player.cid

    local row = MySQL.single.await('SELECT job, grade FROM tfc_character_jobs WHERE character_id = ?', { charId })
    local name, grade = JobsConfig.DefaultJob, 0

    if row then
        name, grade = row.job, math.tointeger(row.grade) or 0
        -- A job removed from the config, or a grade that no longer exists, falls back safely.
        if not Jobs[name] then
            TFC.Log.Warn('character %d had unknown job "%s"; reset to %s', charId, name, JobsConfig.DefaultJob)
            name, grade = JobsConfig.DefaultJob, 0
            JobsSrv.Save(charId, name, grade)
        elseif not JobsSrv.GradeOf(name, grade) then
            grade = math.min(grade, JobsSrv.MaxGrade(name))
            if not JobsSrv.GradeOf(name, grade) then grade = 0 end
            JobsSrv.Save(charId, name, grade)
        end
    else
        JobsSrv.Save(charId, name, grade)
    end

    -- Still the same character after the query?
    local now = TFC.GetPlayer(src)
    if not now or now.characterId ~= charId then return nil end

    cache[src] = { charId = charId, cid = cid, name = name, grade = grade, onDuty = false, minutes = 0 }
    JobsSrv.Publish(src)
    return cache[src]
end

-- API ------------------------------------------------------------------------------------

local function GetJob(src)
    local state = JobsSrv.Load(src)
    return state and JobsSrv.View(state) or nil
end

---@return boolean ok
---@return string|nil err
local function SetJob(src, name, grade)
    src = tonumber(src) --[[@as integer]]
    grade = math.tointeger(tonumber(grade) or 0)
    if not Jobs[name] then return false, ('job "%s" does not exist'):format(tostring(name)) end
    if not grade or not JobsSrv.GradeOf(name, grade) then
        return false, ('%s has ranks 0-%d'):format(Jobs[name].label, JobsSrv.MaxGrade(name))
    end

    local state = JobsSrv.Load(src)
    if not state then return false, 'player has no loaded character' end

    local old = JobsSrv.View(state)
    JobsSrv.Save(state.charId, name, grade)

    if state.name ~= name then
        if state.onDuty then
            state.onDuty = false
            TFC.Emit('dutyChanged', src, false, old) -- closes the duty session
        end
        state.minutes = 0
    end
    state.name, state.grade = name, grade

    JobsSrv.Publish(src)
    TFC.Emit('jobChanged', src, JobsSrv.View(state), old)
    return true
end

---Change the job of a character who may be offline.
local function SetJobByCid(cid, name, grade)
    local online = TFC.GetPlayerByCid(cid)
    if online then return SetJob(online.source, name, grade) end

    grade = math.tointeger(tonumber(grade) or 0)
    if not Jobs[name] then return false, ('job "%s" does not exist'):format(tostring(name)) end
    if not grade or not JobsSrv.GradeOf(name, grade) then return false, 'that rank does not exist' end

    local charId = MySQL.scalar.await('SELECT id FROM tfc_characters WHERE cid = ?', { cid })
    if not charId then return false, ('no character with cid %s'):format(tostring(cid)) end

    JobsSrv.Save(charId, name, grade)
    return true
end

local function SetDuty(src, onDuty)
    src = tonumber(src) --[[@as integer]]
    local state = JobsSrv.Load(src)
    if not state then return false, 'player has no loaded character' end
    if Jobs[state.name].noDuty then return false, ('%s has no duty'):format(Jobs[state.name].label) end

    onDuty = onDuty == true
    if state.onDuty == onDuty then return true end

    state.onDuty = onDuty
    JobsSrv.Publish(src)
    TFC.Emit('dutyChanged', src, onDuty, JobsSrv.View(state))
    return true
end

local function ToggleDuty(src)
    local state = JobsSrv.Load(src)
    if not state then return false, 'player has no loaded character' end
    local ok, err = SetDuty(src, not state.onDuty)
    if not ok then return false, err end
    return true, state.onDuty
end

local function IsOnDuty(src)
    local state = JobsSrv.Load(src)
    return state ~= nil and state.onDuty == true
end

local function HasJob(src, name, minGrade)
    local state = JobsSrv.Load(src)
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

JobsSrv.GetJob = GetJob
JobsSrv.SetJob = SetJob
JobsSrv.SetJobByCid = SetJobByCid
JobsSrv.SetDuty = SetDuty

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

TFC.On('playerLoaded', function(src)
    CreateThread(function() JobsSrv.Load(src) end)
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
                    local grade = job.grades[state.grade]
                    local pay = grade and grade.pay or 0
                    if accounts and pay > 0 then
                        local reason = ('Paycheck: %s'):format(JobsSrv.Describe(state.name, state.grade))
                        if exports['tfc-accounts']:AddMoney(src, 'bank', pay, reason) then
                            JobsSrv.RecordPay(state.name, state.charId, pay)
                        end
                    end
                end
            end
        end

        JobsSrv.TouchDutySessions()
    end
end)

-- Everyday commands ------------------------------------------------------------------------

TFC.RegisterCommand('duty', { help = 'Go on or off duty' }, function(src)
    if src == 0 then return end
    local ok, result = ToggleDuty(src)
    if not ok then return JobsSrv.Notify(src, result, 'error') end
    local job = GetJob(src)
    JobsSrv.Notify(src, ('%s: %s duty'):format(job.label, result and 'on' or 'off'), result and 'success' or 'inform')
end)

TFC.RegisterCommand('job', { help = 'Show your job, rank and pay' }, function(src)
    if src == 0 then return end
    local job = GetJob(src)
    if not job then return end
    local text = JobsSrv.Describe(job.name, job.grade)
    if job.onDuty ~= nil then text = text .. (job.onDuty and ' (on duty)' or ' (off duty)') end
    text = text .. (' | $%d every %d min'):format(job.pay, JobsConfig.PaycheckMinutes)
    JobsSrv.Notify(src, text)
end)

TFC.RegisterCommand('setjob', {
    help = 'Admin: set a player\'s job',
    permission = TFC.Permissions.Admin,
    params = {
        { name = 'id', help = 'Player server ID, or "me"' },
        { name = 'job', help = 'Job name, e.g. police, ambulance, unemployed' },
        { name = 'grade', help = 'Rank number, 0 = lowest', optional = true },
    },
}, function(src, args)
    local target = TFC.ResolveTarget(src, args[1])
    if not target then return JobsSrv.Notify(src, ('no player with ID %s is online'):format(tostring(args[1])), 'error') end

    local before = GetJob(target)
    local ok, err = SetJob(target, args[2], args[3] or 0)
    if not ok then return JobsSrv.Notify(src, err, 'error') end

    local job = GetJob(target)
    local text = JobsSrv.Describe(job.name, job.grade)
    JobsSrv.LogAction(job.name, src, 'setjob', JobsSrv.cache[target].cid, ('to %s (was %s)'):format(text,
        before and JobsSrv.Describe(before.name, before.grade) or '?'))
    JobsSrv.Notify(src, ('%s is now %s'):format(GetPlayerName(target) or target, text), 'success')
    if target ~= src then JobsSrv.Notify(target, ('You are now %s'):format(text), 'success') end
end)
