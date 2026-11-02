-- Admin tools (tfc.admin only). Keys can be rebound in GTA Settings > Key Bindings > FiveM.

AdminConfig = {
    MenuKey = 'F10',        -- admin menu (also /admin)
    NoclipKey = 'F2',       -- noclip on/off (also /noclip)

    Noclip = {
        speeds = { 0.5, 1.5, 4.0, 10.0 },  -- scroll wheel cycles through these
        startSpeed = 2,                     -- index into speeds
        fastMultiplier = 3.0,               -- while holding Shift
        invisible = true,                   -- hidden from other players while flying
    },

    MaxGive = 1000,         -- most of one item per give from the item browser
}
