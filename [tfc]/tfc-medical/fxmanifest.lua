fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-medical'
author 'Andrew'
description 'The Final Core - downed state, EMS revive and heal, hospital respawn'
version '0.1.0'

dependencies {
    'tfc-core',
}

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}

server_script 'server.lua'
client_script 'client.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
}
