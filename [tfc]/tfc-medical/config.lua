-- Death and EMS. When a player is "killed" they go down instead: EMS (or an admin) can revive
-- them, or after the bleed-out timer they can respawn at the nearest hospital for a fee.

MedicalConfig = {
    -- Respawning at the hospital while down (seconds since going down):
    --   EMS on duty:     early respawn for `earlyFee` after `earlySeconds`, free after `freeSeconds`
    --   no EMS on duty:  free after `noEmsSeconds`
    -- "On duty" is checked live, so if EMS clock in or out while you're down the rules follow.
    Respawn = {
        earlySeconds = 150,
        earlyFee = 1000,
        freeSeconds = 300,
        noEmsSeconds = 60,
    },
    RespawnFeeFrom = { 'bank', 'credit' },  -- early bill: bank first, then credit
    -- Disconnecting while down puts you down again (timer restarts) when you come back.
    StayDownOnReconnect = true,

    EmsJobs = { 'ambulance' },      -- jobs that can revive and heal (on duty)
    ReviveDistance = 3.0,
    ReviveSeconds = 8,              -- CPR time
    HealSeconds = 5,
    ReviveHealth = 150,             -- health after an EMS revive (GTA: 100 = dead, 200 = full)

    DistressCooldown = 60,          -- seconds between [G] calls for EMS
    DistressBlipSeconds = 120,

    Hospitals = {
        { label = 'Pillbox Hill Medical', coords = vector4(298.6, -584.6, 43.26, 70.0) },
        { label = 'Sandy Shores Medical', coords = vector4(1839.4, 3672.9, 34.28, 210.0) },
        { label = 'Paleto Bay Medical', coords = vector4(-247.8, 6331.2, 32.43, 225.0) },
    },
}

---What a downed player can do right now. Shared by server (decides) and client (shows).
---@param elapsed integer seconds since going down
---@param ems integer EMS on duty
---@return { now: boolean, fee: integer, paidIn: integer|nil, freeIn: integer|nil, total: integer }
function MedicalConfig.RespawnOption(elapsed, ems)
    local R = MedicalConfig.Respawn
    if ems == 0 then
        local left = R.noEmsSeconds - elapsed
        return { now = left <= 0, fee = 0, freeIn = left > 0 and left or nil, total = R.noEmsSeconds }
    end
    if elapsed >= R.freeSeconds then
        return { now = true, fee = 0, total = R.freeSeconds }
    end
    if elapsed >= R.earlySeconds then
        return { now = true, fee = R.earlyFee, freeIn = R.freeSeconds - elapsed, total = R.freeSeconds }
    end
    return { now = false, fee = R.earlyFee, paidIn = R.earlySeconds - elapsed, freeIn = R.freeSeconds - elapsed, total = R.freeSeconds }
end
