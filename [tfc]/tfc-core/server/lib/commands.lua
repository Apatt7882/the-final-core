-- Commands with chat suggestions and usage help.
--
--   TFC.RegisterCommand('givemoney', {
--       help = 'Give money to a player',
--       permission = 'tfc.admin',                -- or restricted = true (ACE command.givemoney)
--       params = {
--           { name = 'id', help = 'Player server ID, or "me"' },
--           { name = 'account', help = 'cash, bank or credit' },
--           { name = 'amount', help = 'Whole dollars' },
--           { name = 'reason', help = 'Optional note', optional = true },
--       },
--   }, function(source, args, raw) ... end)
--
-- Players only get suggestions for commands they are allowed to use. If fewer
-- arguments than required are given, the player sees the usage instead of the handler running.

---@class TFCCommandParam
---@field name string
---@field help? string
---@field optional? boolean

---@class TFCCommandDef
---@field help string
---@field params? TFCCommandParam[]
---@field restricted? boolean ACE-restricted by FiveM (command.<name>)
---@field permission? string checked by TFC, e.g. 'tfc.admin' (one ACE line covers every admin command)

---@type table<string, TFCCommandDef>
local commands = {}

local function allowed(src, name, def)
    if def.permission and not TFC.HasPermission(src, def.permission) then return false end
    if def.restricted and src ~= 0 and not IsPlayerAceAllowed(tostring(src), 'command.' .. name) then return false end
    return true
end

local function usage(name, def)
    local parts = { '/' .. name }
    for _, p in ipairs(def.params or {}) do
        parts[#parts + 1] = p.optional and ('[%s]'):format(p.name) or ('<%s>'):format(p.name)
    end
    return table.concat(parts, ' ')
end

---Send this resource's suggestions to one player (only the ones they may use).
---@param src integer
local function pushTo(src)
    local list = {}
    for name, def in pairs(commands) do
        if allowed(src, name, def) then
            local params = {}
            for i, p in ipairs(def.params or {}) do
                params[i] = { name = p.optional and ('%s (optional)'):format(p.name) or p.name, help = p.help or '' }
            end
            list[#list + 1] = { name = '/' .. name, help = def.help or '', params = params }
        end
    end
    if #list > 0 then
        TriggerClientEvent('tfc:client:suggestions', src, list)
    end
end

---@param name string
---@param def TFCCommandDef
---@param handler fun(source: integer, args: string[], raw: string)
function TFC.RegisterCommand(name, def, handler)
    commands[name] = def

    local required = 0
    for _, p in ipairs(def.params or {}) do
        if not p.optional then required = required + 1 end
    end

    RegisterCommand(name, function(src, args, raw)
        if def.permission and not TFC.HasPermission(src, def.permission) then
            TFC.UI.Notify(src, { description = 'You do not have permission to use that', type = 'error' })
            return
        end

        if #args < required then
            local text = ('Usage: %s'):format(usage(name, def))
            if src == 0 then
                TFC.Log.Info(text)
            else
                TFC.UI.Notify(src, { title = '/' .. name, description = text, type = 'error' })
            end
            return
        end

        local ok, err = pcall(handler, src, args, raw)
        if not ok then
            TFC.Log.Error('command /%s failed: %s', name, err)
        end
    end, def.restricted == true)

    -- Players already in game (e.g. this resource restarted) get it right away.
    for _, id in ipairs(GetPlayers()) do
        pushTo(tonumber(id) --[[@as integer]])
    end
end

---Resolve a player argument: a server ID, or "me" for the caller.
---@param src integer caller
---@param arg string|nil
---@return integer|nil
function TFC.ResolveTarget(src, arg)
    if arg == 'me' and src > 0 then return src end
    local id = tonumber(arg)
    if id and GetPlayerName(tostring(id)) then return math.tointeger(id) end
    return nil
end

-- Suggestions are sent once a character is loaded (chat is ready by then).
TFC.On('playerLoaded', function(src)
    pushTo(src)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= TFC.Resource then return end
    local names = {}
    for name in pairs(commands) do names[#names + 1] = '/' .. name end
    if #names > 0 then
        TriggerClientEvent('tfc:client:removeSuggestions', -1, names)
    end
end)
