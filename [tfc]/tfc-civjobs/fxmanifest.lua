fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-civjobs'
author 'Andrew'
description 'The Final Core - civilian jobs: clerk, garbage, delivery, mechanic calls, taxi fares'
version '0.2.0'

dependencies {
    'tfc-core',
    'tfc-jobs',
    'tfc-shops',
    'tfc-accounts',
}

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}

server_scripts {
    'server.lua',
    'server/clerk.lua',
    'server/routes.lua',
    'server/calls.lua',
    'server/start.lua',
}

client_scripts {
    'client.lua',
    'client/clerk.lua',
    'client/routes.lua',
    'client/calls.lua',
}
