-- Admin server: every admin action is checked here (tfc.admin).
--
-- State bags (public): 'tfc:admin' = true on admins (lets their client offer noclip / the menu;
-- the server still checks every action), 'tfc:frozen' = true while frozen by an admin.

local Cfg = AdminConfig

local function notify(src, text, kind)
    TFC.UI.Notify(src, { title = 'Admin', description = text, type = kind or 'inform' })
end

local function fail(err) return { ok = false, error = err } end

local function charName(src)
    local p = TFC.GetPlayer(src)
    return p and p:GetFullName() or nil
end

local function label(src)
    return ('%s (%d)'):format(charName(src) or GetPlayerName(src) or '?', src)
end

local function coordsOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) }
end

local function online(src)
    return src and GetPlayerName(src) ~= nil
end

local function log(admin, text, ...)
    TFC.Log.Info('[admin] %s ' .. text, label(admin), ...)
end

-- Admin flag on the client ---------------------------------------------------------------------

local function refreshFlag(src)
    local is = TFC.IsAdmin(src) or nil
    if Player(src).state['tfc:admin'] ~= is then Player(src).state:set('tfc:admin', is, true) end
end

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(1000, function() if online(src) then refreshFlag(src) end end)
end)

CreateThread(function()
    while true do
        for _, id in ipairs(GetPlayers()) do refreshFlag(tonumber(id)) end
        Wait(30000)
    end
end)

-- Data for the menu ---------------------------------------------------------------------------

local function playerList()
    local list = {}
    local hasJobs = GetResourceState('tfc-jobs') == 'started'
    local hasAccounts = GetResourceState('tfc-accounts') == 'started'
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id) --[[@as integer]]
        local p = TFC.GetPlayer(src)
        local entry = {
            id = src,
            account = GetPlayerName(src) or '?',
            name = p and p:GetFullName() or false,
            cid = p and p.cid or false,
            ping = GetPlayerPing(src),
            loaded = p ~= nil,
        }
        if p then
            local st = Player(src).state
            entry.down = st['tfc:down'] == true
            entry.cuffed = st['tfc:cuffed'] == true
            entry.jailed = st['tfc:jailed'] == true
            entry.frozen = st['tfc:frozen'] == true
            entry.admin = st['tfc:admin'] == true
            local ped = GetPlayerPed(src)
            entry.health = ped ~= 0 and GetEntityHealth(ped) or 0
            if hasJobs then
                local job = exports['tfc-jobs']:GetJob(src)
                if job then
                    entry.job = job.gradeLabel and ('%s · %s'):format(job.label, job.gradeLabel) or job.label
                    entry.onDuty = job.onDuty
                end
            end
            if hasAccounts then
                local b = exports['tfc-accounts']:GetBalances(src)
                if b then entry.cash, entry.bank = b.cash, b.bank end
            end
        end
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function itemList()
    if GetResourceState('tfc-inventory') ~= 'started' then return {} end
    local list = {}
    for name, def in pairs(exports['tfc-inventory']:GetItems() or {}) do
        local category = def.category
        if not category then
            if def.weapon then category = 'weapon'
            elseif name:sub(1, 5) == 'ammo_' then category = 'ammo'
            else category = 'general' end
        end
        list[#list + 1] = {
            name = name, label = def.label or name, category = category,
            weight = def.weight or 0, description = def.description or '',
            stack = def.stack ~= false,
        }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function menuData(src)
    return { ok = true, me = src, players = playerList(), items = itemList(), maxGive = Cfg.MaxGive }
end

-- Actions ------------------------------------------------------------------------------------

local function teleport(src, coords, opts)
    TriggerClientEvent('tfc-admin:client:teleport', src, coords, opts or {})
end

local Actions = {}

Actions['goto'] = function(admin, target)
    local c = coordsOf(target)
    if not c then return fail('could not find them') end
    teleport(admin, { x = c.x + 1.0, y = c.y, z = c.z, w = c.w })
    log(admin, 'went to %s', label(target))
    return { ok = true, message = ('Went to %s'):format(label(target)) }
end

function Actions.bring(admin, target)
    if target == admin then return fail('that\'s you') end
    local c = coordsOf(admin)
    if not c then return fail('could not read your position') end
    teleport(target, { x = c.x + 1.0, y = c.y, z = c.z, w = c.w })
    log(admin, 'brought %s', label(target))
    return { ok = true, message = ('Brought %s'):format(label(target)) }
end

