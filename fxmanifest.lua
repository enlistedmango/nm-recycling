fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author "NM Recycling"
description "Recycling Script with Custom UI"
version '1.0.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config/shared.lua'
}

server_scripts {
  'server/**/*'
}

client_scripts {
  'client/**/*',
}

-- ui_page 'http://localhost:3000/' -- (for local dev)
ui_page 'web/build/index.html'

files {
  'web/build/index.html',
  'web/build/**/*',
  'config/*.lua'
}

dependencies {
  'qbx_core',
  'ox_lib',
  'ox_inventory',
  'ox_target'
}
