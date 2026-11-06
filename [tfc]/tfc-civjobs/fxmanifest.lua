fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-civjobs'
author 'Andrew'
description 'The Final Core - civilian jobs (convenience store clerk)'
version '0.1.0'

dependencies {
    'tfc-core',
    'tfc-jobs',
    'tfc-shops',
}

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}

server_script 'server.lua'
client_script 'client.lua'
