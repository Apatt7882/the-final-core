-- HUD server: counts who's on (staff online, services on duty) for the HUD's "who's on" box.
-- Published to every client as GlobalState['tfc:counts'] = { { key, label, icon, count }, ... }

local Cfg = HudConfig.Counts
if not Cfg or not Cfg.Enabled then return end

local function isStaff(src)
    for _, perm in ipairs(Cfg.Staff) do
        if IsPlayerAceAllowed(tostring(src), perm) then return true end
    end
    return false
end

local function count()
    local list = {}

    local staff = 0
    for _, id in ipairs(GetPlayers()) do
        if isStaff(id) then staff = staff + 1 end
    end
    list[1] = { key = 'staff', label = 'Staff', icon = 'staff', count = staff }

    local jobs = GetResourceState('tfc-jobs') == 'started' and exports['tfc-jobs'] or nil
    for _, g in ipairs(Cfg.Groups) do
        local n = 0
        if jobs then
            for _, job in ipairs(g.jobs) do
                n = n + #(jobs:GetPlayersWithJob(job, true) or {})
            end
        end
        list[#list + 1] = { key = g.key, label = g.label, icon = g.icon or g.key, count = n }
    end
    return list
end

local last = nil

CreateThread(function()
    while true do
        local ok, list = pcall(count)
        if ok then
            local encoded = json.encode(list)
            if encoded ~= last then
                last = encoded
                GlobalState:set('tfc:counts', list, true)
            end
        else
            TFC.Log.Error('could not count players: %s', tostring(list))
        end
        Wait(Cfg.Interval * 1000)
    end
end)
