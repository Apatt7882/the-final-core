-- Loaded last: create tables, load ranks, then register the module and load online players.

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

CreateThread(function()
    while not exports['tfc-core']:IsDatabaseReady() do Wait(250) end

    MySQL.query.await(SCHEMA)
    JobsSrv.CreateStatsTables()
    JobsSrv.LoadRanks()
    JobsSrv.ready = true

    local count = 0
    for _ in pairs(Jobs) do count = count + 1 end
    TFC.RegisterModule({ name = 'jobs', version = '0.2.2' }, function()
        TFC.Log.Info('jobs ready: %d jobs, paycheck every %d min on the clock', count, JobsConfig.PaycheckMinutes)
    end)

    for _, src in ipairs(TFC.GetPlayers()) do
        CreateThread(function() JobsSrv.Load(src) end)
    end
end)
