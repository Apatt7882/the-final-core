-- Ranks (grades) live in tfc_job_grades. config.lua seeds a job the first time it's seen;
-- after that the database is the source of truth and the Boss Menu edits it.
-- Grades are always numbered 0..n with no gaps, so adding or removing a rank renumbers
-- the ranks (and the people holding them) above it.

local SCHEMA = [[
    CREATE TABLE IF NOT EXISTS `tfc_job_grades` (
        `job`   VARCHAR(32)      NOT NULL,
        `grade` TINYINT UNSIGNED NOT NULL,
        `label` VARCHAR(48)      NOT NULL,
        `pay`   INT UNSIGNED     NOT NULL DEFAULT 0,
        `boss`  TINYINT(1)       NOT NULL DEFAULT 0,
        PRIMARY KEY (`job`, `grade`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]]

local function seed(name)
    local queries = {}
    for grade, def in pairs(JobsConfig.Jobs[name].grades) do
        queries[#queries + 1] = {
            query = 'INSERT INTO tfc_job_grades (job, grade, label, pay, boss) VALUES (?, ?, ?, ?, ?)',
            values = { name, grade, def.label, def.pay or 0, def.boss and 1 or 0 },
        }
    end
    MySQL.transaction.await(queries)
end

---Read one job's ranks from the database into Jobs[name].grades.
local function reload(name)
    local grades = {}
    for _, row in ipairs(MySQL.query.await('SELECT grade, label, pay, boss FROM tfc_job_grades WHERE job = ? ORDER BY grade', { name }) or {}) do
        local g = math.tointeger(row.grade)
        grades[g] = { label = row.label, pay = math.tointeger(row.pay) or 0, boss = row.boss == 1 or row.boss == true }
    end
    if grades[0] then
        Jobs[name].grades = grades
    end
end

---Create the table, seed any job with no ranks yet, and load every job's ranks.
function JobsSrv.LoadRanks()
    MySQL.query.await(SCHEMA)

    -- Remember the config's ranks so `resetranks` can restore them.
    for _, job in pairs(Jobs) do
        job.configGrades = job.configGrades or job.grades
    end

    for name in pairs(Jobs) do
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM tfc_job_grades WHERE job = ?', { name }) or 0
        if tonumber(count) == 0 then
            seed(name)
            TFC.Log.Info('seeded ranks for %s from config', name)
        end
        reload(name)
    end
end

-- Rank changes (callers check permissions) ---------------------------------------------

local function after(name)
    reload(name)
    JobsSrv.PublishJob(name)
end

local function validLabel(label)
    if type(label) ~= 'string' then return nil end
    label = label:match('^%s*(.-)%s*$')
    if #label < 1 or #label > 48 then return nil end
    return label
end

---@return boolean ok, string|nil err
function JobsSrv.SetRankPay(name, grade, pay)
    if not JobsSrv.GradeOf(name, grade) then return false, 'that rank does not exist' end
    pay = math.tointeger(tonumber(pay))
    local range = JobsSrv.PayRange(name)
    if not pay or pay < range.min or pay > range.max then
        return false, ('pay must be a whole number from $%d to $%d'):format(range.min, range.max)
    end
    MySQL.update.await('UPDATE tfc_job_grades SET pay = ? WHERE job = ? AND grade = ?', { pay, name, grade })
    after(name)
    return true
end

function JobsSrv.RenameRank(name, grade, label)
    if not JobsSrv.GradeOf(name, grade) then return false, 'that rank does not exist' end
    label = validLabel(label)
    if not label then return false, 'rank names must be 1-48 characters' end
    MySQL.update.await('UPDATE tfc_job_grades SET label = ? WHERE job = ? AND grade = ?', { label, name, grade })
    after(name)
    return true
end

function JobsSrv.SetRankBoss(name, grade, boss)
    if not JobsSrv.GradeOf(name, grade) then return false, 'that rank does not exist' end
    if name == JobsConfig.DefaultJob then return false, ('%s cannot have bosses'):format(Jobs[name].label) end
    MySQL.update.await('UPDATE tfc_job_grades SET boss = ? WHERE job = ? AND grade = ?', { boss and 1 or 0, name, grade })
    after(name)
    return true
end

---Number of characters (online or not) holding a rank.
function JobsSrv.CountAtGrade(name, grade)
    return tonumber((MySQL.scalar.await('SELECT COUNT(*) FROM tfc_character_jobs WHERE job = ? AND grade = ?', { name, grade }))) or 0
end

---Insert a rank at `position` (0 = new lowest rank; omit for a new top rank).
---Everyone at or above that position moves up one grade number (their rank is unchanged).
function JobsSrv.AddRank(name, label, pay, position)
    label = validLabel(label)
    if not label then return false, 'rank names must be 1-48 characters' end

    local top = JobsSrv.MaxGrade(name)
    if top + 1 >= JobsConfig.BossMenu.MaxRanks then
        return false, ('a job can have at most %d ranks'):format(JobsConfig.BossMenu.MaxRanks)
    end

    position = math.tointeger(tonumber(position)) or (top + 1)
    if position < 0 or position > top + 1 then return false, 'invalid position' end

    pay = math.tointeger(tonumber(pay)) or 0
    local range = JobsSrv.PayRange(name)
    if pay < range.min or pay > range.max then
        return false, ('pay must be from $%d to $%d'):format(range.min, range.max)
    end

    -- Shift from the top down so (job, grade) never collides.
    MySQL.transaction.await({
        { query = 'UPDATE tfc_job_grades SET grade = grade + 1 WHERE job = ? AND grade >= ? ORDER BY grade DESC', values = { name, position } },
        { query = 'UPDATE tfc_character_jobs SET grade = grade + 1 WHERE job = ? AND grade >= ?', values = { name, position } },
        { query = 'INSERT INTO tfc_job_grades (job, grade, label, pay, boss) VALUES (?, ?, ?, ?, 0)', values = { name, position, label, pay } },
    })

    for _, state in pairs(JobsSrv.cache) do
        if state.name == name and state.grade >= position then state.grade = state.grade + 1 end
    end
    after(name)
    return true, position
end

---Remove an empty rank. Ranks above it move down one grade number.
function JobsSrv.RemoveRank(name, grade)
    if not JobsSrv.GradeOf(name, grade) then return false, 'that rank does not exist' end
    if JobsSrv.MaxGrade(name) == 0 then return false, 'a job needs at least one rank' end

    local holders = JobsSrv.CountAtGrade(name, grade)
    if holders > 0 then
        return false, ('%d %s this rank; move them first'):format(holders, holders == 1 and 'person holds' or 'people hold')
    end

    MySQL.transaction.await({
        { query = 'DELETE FROM tfc_job_grades WHERE job = ? AND grade = ?', values = { name, grade } },
        { query = 'UPDATE tfc_job_grades SET grade = grade - 1 WHERE job = ? AND grade > ? ORDER BY grade ASC', values = { name, grade } },
        { query = 'UPDATE tfc_character_jobs SET grade = grade - 1 WHERE job = ? AND grade > ?', values = { name, grade } },
    })

    for _, state in pairs(JobsSrv.cache) do
        if state.name == name and state.grade > grade then state.grade = state.grade - 1 end
    end
    after(name)
    return true
end

---Throw away a job's edited ranks and restore the ones in config.lua.
---People above the new top rank are moved to it.
function JobsSrv.ResetRanks(name)
    if not Jobs[name] then return false, 'no such job' end
    local configGrades = Jobs[name].configGrades
    local top = 0
    for g in pairs(configGrades) do if g > top then top = g end end

    MySQL.transaction.await({
        { query = 'DELETE FROM tfc_job_grades WHERE job = ?', values = { name } },
        { query = 'UPDATE tfc_character_jobs SET grade = ? WHERE job = ? AND grade > ?', values = { top, name, top } },
    })
    Jobs[name].grades = configGrades
    seed(name)

    for _, state in pairs(JobsSrv.cache) do
        if state.name == name and state.grade > top then state.grade = top end
    end
    after(name)
    return true
end

TFC.RegisterCommand('resetranks', {
    help = 'Admin: restore a job\'s ranks from config.lua',
    permission = TFC.Permissions.Admin,
    params = { { name = 'job', help = 'Job name, e.g. police' } },
}, function(src, args)
    local ok, err = JobsSrv.ResetRanks(args[1])
    if ok then JobsSrv.LogAction(args[1], src, 'resetranks', nil, 'ranks restored from config') end
    JobsSrv.Notify(src, ok and ('%s ranks restored from config'):format(args[1]) or err, ok and 'success' or 'error')
end)
