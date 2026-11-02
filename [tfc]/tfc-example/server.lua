-- Template module. Shows module registration, hooks, callbacks and the player API.
-- The test commands here are for the dev server only: remove them before going live.

TFC.RegisterModule({
    name = 'example',
    version = '0.2.0',
    dependencies = {},
}, function()
    TFC.Log.Info('example module is ready')
end)

-- Hook: fires for every module that becomes ready, including this one.
TFC.On('moduleReady', function(name, resource)
    TFC.Log.Debug('saw moduleReady: %s (%s)', name, resource)
end)

-- Persistence test: count how many times this character has loaded.
-- Reconnect and the number should go up by one.
TFC.On('playerLoaded', function(source)
    local player = TFC.GetPlayer(source)
    if not player then return end

    local joins = (player:GetMetadata('example_joins') or 0) + 1
    player:SetMetadata('example_joins', joins)
    TFC.Log.Info('%s (%s) has loaded %d time(s)', player:GetFullName(), player:GetCid(), joins)
end)

-- Client -> server callback. Players can call it at most once per second.
TFC.Callback.Register('example:ping', function(source)
    return 'pong', GetPlayerName(source)
end, { rateLimit = 1000 })

-- Server -> client callback test: /tfcscreen
RegisterCommand('tfcscreen', function(source)
    if source == 0 then return end

    local width, height = TFC.Callback.AwaitClient(source, 'example:screen')
    if not width then
        TFC.Log.Warn('player %d did not answer', source)
        return
    end

    TFC.Log.Info('%s is playing at %dx%d', GetPlayerName(source), width, height)
end, false)

-- /tfcwhoami: print the loaded character to the server console.
RegisterCommand('tfcwhoami', function(source)
    local player = TFC.GetPlayer(source)
    if not player then
        TFC.Log.Warn('player %d has no character loaded', source)
        return
    end

    local pos = player:GetPosition()
    TFC.Log.Info('%s | cid %s | slot %d | joins %s | at %s', player:GetFullName(), player:GetCid(), player:GetSlot(),
        tostring((player:GetMetadata('example_joins'))),
        pos and ('%.1f, %.1f, %.1f'):format(pos.x, pos.y, pos.z) or 'unknown')
end, false)

-- /tfcsave: save now instead of waiting for the batch.
RegisterCommand('tfcsave', function(source)
    local player = TFC.GetPlayer(source)
    if not player then return end
    TFC.Log.Info('saved %d character(s)', player:Save())
end, false)
