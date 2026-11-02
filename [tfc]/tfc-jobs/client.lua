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

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then
        SetNuiFocus(false, false)
    end
end)
