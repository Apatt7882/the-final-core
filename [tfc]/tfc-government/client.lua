-- Government client: clerks at the Government Center and DMV ([E]), blips, the window,
-- and the police "Licenses" job-menu action.

local Cfg = GovConfig
local NO_RESPONSE = { ok = false, error = 'no response from server, try again' }
local isOpen = false
local peds = {}

local function notify(text, kind)
    TFC.UI.Notify({ title = 'Government', description = text, type = kind or 'inform' })
end

local PLACES = {
    { key = 'cityhall', def = Cfg.CityHall },
    { key = 'dmv', def = Cfg.Dmv },
}

-- Blips and clerks -------------------------------------------------------------------------------

CreateThread(function()
    for _, p in ipairs(PLACES) do
        local c, b = p.def.coords, p.def.blip
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, b.sprite)
        SetBlipColour(blip, b.color)
        SetBlipScale(blip, b.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(p.def.label)
        EndTextCommandSetBlipName(blip)
    end
end)

local function spawnPed(def)
    local model = joaat(def.ped)
    if not IsModelInCdimage(model) then return nil end
    RequestModel(model)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(0) end
    if not HasModelLoaded(model) then return nil end
    local c = def.coords
    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    if def.scenario then TaskStartScenarioInPlace(ped, def.scenario, 0, true) end
    return ped
end

CreateThread(function()
    while true do
        local here = GetEntityCoords(PlayerPedId())
        for _, p in ipairs(PLACES) do
            local c = p.def.coords
            local near = #(here - vector3(c.x, c.y, c.z)) < 60.0
            if near and not peds[p.key] then
                peds[p.key] = spawnPed(p.def) or false
            elseif not near and peds[p.key] ~= nil then
                if peds[p.key] and DoesEntityExist(peds[p.key]) then DeleteEntity(peds[p.key]) end
                peds[p.key] = nil
            end
        end
        Wait(1000)
    end
end)

-- Window ------------------------------------------------------------------------------------------

local function show(view, data)
    isOpen = true
    TFC.UI.HidePrompt()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', view = view, data = data })
end

local function open(place)
    if isOpen or not TFC.PlayerData then return end
    local r = TFC.Callback.Await('gov:open', place) or NO_RESPONSE
    if not r.ok then return notify(r.error, 'error') end
    show(place, r)
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

CreateThread(function()
    while true do
        local sleep = 500
        if TFC.PlayerData and not isOpen and not IsPauseMenuActive() then
            local here = GetEntityCoords(PlayerPedId())
            local found = nil
            for _, p in ipairs(PLACES) do
                local c = p.def.coords
                local d = #(here - vector3(c.x, c.y, c.z))
                if d < Cfg.InteractDistance then found = p end
                if d < 20.0 then sleep = 200 end
            end
            if found then
                sleep = 0
                TFC.UI.ShowPrompt('[E] ' .. found.def.label)
                if IsControlJustReleased(0, 38) then open(found.key) end
            else
                TFC.UI.HidePrompt()
            end
        end
        Wait(sleep)
    end
end)

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('city', function(d, cb)
    cb(TFC.Callback.Await('gov:city', d.action, d.data or {}) or NO_RESPONSE)
end)

RegisterNUICallback('dmv', function(d, cb)
    cb(TFC.Callback.Await('gov:dmv', d.action, d.data or {}) or NO_RESPONSE)
end)

RegisterNUICallback('police', function(d, cb)
    cb(TFC.Callback.Await('gov:police', d.action, d.a, d.b, d.c) or NO_RESPONSE)
end)

RegisterNUICallback('waypoint', function(d, cb)
    SetNewWaypoint(d.x + 0.0, d.y + 0.0)
    notify(('Waypoint set: %s'):format(d.label or 'destination'), 'success')
    cb({ ok = true })
end)

RegisterNUICallback('accountant', function(_, cb)
    close()
    TriggerEvent('tfc-finance:client:openAdvisor')
    cb({ ok = true })
end)

-- Police --------------------------------------------------------------------------------------------

TFC.OnNet('tfc-government:client:police', function(r)
    if isOpen then return end
    show('police', r)
end)

TFC.OnNet('tfc-government:client:requests', function(r)
    if isOpen then return end
    show('requests', r)
end)

AddEventHandler('tfc-government:client:actionLicenses', function(args)
    local target = args and args.target
    if not target or isOpen then return end
    local r = TFC.Callback.Await('gov:police', 'view', target) or NO_RESPONSE
    if not r.ok then return notify(r.error, 'error') end
    show('police', r)
end)

local function registerActions()
    if GetResourceState('tfc-jobs') ~= 'started' then return end
    exports['tfc-jobs']:AddJobAction({
        id = 'gov_licenses', jobs = Cfg.Authority.jobs, label = 'Check licenses',
        description = 'View, suspend or revoke the closest player\'s licenses', icon = 'id-card', event = 'tfc-government:client:actionLicenses',
    })
end
CreateThread(registerActions)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'tfc-jobs' then registerActions() end
end)

TFC.OnPlayerUnloaded(close)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false) end
    for _, ped in pairs(peds) do
        if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    end
end)
