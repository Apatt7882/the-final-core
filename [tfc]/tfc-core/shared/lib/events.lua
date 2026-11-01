-- Event bus.
--   TFC.On / TFC.Emit  : hooks between resources on the same side (server<->server, client<->client)
--   TFC.OnNet          : net events with source validation and optional rate limiting

local HOOK = 'tfc:hook:%s'

---Listen for a TFC hook. Errors in the handler are logged instead of breaking other listeners.
---@param name string hook name, e.g. 'moduleReady'
---@param handler fun(...: any)
---@return table handle pass to TFC.Off
function TFC.On(name, handler)
    return AddEventHandler(HOOK:format(name), function(...)
        local ok, err = pcall(handler, ...)
        if not ok then
            TFC.Log.Error('hook "%s" handler failed: %s', name, err)
        end
    end)
end

---Stop listening.
---@param handle table returned by TFC.On or TFC.OnNet
function TFC.Off(handle)
    RemoveEventHandler(handle)
end

---Fire a hook for every resource on this side.
---@param name string
---@param ... any
function TFC.Emit(name, ...)
    TriggerEvent(HOOK:format(name), ...)
end

if TFC.IsServer then
    ---@type table<integer, table<string, integer>>
    local lastCall = {}

    AddEventHandler('playerDropped', function()
        lastCall[tonumber(source)] = nil
    end)

    ---Handle a net event from clients. Drops calls from invalid sources and,
    ---with opts.rateLimit, calls that arrive faster than the limit.
    ---@param eventName string full event name, e.g. 'tfc:server:somethingHappened'
    ---@param handler fun(source: integer, ...: any)
    ---@param opts? { rateLimit?: integer } rateLimit in ms per player
    ---@return table handle
    function TFC.OnNet(eventName, handler, opts)
        local limit = opts and opts.rateLimit or 0
        RegisterNetEvent(eventName)

        return AddEventHandler(eventName, function(...)
            local src = tonumber(source)
            if not src or src <= 0 or not GetPlayerName(src) then return end

            if limit > 0 then
                local now = GetGameTimer()
                local calls = lastCall[src]
                if not calls then
                    calls = {}
                    lastCall[src] = calls
                end
                local last = calls[eventName]
                if last and now - last < limit then
                    TFC.Log.Debug('rate limited %s from player %d', eventName, src)
                    return
                end
                calls[eventName] = now
            end

            local ok, err = pcall(handler, src, ...)
            if not ok then
                TFC.Log.Error('net event "%s" from %d failed: %s', eventName, src, err)
            end
        end)
    end
else
    ---Handle a net event from the server.
    ---@param eventName string
    ---@param handler fun(...: any)
    ---@return table handle
    function TFC.OnNet(eventName, handler)
        RegisterNetEvent(eventName)

        return AddEventHandler(eventName, function(...)
            local ok, err = pcall(handler, ...)
            if not ok then
                TFC.Log.Error('net event "%s" failed: %s', eventName, err)
            end
        end)
    end
end
