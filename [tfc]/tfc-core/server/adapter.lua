-- Game adapter (server). Every GTA/FiveM-specific call the core makes about players goes here,
-- so porting to another platform means rewriting this file, not the core.

TFC.Adapter = {}

---Identifier value without its prefix, e.g. GetIdentifier(src, 'discord') -> '1234567890'.
---@param src integer
---@param idType string license, license2, discord, fivem, steam, xbl, live
---@return string|nil
function TFC.Adapter.GetIdentifier(src, idType)
    local full = GetPlayerIdentifierByType(tostring(src), idType)
    if not full then return nil end
    return full:match('^[^:]+:(.+)$') or full
end

---@param src integer
---@return string|nil
function TFC.Adapter.GetName(src)
    return GetPlayerName(tostring(src))
end

---Current position and heading, or nil if the ped isn't available yet.
---@param src integer
---@return { x: number, y: number, z: number, w: number }|nil
function TFC.Adapter.GetPosition(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    local coords = GetEntityCoords(ped)
    if coords.x == 0.0 and coords.y == 0.0 then return nil end

    return {
        x = math.floor(coords.x * 100 + 0.5) / 100,
        y = math.floor(coords.y * 100 + 0.5) / 100,
        z = math.floor(coords.z * 100 + 0.5) / 100,
        w = math.floor(GetEntityHeading(ped) * 10 + 0.5) / 10,
    }
end

---Replicated state bag value visible to every client.
---@param src integer
---@param key string
---@param value any
function TFC.Adapter.SetPublicState(src, key, value)
    Player(src).state:set(key, value, true)
end

---@param src integer
---@param key string
function TFC.Adapter.GetPublicState(src, key)
    return Player(src).state[key]
end
