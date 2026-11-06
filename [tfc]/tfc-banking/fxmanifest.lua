fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-banking'
author 'Andrew'
description 'The Final Core - banks, ATMs, transfers, bills, credit and department accounts'
version '0.1.0'

dependencies {
    'oxmysql',
    'tfc-core',
    'tfc-accounts',
}

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/billing.lua',
}

client_script 'client.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
