# The Final Core

A modular, performance-first roleplay framework for FiveM, written in Lua 5.4.

- **`tfc-core`** stays small and self-contained: logging, hooks, net events, callbacks, module loader, config.
- **Modules** (`tfc-multichar`, `tfc-accounts`, `tfc-jobs`, `tfc-inventory`, ...) are optional resources that register with the core.
- Modules may use **ox_lib v3.41.0**, always through TFC wrappers so it can be swapped later.

Status: **phase 8c (job and business accounts)**. Phases 1-4 are done; phase 5 (ESX/QB bridges) is on hold. See the design doc for the full plan.

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
  tfc-hud/            -- date/time, money, job, location and who's-on HUD (NUI)
  tfc-world/          -- synced time and weather, blackout, holiday snow
  tfc-banking/        -- banks, ATMs, transfers, bills, credit, department accounts (NUI)
  tfc-business/       -- player-owned stores: owners, staff, sales split, stock, prices (NUI)
  tfc-jobs/           -- jobs, ranks, duty, paychecks, Boss Menu (NUI)
  tfc-inventory/      -- slot + weight inventory, hotbar, usable items, cash item (NUI)
  tfc-shops/          -- stores, dealers, armories; buy/sell, stock, admin shop manager (NUI)
  tfc-medical/        -- downed state, EMS revive/heal, hospital respawn (NUI overlay)
  tfc-police/         -- cuffs, escort, vehicles, search, fines, jail
  tfc-admin/          -- admin menu, item browser, noclip, spectate, teleports (NUI)
  tfc-example/        -- template module: copy it to start a new one
