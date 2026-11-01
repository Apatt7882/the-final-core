-- Loaded players, batched saving, and the exports other resources use to reach them.

---@type table<integer, TFCPlayer>
local players = {}
---@type table<string, integer> cid -> source
local byCid = {}

local POSITION_CACHE_MS = 5000

---@param src integer|string
---@return TFCPlayer|nil
function TFC.GetPlayer(src)
    return players[tonumber(src)]
end

---@param cid string
---@return TFCPlayer|nil
function TFC.GetPlayerByCid(cid)
    local src = byCid[cid]
    return src and players[src] or nil
end

---Sources of every loaded player (same shape as the proxy version other resources get).
---@return integer[]
function TFC.GetPlayers()
    local list = {}
    for src in pairs(players) do list[#list + 1] = src end
    return list
end

---@return TFCPlayer[]
local function allPlayers()
    local list = {}
    for _, p in pairs(players) do list[#list + 1] = p end
    return list
end

---@param p TFCPlayer
function TFC.AddPlayer(p)
    players[p.source] = p
    byCid[p.character.cid] = p.source
end

---@param src integer
---@return TFCPlayer|nil
function TFC.RemovePlayer(src)
    local p = players[src]
    if p then
        players[src] = nil
        byCid[p.character.cid] = nil
    end
    return p
end

---True if two positions differ by more than 1 metre.
local function moved(a, b)
    if not a or not b then return a ~= b end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz > 1.0
end

---Save players that changed (or all given, with force) in one transaction.
---@param list TFCPlayer[]
---@param opts? { force?: boolean, async?: boolean } async = fire and forget, for shutdown
---@return integer saved
function TFC.SavePlayers(list, opts)
    local force = opts and opts.force
    local queries, included = {}, {}

    for _, p in ipairs(list) do
        local pos = TFC.Adapter.GetPosition(p.source) or p._cachedPos
        local posChanged = moved(pos, p._lastSavedPos)

        if force or p._dirty or posChanged then
            queries[#queries + 1] = TFC.Characters.SaveQuery(p.character.id, p.character.metadata, posChanged and pos or nil)
            included[#included + 1] = p
            p._dirty = false
            if pos then
                p._lastSavedPos = pos
                p.character.position = pos
            end
        end
    end

    if #queries == 0 then return 0 end

    if opts and opts.async then
        MySQL.transaction(queries)
        return #queries
    end

    if not MySQL.transaction.await(queries) then
        TFC.Log.Error('save failed for %d character(s); will retry next batch', #queries)
        for _, p in ipairs(included) do p._dirty = true end
        return 0
    end

    return #queries
end

---@param opts? { force?: boolean, async?: boolean }
function TFC.SaveAll(opts)
    local saved = TFC.SavePlayers(allPlayers(), opts)
    if saved > 0 then
        TFC.Log.Debug('saved %d character(s)', saved)
    end
end

-- Batched save loop.
CreateThread(function()
    while true do
        Wait(TFC.Config.SaveInterval * 1000)
        TFC.SaveAll()
    end
end)

-- Cache positions so a player who drops after their ped is gone still saves where they were.
CreateThread(function()
    while true do
        Wait(POSITION_CACHE_MS)
        for _, p in pairs(players) do
            local pos = TFC.Adapter.GetPosition(p.source)
            if pos then p._cachedPos = pos end
        end
    end
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function()
    TFC.Log.Info('server shutting down, saving everyone')
    TFC.SaveAll({ force = true })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == TFC.Resource then
        TFC.SaveAll({ force = true, async = true })
    end
end)

-- Exports ------------------------------------------------------------------

exports('GetPlayerData', function(src)
    local p = players[tonumber(src)]
    return p and p:Serialize() or nil
end)

exports('GetPlayers', TFC.GetPlayers)

exports('GetPlayerByCid', function(cid)
    return byCid[cid]
end)

---Forward a method call from a proxy in another resource to the real player object.
exports('PlayerCall', function(src, method, ...)
    local p = players[tonumber(src)]
    if not p then return nil end

    local fn = type(method) == 'string' and method:sub(1, 1) ~= '_' and TFC.PlayerClass[method]
    if type(fn) ~= 'function' or method == 'new' then
        error(('TFCPlayer has no method "%s"'):format(tostring(method)), 2)
    end

    return fn(p, ...)
end)
