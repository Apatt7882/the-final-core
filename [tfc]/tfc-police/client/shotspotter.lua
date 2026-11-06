-- ShotSpotter (client). Every player reports their own gunfire (not suppressed, not tasers or
-- melee) at most every few seconds; on-duty police get the alerts the server sends back.

local Cfg = PoliceConfig.ShotSpotter
if not Cfg or not Cfg.Enabled then return end

-- Weapon groups that fire fully automatic: SMGs, machine guns, assault rifles.
local AUTO_GROUPS = {
    [joaat('GROUP_SMG')] = true,
    [joaat('GROUP_MG')] = true,
    [joaat('GROUP_RIFLE')] = true,
}
local BULLET = 3   -- GetWeaponDamageType: 3 = bullet
local IGNORE = { [joaat('WEAPON_STUNGUN')] = true, [joaat('WEAPON_STUNGUN_MP')] = true, [joaat('WEAPON_FLAREGUN')] = true }

-- Rough colour names for GTA's vehicle colour indexes.
local COLOR_RANGES = {
    { 0, 2, 'black' }, { 3, 11, 'silver' }, { 12, 12, 'black' }, { 13, 14, 'grey' }, { 15, 16, 'black' }, { 17, 20, 'grey' },
    { 21, 21, 'black' }, { 22, 26, 'grey' }, { 27, 35, 'red' }, { 36, 36, 'orange' }, { 37, 37, 'gold' }, { 38, 38, 'orange' },
    { 39, 40, 'red' }, { 41, 41, 'orange' }, { 42, 42, 'yellow' }, { 43, 48, 'red' }, { 49, 60, 'green' }, { 61, 87, 'blue' },
    { 88, 89, 'yellow' }, { 90, 90, 'bronze' }, { 91, 91, 'yellow' }, { 92, 92, 'green' }, { 93, 95, 'beige' },
    { 96, 104, 'brown' }, { 105, 107, 'beige' }, { 108, 110, 'brown' }, { 111, 112, 'white' }, { 113, 116, 'brown' },
    { 117, 120, 'silver' }, { 121, 122, 'white' }, { 123, 124, 'orange' }, { 125, 125, 'green' }, { 126, 126, 'yellow' },
    { 127, 127, 'blue' }, { 128, 128, 'green' }, { 129, 129, 'brown' }, { 130, 130, 'orange' }, { 131, 132, 'white' },
    { 133, 133, 'green' }, { 134, 134, 'white' }, { 135, 137, 'pink' }, { 138, 138, 'orange' }, { 139, 139, 'green' },
    { 140, 141, 'blue' }, { 142, 142, 'purple' }, { 143, 143, 'red' }, { 144, 144, 'green' }, { 145, 145, 'purple' },
    { 146, 146, 'blue' }, { 147, 147, 'black' }, { 148, 149, 'purple' }, { 150, 150, 'red' }, { 151, 152, 'green' },
    { 153, 154, 'brown' }, { 155, 155, 'green' }, { 156, 156, 'silver' }, { 157, 157, 'blue' }, { 158, 159, 'gold' },
}

local function colorName(index)
    for _, r in ipairs(COLOR_RANGES) do
        if index >= r[1] and index <= r[2] then return r[3] end
    end
    return nil
end

local FREEMODE = { [joaat('mp_m_freemode_01')] = true, [joaat('mp_f_freemode_01')] = true }

---What a camera could make out about the shooter.
local function look(ped)
    local d = { male = IsPedMale(ped) }
    d.mask = GetPedDrawableVariation(ped, 1) > 0
    d.hat = GetPedPropIndex(ped, 0) ~= -1
    d.glasses = GetPedPropIndex(ped, 1) ~= -1
    d.bag = GetPedDrawableVariation(ped, 5) > 0
    if FREEMODE[GetEntityModel(ped)] then d.shirtless = GetPedDrawableVariation(ped, 11) == 15 end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        local label = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
        if label == 'NULL' then label = 'vehicle' end
        d.vehicle = label
        local primary = GetVehicleColours(veh)
        d.color = colorName(primary)
    end
    return d
end

CreateThread(function()
    local lastReport = 0
    while true do
        local ped = PlayerPedId()
        if TFC.PlayerData and IsPedShooting(ped) then
            local weapon = GetSelectedPedWeapon(ped)
            if not IGNORE[weapon] and GetWeaponDamageType(weapon) == BULLET and not IsPedCurrentWeaponSilenced(ped) then
                local now = GetGameTimer()
                if now - lastReport > 4000 then
                    lastReport = now
                    local c = GetEntityCoords(ped)
                    TriggerServerEvent('tfc-police:server:shots', {
                        x = c.x, y = c.y, z = c.z,
                        auto = AUTO_GROUPS[GetWeapontypeGroup(weapon)] == true,
                        look = look(ped),
                    })
                end
            end
            Wait(0)
        elseif IsPedArmed(ped, 4) then
            Wait(0)      -- holding a gun: watch every frame
        else
            Wait(500)
        end
    end
end)

-- Alerts (on-duty police) ----------------------------------------------------------------------

local latest = nil

local function place(x, y, z)
    local s1, s2 = GetStreetNameAtCoord(x, y, z)
    local street = GetStreetNameFromHashKey(s1)
    local cross = s2 ~= 0 and GetStreetNameFromHashKey(s2) or ''
    local zone = GetLabelText(GetNameOfZone(x, y, z))
    local text = street ~= '' and street or 'unknown street'
    if cross ~= '' then text = text .. ' / ' .. cross end
    if zone ~= '' and zone ~= 'NULL' then text = text .. ', ' .. zone end
    return text
end

TFC.OnNet('tfc-police:client:shotspotter', function(a)
    if type(a) ~= 'table' then return end
    local area = AddBlipForRadius(a.x + 0.0, a.y + 0.0, a.z + 0.0, (a.radius or 90.0) + 0.0)
    SetBlipColour(area, 1)
    SetBlipAlpha(area, 110)
    SetBlipFlashes(area, true)

    local mark = AddBlipForCoord(a.x + 0.0, a.y + 0.0, a.z + 0.0)
    SetBlipSprite(mark, 110)
    SetBlipColour(mark, 1)
    SetBlipScale(mark, 0.9)
    SetBlipAsShortRange(mark, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('ShotSpotter')
    EndTextCommandSetBlipName(mark)

    latest = { x = a.x, y = a.y, until_ = GetGameTimer() + (a.duration or 90) * 1000 }

    local kind = a.auto and 'fully automatic' or 'semi-automatic'
    local text = ('Shots fired (%s) near %s.'):format(kind, place(a.x, a.y, a.z))
    if a.camera then text = text .. '\nCamera: ' .. a.camera .. '.' end
    if Cfg.Command then text = text .. ('\n/%s sets a waypoint.'):format(Cfg.Command) end
    TFC.UI.Notify({ title = 'ShotSpotter', description = text, type = 'warning', duration = 12000 })
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', false)

    SetTimeout((a.duration or 90) * 1000, function()
        if DoesBlipExist(area) then RemoveBlip(area) end
        if DoesBlipExist(mark) then RemoveBlip(mark) end
    end)
end)

if Cfg.Command then
    RegisterCommand(Cfg.Command, function()
        if not latest or GetGameTimer() > latest.until_ then
            return TFC.UI.Notify({ title = 'ShotSpotter', description = 'No active ShotSpotter alert.', type = 'error' })
        end
        SetNewWaypoint(latest.x + 0.0, latest.y + 0.0)
        TFC.UI.Notify({ title = 'ShotSpotter', description = 'Waypoint set to the latest alert.', type = 'success' })
    end, false)
end
