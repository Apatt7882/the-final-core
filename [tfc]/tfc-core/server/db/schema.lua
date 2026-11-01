-- Runs sql/schema.sql once oxmysql is connected, then marks the database ready.

TFC.DB = { Ready = false, Failed = false }

local function runSchema()
    local sql = LoadResourceFile(TFC.Resource, 'sql/schema.sql')
    if not sql then
        error('sql/schema.sql is missing')
    end

    -- Drop comment lines, then split on semicolons that end a line.
    sql = sql:gsub('%-%-[^\n]*', '')
    for statement in sql:gmatch('(.-);%s*\n') do
        statement = statement:match('^%s*(.-)%s*$')
        if statement ~= '' then
            MySQL.query.await(statement)
        end
    end
end

MySQL.ready(function()
    local ok, err = pcall(runSchema)
    if not ok then
        TFC.DB.Failed = true
        TFC.Log.Error('database setup failed, players cannot load: %s', err)
        return
    end

    TFC.DB.Ready = true
    TFC.Log.Info('database ready')
    TFC.Emit('databaseReady')
end)

---Wait (yielding) until the schema has run. Returns false if setup failed or timed out.
---@param timeoutMs? integer default 15000
---@return boolean
function TFC.DB.AwaitReady(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 15000)
    while not TFC.DB.Ready do
        if TFC.DB.Failed or GetGameTimer() > deadline then return false end
        Wait(100)
    end
    return true
end
