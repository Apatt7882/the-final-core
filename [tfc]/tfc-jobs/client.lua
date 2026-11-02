-- Client side: the job lives in the public 'tfc:job' state bag set by the server.
-- Client exports: GetJob(), IsOnDuty()
-- Client hook: jobChanged(job) whenever the local player's job, rank or duty changes.

local function mine(bagName)
    return bagName == ('player:%d'):format(GetPlayerServerId(PlayerId()))
end

AddStateBagChangeHandler('tfc:job', nil, function(bagName, _, value)
    if not mine(bagName) then return end
    TFC.Emit('jobChanged', value)
end)

exports('GetJob', function()
    return LocalPlayer.state['tfc:job']
end)

exports('IsOnDuty', function()
    local job = LocalPlayer.state['tfc:job']
    return job ~= nil and job.onDuty == true
end)
