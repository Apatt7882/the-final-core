fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-core'
author 'Andrew'
description 'The Final Core - a modular, performance-first roleplay framework'
version '0.5.3'

dependency 'oxmysql'

shared_scripts {
    'shared/init.lua',
    'shared/config.lua',
    'shared/lib/log.lua',
    'shared/lib/events.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/lib/callback.lua',
    'server/lib/ui.lua',
    'server/lib/permissions.lua',
    'server/lib/commands.lua',
    'server/adapter.lua',
    'server/db/schema.lua',
    'server/db/users.lua',
    'server/db/characters.lua',
    'server/modules.lua',
    'server/player/class.lua',
    'server/player/manager.lua',
    'server/player/lifecycle.lua',
    'server/main.lua',
}

client_scripts {
    'client/lib/callback.lua',
    'client/lib/player.lua',
    'client/lib/ui.lua',
    'client/adapter.lua',
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
    'client/lib/player.lua',
    'client/lib/ui.lua',
}
