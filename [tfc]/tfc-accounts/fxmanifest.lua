fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-accounts'
author 'Andrew'
description 'The Final Core - cash, bank and credit accounts'
version '0.1.2'

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
