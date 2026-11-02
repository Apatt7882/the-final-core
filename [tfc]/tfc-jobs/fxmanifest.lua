fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-jobs'
author 'Andrew'
description 'The Final Core - jobs, ranks, duty and paychecks'
version '0.1.0'

dependencies {
    'oxmysql',
    'tfc-core',
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