function Actions.spectate(admin, target)
    if target == admin then return fail('you can\'t spectate yourself') end
    local c = coordsOf(target)
    if not c then return fail('could not find them') end
    TriggerClientEvent('tfc-admin:client:spectate', admin, target, c)
    log(admin, 'is spectating %s', label(target))
    return { ok = true, close = true }
end

function Actions.revive(admin, target)
    if GetResourceState('tfc-medical') ~= 'started' then return fail('tfc-medical is not running') end
    exports['tfc-medical']:Revive(target, true)
    log(admin, 'revived %s', label(target))
    return { ok = true, message = ('Revived %s'):format(label(target)) }
end

function Actions.heal(admin, target)
    if GetResourceState('tfc-medical') == 'started' then
        exports['tfc-medical']:Heal(target)
    else
        TriggerClientEvent('tfc-admin:client:heal', target)
    end
    log(admin, 'healed %s', label(target))
    return { ok = true, message = ('Healed %s'):format(label(target)) }
end

function Actions.freeze(admin, target)
    if target == admin then return fail('that\'s you') end
    local frozen = not Player(target).state['tfc:frozen']
    Player(target).state:set('tfc:frozen', frozen or nil, true)
    notify(target, frozen and 'An admin froze you.' or 'You can move again.', frozen and 'warning' or 'inform')
    log(admin, '%s %s', frozen and 'froze' or 'unfroze', label(target))
    return { ok = true, message = ('%s %s'):format(frozen and 'Froze' or 'Unfroze', label(target)) }
end

function Actions.kick(admin, target, d)
    if target == admin then return fail('that\'s you') end
    local reason = type(d.reason) == 'string' and d.reason:gsub('[%c<>]', ''):sub(1, 120) or ''
    if #reason < 3 then return fail('give a reason') end
    log(admin, 'kicked %s: %s', label(target), reason)
    DropPlayer(tostring(target), 'Kicked by an admin: ' .. reason)
    return { ok = true, message = ('Kicked %s'):format(label(target)) }
end

function Actions.give(admin, target, d)
    if GetResourceState('tfc-inventory') ~= 'started' then return fail('tfc-inventory is not running') end
    local count = math.tointeger(tonumber(d.count))
    if not count or count < 1 or count > Cfg.MaxGive then return fail(('amount must be 1 to %d'):format(Cfg.MaxGive)) end
    local items = exports['tfc-inventory']:GetItems()
    local def = type(d.item) == 'string' and items[d.item]
    if not def then return fail('unknown item') end
    if not TFC.GetPlayer(target) then return fail('they have no character loaded') end
    local ok, err = exports['tfc-inventory']:AddItem(target, d.item, count, nil, nil, 'admin give by ' .. label(admin))
    if not ok then return fail(err or 'could not give that') end
    log(admin, 'gave %dx %s to %s', count, d.item, label(target))
    if target ~= admin then notify(target, ('An admin gave you %dx %s.'):format(count, def.label)) end
    return { ok = true, message = ('Gave %dx %s to %s'):format(count, def.label, target == admin and 'you' or label(target)) }
end

TFC.Callback.Register('admin:data', function(src)
    if not TFC.IsAdmin(src) then return fail('admins only') end
    return menuData(src)
end, { rateLimit = 500 })

TFC.Callback.Register('admin:action', function(src, action, target, d)
    if not TFC.IsAdmin(src) then return fail('admins only') end
    local fn = type(action) == 'string' and Actions[action]
    if not fn then return fail('unknown action') end
    target = math.tointeger(tonumber(target))
    if not target or not online(target) then return fail('that player is not online') end
    local r = fn(src, target, type(d) == 'table' and d or {})
    r.players = playerList()
    return r
end, { rateLimit = 250 })

-- Noclip and spectate only need the server to say yes (and log it).
TFC.Callback.Register('admin:noclip', function(src, on)
    if not TFC.IsAdmin(src) then return fail('admins only') end
    log(src, 'noclip %s', on and 'on' or 'off')
    return { ok = true }
end, { rateLimit = 250 })

TFC.Callback.Register('admin:targetCoords', function(src, target)
    if not TFC.IsAdmin(src) then return nil end
    target = math.tointeger(tonumber(target))
    return target and online(target) and coordsOf(target) or nil
end, { rateLimit = 200 })

-- Commands -----------------------------------------------------------------------------------

local ADMIN = TFC.Permissions.Admin

