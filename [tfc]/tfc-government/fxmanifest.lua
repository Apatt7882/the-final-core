fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-government'
author 'Andrew'
description 'The Final Core - Government Center, DMV and licenses'
version '0.1.0'

dependencies {
    'oxmysql',
    'tfc-core',
    'tfc-accounts',
    'tfc-inventory',
    'tfc-jobs',
}

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'quizzes.lua',          -- server only: the answers never reach players
    'server/licenses.lua',
    'server/cityhall.lua',
}

client_script 'client.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
