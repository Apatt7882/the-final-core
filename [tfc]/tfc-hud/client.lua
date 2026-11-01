-- HUD client: gathers data and sends only what changed to the NUI page.
-- Money comes from tfc-accounts, job from the 'tfc:job' state bag (set by tfc-jobs),
-- time and location from the game.

local enabled = true   -- player's /hud toggle
local visible = false  -- what the page currently shows
local last = {}        -- last value sent for each field

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
    local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local cross = crossHash ~= 0 and GetStreetNameFromHashKey(crossHash) or ''
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    if zone == 'NULL' then zone = '' end

    return { dir = heading(), street = street, cross = cross, zone = zone }
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

-- Lifecycle --------------------------------------------------------------------------

TFC.OnPlayerLoaded(function()
    last = {}
    SendNUIMessage({
        action = 'init',
        config = {
            timeSource = HudConfig.TimeSource,
            use24Hour = HudConfig.Use24Hour,
            showLocation = HudConfig.ShowLocation,
        },
        anchor = minimapAnchor(),
    })

    if GetResourceState('tfc-accounts') == 'started' then
        sendMoney(exports['tfc-accounts']:GetBalances())
    end
    sendJob(LocalPlayer.state['tfc:job'])
end)

TFC.OnPlayerUnloaded(function()
    setVisible(false)
end)

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
