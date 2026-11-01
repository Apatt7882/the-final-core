fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-core'
author 'Andrew'
description 'The Final Core - a modular, performance-first roleplay framework'
version '0.1.0'

shared_scripts {
    'shared/init.lua',
    'shared/config.lua',
    'shared/lib/log.lua',
    'shared/lib/events.lua',
}

server_scripts {
    'server/lib/callback.lua',
    'server/modules.lua',
    'server/main.lua',
}

client_scripts {
    'client/lib/callback.lua',
    'client/main.lua',
}

-- Files other resources load through @tfc-core/import.lua.
-- Clients only download what is listed here, so server code never ships to players.
files {
    'import.lua',
    'shared/init.lua',
    'shared/lib/log.lua',
    'shared/lib/events.lua',
    'client/lib/callback.lua',
}
