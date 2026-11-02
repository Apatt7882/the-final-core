-- Shops client: shopkeeper peds, map blips, the [E] prompt, the shop window and the
-- admin shop manager (/shops). Every purchase, sale and admin change is checked on the server.

local Cfg = ShopsConfig
local NO_RESPONSE = { ok = false, error = 'no response from server, try again' }
local IMAGE_PATH = 'nui://tfc-inventory/html/images/'

local shops = {}        -- list from the server
local peds = {}         -- shop id -> ped handle
local blips = {}        -- shop id -> blip handle
local openShop = nil    -- the shop whose window is open
local adminOpen = false

-- Shop list ----------------------------------------------------------------------------------

local function clearWorld()
    for id, ped in pairs(peds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
        peds[id] = nil
    end
    for id, blip in pairs(blips) do
        RemoveBlip(blip)
        blips[id] = nil
    end
end

local function makeBlips()
    for _, shop in ipairs(shops) do
        if shop.blip then
            local b = AddBlipForCoord(shop.x, shop.y, shop.z)
            SetBlipSprite(b, shop.blip.sprite or 52)
            SetBlipColour(b, shop.blip.color or 0)
            SetBlipScale(b, shop.blip.scale or 0.7)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(shop.label)
            EndTextCommandSetBlipName(b)
            blips[shop.id] = b
        end
    end
end

local function setShops(list)
    clearWorld()
    shops = list or {}
    makeBlips()
end

TFC.OnNet('tfc-shops:client:shops', function(list)
    setShops(list)
end)

TFC.OnPlayerLoaded(function()
    local r = TFC.Callback.Await('shops:list')
    if r then setShops(r.shops) end
end)

-- Shopkeepers ----------------------------------------------------------------------------------

local function spawnPed(shop)
    local model = joaat(shop.ped)
    if not IsModelInCdimage(model) then return nil end
    RequestModel(model)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(0) end
    if not HasModelLoaded(model) then return nil end

    local ped = CreatePed(4, model, shop.x, shop.y, shop.z - 1.0, shop.h, false, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDiesWhenInjured(ped, false)
    if shop.scenario then TaskStartScenarioInPlace(ped, shop.scenario, 0, true) end
    return ped
end

CreateThread(function()
    while true do
        if TFC.PlayerData then
            local here = GetEntityCoords(PlayerPedId())
            for _, shop in ipairs(shops) do
                local near = #(here - vector3(shop.x, shop.y, shop.z)) < Cfg.PedDistance
                local ped = peds[shop.id]
                if near and not ped then
                    peds[shop.id] = spawnPed(shop) or false
                elseif not near and ped ~= nil then
                    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
                    peds[shop.id] = nil
                end
            end
        end
        Wait(1000)
    end
end)

-- Prompt and opening ------------------------------------------------------------------------------

local function isOpenAt(hours, hour)
    if not hours then return true end
    local open, close = hours[1], hours[2]
    if open == close then return true end
    if open < close then return hour >= open and hour < close end
    return hour >= open or hour < close
end

---What the prompt says, and whether E does anything.
local function promptFor(shop)
    if shop.job then
        local job = LocalPlayer.state['tfc:job']
        if not job or job.name ~= shop.job then return ('%s · employees only'):format(shop.label), false end
    end
    if shop.hours and Cfg.Clock == 'game' and not isOpenAt(shop.hours, GetClockHours()) then
        return ('%s · closed until %02d:00'):format(shop.label, shop.hours[1]), false
    end
    return ('[E] %s'):format(shop.label), true
end

local function nearestShop()
    local here = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, Cfg.InteractDistance
    local anyClose = false
    for _, shop in ipairs(shops) do
        local d = #(here - vector3(shop.x, shop.y, shop.z))
        if d < 15.0 then anyClose = true end
        if d < bestDist then best, bestDist = shop, d end
    end
    return best, anyClose
end

local function closeShop()
    if not openShop then return end
    openShop = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openShopWindow(shop)
    if openShop or adminOpen then return end
    local r = TFC.Callback.Await('shops:open', shop.id, GetClockHours()) or NO_RESPONSE
    if not r.ok then
        TFC.UI.Notify({ title = shop.label, description = r.error, type = 'error' })
        return
    end
    openShop = shop
    TFC.UI.HidePrompt()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'shop', shop = r.shop, imagePath = IMAGE_PATH })
end

CreateThread(function()
    while true do
        local sleep = 500
        if TFC.PlayerData and not openShop and not adminOpen and not IsPauseMenuActive() then
            local shop, anyClose = nearestShop()
            if shop then
                sleep = 0
                local text, usable = promptFor(shop)
                TFC.UI.ShowPrompt(text)
                if usable and IsControlJustReleased(0, 38) then
                    openShopWindow(shop)
                end
            else
                TFC.UI.HidePrompt()
                if anyClose then sleep = 150 end
            end
        elseif openShop then
            -- Walked (or got dragged) away: close the window.
            local here = GetEntityCoords(PlayerPedId())
            if #(here - vector3(openShop.x, openShop.y, openShop.z)) > Cfg.InteractDistance + 3.0 then closeShop() end
        end
        Wait(sleep)
    end
end)

-- Shop window callbacks ---------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    closeShop()
    if adminOpen then
        adminOpen = false
        SetNuiFocus(false, false)
    end
    cb({})
end)

RegisterNUICallback('buy', function(d, cb)
    if not openShop then return cb(NO_RESPONSE) end
    cb(TFC.Callback.Await('shops:buy', openShop.id, d.name, d.count, d.payment, GetClockHours()) or NO_RESPONSE)
end)

RegisterNUICallback('sell', function(d, cb)
    if not openShop then return cb(NO_RESPONSE) end
    cb(TFC.Callback.Await('shops:sell', openShop.id, d.name, d.count, GetClockHours()) or NO_RESPONSE)
end)

-- Admin shop manager ---------------------------------------------------------------------------------

TFC.OnNet('tfc-shops:client:admin', function()
    if openShop then closeShop() end
    local r = TFC.Callback.Await('shops:admin:data') or NO_RESPONSE
    if not r.ok then
        TFC.UI.Notify({ title = 'Shops', description = r.error, type = 'error' })
        return
    end
    adminOpen = true
    TFC.UI.HidePrompt()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'admin', data = r })
end)

RegisterNUICallback('adminAction', function(d, cb)
    cb(TFC.Callback.Await('shops:admin:action', d.action, d.data or {}) or NO_RESPONSE)
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    cb(TFC.Callback.Await('shops:admin:data') or NO_RESPONSE)
end)

-- Go to a shop: stand 1.5 m in front of the shopkeeper, facing them.
RegisterNUICallback('adminGoto', function(d, cb)
    local h = tonumber(d.h) or 0.0
    local rad = math.rad(h)
    local x = d.x + -math.sin(rad) * 1.5
    local y = d.y + math.cos(rad) * 1.5
    local ped = PlayerPedId()
    SetEntityCoords(ped, x, y, d.z - 1.0, false, false, false, false)
    SetEntityHeading(ped, (h + 180.0) % 360.0)
    cb({ ok = true })
end)

-- Cleanup -------------------------------------------------------------------------------------------

TFC.OnPlayerUnloaded(function()
    closeShop()
    if adminOpen then adminOpen = false SetNuiFocus(false, false) SendNUIMessage({ action = 'close' }) end
    TFC.UI.HidePrompt()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearWorld()
    TFC.UI.HidePrompt()
    if openShop or adminOpen then SetNuiFocus(false, false) end
end)
