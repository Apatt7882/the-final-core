HudConfig = {
    ---'game' = in-game clock and date; 'real' = the player's real local date and time.
    TimeSource = 'game',
    Use24Hour = true,

    ---Show the credit balance under bank (only when it's below zero).
    ShowCredit = true,

    ---Shown when the character has no job (tfc-jobs sets the 'tfc:job' state bag).
    NoJobLabel = 'Unemployed',

    ---Show the street/area display next to the minimap.
    ShowLocation = true,

    ---Nearest postal, shown in the location box. Uses the same JSON format as the
    ---nearest-postal resource and postal map packs: [{ "code": "101", "x": 0.0, "y": 0.0 }, ...]
    ---Copy your map's postal file to tfc-hud/data/postals.json. Missing file = postal hidden.
    Postals = {
        Enabled = true,
        File = 'data/postals.json',
        ---/postal <code> sets a waypoint; /postal on its own clears it. false to disable.
        Command = 'postal',
        ---The waypoint clears itself within this many metres of the postal.
        ArriveDistance = 50.0,
    },

    ---Chat command that toggles the HUD for this player. Set to false to disable.
    ToggleCommand = 'hud',

    ---How often (ms) to check time and location. Updates are only sent when something changes.
    TickMs = 250,
}
