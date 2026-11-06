-- Businesses client: the store manager (owners, managers) and the admin businesses panel.
-- The server checks everything.

local NO_RESPONSE = { ok = false, error = 'no response from server, try again' }
local IMAGE_PATH = 'nui://tfc-inventory/html/images/'
local isOpen = false

local function notify(text, kind)
    TFC.UI.Notify({ title = 'Business', description = text, type = kind or 'inform' })
end

local function open(view)
    if isOpen then return end
    local r
    if view == 'admin' then
        r = TFC.Callback.Await('business:admin', 'data') or NO_RESPONSE
    else
        r = TFC.Callback.Await('business:data') or NO_RESPONSE
    end
    if not r.ok then return notify(r.error, 'error') end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', view = view, data = r, imagePath = IMAGE_PATH })
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

TFC.OnNet('tfc-business:client:open', open)

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('action', function(d, cb)
    cb(TFC.Callback.Await('business:action', d.action, d.data or {}) or NO_RESPONSE)
end)

RegisterNUICallback('admin', function(d, cb)
    cb(TFC.Callback.Await('business:admin', d.action, d.data or {}) or NO_RESPONSE)
end)

-- "Manage store" in the job menu (F6) for every business job ----------------------------------------

AddEventHandler('tfc-business:client:actionManage', function()
    open('business')
end)

local function registerActions()
    if GetResourceState('tfc-jobs') ~= 'started' then return end
    local jobs = GlobalState['tfc:businessJobs'] or {}
    if #jobs == 0 then return end
    exports['tfc-jobs']:AddJobAction({
        id = 'business_manage', jobs = jobs, label = 'Manage store', description = 'Stock, prices and sales (managers and owner)',
        icon = 'store', event = 'tfc-business:client:actionManage', target = false, duty = false,
    })
end

CreateThread(registerActions)
AddStateBagChangeHandler('tfc:businessJobs', 'global', function()
    SetTimeout(0, registerActions)
end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'tfc-jobs' then registerActions() end
end)

TFC.OnPlayerUnloaded(close)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then SetNuiFocus(false, false) end
end)
