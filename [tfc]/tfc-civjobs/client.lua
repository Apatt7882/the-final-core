-- Civilian jobs client. Clerk: F6 > Clock in / out, and a hint when an off-duty clerk walks
-- into a store they can work at. The server decides everything.

local C = CivJobsConfig.Clerk

local function addActions()
    exports['tfc-jobs']:AddJobAction({
        id = 'clerk_clock', jobs = { C.Job }, label = 'Clock in / out',
        description = 'Start or end your shift at this 24/7 store', icon = 'clock',
        event = 'tfc-civjobs:client:clock', target = false, duty = false,
    })
end

CreateThread(function()
    while GetResourceState('tfc-jobs') ~= 'started' do Wait(500) end
    addActions()
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'tfc-jobs' then addActions() end
end)

AddEventHandler('tfc-civjobs:client:clock', function()
    local r = TFC.Callback.Await('civjobs:clock')
    if not r then return end
    if not r.ok then
        TFC.UI.Notify({ title = 'Store clerk', description = r.error, type = 'error' })
    elseif not r.onDuty then
        TFC.UI.Notify({ title = 'Store clerk', description = 'Clocked out. See you next shift.', type = 'inform' })
    end
end)

-- "Clock in here" hint for off-duty clerks.
CreateThread(function()
    local stores, fetchedAt = {}, 0
    local hinted = nil
    while true do
        Wait(2000)
        local job = LocalPlayer.state['tfc:job']
        if job and job.name == C.Job and job.onDuty == false then
            if GetGameTimer() - fetchedAt > 60000 then
                stores = TFC.Callback.Await('civjobs:stores') or {}
                fetchedAt = GetGameTimer()
            end
            local here = GetEntityCoords(PlayerPedId())
            local near = nil
            for _, s in ipairs(stores) do
                if #(here - vector3(s.x, s.y, s.z)) < C.HintDistance then near = s break end
            end
            if near and hinted ~= near.id then
                hinted = near.id
                TFC.UI.Notify({ title = 'Store clerk', description = ('You can work at %s. Go to the counter and press F6 > Clock in / out (or type /duty).'):format(near.label), duration = 8000 })
            elseif not near then
                hinted = nil
            end
        else
            fetchedAt = 0
        end
    end
end)
