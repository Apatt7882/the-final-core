# The Final Core

A modular, performance-first roleplay framework for FiveM, written in Lua 5.4.

- **`tfc-core`** stays small and self-contained: logging, hooks, net events, callbacks, module loader, config.
- **Modules** (`tfc-multichar`, `tfc-accounts`, `tfc-jobs`, `tfc-inventory`, ...) are optional resources that register with the core.
- Modules may use **ox_lib v3.41.0**, always through TFC wrappers so it can be swapped later.

Status: **phase 3 (character select)**. Phases 1 (foundation) and 2 (players and data) are done. See the design doc for the full plan.

## Layout

```
[tfc]/
  tfc-core/
    fxmanifest.lua
    import.lua        -- other resources include this to get a TFC object
    shared/           -- TFC global, config, log, event bus
    server/
      adapter.lua     -- every GTA-specific server call (identifiers, peds, state bags)
      db/             -- schema runner, users, characters
      player/         -- player object, save queue, connect/load/drop lifecycle
      lib/            -- callbacks + player proxies for other resources
    client/           -- client callbacks, player data, adapter, spawn placement
    sql/schema.sql    -- tables; created automatically on start
    types/            -- LuaLS type definitions (not loaded at runtime)
  tfc-multichar/       -- character select + creation (custom NUI in html/)
  tfc-example/        -- template module: copy it to start a new one
```

## Install on the dev server

1. Upload the `[tfc]` folder into the server's `resources` folder.
2. Add to `server.cfg`, after your base resources:

   ```cfg
   setr tfc_debug 1
   ensure oxmysql
   ensure tfc-core
   ensure tfc-multichar
   ensure tfc-example

   add_ace group.admin command.tfc allow
   ```

3. Restart the server. The `tfc_users`, `tfc_user_identifiers` and `tfc_characters` tables are created automatically.

## Check that phase 3 works

Preview the screen in any browser by opening `tfc-multichar/html/index.html` (it shows sample data).

| Where | Do | Expect |
| --- | --- | --- |
| Server console | Start the server | `The Final Core v0.3.0 starting`, `module multichar v0.1.0 ready` |
| Join | Connect | Camera over the city with the character list; Dev Tester is there from phase 2 |
| Select screen | Play Dev Tester | Fade, then you spawn where you last saved |
| In game | `/logout` | Back to the select screen |
| Select screen | New character, fill the form, Create | New card appears and is selected |
| Select screen | Try a date of birth under 18 | Error message, nothing created |
| Select screen | Play the new character | Spawns at the airport (no saved position yet), as a female/male freemode ped |
| Select screen | Delete a character, type its name | Deleted; the Delete button stays disabled until the name matches |
| Reconnect | Quit and rejoin | Select screen again; both characters keep their own position and data |

With `tfc-multichar` running, `Config.AutoLoadCharacter` is ignored automatically.
The select camera is set in `tfc-multichar/config.lua` (`Scene`) if you want a different view.

## Writing a module

```lua
-- fxmanifest.lua
dependency 'tfc-core'
shared_script '@tfc-core/import.lua'
```

```lua
-- server.lua
TFC.RegisterModule({ name = 'mymodule', version = '0.1.0', dependencies = { accounts = '>=0.1.0' } }, function()
    TFC.Log.Info('ready')
end)

TFC.Callback.Register('mymodule:getThing', function(source, id)
    return { id = id }
end, { rateLimit = 500 })
```

```lua
-- client.lua
local thing = TFC.Callback.Await('mymodule:getThing', 42)
```

`Await` and `AwaitClient` yield, so call them from a command, event handler or `CreateThread`.

## API (phase 1)

| Call | Side | Purpose |
| --- | --- | --- |
| `TFC.Log.Debug/Info/Warn/Error(msg, ...)` | both | Prefixed logs; Debug needs `setr tfc_debug 1` |
| `TFC.On(name, fn)` / `TFC.Off(handle)` / `TFC.Emit(name, ...)` | both | Hooks between resources on the same side |
| `TFC.OnNet(event, fn, { rateLimit })` | both | Net events; server side validates the source and rate limits |
| `TFC.Callback.Register(name, fn, opts)` | both | Answer callback requests |
| `TFC.Callback.Await(name, ...)` | client | Ask the server |
| `TFC.Callback.AwaitClient(src, name, ...)` | server | Ask one client |
| `TFC.RegisterModule(def, onReady)` | server | Register a module |
| `exports['tfc-core']:GetModule(name)` / `GetModules()` / `IsModuleReady(name)` / `GetVersion()` | server | Module registry |

### Players (phase 2)

| Call | Side | Purpose |
| --- | --- | --- |
| `TFC.GetPlayer(src)` / `TFC.GetPlayerByCid(cid)` / `TFC.GetPlayers()` | server | Player object (proxy outside the core) / sources of loaded players |
| `player:GetCid()`, `GetFullName()`, `GetSlot()`, `GetDob()`, `GetSex()`, `GetUserId()` | server | Character info |
| `player:GetMetadata(key)` / `player:SetMetadata(key, value)` | server | Private, saved data; synced to the owning client |
| `player:GetState(key)` / `player:SetState(key, value)` | server | Public, unsaved state bag `tfc:<key>` every client can read |
| `player:GetPosition()` / `player:Save()` | server | Live position / save now |
| `exports['tfc-core']:GetCharacters(src)` / `CreateCharacter(src, data)` / `LoadCharacter(src, id)` / `UnloadCharacter(src)` | server | Character API for tfc-multichar |
| `TFC.PlayerData`, `TFC.OnPlayerLoaded(fn)`, `TFC.OnPlayerUnloaded(fn)`, `TFC.OnMetadataChanged(fn)` | client | Local player data |

State bags on every loaded player: `tfc:loaded`, `tfc:cid`, `tfc:name`.

Core hooks (server, `TFC.On`): `moduleReady(name, resource)`, `moduleStopped(name, resource)`, `databaseReady()`,
`characterSelect(source, userId)`, `playerLoaded(source, cid)`, `playerUnloaded(source, cid)`,
`metadataChanged(source, key, value, old)`.

Phase 3 adds: `exports['tfc-core']:DeleteCharacter(src, id)` and `GetConfig(key)`, the server hook
`characterDeleted(source, cid)`, and the client hook `playerSpawned(data)` (fires once the character is placed).

Saving: changed characters are saved in one transaction every `Config.SaveInterval` seconds (default 300),
and always on character switch, disconnect, and txAdmin shutdown.

## Editor setup

Use VS Code with the **Lua** extension (LuaLS) and **CfxLua IntelliSense** for FiveM natives.
`.luarc.json` and `types/` give autocomplete for the whole `TFC` API.

## License

Private, all rights reserved, until a license is chosen before any public release.
