fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-inventory'
author 'Andrew'
description 'The Final Core - slot and weight inventory'
version '0.2.0'

dependencies {
    'oxmysql',
    'tfc-core',
}

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
    'items.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/engine.lua',
    'server/main.lua',
    'server/containers.lua',
}

client_script 'client.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/images/*.png',
}
