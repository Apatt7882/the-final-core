-- Player proxies for other resources (loaded by import.lua, not by tfc-core itself).
-- TFC.GetPlayer(src) returns an object whose methods forward to the real player in tfc-core:
--     local player = TFC.GetPlayer(source)
--     player:SetMetadata('hunger', 80)

local CORE = TFC.CoreResource

---@type table<integer, table>
local proxies = {}
---@type table<string, function>
local methods = {}

local Proxy = {}
Proxy.__index = function(self, key)
    local fn = methods[key]
    if not fn then
        fn = function(proxy, ...)
            return exports[CORE]:PlayerCall(rawget(proxy, 'source'), key, ...)
        end
        methods[key] = fn
    end
    return fn
end

---@param src integer|string
---@return TFCPlayer|nil
function TFC.GetPlayer(src)
    src = tonumber(src) --[[@as integer]]
    local proxy = proxies[src]
    if proxy then return proxy end

    local data = exports[CORE]:GetPlayerData(src)
    if not data then return nil end

    proxy = setmetatable({
        source = src,
        userId = data.userId,
        characterId = data.characterId,
        cid = data.cid,
    }, Proxy)
    proxies[src] = proxy
    return proxy
end

---@param cid string
---@return TFCPlayer|nil
function TFC.GetPlayerByCid(cid)
    local src = exports[CORE]:GetPlayerByCid(cid)
    return src and TFC.GetPlayer(src) or nil
end

---Sources of every loaded player.
---@return integer[]
function TFC.GetPlayers()
    return exports[CORE]:GetPlayers()
end

TFC.On('playerUnloaded', function(src)
    proxies[src] = nil
end)
