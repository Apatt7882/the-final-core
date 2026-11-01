fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-multichar'
author 'Andrew'
description 'The Final Core - character select and creation'
version '0.1.0'

dependency 'tfc-core'

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}
server_script 'server.lua'
client_script 'client.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
