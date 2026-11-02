-- Client weapons: hold / holster, count shots, reload with R, jam at 0% durability,
-- and keep GTA's weapon wheel and weapon keys out of the way.

local Cfg = InventoryConfig.Weapons
local UNARMED = joaat('WEAPON_UNARMED')

---@type { name: string, label: string, hash: integer, serial: string|nil, ammo: integer|nil, durability: number|nil, ammoItem: string|nil, clip: integer|nil, infinite: boolean }|nil
local held = nil
local shots = 0
local reloading = false
local jamNotified = false

ClientWeapons = {}

local function notify(text, kind)
    TFC.UI.Notify({ title = 'Weapons', description = text, type = kind or 'inform' })
end

local function holster(tellServer)
    if not held then return end
    local ped = PlayerPedId()
    RemoveWeaponFromPed(ped, held.hash)
    SetCurrentPedWeapon(ped, UNARMED, true)
    held = nil
    shots = 0
    if tellServer then TFC.Callback.Await('weapons:holster') end
end

local function equip(w)
    if held then holster(false) end
    local ped = PlayerPedId()
    local hash = joaat(w.hash)

    held = {
        name = w.name, label = w.label, hash = hash, serial = w.serial,
        ammo = w.ammo, durability = w.durability, ammoItem = w.ammoItem,
        clip = w.clip, infinite = w.infinite,
    }
    jamNotified = false

    GiveWeaponToPed(ped, hash, 0, false, true)
    if w.infinite then
        SetPedAmmo(ped, hash, 4500)
    elseif w.ammoItem then
        -- The gun only ever holds its loaded rounds; reserve ammo stays in the inventory.
        SetPedAmmo(ped, hash, w.ammo or 0)
        SetAmmoInClip(ped, hash, w.ammo or 0)
    end
    SetCurrentPedWeapon(ped, hash, true)

    if held.durability and held.durability <= 0 then
        notify(('%s is jammed. Use a Gun Cleaning Kit.'):format(w.label), 'error')
        jamNotified = true
    end
end

---Called by client.lua with the server's answer to using a weapon / ammo / kit.
function ClientWeapons.handle(w)
    if w.action == 'equip' then equip(w)
    elseif w.action == 'holster' then holster(false) end
end

function ClientWeapons.update(u)
    if not held then return end
    if u.ammo ~= nil then
        held.ammo = u.ammo
        local ped = PlayerPedId()
        SetPedAmmo(ped, held.hash, u.ammo)
        SetAmmoInClip(ped, held.hash, u.ammo)
    end
    if u.durability ~= nil then
        held.durability = u.durability
        if u.durability > 0 then jamNotified = false end
    end
end

---Our inventory changed: if the held weapon left it (dropped, given, stored), put it away.
function ClientWeapons.onInventory(view)
    if not held or not view then return end
    for _, item in ipairs(view.items) do
        if item.name == held.name and (not held.serial or (item.metadata and item.metadata.serial == held.serial)) then
            return
        end
    end
    holster(true)
end

local function sendShots()
    if not held or shots == 0 then return end
    local n = shots
    shots = 0
    local r = TFC.Callback.Await('weapons:shots', n)
    if not r then return end
    if r.gone then
        holster(false)
        return
    end
    if r.durability ~= nil and held then held.durability = r.durability end
end

local function reload()
    if not held or reloading or not held.ammoItem then return end
    reloading = true
    sendShots()
    local r = TFC.Callback.Await('weapons:reload')
    if r and r.ok then
        ClientWeapons.update({ ammo = r.ammo })
        local ped = PlayerPedId()
        MakePedReload(ped)
    elseif r and r.error then
        notify(r.error, 'error')
    end
    reloading = false
end

-- Every frame while a weapon is held ----------------------------------------------------------

CreateThread(function()
    local lastReport = 0
    while true do
        if held then
            local ped = PlayerPedId()
            local player = PlayerId()

            -- Someone (or something) switched weapons: holster ours.
            if GetSelectedPedWeapon(ped) ~= held.hash then
                holster(true)
            else
                if IsPedShooting(ped) then
                    -- Guns lose rounds; anything with durability (incl. the taser) wears.
                    if held.ammoItem or held.durability then shots = shots + 1 end
                    if held.ammo then held.ammo = math.max(0, held.ammo - 1) end
                end

                -- Jammed.
                if held.durability and held.durability <= 0 then
                    DisablePlayerFiring(player, true)
                    if not jamNotified then
                        notify(('%s jammed. Use a Gun Cleaning Kit.'):format(held.label), 'error')
                        jamNotified = true
                    end
                end

                -- Our own reload: R, or automatically when the clip runs dry.
                if held.ammoItem then
                    DisableControlAction(0, 45, true) -- native reload
                    if IsDisabledControlJustPressed(0, 45) or (held.ammo == 0 and IsControlJustPressed(0, 24)) then
                        CreateThread(reload)
                    end
                end

                if shots > 0 and GetGameTimer() - lastReport > 1000 then
                    lastReport = GetGameTimer()
                    CreateThread(sendShots)
                end
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- Weapon wheel off, and no weapons except the one from the inventory --------------------------------

if Cfg.DisableWeaponWheel then
    CreateThread(function()
        while true do
            if TFC.PlayerData then
                DisableControlAction(0, 37, true)   -- weapon wheel (Tab)
                for _, control in ipairs({ 157, 158, 159, 160, 161, 162, 163, 164, 165 }) do
                    DisableControlAction(0, control, true) -- number keys selecting weapons
                end
                HideHudComponentThisFrame(19)
                HideHudComponentThisFrame(20)
                Wait(0)
            else
                Wait(500)
            end
        end
    end)
end

if Cfg.RemoveOtherWeapons then
    CreateThread(function()
        while true do
            Wait(1500)
            if TFC.PlayerData then
                local ped = PlayerPedId()
                local current = GetSelectedPedWeapon(ped)
                if current ~= UNARMED and (not held or current ~= held.hash) then
                    RemoveWeaponFromPed(ped, current)
                    SetCurrentPedWeapon(ped, UNARMED, true)
                end
            end
        end
    end)
end

TFC.OnPlayerUnloaded(function()
    holster(false)
    RemoveAllPedWeapons(PlayerPedId(), true)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and held then
        RemoveWeaponFromPed(PlayerPedId(), held.hash)
    end
end)
