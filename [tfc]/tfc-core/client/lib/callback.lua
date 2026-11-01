-- Client side of request/response callbacks.
--   Await    : ask the server for an answer    (server registers with TFC.Callback.Register)
--   Register : answer requests from the server (server calls TFC.Callback.AwaitClient)
-- Await yields, so call it from a thread, command or event handler.

local resource = TFC.Resource
local TO_SERVER = 'tfc:cb:sv:%s'
local TO_CLIENT = 'tfc:cb:cl:%s'
local RESPONSE = 'tfc:cb:res:%s'

---@type table<integer, { p: table, name: string }>
local pending = {}
local nextId = 0

TFC.Callback = {}

RegisterNetEvent(RESPONSE:format(resource), function(id, ...)
    local entry = pending[id]
    if not entry then return end

    pending[id] = nil
    entry.p:resolve(table.pack(...))
end)

---Ask the server for an answer and wait for it. Returns nothing on timeout.
---@param name string e.g. 'example:ping'
---@param ... any
---@return ...
function TFC.Callback.Await(name, ...)
    nextId = nextId + 1
    local id = nextId
    local p = promise.new()
    pending[id] = { p = p, name = name }

    SetTimeout(GetConvarInt('tfc_callback_timeout', 10000), function()
        if pending[id] then
            pending[id] = nil
            TFC.Log.Warn('callback "%s" timed out', name)
            p:resolve({ n = 0 })
        end
    end)

    TriggerServerEvent(TO_SERVER:format(name), resource, id, ...)

    local result = Citizen.Await(p)
    return table.unpack(result, 1, result.n)
end

---Register a callback the server can call on this client.
---@param name string
---@param handler fun(...: any): ...
function TFC.Callback.Register(name, handler)
    TFC.OnNet(TO_CLIENT:format(name), function(callerResource, id, ...)
        if type(callerResource) ~= 'string' or type(id) ~= 'number' then return end

        local result = table.pack(pcall(handler, ...))
        if not result[1] then
            TFC.Log.Error('callback "%s" failed: %s', name, result[2])
            TriggerServerEvent(RESPONSE:format(callerResource), id)
            return
        end

        TriggerServerEvent(RESPONSE:format(callerResource), id, table.unpack(result, 2, result.n))
    end)
end
