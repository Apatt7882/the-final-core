-- Noclip (admins): fly through everything. F2 (rebindable) or /noclip.
--   W/S forward/back (where the camera looks)   A/D sideways
--   Space up, Ctrl down                          Shift faster
--   Mouse wheel: change speed
-- Works on foot and as the driver of a vehicle (the vehicle flies with you).

local Cfg = AdminConfig.Noclip

local active = false
local speedIndex = Cfg.startSpeed
local entity = nil

AdminNoclip = {}

local function notify(text, kind)
    TFC.UI.Notify({ title = 'Noclip', description = text, type = kind or 'inform' })
end

local function target()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then return veh end
    return ped
end

local function setup(ent, on)
    FreezeEntityPosition(ent, on)
    SetEntityCollision(ent, not on, not on)
    SetEntityInvincible(ent, on)
    if Cfg.invisible then
        SetEntityVisible(ent, not on, false)
        if ent ~= PlayerPedId() then SetEntityVisible(PlayerPedId(), not on, false) end
    end
    if not on then
        SetEntityVelocity(ent, 0.0, 0.0, 0.0)
        ResetEntityAlpha(ent)
        ResetEntityAlpha(PlayerPedId())
    end
end

local function camDirection()
    local rot = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local cp = math.abs(math.cos(pitch))
    return vector3(-math.sin(yaw) * cp, math.cos(yaw) * cp, math.sin(pitch)), yaw
end

local function loop()
    while active do
        local ent = target()
        if ent ~= entity then
            -- Got into / out of a vehicle while flying.
            if entity and DoesEntityExist(entity) then setup(entity, false) end
            entity = ent
            setup(entity, true)
        end

        -- Block things that fight with noclip.
        for _, c in ipairs({ 21, 22, 23, 24, 25, 36, 44, 75, 85, 86, 14, 15, 16, 17 }) do DisableControlAction(0, c, true) end

        if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then -- wheel up
            speedIndex = math.min(#Cfg.speeds, speedIndex + 1)
            notify(('Speed %d / %d'):format(speedIndex, #Cfg.speeds))
        elseif IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then -- wheel down
            speedIndex = math.max(1, speedIndex - 1)
            notify(('Speed %d / %d'):format(speedIndex, #Cfg.speeds))
        end

        local speed = Cfg.speeds[speedIndex]
        if IsDisabledControlPressed(0, 21) then speed = speed * Cfg.fastMultiplier end -- Shift

        local dir, yaw = camDirection()
        local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
        local move = vector3(0.0, 0.0, 0.0)
        if IsControlPressed(0, 32) then move = move + dir end            -- W
        if IsControlPressed(0, 33) then move = move - dir end            -- S
        if IsControlPressed(0, 35) then move = move + right end          -- D
        if IsControlPressed(0, 34) then move = move - right end          -- A
        if IsDisabledControlPressed(0, 22) then move = move + vector3(0.0, 0.0, 1.0) end -- Space
        if IsDisabledControlPressed(0, 36) then move = move - vector3(0.0, 0.0, 1.0) end -- Ctrl

        local pos = GetEntityCoords(ent)
        local new = pos + move * speed
        SetEntityCoordsNoOffset(ent, new.x, new.y, new.z, true, true, true)
        SetEntityHeading(ent, math.deg(yaw))
        if Cfg.invisible then
            SetEntityLocallyVisible(ent)
            SetEntityAlpha(ent, 140, false)
        end
        Wait(0)
    end
end

function AdminNoclip.active()
    return active
end

function AdminNoclip.set(on)
    if on == active then return end
    if on then
        if not AdminClient.isAdmin() then return end
        local r = TFC.Callback.Await('admin:noclip', true)
        if not r or not r.ok then return notify(r and r.error or 'not allowed', 'error') end
        active = true
        entity = nil
        notify('On. WASD + mouse to fly, Space/Ctrl up/down, Shift faster, wheel for speed.', 'success')
        CreateThread(loop)
    else
        active = false
        if entity and DoesEntityExist(entity) then setup(entity, false) end
        local ped = PlayerPedId()
        if entity ~= ped then setup(ped, false) end
        entity = nil
        -- Put the player on the ground instead of leaving them mid-air.
        local c = GetEntityCoords(ped)
        local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
        if found and not IsPedInAnyVehicle(ped, false) and c.z - z < 50.0 then
            SetEntityCoordsNoOffset(ped, c.x, c.y, z + 0.5, false, false, false)
        end
        TFC.Callback.Await('admin:noclip', false)
        notify('Off.')
    end
end

function AdminNoclip.toggle()
    AdminNoclip.set(not active)
end

TFC.OnNet('tfc-admin:client:noclip', AdminNoclip.toggle)

RegisterCommand('tfc_noclip', function()
    if AdminClient.isAdmin() then AdminNoclip.toggle() end
end, false)
RegisterKeyMapping('tfc_noclip', 'Noclip (admins only)', 'keyboard', AdminConfig.NoclipKey)

TFC.OnPlayerUnloaded(function()
    if active then AdminNoclip.set(false) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then
        active = false
        if entity and DoesEntityExist(entity) then setup(entity, false) end
        setup(PlayerPedId(), false)
    end
end)
