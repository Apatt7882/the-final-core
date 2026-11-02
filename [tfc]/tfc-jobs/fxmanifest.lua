fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-jobs'
author 'Andrew'
description 'The Final Core - jobs, ranks, duty, paychecks and the Boss Menu'
version '0.2.1'

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
    'server/ranks.lua',
    'server/stats.lua',
    'server/bossmenu.lua',
    'server/start.lua',
}

client_script 'client.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
