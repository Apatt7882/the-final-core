-- Client side: the job lives in the public 'tfc:job' state bag set by the server.
-- Client exports: GetJob(), IsOnDuty()
-- Client hook: jobChanged(job) whenever the local player's job, rank or duty changes.
-- Also opens the Boss Menu (/bossmenu); all rules are checked on the server.

local function mine(bagName)
    return bagName == ('player:%d'):format(GetPlayerServerId(PlayerId()))
end

AddStateBagChangeHandler('tfc:job', nil, function(bagName, _, value)
    if not mine(bagName) then return end
    TFC.Emit('jobChanged', value)
end)

exports('GetJob', function()
    return LocalPlayer.state['tfc:job']
end)

exports('IsOnDuty', function()
    local job = LocalPlayer.state['tfc:job']
    return job ~= nil and job.onDuty == true
end)

-- Boss Menu ---------------------------------------------------------------------------------

local open = false
local NO_RESPONSE = { ok = false, error = 'no response from server, try again' }

local function close()
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openMenu()
    if open or not TFC.PlayerData then return end
    local data = TFC.Callback.Await('jobs:boss:open') or NO_RESPONSE
    if not data.ok then
        TFC.UI.Notify({ title = 'Boss Menu', description = data.error, type = 'error' })
        return
    end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end

if JobsConfig.BossMenu.Command then
    RegisterCommand(JobsConfig.BossMenu.Command, openMenu, false)
end

TFC.OnPlayerLoaded(function()
    if JobsConfig.BossMenu.Command then
        TriggerEvent('chat:addSuggestion', '/' .. JobsConfig.BossMenu.Command, 'Open the Boss Menu (bosses and admins)')
    end
end)

TFC.OnPlayerUnloaded(function()
    if open then close() end
end)

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('get', function(data, cb)
    cb(TFC.Callback.Await('jobs:boss:get', data.job) or NO_RESPONSE)
end)

RegisterNUICallback('nearby', function(data, cb)
    cb(TFC.Callback.Await('jobs:boss:nearby', data.job) or NO_RESPONSE)
end)

RegisterNUICallback('action', function(data, cb)
    cb(TFC.Callback.Await('jobs:boss:action', data.job, data.action, data.data) or NO_RESPONSE)
end)

-- Job menu (F6) ------------------------------------------------------------------------------
-- Other resources add actions with exports['tfc-jobs']:AddJobAction({ ... }) (client).
-- Picking an action triggers its client event with { target = <closest player's server ID> }.
-- The server still checks everything; this menu only saves typing commands.

local actions = {}       -- id -> action
local actionOrder = {}   -- ids in the order added

---@param a { id: string, jobs: string[], label: string, description?: string, icon?: string, event: string, target?: boolean, duty?: boolean, available?: string }
exports('AddJobAction', function(a)
    if type(a) ~= 'table' or type(a.id) ~= 'string' or type(a.event) ~= 'string' then return false end
    a.owner = GetInvokingResource()
    if not actions[a.id] then actionOrder[#actionOrder + 1] = a.id end
    actions[a.id] = a
    return true
end)

AddEventHandler('onClientResourceStop', function(resource)
    for id, a in pairs(actions) do
        if a.owner == resource then actions[id] = nil end
    end
end)

local function closestPlayer(maxDist)
    local me = PlayerPedId()
    local here = GetEntityCoords(me)
    local best, bestDist = nil, maxDist
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= me then
            local d = #(GetEntityCoords(ped) - here)
            if d < bestDist then best, bestDist = player, d end
        end
    end
    return best
end

local function playerLabel(player)
    local id = GetPlayerServerId(player)
    local name = Player(id).state['tfc:name'] or GetPlayerName(player)
    return ('%s (%d)'):format(name, id), id
end

local function stateOf(id, key)
    return Player(id).state[key]
end

local function openJobMenu()
    if not TFC.PlayerData or IsPauseMenuActive() then return end
    local job = LocalPlayer.state['tfc:job']
    if not job then return end

    local target = closestPlayer(JobsConfig.JobMenu.Distance)
    local targetLabel, targetId = nil, nil
    if target then targetLabel, targetId = playerLabel(target) end

    local options = {}
    for _, id in ipairs(actionOrder) do
        local a = actions[id]
        local forJob = false
        for _, j in ipairs(a and a.jobs or {}) do
            if j == job.name then forJob = true break end
        end
        if forJob then
            local offDuty = a.duty ~= false and job.onDuty == false
            local disabled, note = false, a.description
            if offDuty then
                disabled, note = true, 'Go on duty first (/duty)'
            elseif a.target ~= false and not targetId then
                disabled, note = true, 'Nobody close enough'
            elseif a.available and targetId and not stateOf(targetId, a.available) then
                disabled = true
            end
            options[#options + 1] = {
                title = a.label, description = note, icon = a.icon, disabled = disabled,
                event = a.event, args = { target = targetId },
            }
        end
    end

    if #options == 0 then
        TFC.UI.Notify({ title = 'Job menu', description = 'Your job has no actions here.' })
        return
    end

    local title = job.label .. (targetLabel and (' · ' .. targetLabel) or '')
    if not TFC.UI.Menu({ id = 'tfc_jobmenu', title = title, options = options }) then
        TFC.UI.Notify({ title = 'Job menu', description = 'The menu needs ox_lib. Use the chat commands instead.', type = 'error' })
    end
end

RegisterCommand('tfc_jobmenu', openJobMenu, false)
RegisterKeyMapping('tfc_jobmenu', 'Job menu (police, EMS...)', 'keyboard', JobsConfig.JobMenu.Key)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then
        SetNuiFocus(false, false)
    end
end)
