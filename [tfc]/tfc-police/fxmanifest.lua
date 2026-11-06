fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-police'
author 'Andrew'
description 'The Final Core - cuffs, escort, vehicles, search, fines, jail and ShotSpotter'
version '0.2.0'

dependencies {
    'oxmysql',
    'tfc-core',
    'tfc-jobs',
}

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'server/shotspotter.lua',
}

client_scripts {
    'client.lua',
    'client/shotspotter.lua',
}
