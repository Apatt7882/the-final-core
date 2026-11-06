fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-world'
author 'Andrew'
description 'The Final Core - synced time and weather, blackout and holiday snow'
version '0.3.0'

dependency 'tfc-core'

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}

server_script 'server.lua'
client_script 'client.lua'
