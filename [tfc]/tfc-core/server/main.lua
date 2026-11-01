TFC.Log.Info('%s v%s starting', TFC.Name, TFC.Version)

exports('GetVersion', function()
    return TFC.Version
end)

---True once the core tables exist. Modules with their own tables wait for this
---(or the databaseReady hook) before creating tables that reference tfc_characters.
exports('IsDatabaseReady', function()
    return TFC.DB.Ready
end)

---Read a core config value, e.g. exports['tfc-core']:GetConfig('MaxCharacters')
---@param key string
exports('GetConfig', function(key)
    if key == 'MaxCharacters' then
        return math.min(TFC.Config.MaxCharacters, 10)
    end
    return TFC.Config[key]
end)

local function printModules()
    local list = TFC.Modules.List()
    if #list == 0 then
        TFC.Log.Info('no modules registered')
        return
    end

    TFC.Log.Info('%d module(s):', #list)
    for _, m in ipairs(list) do
        local color = m.state == 'ready' and '^2' or '^3'
        TFC.Log.Info('  %s%-7s^7 %s v%s (%s)', color, m.state, m.name, m.version, m.resource)
    end
end

-- Admin command. From the server console: `tfc modules`, `tfc version`.
-- Players need: add_ace group.admin command.tfc allow
RegisterCommand('tfc', function(_, args)
    local sub = args[1]

    if sub == 'modules' then
        printModules()
    elseif sub == 'version' then
        TFC.Log.Info('%s v%s', TFC.Name, TFC.Version)
    else
        TFC.Log.Info('usage: tfc <modules|version>')
    end
end, true)
