-- Banking client: bank blips, [E] at tellers and ATMs, the bank / ATM window, /bills, and the
-- "Send bill" job-menu action. The server checks everything.

local Cfg = BankingConfig
local NO_RESPONSE = { ok = false, error = 'no response from server, try again' }

local isOpen = false

local function notify(text, kind)
    TFC.UI.Notify({ title = 'Bank', description = text, type = kind or 'inform' })
end

-- Blips -------------------------------------------------------------------------------------------

CreateThread(function()
    for _, bank in ipairs(Cfg.Banks) do
        local b = AddBlipForCoord(bank.coords.x, bank.coords.y, bank.coords.z)
        SetBlipSprite(b, Cfg.Blip.sprite)
        SetBlipColour(b, Cfg.Blip.color)
        SetBlipScale(b, Cfg.Blip.scale)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(bank.label)
        EndTextCommandSetBlipName(b)
    end
end)

-- Opening and closing ------------------------------------------------------------------------------

local function open(kind, where)
    if isOpen or not TFC.PlayerData then return end
    local r = TFC.Callback.Await('banking:open', kind, where) or NO_RESPONSE
    if not r.ok then return notify(r.error, 'error') end
    isOpen = true
    TFC.UI.HidePrompt()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = r })
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TFC.Callback.Await('banking:close')
end

-- Banks and ATMs nearby: prompt and [E] ---------------------------------------------------------------

local atmHashes = {}
for _, m in ipairs(Cfg.AtmModels) do atmHashes[#atmHashes + 1] = joaat(m) end

local function nearestBank(here)
    for i, bank in ipairs(Cfg.Banks) do
        if #(here - bank.coords) < Cfg.BankDistance then return i, bank end
    end
    return nil
end

local function nearestAtm(here)
    for _, hash in ipairs(atmHashes) do
        local obj = GetClosestObjectOfType(here.x, here.y, here.z, Cfg.AtmDistance, hash, false, false, false)
        if obj ~= 0 then return obj end
    end
    return nil
end

local function anyBankWithin(here, d)
    for _, bank in ipairs(Cfg.Banks) do
        if #(here - bank.coords) < d then return true end
    end
    return false
end

CreateThread(function()
    while true do
        local sleep = 500
        if TFC.PlayerData and not isOpen and not IsPauseMenuActive() then
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) and not LocalPlayer.state['tfc:down'] and not LocalPlayer.state['tfc:cuffed'] then
                local here = GetEntityCoords(ped)
                local bankIndex, bank = nearestBank(here)
                local atm = not bankIndex and nearestAtm(here) or nil
                if bankIndex then
                    sleep = 0
                    TFC.UI.ShowPrompt('[E] ' .. bank.label)
                    if IsControlJustReleased(0, 38) then open('bank', bankIndex) end
                elseif atm then
                    sleep = 0
                    TFC.UI.ShowPrompt('[E] Use ATM')
                    if IsControlJustReleased(0, 38) then
                        local c = GetEntityCoords(atm)
                        open('atm', { x = c.x, y = c.y, z = c.z })
                    end
                else
                    TFC.UI.HidePrompt()
                    if anyBankWithin(here, 20.0) then sleep = 200 end
                end
            end
        end
        Wait(sleep)
    end
end)

TFC.OnNet('tfc-banking:client:openBills', function()
    if isOpen then return end
    open('bills')
end)

TFC.OnNet('tfc-banking:client:billsChanged', function()
    if isOpen then SendNUIMessage({ action = 'billsChanged' }) end
end)

-- NUI --------------------------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('action', function(d, cb)
    cb(TFC.Callback.Await('banking:action', d.action, d.data or {}) or NO_RESPONSE)
end)

-- Walked away from the teller / ATM: close.
CreateThread(function()
    while true do
        Wait(1000)
        if isOpen and (LocalPlayer.state['tfc:down'] or LocalPlayer.state['tfc:cuffed']) then close() end
    end
end)

-- "Send bill" in the job menu (F6) --------------------------------------------------------------------

AddEventHandler('tfc-banking:client:actionBill', function(args)
    local target = args and args.target
    if not target then return end
    local values = TFC.UI.Input('Send a bill', {
        { type = 'number', label = 'Amount ($)', min = 1, max = Cfg.Billing.MaxAmount, required = true },
        { type = 'input', label = 'What for', placeholder = 'e.g. Engine repair', required = true, min = 3, max = 120 },
    })
    if not values then return end
    local r = TFC.Callback.Await('banking:sendBill', target, values[1], values[2]) or NO_RESPONSE
    notify(r.ok and r.message or r.error, r.ok and 'success' or 'error')
end)

local function registerActions()
    if GetResourceState('tfc-jobs') ~= 'started' then return end
    local jobs = {}
    for name in pairs(Cfg.Billing.Jobs) do jobs[#jobs + 1] = name end
    exports['tfc-jobs']:AddJobAction({
        id = 'bank_bill', jobs = jobs, label = 'Send bill', description = 'Bill the closest player',
        icon = 'file-invoice-dollar', event = 'tfc-banking:client:actionBill',
    })
end

CreateThread(registerActions)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'tfc-jobs' then registerActions() end
end)

TFC.OnPlayerUnloaded(function()
    if isOpen then
        isOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then SetNuiFocus(false, false) end
end)
