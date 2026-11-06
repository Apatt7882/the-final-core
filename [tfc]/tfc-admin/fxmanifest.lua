fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-admin'
author 'Andrew'
description 'The Final Core - admin menu, noclip, spectate, teleports and item browser'
version '0.2.0'

dependencies {
    'tfc-core',
}

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}

server_script 'server.lua'

client_scripts {
    'client.lua',
    'client/noclip.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
