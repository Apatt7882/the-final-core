# The Final Core

A modular, performance-first roleplay framework for FiveM, written in Lua 5.4.

- **`tfc-core`** stays small and self-contained: logging, hooks, net events, callbacks, module loader, config.
- **Modules** (`tfc-multichar`, `tfc-accounts`, `tfc-jobs`, `tfc-inventory`, ...) are optional resources that register with the core.
- Modules may use **ox_lib v3.41.0**, always through TFC wrappers so it can be swapped later.

Status: **phase 6c (weapons, drugs, item images)**. Phases 1-4 are done; phase 5 (ESX/QB bridges) is on hold. See the design doc for the full plan.

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
  tfc-jobs/           -- jobs, ranks, duty, paychecks, Boss Menu (NUI)
  tfc-inventory/      -- slot + weight inventory, hotbar, usable items, cash item (NUI)
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
   ensure tfc-inventory
   ensure tfc-accounts
   ensure tfc-jobs
   ensure tfc-hud
   ensure tfc-example

   # One line gives admins every TFC admin feature (commands, Boss Menu for all jobs):
   add_ace group.admin tfc.admin allow
   # Make someone an admin (their license is in tfc_users):
   add_principal identifier.license:<license> group.admin
   ```

   The old per-command lines (`command.givemoney`, `command.setjob`, ...) are no longer needed and can be removed.

3. Restart the server. The `tfc_users`, `tfc_user_identifiers` and `tfc_characters` tables are created automatically.

## Check that phase 6c works (weapons, drugs, item images)

Every item now has an image (`tfc-inventory/html/images/`). Food and water are gone; any left in inventories is removed
(with a console warning) the next time that inventory loads.

**Weapons** (28, in `tfc-inventory/items.lua`): melee (knife, switchblade, bat, crowbar, hammer, golf club, knuckles,
nightstick, flashlight), pistols (pistol, combat, SNS, vintage, heavy, .50, revolver, taser), SMGs (micro, machine pistol,
SMG, PDW), rifles (carbine, assault, compact), shotguns (pump, sawed-off), tools (extinguisher, jerry can).
Ammo: `ammo_9mm`, `ammo_45`, `ammo_556`, `ammo_762`, `ammo_12g`.

| Do | Expect |
| --- | --- |
| `/giveitem me pistol` and `/giveitem me ammo_9mm 50` | Pistol with a serial, 0 loaded, 100% condition (hover it) |
| Put the pistol in slot 1, press **1** | You hold it; press 1 again to put it away. Tab weapon wheel and GTA's weapon keys do nothing |
| Press **R** (or pull the trigger when empty) | Reloads 12 rounds from your 9mm stack |
| Fire a few shots, reopen inventory | "Loaded" and "Condition" went down |
| Drop or give the pistol while holding it | It's taken out of your hands |
| `/giveitem me weapon_kit`, use it while holding a worn gun | Condition back to 100% (a gun at 0% is jammed and can't fire) |

**Drugs**: `weed_bag`, `rolling_papers`, `joint`, `coke_bag`, `coke_brick`, `crack_rock`, `meth_bag`, `oxy`, `ecstasy`.

| Item | When used |
| --- | --- |
| Bag of Weed (+ Rolling Papers) | Rolls 2 joints |
| Joint | +10 health, smoking animation, 30 s visual effect |
| Bag of Coke | 30 s sprint boost and visual effect |
| Brick of Coke | Breaks into 20 bags (needs room) |
| Crack Rock | +5 health, 20 s smaller sprint boost |
| Bag of Meth | +25 armor, 45 s visual effect |
| Oxy | +30 health |
| Ecstasy | +10 armor, 60 s visual effect |

Effects, amounts and durations are set per item in `items.lua` (`effect = { heal, armor, sprint, screen, anim }`).

## Check that phase 6b works (drops, trunks, gloveboxes, giving)

F2 opens your inventory plus whatever is around you:

| Where you are | Second panel |
| --- | --- |
| Sitting in a vehicle | Glovebox (5 slots) |
| Standing at the back of a vehicle | Trunk (size by vehicle class; bikes have none) and the trunk opens |
| Anywhere else | Ground |

| Who | Do | Expect |
| --- | --- | --- |
| You | Open on foot, drag water to the Ground panel | A bag appears on the ground |
| Second player | Walk to the bag, F2 | Same ground panel; take the water and the bag disappears once both close |
| You | Drop cash on the ground | HUD cash goes down; `tfc_transactions` shows "moved to Ground" |
| You | Stand at a car's trunk, F2, store items, close, come back | Items are still there (saved by plate) |
| You | Sit in the car, F2 | Glovebox instead of trunk |
| You + second player standing close | Drag an item onto **Give** | They get it; both see a notification |
| You | Walk away with a drop or trunk open, then move an item | "You cannot reach that" |

Drops last 30 minutes untouched (`Drop.lifetime`). Vehicle storage nobody has touched for 7 days is cleared on server
start (`Vehicle.purgeDays`) so random NPC cars don't pile up; that becomes "owned vehicles only" once vehicles have owners.

## Check that phase 6a works (inventory)

Open `tfc-inventory/html/index.html` in a browser to try the drag-and-drop with sample items.

| Where | Do | Expect |
| --- | --- | --- |
| Server console | Start the server | `inventory ready: 9 items`, `module accounts v0.2.0 ready` |
| In game | Load a character, press **F2** | Inventory opens: phone, water, sandwiches and your cash as an item |
| In game | HUD | Cash still shows the same amount; it now *is* the cash item |
| Inventory | Drag items; hold **Shift** (half) or **Ctrl** (one), or type an amount | Moves, splits, stacks and swaps |
| Inventory | Double-click or right-click water | Water used (one fewer) |
| In game | `/giveitem me bandage 5`, press **3** if it's in slot 3 | Hotbar flashes, bandage used, health goes up |
| In game | `/givemoney me cash 100` | Cash item +$100, HUD +$100 |
| Reconnect | Rejoin | Same items in the same slots |

Items are defined in `tfc-inventory/items.lua`; sizes and starting items in `config.lua`. Item images go in
`tfc-inventory/html/images/<item>.png` (items without one show a lettered tile).

**Keys:** F2 opens the inventory and 1-5 use hotbar slots. Both can be rebound in GTA's Settings > Key Bindings > FiveM.
GTA's weapon wheel and weapon keys are turned off (`Weapons.DisableWeaponWheel` in config).

**Cash:** with `CashItem = true` in `tfc-accounts/config.lua`, cash is an inventory item. Existing cash balances move
into each character's inventory the next time they load. Bank and credit are unchanged.

## Check that phase 4c works (permissions + Boss Menu)

Open `tfc-jobs/html/index.html` in a browser to preview the Boss Menu with sample data.

| Who | Do | Expect |
| --- | --- | --- |
| Regular player | `/bossmenu` | "the Boss Menu is for bosses and admins"; admin commands not suggested in chat |
| Admin (not in the job) | `/bossmenu` | Job dropdown with every job; can change anyone's rank and edit ranks; Hire tab hidden; pay read-only |
| Boss (e.g. Chief of Police) | `/bossmenu` | Only their job; Hire tab lists players within 5 m; fire/promote/demote people below their rank; pay editable within the job's range |
| Admin who is a boss | `/bossmenu` | Everything for that job |
| Admin | Ranks tab: rename, toggle Boss, add a rank, remove an empty rank | Changes show on employees' HUDs immediately |
| Anyone | Activity tab | Every hire, fire, rank and pay change with who did it |
| Server console | `resetranks police` | Police ranks restored from `config.lua` |

Ranks now live in the database (`tfc_job_grades`). `config.lua` only seeds a job the first time it's seen;
use `resetranks <job>` to re-apply the file. Pay ranges per job are in `config.lua` (`payRange`).

## Check that phase 4b works (jobs)

Jobs, ranks and pay are in `tfc-jobs/config.lua` (unemployed, police, ambulance, mechanic, taxi to start).

| Where | Do | Expect |
| --- | --- | --- |
| Server console | Start the server | `module jobs v0.1.0 ready`, `jobs ready: 5 jobs, paycheck every 15 min` |
| In game | Load a character | HUD job line: "Unemployed" (no duty dot) |
| In game | `/setjob me police 5` | HUD: "LSPD · Chief of Police" with a grey dot (off duty) |
| In game | `/duty` | Dot turns green; `/duty` again turns it grey |
| In game | Stay on duty 15 minutes | Bank +$850 "Paycheck: LSPD Chief of Police" |
| In game | `/job` | Your job, rank, duty and pay |
| Second player | `/hire <their id> 1`, `/promote`, `/demote`, `/fire` | Works for ranks below yours; refused at or above your rank |
| Reconnect | Rejoin | Same job and rank; duty starts off |

Boss commands work for ranks marked `boss = true` (Captain and Chief for police). Bosses can only hire, promote
up to, or manage people below their own rank.

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
The job line reads the `tfc:job` state bag set by `tfc-jobs`.

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

### Inventory (phase 6a, `exports['tfc-inventory']`, server)

`target` is a player's server ID or an inventory id.

| Call | Returns |
| --- | --- |
| `AddItem(target, name, count, metadata?, slot?, reason?)` / `RemoveItem(...)` | ok, err |
| `GetItemCount(target, name, metadata?)` / `HasItem(target, name, count?)` | number / bool |
| `CanCarry(target, name, count, metadata?)` | ok, err |
| `Search(target, name)` | `{ slot, count, metadata }[]` |
| `SetMetadata(target, slot, metadata)` / `GetInventory(target)` / `ClearInventory(target, keep?)` | |
| `RegisterItem(name, def)` / `GetItems()` | add items from other resources |

Giving a weapon with `AddItem` creates a serial number, 0 rounds loaded and 100% condition automatically.

Server hooks: `itemUsed(source, name, slot)`, `itemCountChanged(source, name, count, delta, reason)`.
Admin: `/giveitem`, `/removeitem`, `/clearinventory`.

### Permissions (phase 4c)

`TFC.HasPermission(src, 'tfc.admin')`, `TFC.IsAdmin(src)` (server, any module), plus `exports['tfc-core']:HasPermission` /
`IsAdmin`. Built-in permission names: `TFC.Permissions.Admin` (`tfc.admin`) and `TFC.Permissions.Mod` (`tfc.mod`).
Commands can require one: `TFC.RegisterCommand(name, { permission = TFC.Permissions.Admin, ... }, fn)`; they are then
only suggested to, and only run for, players who have it. The server console always has every permission.

### Jobs (phase 4b, `exports['tfc-jobs']`, server)

| Call | Returns | Notes |
| --- | --- | --- |
| `GetJob(src)` | `{ name, label, grade, gradeLabel, onDuty, isBoss, pay }` | `onDuty` is nil for jobs without duty |
| `SetJob(src, job, grade)` / `SetJobByCid(cid, job, grade)` | ok, err | `SetJobByCid` works for offline characters |
| `SetDuty(src, bool)` / `ToggleDuty(src)` / `IsOnDuty(src)` | | |
| `HasJob(src, job, minGrade?)` | bool | e.g. `HasJob(src, 'police', 2)` = Sergeant or above |
| `GetPlayersWithJob(job, onDutyOnly?)` | sources | e.g. count on-duty police |

State bag `tfc:job` on every loaded player (public). Server hooks: `jobChanged(source, job, oldJob)`,
`dutyChanged(source, onDuty, job)`. Client: `exports['tfc-jobs']:GetJob()`, `IsOnDuty()`, hook `jobChanged(job)`.

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
