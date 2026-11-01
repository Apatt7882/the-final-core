-- Template module. Shows module registration, hooks and callbacks in both directions.

TFC.RegisterModule({
    name = 'example',
    version = '0.1.0',
    dependencies = {},
}, function()
    TFC.Log.Info('example module is ready')
end)

-- Hook: fires for every module that becomes ready, including this one.
TFC.On('moduleReady', function(name, resource)
    TFC.Log.Debug('saw moduleReady: %s (%s)', name, resource)
end)

-- Client -> server callback. Players can call it at most once per second.
TFC.Callback.Register('example:ping', function(source)
    return 'pong', GetPlayerName(source)
end, { rateLimit = 1000 })

-- Server -> client callback test: type /tfcscreen in game.
RegisterCommand('tfcscreen', function(source)
    if source == 0 then
        TFC.Log.Warn('run /tfcscreen in game, not from the console')
        return
    end

    local width, height = TFC.Callback.AwaitClient(source, 'example:screen')
    if not width then
        TFC.Log.Warn('player %d did not answer', source)
        return
    end

    TFC.Log.Info('%s is playing at %dx%d', GetPlayerName(source), width, height)
end, false)
