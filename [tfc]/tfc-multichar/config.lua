MulticharConfig = {
    ---Background scene while choosing a character: a camera looking at a point.
    ---The hidden, frozen player is parked at `lookAt` so the area streams in.
    Scene = {
        camera = { x = -75.0, y = -830.0, z = 340.0 },
        lookAt = { x = 215.5, y = -810.2, z = 30.7 },
        fov = 50.0,
    },

    ---Default ped models until tfc-appearance exists.
    Models = {
        m = 'mp_m_freemode_01',
        f = 'mp_f_freemode_01',
    },

    ---Players must be at least this old in-character (based on date of birth).
    MinAge = 18,

    ---Chat command that returns a loaded player to character select. Set to false to disable.
    LogoutCommand = 'logout',
}
