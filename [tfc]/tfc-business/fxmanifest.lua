fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-business'
author 'Andrew'
description 'The Final Core - player-owned stores: owners, staff, sales split, stock and savings'
version '0.1.0'

dependencies {
    'oxmysql',
    'tfc-core',
    'tfc-jobs',
    'tfc-shops',
    'tfc-banking',
    'tfc-accounts',
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

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
