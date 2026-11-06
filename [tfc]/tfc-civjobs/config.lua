-- Civilian jobs. Each job gets something to do even with nobody else online (coming next).
--
-- Convenience Store Clerk (job `clerk` in tfc-jobs/config.lua, public at the Government Center):
-- go to any 24/7 store that is NOT privately owned (tfc-business) and clock in there with
-- F6 > Clock in / out, or /duty. Walk away from the store and you're clocked out.

CivJobsConfig = {
    Clerk = {
        Job = 'clerk',
        ShopTypes = { general = true },  -- tfc-shops types a clerk can work at
        ClockInDistance = 10.0,          -- metres from the store counter to clock in
        LeaveDistance = 60.0,            -- metres from the store before you get clocked out
        LeaveGraceSeconds = 30,          -- how long you can be away before that happens
        HintDistance = 20.0,             -- off-duty clerks get a "clock in here" hint this close
    },
}
