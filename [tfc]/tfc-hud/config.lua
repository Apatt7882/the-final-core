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

    ---Chat command that toggles the HUD for this player. Set to false to disable.
    ToggleCommand = 'hud',

    ---How often (ms) to check time and location. Updates are only sent when something changes.
    TickMs = 250,
}
