fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-example'
author 'Andrew'
description 'Template module for The Final Core - copy this to start a new module'
version '0.1.0'

dependency 'tfc-core'

shared_script '@tfc-core/import.lua'
server_script 'server.lua'
client_script 'client.lua'
