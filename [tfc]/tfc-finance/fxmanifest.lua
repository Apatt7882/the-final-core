fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tfc-finance'
author 'Andrew'
description 'The Final Core - stock market and the City Accountant'
version '0.1.1'

dependencies {
    'oxmysql',
    'tfc-core',
    'tfc-accounts',
    'tfc-banking',
}

shared_scripts {
    '@tfc-core/import.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/market.lua',
    'server/advisor.lua',
}

client_script 'client.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
