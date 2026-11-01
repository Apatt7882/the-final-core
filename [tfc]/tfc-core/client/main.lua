-- Client entry point: tells the server we're ready, then places the player at their saved position.
-- Phase 3 (tfc-multichar) replaces the placement with a proper spawn flow.

local spawned = false
AddEventHandler('playerSpawned', function()
    spawned = true
end)

CreateThread(function()
    while not TFC.Adapter.IsSessionStarted() do
        Wait(250)
    end
    TFC.Log.Debug('%s v%s client ready', TFC.Name, TFC.Version)
    TriggerServerEvent('tfc:server:clientReady')
end)

-- Only tfc-core listens, so a notification never shows twice.
TFC.OnNet('tfc:client:notify', function(data)
    TFC.UI.Notify(data)
end)

TFC.OnNet('tfc:client:playerLoaded', function(data, spawn)
    CreateThread(function()
        -- If spawnmanager is running, wait for its spawn so it doesn't move us afterwards.
        if GetResourceState('spawnmanager') == 'started' then
            local deadline = GetGameTimer() + 10000
            while not spawned and GetGameTimer() < deadline do
                Wait(100)
            end
        end

        if spawn then
            TFC.Adapter.Teleport(spawn)
        end

        TFC.Log.Info('playing as %s %s (%s)', data.firstname, data.lastname, data.cid)

        -- Client hook for every resource: the character is in the world at their position.
        TFC.Emit('playerSpawned', data)
    end)
end)
