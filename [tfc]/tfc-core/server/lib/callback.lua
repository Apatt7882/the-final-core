-- Server side of request/response callbacks.
--   Register    : answer requests from clients   (client calls TFC.Callback.Await)
--   AwaitClient : ask one client for an answer   (client registers with TFC.Callback.Register)
-- Await functions yield, so call them from a thread, command or event handler.

local resource = TFC.Resource
local TO_SERVER = 'tfc:cb:sv:%s'
local TO_CLIENT = 'tfc:cb:cl:%s'
local RESPONSE = 'tfc:cb:res:%s'

---@type table<integer, { p: table, target: integer, name: string }>
local pending = {}
local nextId = 0

TFC.Callback = {}

---Register a callback that clients can call.
---If the handler errors or the request is rate limited, the client gets no values back.
---@param name string e.g. 'example:ping'
---@param handler fun(source: integer, ...: any): ...
---@param opts? { rateLimit?: integer } rateLimit in ms per player
function TFC.Callback.Register(name, handler, opts)
    TFC.OnNet(TO_SERVER:format(name), function(src, callerResource, id, ...)
        if type(callerResource) ~= 'string' or #callerResource > 64 or type(id) ~= 'number' then return end

        local result = table.pack(pcall(handler, src, ...))
        if not result[1] then
            TFC.Log.Error('callback "%s" failed: %s', name, result[2])
            TriggerClientEvent(RESPONSE:format(callerResource), src, id)
            return
        end

        TriggerClientEvent(RESPONSE:format(callerResource), src, id, table.unpack(result, 2, result.n))
    end, opts)
end

RegisterNetEvent(RESPONSE:format(resource), function(id, ...)
    local src = tonumber(source)
    local entry = pending[id]
    if not entry or entry.target ~= src then return end

    pending[id] = nil
    entry.p:resolve(table.pack(...))
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    for id, entry in pairs(pending) do
        if entry.target == src then
            pending[id] = nil
            entry.p:resolve({ n = 0 })
        end
    end
end)

---Ask a client for an answer and wait for it. Returns nothing on timeout or disconnect.
---@param target integer player server id
---@param name string
---@param ... any
---@return ...
function TFC.Callback.AwaitClient(target, name, ...)
    target = tonumber(target) --[[@as integer]]
    nextId = nextId + 1
    local id = nextId
    local p = promise.new()
    pending[id] = { p = p, target = target, name = name }

    SetTimeout(GetConvarInt('tfc_callback_timeout', 10000), function()
        if pending[id] then
            pending[id] = nil
            TFC.Log.Warn('callback "%s" to player %d timed out', name, target)
            p:resolve({ n = 0 })
        end
    end)

    TriggerClientEvent(TO_CLIENT:format(name), target, resource, id, ...)

    local result = Citizen.Await(p)
    return table.unpack(result, 1, result.n)
end
