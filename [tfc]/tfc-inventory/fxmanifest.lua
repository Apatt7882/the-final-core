fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-inventory'
author 'Andrew'
description 'The Final Core - slot and weight inventory'
version '0.3.1'

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
    'server/weapons.lua',
}

client_scripts {
    'client.lua',
    'client/weapons.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/images/*.png',
}
