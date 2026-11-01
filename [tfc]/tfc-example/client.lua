-- Server -> client callback: the server asks for this player's screen size.
TFC.Callback.Register('example:screen', function()
    local width, height = GetActiveScreenResolution()
    return width, height
end)

-- Client -> server callback test: type /tfctest in game, then check F8.
RegisterCommand('tfctest', function()
    local started = GetGameTimer()
    local reply, name = TFC.Callback.Await('example:ping')

    if not reply then
        TFC.Log.Warn('no reply (timed out or rate limited)')
        return
    end

    TFC.Log.Info('%s for %s in %d ms', reply, name, GetGameTimer() - started)
end, false)
