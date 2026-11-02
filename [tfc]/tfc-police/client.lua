-- Police client: what it's like to be cuffed, escorted, seated and jailed, plus the officer's
-- job-menu actions (F6). The server decides everything; this only plays it out.

local Cfg = PoliceConfig
local busy = false

local function notify(text, kind)
    TFC.UI.Notify({ title = 'Police', description = text, type = kind or 'inform' })
end

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function myState(key)
    return LocalPlayer.state[key]
end

local function isMine(bagName)
    return bagName == ('player:%d'):format(GetPlayerServerId(PlayerId()))
end

-- Cuffed --------------------------------------------------------------------------------------------

local CUFF_ANIM = { dict = 'mp_arresting', clip = 'idle' }
local BLOCKED = { 21, 22, 23, 24, 25, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264, 288, 289 }
-- sprint, jump, enter vehicle, attack, aim, weapon wheel, cover, reload, weapons, melee...

local cuffLoop = false
local function startCuffLoop()
    if cuffLoop then return end
    cuffLoop = true
    CreateThread(function()
        while myState('tfc:cuffed') do
            local ped = PlayerPedId()
            for _, c in ipairs(BLOCKED) do DisableControlAction(0, c, true) end
            SetEnableHandcuffs(ped, true)
            if not myState('tfc:down') and not IsPedInAnyVehicle(ped, false)
                and not IsEntityPlayingAnim(ped, CUFF_ANIM.dict, CUFF_ANIM.clip, 3) and loadDict(CUFF_ANIM.dict) then
                TaskPlayAnim(ped, CUFF_ANIM.dict, CUFF_ANIM.clip, 8.0, -8.0, -1, 49, 0.0, false, false, false)
            end
            Wait(0)
        end
        local ped = PlayerPedId()
        SetEnableHandcuffs(ped, false)
        StopAnimTask(ped, CUFF_ANIM.dict, CUFF_ANIM.clip, 1.0)
        cuffLoop = false
    end)
end

AddStateBagChangeHandler('tfc:cuffed', nil, function(bagName, _, value)
    if not isMine(bagName) then return end
    if value then
        -- Wait a tick so LocalPlayer.state has the new value before the loop reads it.
        SetTimeout(0, startCuffLoop)
    end
end)

-- Resource restarted while we were cuffed.
CreateThread(function()
    if myState('tfc:cuffed') then startCuffLoop() end
end)

TFC.OnNet('tfc-police:client:cuffedAnim', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or myState('tfc:down') then return end
    if loadDict('mp_arresting') then
        TaskPlayAnim(ped, 'mp_arresting', 'arrested_spin_r_0', 8.0, -8.0, 2500, 0, 0.0, false, false, false)
    end
end)

-- Escorted -------------------------------------------------------------------------------------------

local function detach()
    local ped = PlayerPedId()
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
end

AddStateBagChangeHandler('tfc:escortedBy', nil, function(bagName, _, officerId)
    if not isMine(bagName) then return end
    if not officerId then return detach() end
    CreateThread(function()
        local officer = GetPlayerFromServerId(officerId)
        if officer == -1 then return end
        local ped = PlayerPedId()
        AttachEntityToEntity(ped, GetPlayerPed(officer), 11816, 0.45, 0.45, 0.0, 0.0, 0.0, 0.0,
            false, false, false, false, 2, true)
        -- Stay attached until the server lets go (or the officer disappears).
        while LocalPlayer.state['tfc:escortedBy'] == officerId do
            if not DoesEntityExist(GetPlayerPed(officer)) then break end
            Wait(500)
        end
        detach()
    end)
end)

-- Seated in / taken out of a vehicle ----------------------------------------------------------

TFC.OnNet('tfc-police:client:seat', function(netId)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetToVeh(netId)
    if veh == 0 then return end
    detach()
    local ped = PlayerPedId()
    -- Back seats first (1, 2), then front passenger (0).
    for _, seat in ipairs({ 1, 2, 0 }) do
        if IsVehicleSeatFree(veh, seat) then
            TaskWarpPedIntoVehicle(ped, veh, seat)
            return
        end
    end
    notify('There was no free seat.', 'error')
end)

TFC.OnNet('tfc-police:client:unseat', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then TaskLeaveVehicle(ped, veh, 16) end
end)

-- Jail -----------------------------------------------------------------------------------------------

local jailEnds = 0
local inJail = false

local function teleport(c)
    local ped = PlayerPedId()
    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(0) end
    detach()
    if IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end
    SetEntityCoords(ped, c.x, c.y, c.z - 1.0, false, false, false, false)
    SetEntityHeading(ped, c.w or 0.0)
    Wait(300)
    DoScreenFadeIn(600)
end

local function drawText(text)
    SetTextFont(4)
    SetTextScale(0.45, 0.45)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.94)
end

