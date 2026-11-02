# The Final Core

A modular, performance-first roleplay framework for FiveM, written in Lua 5.4.

- **`tfc-core`** stays small and self-contained: logging, hooks, net events, callbacks, module loader, config.
- **Modules** (`tfc-multichar`, `tfc-accounts`, `tfc-jobs`, `tfc-inventory`, ...) are optional resources that register with the core.
- Modules may use **ox_lib v3.41.0**, always through TFC wrappers so it can be swapped later.

Status: **phase 4a (accounts)**. Phases 1-3 (foundation, players and data, character select) are done. See the design doc for the full plan.

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
  tfc-multichar/      -- character select + creation (custom NUI in html/)
  tfc-accounts/       -- cash, bank and credit; transaction log
  tfc-hud/            -- date/time, money, job and location HUD (NUI)
  tfc-example/        -- template module: copy it to start a new one
```

## Install on the dev server

1. Upload the `[tfc]` folder into the server's `resources` folder.
2. Add to `server.cfg`, after your base resources:

   ```cfg
   setr tfc_debug 1
   ensure oxmysql
   ensure ox_lib          # optional: nicer notifications; falls back to the GTA feed
   ensure tfc-core
   ensure tfc-multichar
   ensure tfc-accounts
   ensure tfc-hud
   ensure tfc-example

   add_ace group.admin command.tfc allow
   add_ace group.admin command.givemoney allow
   add_ace group.admin command.takemoney allow
   add_ace group.admin command.setmoney allow
   ```

3. Restart the server. The `tfc_users`, `tfc_user_identifiers` and `tfc_characters` tables are created automatically.

## Check that phase 4a works

| Where | Do | Expect |
| --- | --- | --- |
| Server console | Start the server | `The Final Core v0.4.0 starting`, `module accounts v0.1.0 ready` |
| In game | Load any character, then `/money` | Notification: Cash $500, Bank $5,000, Credit $0 (new characters) |
| Server console | `givemoney <your id> cash 250` | `<you> cash: now $750`, and an in-game notification |
| Server console | `takemoney <your id> cash 99999` | `failed: not enough cash` |
| Server console | `takemoney <your id> credit 2000` | Credit now -$2,000 |
| In game | `/repaycredit` | Bank -$2,000, credit back to $0 |
| Reconnect | Rejoin the same character | `/money` shows the same balances |
| Database | `tfc_transactions` | One row per change with amount, balance after and reason |

**HUD** (open `tfc-hud/html/index.html` in a browser to preview it):

| Where | Do | Expect |
| --- | --- | --- |
| In game | Load a character | Time/date, cash, bank and "Unemployed" top right; street and area beside the minimap |
| Server console | `givemoney <your id> cash 250` | Cash flashes green with "+$250" beside it |
| In game | Drive around | Compass, street and area update as you move |
| In game | Open the pause menu, then `/hud` | HUD hides in the menu; `/hud` toggles it |
| Server console | `takemoney <your id> credit 500` | A red credit row appears (only shown while you owe) |

**Postals:** copy your postal map's JSON (e.g. `new-postals.json` from nearest-postal or your postal map pack) to
`tfc-hud/data/postals.json`. The HUD then shows the nearest postal beside the compass, and `/postal 123` sets a
waypoint (`/postal` alone clears it; it also clears when you arrive). If you were running the nearest-postal resource,
stop it so its own text doesn't appear twice.

**Commands:** start typing `/givemoney`, `/takemoney` or `/setmoney` in chat to see the parameters. Admin commands are
only suggested to players with the ACE permission. Use `me` as the ID for yourself, and add an optional reason at the end:
`/givemoney me cash 500 event prize`.

Settings (`tfc-hud/config.lua`): in-game vs real time, 12/24 hour, credit row, location on/off, toggle command.
The job line reads the `tfc:job` state bag that `tfc-jobs` (phase 4b) will set:
`{ label = 'Police', gradeLabel = 'Sergeant', onDuty = true }`.

Phase 3 checks (character select) still apply: see the git history of this file.

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

### Accounts (phase 4a, `exports['tfc-accounts']`, server)

| Call | Returns | Notes |
| --- | --- | --- |
| `GetBalance(src, account)` / `GetBalances(src)` | number / table | `cash`, `bank`, `credit` |
| `AddMoney(src, account, amount, reason)` / `RemoveMoney(...)` | ok, newBalanceOrError | Whole dollars only; never passes the account's min/max |
| `Charge(src, amount, reason, order?)` | ok, accountUsedOrError | Tries `cash`, `bank`, `credit` in order (configurable) |
| `Transfer(src, from, to, amount, reason)` | ok, newBalanceOrError | Between the player's own accounts |
| `RepayCredit(src, amount?)` | ok, newBalanceOrError | Bank to credit; omit amount to repay everything |
| `SetBalance(src, account, amount, reason)` | ok, newBalanceOrError | Admin use |
| `RegisterAccount(name, { label, default, min, max })` | ok | Add an account type from another module |

Client: `exports['tfc-accounts']:GetBalance(account)`, `GetBalances()`, hook `moneyChanged(account, balance, delta, reason)`.
Server hook: `moneyChanged(source, account, balance, delta, reason)`.
Money changes are written to the database immediately (not batched), one atomic UPDATE each.

Commands: `TFC.RegisterCommand(name, { help, params, restricted }, handler)` (server) registers a command with chat
suggestions (only shown to players allowed to use it) and an automatic usage message when arguments are missing.
`TFC.ResolveTarget(src, arg)` turns `"me"` or an ID into an online player's source.

UI: `TFC.UI.Notify(data)` on the client, `TFC.UI.Notify(src, data)` on the server. Uses ox_lib if it's running.

Saving: changed characters are saved in one transaction every `Config.SaveInterval` seconds (default 300),
and always on character switch, disconnect, and txAdmin shutdown.

## Editor setup

Use VS Code with the **Lua** extension (LuaLS) and **CfxLua IntelliSense** for FiveM natives.
`.luarc.json` and `types/` give autocomplete for the whole `TFC` API.

## License

Private, all rights reserved, until a license is chosen before any public release.
