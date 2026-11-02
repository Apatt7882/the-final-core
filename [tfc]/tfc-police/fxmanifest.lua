fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-police'
author 'Andrew'
description 'The Final Core - cuffs, escort, vehicles, search, fines and jail'
version '0.1.0'

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
}

client_script 'client.lua'