TFC.OnNet('tfc-police:client:jail', function(seconds, spawn)
    jailEnds = GetGameTimer() + seconds * 1000
    teleport(spawn)
    if inJail then return end
    inJail = true
    CreateThread(function()
        local center = Cfg.Jail.center
        while inJail do
            local ped = PlayerPedId()
            if #(GetEntityCoords(ped) - center) > Cfg.Jail.radius then
                notify('You can\'t leave the prison.', 'error')
                teleport(spawn)
            end
            local left = math.max(0, math.ceil((jailEnds - GetGameTimer()) / 1000))
            drawText(('In jail: %d:%02d left'):format(left // 60, left % 60))
            Wait(0)
        end
    end)
end)

TFC.OnNet('tfc-police:client:release', function(release)
    inJail = false
    teleport(release)
end)

-- Officer actions (job menu) -----------------------------------------------------------------------

local function act(action, target, a, b)
    local r = TFC.Callback.Await('police:action', action, target, a, b)
    if not r then return notify('No response from server, try again.', 'error') end
    if r.ok and r.message then notify(r.message, 'success') elseif not r.ok then notify(r.error, 'error') end
    return r
end

local function withTarget(fn)
    return function(args)
        local target = args and args.target
        if not target or busy then return end
        busy = true
        local ok, err = pcall(fn, target)
        busy = false
        if not ok then print(err) end
    end
end

AddEventHandler('tfc-police:client:actionCuff', withTarget(function(target)
    local uncuff = Player(target).state['tfc:cuffed'] == true
    local done = TFC.UI.Progress({
        duration = uncuff and 1500 or 2500, label = uncuff and 'Uncuffing' or 'Cuffing',
        anim = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 },
    })
    if done then act('cuff', target) end
end))

AddEventHandler('tfc-police:client:actionEscort', withTarget(function(target) act('escort', target) end))
AddEventHandler('tfc-police:client:actionSeat', withTarget(function(target) act('seat', target) end))
AddEventHandler('tfc-police:client:actionUnseat', withTarget(function(target) act('unseat', target) end))
AddEventHandler('tfc-police:client:actionSearch', withTarget(function(target)
    if TFC.UI.Progress({ duration = 2000, label = 'Searching', anim = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search', flag = 49 } }) then
        act('search', target)
    end
end))

AddEventHandler('tfc-police:client:actionFine', withTarget(function(target)
    local values = TFC.UI.Input('Issue a fine', {
        { type = 'number', label = 'Amount ($)', min = 1, max = Cfg.MaxFine, required = true },
        { type = 'input', label = 'Reason', placeholder = 'e.g. Speeding, 40 over', required = true, min = 3, max = 120 },
    })
    if values then act('fine', target, values[1], values[2]) end
end))

AddEventHandler('tfc-police:client:actionJail', withTarget(function(target)
    local values = TFC.UI.Input('Send to jail', {
        { type = 'number', label = 'Minutes', min = 1, max = Cfg.MaxJailMinutes, required = true },
        { type = 'input', label = 'Charges', placeholder = 'e.g. Armed robbery', required = true, min = 3, max = 120 },
    })
    if values then act('jail', target, values[1], values[2]) end
end))

local function registerActions()
    if GetResourceState('tfc-jobs') ~= 'started' then return end
    local jobs = exports['tfc-jobs']
    local list = {
        { id = 'police_cuff', label = 'Cuff / uncuff', description = 'Closest player', icon = 'handcuffs', event = 'tfc-police:client:actionCuff' },
        { id = 'police_escort', label = 'Escort / let go', description = 'Cuffed or downed player', icon = 'people-pulling', event = 'tfc-police:client:actionEscort' },
        { id = 'police_seat', label = 'Put in vehicle', description = 'Into the closest vehicle', icon = 'car-side', event = 'tfc-police:client:actionSeat' },
        { id = 'police_unseat', label = 'Take out of vehicle', icon = 'person-walking-arrow-right', event = 'tfc-police:client:actionUnseat' },
        { id = 'police_search', label = 'Search', description = 'Open their inventory (cuffed or downed)', icon = 'magnifying-glass', event = 'tfc-police:client:actionSearch' },
        { id = 'police_fine', label = 'Issue fine', icon = 'file-invoice-dollar', event = 'tfc-police:client:actionFine' },
        { id = 'police_jail', label = 'Send to jail', description = 'Cuffed player', icon = 'building-shield', event = 'tfc-police:client:actionJail' },
    }
    for _, a in ipairs(list) do
        a.jobs = Cfg.Jobs
        jobs:AddJobAction(a)
    end
end

CreateThread(registerActions)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'tfc-jobs' then registerActions() end
end)

-- Cleanup ------------------------------------------------------------------------------------------

TFC.OnPlayerUnloaded(function()
    inJail = false
    detach()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    detach()
    SetEnableHandcuffs(PlayerPedId(), false)
end)
