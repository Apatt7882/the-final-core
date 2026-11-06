-- Finance client: the City Accountant ([E] in the Government Center), the window, and the
-- hand-offs from the bank and the Government Center.

local Cfg = FinanceConfig
local NO_RESPONSE = { ok = false, error = 'no response from server, try again' }
local isOpen = false
local ped = nil

local function notify(text, kind)
    TFC.UI.Notify({ title = 'Accountant', description = text, type = kind or 'inform' })
end

local function open(tab)
    if isOpen or not TFC.PlayerData then return end
    local r = TFC.Callback.Await('finance:open') or NO_RESPONSE
    if not r.ok then return notify(r.error, 'error') end
    isOpen = true
    TFC.UI.HidePrompt()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', tab = tab or 'advisor', data = r })
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

AddEventHandler('tfc-finance:client:openAdvisor', function() open('advisor') end)
TFC.OnNet('tfc-finance:client:open', open)

-- The Accountant ---------------------------------------------------------------------------------

CreateThread(function()
    local def = Cfg.Accountant
    local c = def.coords
    while true do
        local here = GetEntityCoords(PlayerPedId())
        local d = #(here - vector3(c.x, c.y, c.z))
        if d < 60.0 and not ped then
            local model = joaat(def.ped)
            if IsModelInCdimage(model) then
                RequestModel(model)
                local t = GetGameTimer() + 5000
                while not HasModelLoaded(model) and GetGameTimer() < t do Wait(0) end
                if HasModelLoaded(model) then
                    ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, true)
                    SetModelAsNoLongerNeeded(model)
                    SetEntityInvincible(ped, true)
                    FreezeEntityPosition(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    if def.scenario then TaskStartScenarioInPlace(ped, def.scenario, 0, true) end
                end
            end
        elseif d >= 60.0 and ped then
            if DoesEntityExist(ped) then DeleteEntity(ped) end
            ped = nil
        end

        local sleep = d < 20.0 and 0 or 1000
        if sleep == 0 then
            if not isOpen and d < Cfg.InteractDistance and TFC.PlayerData then
                TFC.UI.ShowPrompt('[E] ' .. def.label)
                if IsControlJustReleased(0, 38) then open('advisor') end
            else
                TFC.UI.HidePrompt()
            end
        end
        Wait(sleep)
    end
end)

-- Window --------------------------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('refresh', function(_, cb)
    cb(TFC.Callback.Await('finance:refresh') or NO_RESPONSE)
end)

RegisterNUICallback('trade', function(d, cb)
    cb(TFC.Callback.Await('finance:trade', d.side, d.symbol, d.shares) or NO_RESPONSE)
end)

RegisterNUICallback('ask', function(d, cb)
    cb(TFC.Callback.Await('finance:ask', d.question) or NO_RESPONSE)
end)

TFC.OnPlayerUnloaded(close)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false) end
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
end)
