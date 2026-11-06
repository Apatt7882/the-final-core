-- HUD client: gathers data and sends only what changed to the NUI page.
-- Money comes from tfc-accounts, job from the 'tfc:job' state bag (set by tfc-jobs),
-- time and location from the game.

local enabled = true   -- player's /hud toggle
local visible = false  -- what the page currently shows
local last = {}        -- last value sent for each field
local updatePostal     -- defined in the Postals section below

local function send(field, value)
    if last[field] == value then return end
    last[field] = value
    SendNUIMessage({ action = 'set', field = field, value = value })
end

local function sendTable(field, value)
    local encoded = json.encode(value)
    if last[field] == encoded then return end
    last[field] = encoded
    SendNUIMessage({ action = 'set', field = field, value = value })
end

-- Minimap placement (so the location sits right beside it at any resolution) --------

local function minimapAnchor()
    local safezone = GetSafeZoneSize()
    local aspect = GetAspectRatio(false)
    local resX, resY = GetActiveScreenResolution()
    local xScale, yScale = 1.0 / resX, 1.0 / resY
    local inset = math.abs(safezone - 1.0) * 10

    local width = xScale * (resX / (4 * aspect))
    local height = yScale * (resY / 5.674)
    local left = xScale * (resX * (0.05 * inset))
    local bottom = 1.0 - yScale * (resY * (0.05 * inset))

    return { left = left, right = left + width, bottom = bottom, top = bottom - height }
end

-- Time -----------------------------------------------------------------------------

local function gameTime()
    return {
        hour = GetClockHours(),
        minute = GetClockMinutes(),
        day = GetClockDayOfMonth(),
        month = GetClockMonth(),      -- 0-11
        year = GetClockYear(),
        weekday = GetClockDayOfWeek() -- 0 = Sunday
    }
end

-- Location -------------------------------------------------------------------------

local COMPASS = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' }

local function heading()
    -- GTA headings run counter-clockwise from north; convert to a compass bearing.
    local bearing = (360.0 - GetEntityHeading(PlayerPedId())) % 360.0
    return COMPASS[math.floor((bearing + 22.5) / 45.0) % 8 + 1]
end

local function location()
    local coords = GetEntityCoords(PlayerPedId())
    updatePostal(coords)
    local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local cross = crossHash ~= 0 and GetStreetNameFromHashKey(crossHash) or ''
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    if zone == 'NULL' then zone = '' end

    return { dir = heading(), street = street, cross = cross, zone = zone }
end

-- Postals ---------------------------------------------------------------------------

---@type { code: string, x: number, y: number }[]
local postals = {}
local postalFrom          -- position the nearest postal was last computed at
local route               -- postal we set a waypoint to

