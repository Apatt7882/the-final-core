-- Game adapter (client). GTA-specific calls the core makes on the client live here.

TFC.Adapter = {}

---@return boolean
function TFC.Adapter.IsSessionStarted()
    return NetworkIsSessionStarted()
end

---Move the local player and wait (up to 5 s) for collision to load.
---@param pos { x: number, y: number, z: number, w?: number }
function TFC.Adapter.Teleport(pos)
    local ped = PlayerPedId()
    local x, y, z = pos.x + 0.0, pos.y + 0.0, pos.z + 0.0

    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, (pos.w or 0.0) + 0.0)

    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        Wait(0)
    end
end
