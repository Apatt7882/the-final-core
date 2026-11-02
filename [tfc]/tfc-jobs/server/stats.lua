-- Job statistics: duty sessions (for hours), payroll, and an activity log.
--
-- Duty sessions: a row is opened when someone goes on duty and its ended_at is refreshed
-- every minute, so a crash or restart never leaves a session "open forever"; it simply
-- ends at the last minute we saw them on duty.

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `tfc_job_duty` (
        `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `job`          VARCHAR(32)  NOT NULL,
        `character_id` INT UNSIGNED NOT NULL,
        `started_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `ended_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_job_duty_job` (`job`, `ended_at`),
        CONSTRAINT `fk_tfc_job_duty_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_job_payroll` (
        `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `job`          VARCHAR(32)  NOT NULL,
        `character_id` INT UNSIGNED NOT NULL,
        `amount`       INT UNSIGNED NOT NULL,
        `created_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_job_payroll_job` (`job`, `created_at`),
        CONSTRAINT `fk_tfc_job_payroll_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_job_log` (
        `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `job`         VARCHAR(32)  NOT NULL,
        `actor_name`  VARCHAR(70)  NOT NULL,
        `action`      VARCHAR(24)  NOT NULL,
        `target_cid`  CHAR(8)      NULL,
        `target_name` VARCHAR(70)  NULL,
        `details`     VARCHAR(160) NOT NULL DEFAULT '',
        `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_job_log_job` (`job`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

---@type table<integer, integer> source -> open tfc_job_duty id
local sessions = {}

function JobsSrv.CreateStatsTables()
    for _, statement in ipairs(SCHEMA) do
        MySQL.query.await(statement)
    end
end

-- Duty sessions ---------------------------------------------------------------------------

local function closeSession(src)
    local id = sessions[src]
    if not id then return end
    sessions[src] = nil
    MySQL.update('UPDATE tfc_job_duty SET ended_at = CURRENT_TIMESTAMP WHERE id = ?', { id })
end

TFC.On('dutyChanged', function(src, onDuty, job)
    closeSession(src)
    if not onDuty then return end

    local state = JobsSrv.cache[src]
    if not state then return end
    sessions[src] = MySQL.insert.await('INSERT INTO tfc_job_duty (job, character_id) VALUES (?, ?)', { job.name, state.charId })
end)

TFC.On('playerUnloaded', function(src)
    closeSession(src)
end)

---Called every minute by the paycheck loop.
function JobsSrv.TouchDutySessions()
    local ids = {}
    for _, id in pairs(sessions) do ids[#ids + 1] = id end
    if #ids == 0 then return end
    MySQL.update(('UPDATE tfc_job_duty SET ended_at = CURRENT_TIMESTAMP WHERE id IN (%s)'):format(table.concat(ids, ',')))
end

-- Payroll and log --------------------------------------------------------------------------

function JobsSrv.RecordPay(job, charId, amount)
    MySQL.insert('INSERT INTO tfc_job_payroll (job, character_id, amount) VALUES (?, ?, ?)', { job, charId, amount })
end

local function actorName(src)
    if src == 0 then return 'Console' end
    local player = TFC.GetPlayer(src)
    if player then return ('%s (%s)'):format(player:GetFullName(), GetPlayerName(src) or src) end
    return GetPlayerName(src) or tostring(src)
end

---Record a management action for the job's activity log.
---@param job string
---@param src integer who did it (0 = console)
---@param action string hire, fire, promote, demote, setgrade, setpay, addrank, ...
---@param targetCid string|nil
---@param details string
function JobsSrv.LogAction(job, src, action, targetCid, details)
    local targetName = nil
    if targetCid then
        local row = MySQL.single.await('SELECT firstname, lastname FROM tfc_characters WHERE cid = ?', { targetCid })
        targetName = row and ('%s %s'):format(row.firstname, row.lastname) or nil
    end
    MySQL.insert('INSERT INTO tfc_job_log (job, actor_name, action, target_cid, target_name, details) VALUES (?, ?, ?, NULLIF(?, \'\'), NULLIF(?, \'\'), ?)',
        { job, actorName(src):sub(1, 70), action, targetCid or '', targetName or '', (details or ''):sub(1, 160) })
end

-- Queries for the Boss Menu -------------------------------------------------------------------

---Everyone in a job (online or offline) with hours on duty over the last 7 days.
function JobsSrv.GetEmployees(job)
    local rows = MySQL.query.await([[
        SELECT c.id AS charId, c.cid, c.firstname, c.lastname, j.grade,
               COALESCE(d.seconds, 0) AS seconds
        FROM tfc_character_jobs j
        JOIN tfc_characters c ON c.id = j.character_id
        LEFT JOIN (
            SELECT character_id,
                   SUM(TIMESTAMPDIFF(SECOND, GREATEST(started_at, NOW() - INTERVAL 7 DAY), ended_at)) AS seconds
            FROM tfc_job_duty
            WHERE job = ? AND ended_at > NOW() - INTERVAL 7 DAY
            GROUP BY character_id
        ) d ON d.character_id = c.id
        WHERE j.job = ?
        ORDER BY j.grade DESC, c.lastname, c.firstname
    ]], { job, job }) or {}

    -- Who's online right now, and on duty.
    local online = {}
    for src, state in pairs(JobsSrv.cache) do
        online[state.charId] = { src = src, onDuty = state.onDuty }
    end

    local list = {}
    for i, row in ipairs(rows) do
        local live = online[row.charId]
        list[i] = {
            cid = row.cid,
            name = ('%s %s'):format(row.firstname, row.lastname),
            grade = math.tointeger(row.grade) or 0,
            online = live ~= nil,
            onDuty = live ~= nil and live.onDuty == true,
            hoursWeek = math.floor((tonumber(row.seconds) or 0) / 360 + 0.5) / 10, -- one decimal
        }
    end
    return list
end

function JobsSrv.GetPayroll(job)
    local row = MySQL.single.await([[
        SELECT COALESCE(SUM(CASE WHEN created_at >= CURDATE() THEN amount END), 0) AS today,
               COALESCE(SUM(amount), 0) AS week
        FROM tfc_job_payroll
        WHERE job = ? AND created_at >= NOW() - INTERVAL 7 DAY
    ]], { job }) or {}
    return { today = tonumber(row.today) or 0, week = tonumber(row.week) or 0 }
end

function JobsSrv.GetLog(job)
    return MySQL.query.await([[
        SELECT actor_name AS actor, action, target_name AS target, details,
               UNIX_TIMESTAMP(created_at) AS at
        FROM tfc_job_log WHERE job = ? ORDER BY id DESC LIMIT ?
    ]], { job, JobsConfig.BossMenu.LogEntries }) or {}
end