```

## Install on the dev server

1. Upload the `[tfc]` folder into the server's `resources` folder.
2. Add to `server.cfg`, after your base resources:

   ```cfg
   setr tfc_debug 1
   ensure oxmysql
   ensure ox_lib          # optional: nicer notifications and prompts; falls back to GTA's own
   ensure tfc-core
   ensure tfc-world
   ensure tfc-multichar
   ensure tfc-inventory
   ensure tfc-accounts
   ensure tfc-jobs
   ensure tfc-banking
   ensure tfc-shops
   ensure tfc-business
   ensure tfc-civjobs
   ensure tfc-government
   ensure tfc-finance
   ensure tfc-medical
   ensure tfc-police
   ensure tfc-admin
   ensure tfc-hud
   ensure tfc-example

   # One line gives admins every TFC admin feature (commands, Boss Menu for all jobs):
   add_ace group.admin tfc.admin allow
   # Make someone an admin (their license is in tfc_users):
   add_principal identifier.license:<license> group.admin

   # Optional: real AI answers from the City Accountant (Claude API). Use `set`, NOT `setr`:
   # setr would send your key to every player.
   # set tfc_ai_key "sk-ant-..."
   # set tfc_ai_model "claude-haiku-5-5"
   ```

   The old per-command lines (`command.givemoney`, `command.setjob`, ...) are no longer needed and can be removed.

3. Restart the server. The `tfc_users`, `tfc_user_identifiers` and `tfc_characters` tables are created automatically.

## Keys

| Key | What | Who |
| --- | --- | --- |
| Tab | Inventory | everyone |
| 1-5 | Hotbar | everyone |
| F6 | Job menu (police / EMS actions on the closest player) | on-duty police, EMS |
| F2 | Noclip | admins |
| F10 | Admin menu | admins |

All of them can be rebound in GTA Settings > Key Bindings > FiveM. Inventory and job menu use new binding names, so
anyone who had F2 bound to the old inventory gets Tab automatically.

## Check that update 9a works (civilian jobs)

All of these are public jobs at the Government Center. Every finished task pays a bonus into the bank on top of
the 15-minute paycheck. F6 > **Current task** (or `/task`) says what to do next; F6 > **Cancel task** gives up a
route, call or fare. Everything is in `tfc-civjobs/config.lua`; places marked "(tune)" can be moved with `/coords`.

| Job | How it works | Pays |
| --- | --- | --- |
| **Convenience Store Clerk** | Clock in at the counter of any 24/7 nobody owns (F6 or `/duty`); the store's NPC clerk steps aside. NPC customers walk up: **[E] Ring up** and pass the quick skill check. Now and then: carry 3 boxes from behind the counter to the marked shelves, or mop a spill. Leave the store for 30 s and you're clocked out | 10% of the sale + $5-25 tip (no tip if you fail the check); $40 a box; $35 a spill |
| **LS Sanitation** (garbage) | Clock in at the depot (map), **Take a work vehicle**, **Start a route**. Drive to the area on your map; dumpsters there get marked. Grab a bag at each, throw it in the back of the truck. Two areas, then back to the depot: **Finish route** | $35 a bag, $150 route bonus |
| **GoPostal** (delivery) | Clock in at the depot, take a van, start a route: 4 stores. Park, take a package from the back of the van, carry it to the counter | $60 a package, $150 route bonus |
| **Mechanic** | Go on duty anywhere. Breakdown calls come in every few minutes (GPS): **[E] Repair** it on the spot. With the Hayes Autos flatbed out, some calls are tows: load it, bring it to the yard, **Drop off** | $120 a repair, $250 a tow |
| **Taxi** | Get a cab at Downtown Cab Co. (or any taxi), go on duty, F6 > **Find a fare**. Stop next to the passenger, they get in and say where to go; stop at the marker | $20 + $70 per km, 0-15% tip |

Cheats are checked on the server: you have to be at each spot, with your work vehicle where it should be, and
can't finish a drive faster than about 160 km/h allows.

## Check that weapon mods and ShotSpotter work

**Weapon mods** (`tfc-inventory`, sold at Ammu-Nation): Flashlight $300, Grip $600, Scope $1,200, Extended Magazine
$900 and Suppressor $4,000 (the last two need a Weapon Permit). The Arms Dealer sells magazines and suppressors with
no permit, for more.

| Do | Expect |
| --- | --- |
| Hold a gun, use a mod from the inventory | It's fitted (shows on the gun) and saved on it; the item is used up |
| Mod that doesn't fit, or one it already has | Refused, item kept |
| Extended Magazine | Bigger magazine (Pistol 12 to 16, SMG 30 to 60...) |
| Hover the gun in the inventory | "Mods: Suppressor, Extended Mag" |
| Holding the gun: `/removemods` | Every mod comes off and back into your inventory (extra rounds too) |

Which mod fits which gun (and the GTA component used) is `WeaponMods` at the bottom of `tfc-inventory/items.lua`.

**ShotSpotter** (`tfc-police`): when someone fires a gun (not suppressed, not a taser), on-duty police get an alert
15 seconds later: a red circle near the shots (not the exact spot) for 90 seconds, a notice saying semi-automatic or
fully automatic and the street, and a 25% chance of a camera description, e.g. "Male, wearing a mask and a hat or
helmet, in a black Sultan". `/shotspotter` sets a waypoint to the latest alert. On-duty police shooting and the
Ammu-Nation ranges don't trigger it. Settings: `PoliceConfig.ShotSpotter`.

GTA doesn't tell scripts the colour of clothes, so the camera describes what it can: male or female, mask, hat or
helmet, glasses, bag, shirtless, and the vehicle (model and colour) or "on foot".

## Check that AOP, priority, the wallet, notifications and admin jobs work

**Notifications** from every TFC resource now show at the **top centre** (drawn by `tfc-hud`, even with the HUD
hidden). Without tfc-hud they fall back to ox_lib (top) or GTA's feed.

**AOP and priority** (`tfc-world`, shown on the HUD above Staff/LEO/EMS):

| Do | Expect |
| --- | --- |
| F10 > World > Area of play: type or pick a preset | Everyone's HUD shows the new AOP and gets a notice. Default "Los Santos"; survives restarts |
| F10 > World > Priority: Available / In progress / Cooldown / On hold for City or County | HUD updates for everyone; Cooldown uses the minutes box |
| Anyone: `/cityprio start` (or `/countyprio start`) | Only when that priority is Available |
| Staff or on-duty police: `/cityprio stop` | Cooldown for 20 min (counts down on the HUD, then Available on its own) |
| `/cityprio cooldown 10`, `/cityprio hold`, `/cityprio reset` | Cooldown 10 min, On hold, Available |

Who may use the commands, the cooldown length and the AOP presets are in `tfc-world/config.lua`. The AOP itself is
admin-menu only.

**Wallet** (`tfc-inventory`): 6 slots on the left of the inventory for cash and cards only (cash, ID card, driver's
license, weapon permit, other licenses). New cash and cards go there first; other items can't be put in it. Cards
already in someone's main inventory move to the wallet the next time they log in. Searched players' wallets show
under their inventory and can be taken from. Size: `Player.wallet` in `tfc-inventory/config.lua`.

**Admin: set a job:** F10 > Players > pick a player > Job: choose the job and rank, then **Set**.

## Check that the paycheck, world clock and store clerk fixes work

**Paychecks:** everyone with a loaded character is paid their rank's pay every 15 minutes on the clock
(HH:00/15/30/45 server time), on or off duty, employed or not (Unemployed = $50). The server console prints
`next paycheck at HH:MM` on start and `payroll: N paycheck(s)` each payday. Admins can force one with `/payday`.
To go back to on-duty-only pay, set `PayOnDutyOnly = true` in `tfc-jobs/config.lua`.

**World clock:** clients now get the time straight from the server and re-apply it every frame, so a wrong PC
clock no longer matters. If the time still jumps, type `/worldcheck`: it shows how often something else changed
the clock, the vMenu convars as your game sees them, and any running resource that might set time or weather.

**Convenience Store Clerk** (`tfc-civjobs`, ensure after `tfc-business`):

| Do | Expect |
| --- | --- |
| Government Center > Jobs > Convenience Store Clerk | You're a Clerk (rank 0, $150 a paycheck) |
| Walk into any 24/7 store | Hint: "You can work at 24/7 Store..." (not at privately owned stores) |
| At the counter: F6 > Clock in / out (or `/duty`) | Clocked in at that store; anywhere else it refuses |
| Walk more than 60 m away for 30 s | Warned, then clocked out |
| An admin gives the store an owner while you work | Clocked out |

## Check that the Quality of Life phase works (Government Center, DMV, Accountant)

Ensure `tfc-government` and `tfc-finance` after `tfc-shops` and `tfc-business`. Tables are created automatically.
Locations, peds and prices are in each `config.lua` (use `/coords` to grab new spots).

**Government Center** (City Hall, blip): Welcome steps, public jobs, license guide, services (ID card $50, waypoints,
Accountant), help and rules. Jobs show here when they have `public = true` in `tfc-jobs/config.lua` (taxi, mechanic).

| Do | Expect |
| --- | --- |
| City Hall > Jobs > Sign up | You get grade 0 of that job; police/EMS can't be joined here |
| Services > ID card | $50, a new `id_card` with your name, CID and DOB |
| DMV > Driver's License | $500, no test; card in your pocket lists your classes (C, M, CDL, H) |
| Motorcycle / CDL / HazMat / Weapon / Boat / Pilot | 5-question test, 4 right to pass, then pay ($1,000 for M/CDL/HazMat) |
| Lost a card | Replacement $250 while the license is valid |
| Ammu-Nation guns | Need a valid Weapon Permit (knives and ammo don't) |
| Police on duty: F6 > Check licenses (or `/licenses`) | See the closest player's licenses, suspend or revoke with a reason (card is taken or reprinted) |
| Suspended/revoked player at the DMV | **Request reinstatement**; it can't be bought back |
| Police supervisor (grade 2+): `/licenserequests` | Approve or deny; only supervisors can reinstate |

**City Accountant** (next to City Hall, or the bank's "Investing & advice" button, or `/stocks` to view prices):
advice from your real numbers (bills, credit, cash, paycheck, spending, investing). **Stock market**: 8 companies,
prices move every 5 minutes with news events, 1% trade fee; trade at any bank or the Accountant. With `tfc_ai_key`
set, an **Ask** box sends the question plus the player's numbers to Claude (20 s cooldown, 30 a day per player).

## Check that phase 8c works (job and business accounts)

Ensure `tfc-business` after `tfc-shops` and `tfc-banking`. Tables are created automatically.

**Paychecks** still come from the government for every job, including business staff.

**Department savings (police, EMS, any job):** Boss Menu > **Savings**. Fines, police/EMS bills and early hospital
bills land here. Only the member holding the department's highest occupied rank can deposit or withdraw (if nobody is
Chief, the Captain); admins can view.

**Businesses** (`tfc-business/config.lua`): 24/7 Stores, Ammu-Nation and pawn shops can become businesses.

| Do | Expect |
| --- | --- |
| Admin: `/businesses` | Every ownable store: owner, status, savings; purchase requests at the top |
| Pick a store > name it > Create | It becomes a business with its own job (Cashier, Shift Lead, Manager, Owner) |
| Set owner: player ID or CID | They become Owner; shelves start with 10 of everything; the shop shows "Owned by ..." |
| List for sale with a price | The shop window shows "For sale: $X" with **Request to buy** |
| Player requests, admin Approves | Price taken from their bank (they must be in the city); they become the owner |
| Owner/Manager: `/bossmenu` | Hire, fire, promote (managers below their rank). Only the **owner** changes pay and uses **Savings** |
| Owner/Manager: `/business` (or F6 > Manage store) | Stock and prices, sales today/7 days, staff on duty, recent sales |
| Restock | Costs 50% of the base price per item from the store savings; shelves hold up to 100 |
| Owner sets prices | 80% to 200% of the base price |
| Someone buys at an owned store | 0 staff: all to savings. 1 or 2 staff on duty within 50 m: 25% each. 3+: they split 50%. Rest to savings. The buyer never earns from their own purchase |
| Owned store sold out | "Sold out" until restocked |
| Remove owner | The store goes back to a normal shop (unlimited stock, normal prices) |

## Check that phase 8b works (banking and billing)

Ensure `tfc-banking` (after `tfc-jobs`). Tables `tfc_bills`, `tfc_society_accounts` and `tfc_society_transactions`
are created automatically.

| Do | Expect |
| --- | --- |
| Walk up to a Fleeca teller (green $ blip), press E | Bank: overview (bank, cash, credit available), deposit/withdraw, recent activity |
| ATM PIN tab: set a 4-digit PIN | "PIN saved"; ATMs now work |
| Walk up to any ATM, press E | PIN keypad (type or click). 3 wrong PINs lock ATMs for 5 minutes |
| ATM: $20 / $50 ... / other amount | Withdraw and deposit only (transfers, bills, credit are bank-only) |
| Bank > Transfer: player ID, Look up, amount, Send | Shows their name before sending; they get a notice; both histories show it |
| Bank > History | Every money change, newest first, with paging |
| As police/EMS/mechanic/taxi on duty: F6 > Send bill, or `/bill id amount reason` | Player gets a notice and a red badge on Bills |
| `/bills` anywhere, or Bank > Bills | Pay (bank first, then credit for the rest) or Decline. Police and EMS bills can't be declined. The sender is told |
| Bank > Credit | Owed, available, limit, next interest date; Repay / Repay all (as much as your bank covers) |

Paid bills, police fines and early hospital bills go into the job's **department account** (`tfc_society_accounts`),
ready for the department/business accounts phase. Credit interest: 2% of what's owed, every 7 days, never past the
credit limit (offline characters too). Rates, banks, jobs that can bill and limits are in `tfc-banking/config.lua`.

## Check that phase 8a works (world sync)

Everyone now sees the same time and weather. Time runs at GTA's pace (a day every 48 minutes); weather stays as set
until an admin changes it. Time, weather, blackout and snow survive server restarts.

**vMenu:** turn off its own sync in `server.cfg` or the two fight over the clock and weather:

```cfg
setr vmenu_enable_time_sync false
setr vmenu_enable_weather_sync false
```

| Do | Expect |
| --- | --- |
| Start the server | `module world v0.1.0 ready`, `world ready: 08:00, CLEAR` (first start) |
| Two players compare the HUD clock | Same time |
| F10 > World > Noon 12:00 | Everyone's clock jumps to 12:00 |
| Freeze time | Clock stops for everyone until unfrozen |
| Weather > Rain | Rain blends in over ~15 s for everyone |
| Blackout on | City lights go out (car lights still work) |
| Holiday snow on | Snow on the ground, footprints and tyre tracks; weather switches to Christmas |
| Restart the server | Same weather, blackout and snow; clock carries on from where it was |

Shop hours (dealers, pawn shop) now use this shared clock on the server.

## Check that phase 7 works (police, EMS, admin)

Ensure `tfc-medical`, `tfc-police` and `tfc-admin` (after `tfc-shops`). `tfc_police_records` is created automatically.
The F6 menu, fine/jail dialogs and progress bars use ox_lib; without it, use the chat commands.

**Paychecks** are now paid on the clock: every 15 minutes (HH:00, :15, :30, :45 server time) to everyone who is working at
that moment, with no minimum playtime. The console logs `payroll: N paycheck(s)`.

**Death and EMS** (`tfc-medical/config.lua`)

| Do | Expect |
| --- | --- |
| Die (fall, get shot) | You go down instead, and are told how many EMS are on duty. Inventory and hotbar are blocked |
| Press **G** | On-duty EMS get a flashing blip and waypoint; you're told how many EMS are on duty |
| No EMS on duty: wait 60 s, press **E** | Fade to the nearest hospital, full health, no charge |
| EMS on duty: after 2:30, press **E** | Early respawn for $1,000 (bank, then credit). Can't afford it: wait for the free one |
| EMS on duty: after 5:00, press **E** | Free respawn. (If EMS clock out while you're down, the 60 s no-EMS rule applies) |
| As EMS on duty, F6 > Revive next to a downed player (or `/revive`) | 8 s CPR, they get up with 50% health |
| F6 > Treat wounds (or `/heal`) | 5 s, they're at full health |
| Disconnect while down, reconnect | Down again with a full timer (no combat logging) |
| Admin: `/revive [id]`, `/heal [id]` | Instant, any distance, full health |

**Police** (`tfc-police/config.lua`), all as `police` on duty, from F6 or the commands:

| Do | Expect |
| --- | --- |
| Cuff / uncuff (`/cuff [id]`) | Suspect's hands behind back; can walk but not run, jump, fight, use inventory or get in cars |
| Escort (`/escort [id]`) | Cuffed or downed player is held next to you; again to let go |
| Put in vehicle (`/seat [id]`) / Take out (`/unseat [id]`) | Into the closest vehicle's back seat / out of their vehicle |
| Search (`/search [id]`) | Their inventory opens next to yours; take weapons, drugs, cash |
| Issue fine (`/fine id amount reason`) | Paid from bank; what bank can't cover goes on credit (to its -$2,500 limit) |
| Send to jail (`/jail id minutes reason`, cuffed) | Teleported into Bolingbroke with a countdown; walking out puts them back; released at the gate |
| Reconnect while jailed | Time left is kept; back in jail. `/jailtime` shows it. `/unjail id` (police or admin) releases |

Every fine, jail and early release is in `tfc_police_records`.

**Admin** (`tfc.admin`)

| Do | Expect |
| --- | --- |
| **F2** (or `/noclip`) | Fly: WASD + mouse, Space/Ctrl up/down, Shift faster, mouse wheel speed. Invisible to others. F2 again lands you |
| **F10** (or `/admin`) | Players tab: everyone online with job, status (down, cuffed, jailed, frozen); Go to, Bring, Spectate, Revive, Heal, Freeze, Give item, Kick |
| `/items` | Item browser: every item with its picture, search and categories; give any amount to yourself or a player |
| Spectate (menu or `/spectate id`) | Watch them; Backspace or `/spectate` to come back to where you were |
| `/tpm`, `/tp x y [z]`, `/goto id`, `/bring id`, `/back` | Teleports; `/back` returns to where you were before the last one |

**HUD who's-on box**: above the location, *Staff* (online with `tfc.admin` or `tfc.mod`), *LEO* and *EMS* (on duty).
Updates every 5 s. Groups and jobs are set in `tfc-hud/config.lua` (`Counts`); a `fire` icon is ready for later.

Hospital, jail and release positions are in the configs; adjust them if one is slightly off on your map.

## Check that phase 6d works (shops)

Shop **types** (what's sold, prices, payment, hours, job locks) are in `tfc-shops/config.lua`. Shop **locations** are in
the database (`tfc_shops`, `tfc_shop_stock`, created automatically). On the very first start, 9 × 24/7 and
9 × Ammu-Nation are added from `ShopsConfig.Locations`; after that, admins manage every shop in game with `/shops`.

| Type | Pays with | Notes |
| --- | --- | --- |
| `general` 24/7 Store | cash, bank, card (credit) | blip, always open |
| `ammunation` Ammu-Nation | bank, cash, card | buys back guns (into bank) |
| `pawn` Pawn Shop | cash | 08-22, buys phones, radios, kits, tools; small limited stock |
| `drugdealer` Dealer | cash | 20-05, no blip, limited weed stock, buys every drug |
| `armsdealer` Arms Dealer | cash | 22-04, no blip, limited stock, guns have scratched serials |
| `police_armory` Police Armory | free | police on duty; better gear needs higher ranks |
| `ems_supply` EMS Supply | free | ambulance on duty |

| Do | Expect |
| --- | --- |
| Start the server | `module shops v0.1.0 ready`, `shops ready: 18 shops` (first start also: `added 18 shops from config`) |
| Drive to the Strawberry 24/7 (green bag blip) | Shopkeeper behind the counter; walk up: **[E] 24/7 Store** |
| Press E, buy 2 Bandages with Cash | Cash goes down by $50, bandages in your inventory, wallet in the window updates |
| Try to buy more than you can afford or carry | Clear error, nothing charged |
| `/shops` (admin) | Shop Manager: every shop, nearest first, with Go / Edit |
| Pick **Dealer**, name it, stand somewhere, **Place shop here** | Dealer appears where you stood, facing your way; no blip |
| Walk up during the day | "Dealer · closed until 20:00". At night: buy weed (stock goes down), sell drugs for cash |
| Edit the dealer: **Move to me**, **Restock**, change blip, **Remove** (click twice) | Every player sees the change right away |
| Place a **Police Armory**; open it as a civilian, off-duty cop, on-duty cop | "employees only" / "you need to be on duty" / free gear, rank-locked items marked "Rank N+" |

Opening hours follow the GTA clock players see (`Clock = 'game'`); set `Clock = 'real'` to use server time.
If a seeded shopkeeper stands a little off (inside a wall or floating), stand where they should be and use **Move to me**.

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

Tab opens your inventory plus whatever is around you:

| Where you are | Second panel |
| --- | --- |
| Sitting in a vehicle | Glovebox (5 slots) |
| Standing at the back of a vehicle | Trunk (size by vehicle class; bikes have none) and the trunk opens |
| Anywhere else | Ground |

| Who | Do | Expect |
| --- | --- | --- |
| You | Open on foot, drag water to the Ground panel | A bag appears on the ground |
| Second player | Walk to the bag, Tab | Same ground panel; take the water and the bag disappears once both close |
| You | Drop cash on the ground | HUD cash goes down; `tfc_transactions` shows "moved to Ground" |
| You | Stand at a car's trunk, Tab, store items, close, come back | Items are still there (saved by plate) |
| You | Sit in the car, Tab | Glovebox instead of trunk |
| You + second player standing close | Drag an item onto **Give** | They get it; both see a notification |
| You | Walk away with a drop or trunk open, then move an item | "You cannot reach that" |

Drops last 30 minutes untouched (`Drop.lifetime`). Vehicle storage nobody has touched for 7 days is cleared on server
start (`Vehicle.purgeDays`) so random NPC cars don't pile up; that becomes "owned vehicles only" once vehicles have owners.

## Check that phase 6a works (inventory)

Open `tfc-inventory/html/index.html` in a browser to try the drag-and-drop with sample items.

| Where | Do | Expect |
| --- | --- | --- |
| Server console | Start the server | `inventory ready: 9 items`, `module accounts v0.2.0 ready` |
| In game | Load a character, press **Tab** | Inventory opens: phone, water, sandwiches and your cash as an item |
| In game | HUD | Cash still shows the same amount; it now *is* the cash item |
| Inventory | Drag items; hold **Shift** (half) or **Ctrl** (one), or type an amount | Moves, splits, stacks and swaps |
| Inventory | Double-click or right-click water | Water used (one fewer) |
| In game | `/giveitem me bandage 5`, press **3** if it's in slot 3 | Hotbar flashes, bandage used, health goes up |
| In game | `/givemoney me cash 100` | Cash item +$100, HUD +$100 |
| Reconnect | Rejoin | Same items in the same slots |

Items are defined in `tfc-inventory/items.lua`; sizes and starting items in `config.lua`. Item images go in
`tfc-inventory/html/images/<item>.png` (items without one show a lettered tile).

**Keys:** Tab opens the inventory and 1-5 use hotbar slots. Both can be rebound in GTA's Settings > Key Bindings > FiveM.
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
| Server console | Start the server | `module jobs v0.2.1 ready`, `jobs ready: 5 jobs, paycheck every 15 min on the clock` |
| In game | Load a character | HUD job line: "Unemployed" (no duty dot) |
| In game | `/setjob me police 5` | HUD: "LSPD · Chief of Police" with a grey dot (off duty) |
| In game | `/duty` | Dot turns green; `/duty` again turns it grey |
| In game | Be on duty at the next quarter hour (HH:00, :15, :30, :45 server time) | Bank +$850 and a "Paycheck: $850 deposited to your bank" notice. `/job` shows minutes to the next one |
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

### Shops (phase 6d, `exports['tfc-shops']`, server)

| Call | Returns |
| --- | --- |
| `GetShops()` / `GetShop(id)` | shops as players see them (`id, type, label, x, y, z, h, ped, blip, hours, job`) |
| `RestockShop(id)` | fills every limited item back to its maximum |

Server hooks: `shopPurchase(source, shopId, item, count, total, payment)`, `shopSale(source, shopId, item, count, total, account)`.
Admin: `/shops`.

### Government and finance (QoL)

`exports['tfc-government']`: `HasLicense(src, type)`, `GetLicenses(src)`, `GetLicensesByCid(cid)`.
Types: `driver, motorcycle, cdl, hazmat, weapon, hunting, fishing, boat, pilot`.
Hooks: `licenseIssued(src, type)`, `licenseStatusChanged(cid, type, status, by)`.
`exports['tfc-finance']`: `GetQuote(symbol)`, `GetPortfolio(src)`.

### Businesses (phase 8c)

`exports['tfc-business']`: `GetBusiness(id)`, `GetBusinessByShop(shopId)`, `GetBusinessByJob(job)`.
Hooks: `businessOwnerChanged(id, cid)`, `businessSale(id, total, toStaff, toSavings)`.
`tfc-jobs` adds `RegisterJob(name, def)` (runtime jobs, saved) and `GetTopGrade(name)`.
`tfc-shops` adds `SetStoreInfo`, `ResetStoreStock`, `AddStock`, `GetStoreItems`, `GetShopTypes`.
`tfc-banking` adds `GetSocietyHistory(name, limit)`.

### Banking (phase 8b, `exports['tfc-banking']`, server)

| Call | Notes |
| --- | --- |
| `CreateBill({ target, amount, reason, sourceType, sourceName, sourceLabel, sender?, mandatory? })` | for businesses and other jobs |
| `GetPendingBills(src)` | |
| `GetSociety(name)`, `AddSociety(name, amount, reason)`, `RemoveSociety(name, amount, reason)` | department/business accounts |

Hooks: `billCreated(bill)`, `billPaid(bill)`, `billDeclined(bill)`, `societyChanged(name, balance, delta, reason)`.
`tfc-accounts` adds `ApplyCreditInterest(rate, reason)`.

### World (phase 8a, `exports['tfc-world']`, server)

`GetTime()` -> `{ hour, minute }`, `SetTime(h, m)`, `FreezeTime(bool)`, `GetWeather()`, `SetWeather(type)`,
`SetBlackout(bool)`, `SetSnow(bool)`, `GetState()`. Clients read `GlobalState['tfc:world']`.

### Medical, police, admin (phase 7, server exports)

| Resource | Call | Notes |
| --- | --- | --- |
| `tfc-medical` | `IsDown(src)`, `Revive(src, full?)`, `Heal(src)` | hooks `playerDowned(src)`, `playerRevived(src, by)` |
| `tfc-police` | `IsCuffed(src)`, `IsJailed(src)`, `Jail(src, minutes, reason?)`, `Release(src)` | hooks `playerCuffed`, `playerFined`, `playerJailed`, `playerReleased` |
| `tfc-inventory` | `OpenSearch(viewer, target)`, `ForceClose(src)` | search only works on cuffed / downed players |
| `tfc-jobs` (client) | `AddJobAction({ id, jobs, label, icon, event })` | adds an entry to the F6 job menu |

Public state bags: `tfc:down`, `tfc:cuffed`, `tfc:escortedBy`, `tfc:jailed`, `tfc:frozen`, `tfc:admin`.

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

UI: `TFC.UI.Notify(data)` on the client, `TFC.UI.Notify(src, data)` on the server; `TFC.UI.ShowPrompt('[E] ...')` /
`TFC.UI.HidePrompt()`, `TFC.UI.Menu(menu)`, `TFC.UI.Input(heading, rows)`, `TFC.UI.Progress(data)` on the client.
All use ox_lib if it's running, GTA's own UI otherwise (menus and dialogs need ox_lib).

Saving: changed characters are saved in one transaction every `Config.SaveInterval` seconds (default 300),
and always on character switch, disconnect, and txAdmin shutdown.

## Editor setup

Use VS Code with the **Lua** extension (LuaLS) and **CfxLua IntelliSense** for FiveM natives.
`.luarc.json` and `types/` give autocomplete for the whole `TFC` API.

## License

Private, all rights reserved, until a license is chosen before any public release.