local function run(src, action, target, d)
    if src == 0 then return print('use this in game') end
    if not target or not online(target) then return notify(src, 'No such player.', 'error') end
    local r = Actions[action](src, target, d or {})
    if r.ok and r.message then notify(src, r.message, 'success') elseif not r.ok then notify(src, r.error, 'error') end
end

TFC.RegisterCommand('admin', { help = 'Admin: open the admin menu', permission = ADMIN }, function(src)
    if src == 0 then return end
    TriggerClientEvent('tfc-admin:client:openMenu', src, 'players')
end)

TFC.RegisterCommand('items', { help = 'Admin: browse and give items', permission = ADMIN }, function(src)
    if src == 0 then return end
    TriggerClientEvent('tfc-admin:client:openMenu', src, 'items')
end)

TFC.RegisterCommand('noclip', { help = 'Admin: toggle noclip', permission = ADMIN }, function(src)
    if src == 0 then return end
    TriggerClientEvent('tfc-admin:client:noclip', src)
end)

TFC.RegisterCommand('goto', {
    help = 'Admin: teleport to a player', permission = ADMIN,
    params = { { name = 'id', help = 'Player ID' } },
}, function(src, args) run(src, 'goto', TFC.ResolveTarget(src, args[1])) end)

TFC.RegisterCommand('bring', {
    help = 'Admin: bring a player to you', permission = ADMIN,
    params = { { name = 'id', help = 'Player ID' } },
}, function(src, args) run(src, 'bring', TFC.ResolveTarget(src, args[1])) end)

TFC.RegisterCommand('spectate', {
    help = 'Admin: spectate a player (run again to stop)', permission = ADMIN,
    params = { { name = 'id', help = 'Player ID (leave out to stop)', optional = true } },
}, function(src, args)
    if src == 0 then return end
    if not args[1] then return TriggerClientEvent('tfc-admin:client:stopSpectate', src) end
    run(src, 'spectate', TFC.ResolveTarget(src, args[1]))
end)

TFC.RegisterCommand('freeze', {
    help = 'Admin: freeze / unfreeze a player', permission = ADMIN,
    params = { { name = 'id', help = 'Player ID' } },
}, function(src, args) run(src, 'freeze', TFC.ResolveTarget(src, args[1])) end)

TFC.RegisterCommand('kick', {
    help = 'Admin: kick a player', permission = ADMIN,
    params = { { name = 'id', help = 'Player ID' }, { name = 'reason', help = 'Why' } },
}, function(src, args)
    local target = TFC.ResolveTarget(src, args[1])
    local reason = table.concat(args, ' ', 2)
    if src == 0 then
        if target then DropPlayer(tostring(target), 'Kicked: ' .. reason) end
        return
    end
    run(src, 'kick', target, { reason = reason })
end)

TFC.RegisterCommand('tpm', { help = 'Admin: teleport to your map waypoint', permission = ADMIN }, function(src)
    if src == 0 then return end
    TriggerClientEvent('tfc-admin:client:tpm', src)
    log(src, 'teleported to their waypoint')
end)

TFC.RegisterCommand('tp', {
    help = 'Admin: teleport to coordinates', permission = ADMIN,
    params = { { name = 'x', help = 'X' }, { name = 'y', help = 'Y' }, { name = 'z', help = 'Z (optional: finds the ground)', optional = true } },
}, function(src, args)
    if src == 0 then return end
    local function num(v) return v and tonumber((v:gsub(',', ''))) or nil end
    local x, y, z = num(args[1]), num(args[2]), num(args[3])
    if not x or not y then return notify(src, 'Usage: /tp x y [z]', 'error') end
    teleport(src, { x = x, y = y, z = z or 0.0 }, { findGround = z == nil })
    log(src, 'teleported to %.1f, %.1f, %s', x, y, z and ('%.1f'):format(z) or 'ground')
end)

TFC.RegisterCommand('back', { help = 'Admin: go back to where you were before your last teleport', permission = ADMIN }, function(src)
    if src == 0 then return end
    TriggerClientEvent('tfc-admin:client:back', src)
end)

-- Lifecycle ----------------------------------------------------------------------------------

TFC.On('playerLoaded', function(src) refreshFlag(src) end)

TFC.On('playerUnloaded', function(src)
    Player(src).state:set('tfc:frozen', nil, true)
end)

CreateThread(function()
    TFC.RegisterModule({ name = 'admin', version = '0.1.0' }, function()
        TFC.Log.Info('admin tools ready')
    end)
end)
