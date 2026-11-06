fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-hud'
author 'Andrew'
description 'The Final Core - HUD: date/time, money, job, location, AOP, priority, counts and notifications'
version '0.4.0'

dependency 'tfc-core'

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}
server_script 'server.lua'
client_script 'client.lua'

ui_page 'html/index.html'

files {
    'data/*.json',
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
