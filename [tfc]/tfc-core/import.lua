-- Gives another resource its own TFC object (logging, hooks, callbacks, module registration).
-- In that resource's fxmanifest.lua:
--     dependency 'tfc-core'
--     shared_script '@tfc-core/import.lua'

local CORE = 'tfc-core'
local current = GetCurrentResourceName()

if current == CORE then return end

local state = GetResourceState(CORE)
if state ~= 'started' and state ~= 'starting' then
    error(('^1[%s] tfc-core must be started before this resource (state: %s)^7'):format(current, state), 0)
end

local side = IsDuplicityVersion() and 'server' or 'client'
local files = {
    'shared/init.lua',
    'shared/lib/log.lua',
    'shared/lib/events.lua',
    side .. '/lib/callback.lua',
    side .. '/lib/player.lua',
    side .. '/lib/ui.lua',
}
if side == 'server' then
    files[#files + 1] = 'server/lib/permissions.lua'
    files[#files + 1] = 'server/lib/commands.lua'
end

for _, path in ipairs(files) do
    local code = LoadResourceFile(CORE, path)
    if not code then
        error(('^1[%s] could not load %s/%s^7'):format(current, CORE, path), 0)
    end

    local chunk, err = load(code, ('@@%s/%s'):format(CORE, path), 't', _ENV)
    if not chunk then
        error(('^1[%s] failed to compile %s/%s: %s^7'):format(current, CORE, path, err), 0)
    end

    chunk()
end

if side == 'server' then
    ---Register this resource as a TFC module.
    ---onReady runs once, as soon as every dependency is ready (possibly immediately).
    ---@param def TFCModuleDefinition
    ---@param onReady? fun()
    ---@return boolean ok
    ---@return string stateOrError
    function TFC.RegisterModule(def, onReady)
        local fired = false
        local handle

        if onReady then
            handle = TFC.On('moduleReady', function(name)
                if name ~= def.name or fired then return end
                fired = true
                TFC.Off(handle)
                onReady()
            end)
        end

        local ok, result = exports[CORE]:RegisterModule(def)
        if not ok then
            if handle then TFC.Off(handle) end
            TFC.Log.Error('could not register module: %s', result)
        end

        return ok, result
    end
end
