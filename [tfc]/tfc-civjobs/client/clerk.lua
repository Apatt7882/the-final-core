-- Convenience Store Clerk (client): clock in/out (F6), "you can work here" hint, NPC customers,
-- carrying boxes to the shelves and mopping spills.

local C = CivJobsConfig.Clerk
local M = { job = C.Job }
Civ.modules.clerk = M

local customer = nil   -- { ped, leaving }

local function workplace() return LocalPlayer.state['tfc:workplace'] end

local function sendAway(ped)
    if not ped or not DoesEntityExist(ped) then return end
    local p = GetEntityCoords(ped)
    TaskWanderStandard(ped, 10.0, 10)
    SetPedKeepTask(ped, true)
    SetTimeout(12000, function()
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end)
    return p
end

local function spawnCustomer(t)
    local model = Civ.loadModel(t.model)
    if not model then return end
    local z = Civ.groundZ(t.spawn.x, t.spawn.y, t.spawn.z)
    local ped = CreatePed(4, model, t.spawn.x, t.spawn.y, z, t.heading, false, true)
    SetModelAsNoLongerNeeded(model)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetEntityInvincible(ped, true)
    local sz = Civ.groundZ(t.stand.x, t.stand.y, t.stand.z)
    TaskGoStraightToCoord(ped, t.stand.x, t.stand.y, sz + 1.0, 1.0, 30000, t.heading, 0.3)
    customer = { ped = ped, id = t.id }
end

function M.onTask(t, old)
    if old and old.kind == 'customer' and (not t or t.id ~= old.id) and customer then
        sendAway(customer.ped)
        customer = nil
    end
    if not t or t.job ~= C.Job then return end
    if t.kind == 'customer' and (not customer or customer.id ~= t.id) then
        CreateThread(function() spawnCustomer(t) end)
        Civ.notify(('A customer is coming to the counter (%d item%s, $%d).'):format(#t.items, #t.items == 1 and '' or 's', t.total), 'inform', 'Store clerk')
    elseif t.kind == 'restock' then
        if t.carrying then Civ.carry('box') else Civ.stopCarry() end
        Civ.ground(t.stockroom)
        for _, s in ipairs(t.shelves) do Civ.ground(s) end
    elseif t.kind == 'clean' then
        Civ.ground(t.spot)
    end
end

function M.describe(t)
    if t.job ~= C.Job then return nil end
    if t.kind == 'customer' then return ('Ring up the customer at the counter: %s ($%d).'):format(table.concat(t.items, ', '), t.total) end
    if t.kind == 'restock' then
        return t.carrying and ('Put the box on the marked shelf (%d/%d).'):format(t.done, t.boxes)
            or ('Pick up a box behind the counter (%d/%d done).'):format(t.done, t.boxes)
    end
    if t.kind == 'clean' then return 'Mop up the spill (marked on the floor).' end
end

local function serve()
    local items = Civ.task and Civ.task.items or {}
    local passed = TFC.UI.SkillCheck({ 'easy', 'easy', 'medium' }, { 'e' })
    if customer and DoesEntityExist(customer.ped) and Civ.loadDict('mp_common') then
        TaskPlayAnim(PlayerPedId(), 'mp_common', 'givetake1_a', 8.0, -8.0, 1500, 48, 0.0, false, false, false)
    end
    local r = Civ.act('serve', { passed = passed })
    if r.ok and not passed then Civ.notify('You fumbled the register, no tip this time.', 'warning', 'Store clerk') end
    return items
end

function M.tick(here, t)
    local w = workplace()
    if not w then return false end
    if Civ.dist2d(here, w) > C.WorkDistance + 20.0 then return false end
    if not t or t.job ~= C.Job then return true end

    if t.kind == 'customer' then
        if customer and DoesEntityExist(customer.ped) then
            local cp = GetEntityCoords(customer.ped)
            local arrived = Civ.dist2d(cp, t.stand) < 1.6
            if arrived and Civ.dist2d(here, w) < 3.5 then
                Civ.offer(('[E] Ring up customer ($%d)'):format(t.total), serve)
            end
            DrawMarker(2, cp.x, cp.y, cp.z + 1.2, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.25, 0.25, 0.25, 232, 163, 61, 160, true, true, 2, false, nil, nil, false)
        end
    elseif t.kind == 'restock' then
        if not t.carrying then
            Civ.marker(t.stockroom)
            if Civ.dist2d(here, t.stockroom) < 1.5 then
                Civ.offer('[E] Pick up a box', function()
                    if TFC.UI.Progress({ duration = 1500, label = 'Picking up a box', anim = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49 } }) then
                        Civ.act('pickup')
                    end
                end)
            end
        else
            local shelf = t.shelves[t.shelf]
            Civ.marker(shelf, { 76, 195, 138 })
            if Civ.dist2d(here, shelf) < 1.5 then
                Civ.offer('[E] Stock the shelf', function()
                    Civ.stopCarry()
                    if TFC.UI.Progress({ duration = 4000, label = 'Stocking the shelf', anim = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search', flag = 49 } }) then
                        Civ.act('stock')
                    elseif Civ.task and Civ.task.carrying then
                        Civ.carry('box')
                    end
                end)
            end
        end
    elseif t.kind == 'clean' then
        Civ.marker(t.spot, { 91, 156, 245 }, 1.2)
        if Civ.dist2d(here, t.spot) < 1.5 then
            Civ.offer('[E] Mop the spill', function()
                if TFC.UI.Progress({ duration = 6000, label = 'Mopping', anim = { dict = 'amb@world_human_maid_clean@', clip = 'base', flag = 1 } }) then
                    Civ.act('mop')
                end
            end)
        end
    end
    return true
end

-- F6 > Clock in / out at the counter ------------------------------------------------------------------------

function M.actions(jobs)
    jobs:AddJobAction({
        id = 'clerk_clock', jobs = { C.Job }, label = 'Clock in / out',
        description = 'Start or end your shift at this 24/7 store', icon = 'clock',
        event = 'tfc-civjobs:client:clerkClock', target = false, duty = false,
    })
end

AddEventHandler('tfc-civjobs:client:clerkClock', function()
    Civ.run(function()
        local r = TFC.Callback.Await('civjobs:clock')
        if not r then return end
        if not r.ok then
            Civ.notify(r.error, 'error', 'Store clerk')
        elseif not r.onDuty then
            Civ.notify('Clocked out. See you next shift.', 'inform', 'Store clerk')
        end
    end)
end)

-- "You can work here" hint for off-duty clerks.
CreateThread(function()
    local stores, fetchedAt = {}, 0
    local hinted = nil
    while true do
        Wait(2000)
        local job = Civ.job()
        if job and job.name == C.Job and job.onDuty == false then
            if GetGameTimer() - fetchedAt > 60000 then
                stores = TFC.Callback.Await('civjobs:stores') or {}
                fetchedAt = GetGameTimer()
            end
            local here = Civ.me()
            local near = nil
            for _, s in ipairs(stores) do
                if Civ.dist2d(here, s) < C.HintDistance then near = s break end
            end
            if near and hinted ~= near.id then
                hinted = near.id
                Civ.notify(('You can work at %s. Go to the counter and press F6 > Clock in / out (or type /duty).'):format(near.label), 'inform', 'Store clerk')
            elseif not near then
                hinted = nil
            end
        else
            fetchedAt = 0
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and customer and DoesEntityExist(customer.ped) then DeleteEntity(customer.ped) end
end)