local function loadPostals()
    local cfg = HudConfig.Postals
    if not cfg or not cfg.Enabled then return end

    local raw = LoadResourceFile(GetCurrentResourceName(), cfg.File)
    if not raw then
        TFC.Log.Warn('no postal file at %s; postal display is off', cfg.File)
        return
    end

    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        TFC.Log.Error('could not read %s: not valid JSON', cfg.File)
        return
    end

    for _, p in ipairs(data) do
        if p.code and tonumber(p.x) and tonumber(p.y) then
            postals[#postals + 1] = { code = tostring(p.code), x = tonumber(p.x), y = tonumber(p.y) }
        end
    end
    TFC.Log.Info('loaded %d postals', #postals)
end

---@return { code: string, x: number, y: number }|nil, number
local function nearestPostal(x, y)
    local best, bestDist = nil, math.huge
    for i = 1, #postals do
        local p = postals[i]
        local dx, dy = p.x - x, p.y - y
        local d = dx * dx + dy * dy
        if d < bestDist then best, bestDist = p, d end
    end
    return best, math.sqrt(bestDist)
end

updatePostal = function(coords)
    if #postals == 0 then return end

    -- Only search again after moving 5 m.
    if postalFrom then
        local dx, dy = coords.x - postalFrom.x, coords.y - postalFrom.y
        if dx * dx + dy * dy < 25.0 then return end
    end
    postalFrom = { x = coords.x, y = coords.y }

    local p = nearestPostal(coords.x, coords.y)
    send('postal', p and p.code or false)

    if route then
        local dx, dy = route.x - coords.x, route.y - coords.y
        if dx * dx + dy * dy < HudConfig.Postals.ArriveDistance ^ 2 then
            SetWaypointOff()
            TFC.UI.Notify({ title = 'Postal ' .. route.code, description = 'You have arrived', type = 'success' })
            route = nil
        end
    end
end

local function findPostal(code)
    code = tostring(code):lower()
    for _, p in ipairs(postals) do
        if p.code:lower() == code then return p end
    end
    return nil
end

if HudConfig.Postals and HudConfig.Postals.Enabled and HudConfig.Postals.Command then
    RegisterCommand(HudConfig.Postals.Command, function(_, args)
        if not args[1] then
            if IsWaypointActive() then SetWaypointOff() end
            route = nil
            TFC.UI.Notify({ title = 'Postal', description = 'Route cleared', type = 'inform' })
            return
        end

        local p = findPostal(args[1])
        if not p then
            TFC.UI.Notify({ title = 'Postal', description = ('Postal %s does not exist'):format(args[1]), type = 'error' })
            return
        end

        SetNewWaypoint(p.x, p.y)
        route = p
        TFC.UI.Notify({ title = 'Postal ' .. p.code, description = 'Waypoint set', type = 'success' })
    end, false)
end

-- Visibility -------------------------------------------------------------------------

local function shouldShow()
    return enabled and TFC.PlayerData ~= nil and not IsPauseMenuActive() and not IsScreenFadedOut()
end

local function setVisible(show)
    if visible == show then return end
    visible = show
    SendNUIMessage({ action = 'visible', value = show })
end

-- Money ----------------------------------------------------------------------------

local function sendMoney(balances)
    if not balances then return end
    if balances.cash then send('cash', balances.cash) end
    if balances.bank then send('bank', balances.bank) end
    if HudConfig.ShowCredit and balances.credit then send('credit', balances.credit) end
end

TFC.OnNet('tfc-accounts:client:sync', function(all)
    sendMoney(all)
end)

TFC.On('moneyChanged', function(account, balance, delta)
    if account ~= 'cash' and account ~= 'bank' and not (account == 'credit' and HudConfig.ShowCredit) then return end
    last[account] = balance
    SendNUIMessage({ action = 'money', account = account, value = balance, delta = delta })
end)

-- Job ------------------------------------------------------------------------------
-- Expected shape (set by tfc-jobs): { label = 'Police', gradeLabel = 'Sergeant', onDuty = true }

local function sendJob(job)
    if type(job) ~= 'table' or not job.label then
        sendTable('job', { label = HudConfig.NoJobLabel })
    else
        sendTable('job', { label = job.label, grade = job.gradeLabel, onDuty = job.onDuty })
    end
end

AddStateBagChangeHandler('tfc:job', nil, function(bagName, _, value)
    if bagName ~= ('player:%d'):format(GetPlayerServerId(PlayerId())) then return end
    sendJob(value)
end)

-- Who's on (staff online, LEO / EMS on duty), counted by server.lua ---------------------

local countsOn = HudConfig.Counts and HudConfig.Counts.Enabled

local function sendCounts(list)
    if not countsOn then return end
    SendNUIMessage({ action = 'set', field = 'counts', value = type(list) == 'table' and list or {} })
end

if countsOn then
    AddStateBagChangeHandler('tfc:counts', 'global', function(_, _, value)
        sendCounts(value)
    end)
end

-- AOP and priority (tfc-world publishes GlobalState['tfc:aop']) --------------------------

local function sendAop(value)
    SendNUIMessage({ action = 'set', field = 'aop', value = type(value) == 'table' and value or false })
end

AddStateBagChangeHandler('tfc:aop', 'global', function(_, _, value)
    sendAop(value)
end)

-- Notifications (every TFC resource sends theirs here; shown top centre) -------------------

AddEventHandler('tfc-hud:client:notify', function(data)
    if type(data) ~= 'table' then return end
    SendNUIMessage({ action = 'notify', data = {
        title = data.title, description = data.description, type = data.type, duration = data.duration,
    } })
end)

-- Lifecycle --------------------------------------------------------------------------

local function addSuggestions()
    if HudConfig.ToggleCommand then
        TriggerEvent('chat:addSuggestion', '/' .. HudConfig.ToggleCommand, 'Show or hide the HUD')
    end
    if #postals > 0 and HudConfig.Postals.Command then
        TriggerEvent('chat:addSuggestion', '/' .. HudConfig.Postals.Command, 'Set a waypoint to a postal (no code clears it)',
            { { name = 'code (optional)', help = 'Postal code, e.g. 101' } })
    end
end

TFC.OnPlayerLoaded(function()
    last = {}
    postalFrom = nil
    addSuggestions()
    SendNUIMessage({
        action = 'init',
        config = {
            timeSource = HudConfig.TimeSource,
            use24Hour = HudConfig.Use24Hour,
            showLocation = HudConfig.ShowLocation,
            showPostal = #postals > 0,
        },
        anchor = minimapAnchor(),
    })

    if GetResourceState('tfc-accounts') == 'started' then
        sendMoney(exports['tfc-accounts']:GetBalances())
    end
    sendJob(LocalPlayer.state['tfc:job'])
    sendCounts(GlobalState['tfc:counts'])
    sendAop(GlobalState['tfc:aop'])
end)

TFC.OnPlayerUnloaded(function()
    setVisible(false)
end)

loadPostals()

CreateThread(function()
    local anchorCheck = 0
    while true do
        Wait(HudConfig.TickMs)

        local show = shouldShow()
        setVisible(show)

        if show then
            if HudConfig.TimeSource == 'game' then
                sendTable('time', gameTime())
            end
            if HudConfig.ShowLocation then
                sendTable('location', location())
            end

            -- Resolution or safezone can change in settings: re-check every ~5 s.
            anchorCheck = anchorCheck + HudConfig.TickMs
            if anchorCheck >= 5000 then
                anchorCheck = 0
                sendTable('anchor', minimapAnchor())
            end
        end
    end
end)

if HudConfig.ToggleCommand then
    RegisterCommand(HudConfig.ToggleCommand, function()
        enabled = not enabled
        TFC.UI.Notify({ description = enabled and 'HUD shown' or 'HUD hidden', type = 'inform' })
    end, false)
end
