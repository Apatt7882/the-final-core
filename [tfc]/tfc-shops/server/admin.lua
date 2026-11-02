-- Shop manager for admins (tfc.admin): place, move, edit, restock and remove shops in game.
-- A new or moved shop goes exactly where the admin is standing, facing the way they face.

local Cfg = ShopsConfig
local Types = Cfg.Types
local shops = ShopsSrv.shops

local BLIP_MODES = { default = nil, show = 1, hide = 0 }

local function round(n, places)
    local m = 10 ^ (places or 2)
    return math.floor(n * m + 0.5) / m
end

local function adminPosition(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = round(c.x), y = round(c.y), z = round(c.z), h = round(GetEntityHeading(ped), 1) }
end

local function cleanLabel(v)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('<[^>]*>', ''):gsub('[%c<>]', ''):match('^%s*(.-)%s*$')
    if v == '' then return nil end
    return v:sub(1, 48)
end

---@return string|nil model, string|nil err
local function cleanPed(v)
    if v == nil or v == '' then return nil end
    if type(v) ~= 'string' or #v > 64 or not v:match('^[%w_]+$') then return nil, 'ped model can only use letters, numbers and _' end
    return v:lower()
end

local function blipMode(shop)
    if shop.blip == 1 then return 'show' end
    if shop.blip == 0 then return 'hide' end
    return 'default'
end

local function typeList()
    local list = {}
    for name, def in pairs(Types) do
        list[#list + 1] = {
            name = name, label = def.label, ped = def.ped,
            blip = def.blip ~= false and def.blip ~= nil,
            hours = def.hours or false,
            job = def.job and def.job.name or false,
            payment = def.payment or { 'cash' },
            sells = #(def.items or {}), buys = #(def.buys or {}),
            limited = (function()
                for _, e in ipairs(def.items or {}) do if e.stock then return true end end
                return false
            end)(),
        }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function adminData(src)
    local list = {}
    for _, shop in pairs(shops) do
        local def = Types[shop.type]
        list[#list + 1] = {
            id = shop.id,
            type = shop.type,
            typeLabel = def and def.label or ('unknown type "%s"'):format(shop.type),
            valid = def ~= nil,
            label = shop.label or (def and def.label) or shop.type,
            customLabel = shop.label or '',
            ped = shop.ped or (def and def.ped) or '',
            customPed = shop.ped or '',
            blip = blipMode(shop),
            x = shop.x, y = shop.y, z = shop.z, h = shop.h,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return { ok = true, shops = list, types = typeList(), position = adminPosition(src) }
end

local function fail(err) return { ok = false, error = err } end

local function actor(src)
    return ('%s (%d)'):format(GetPlayerName(src) or 'unknown', src)
end

local Actions = {}

function Actions.place(src, d)
    if not Types[d.type] then return fail('pick a shop type') end
    local pos = adminPosition(src)
    if not pos then return fail('could not read your position') end
    local label = cleanLabel(d.label)
    local ped, pedErr = cleanPed(d.ped)
    if pedErr then return fail(pedErr) end
    local blip = BLIP_MODES[d.blip]

    local id = MySQL.insert.await(
        'INSERT INTO tfc_shops (type, label, x, y, z, h, ped, blip, created_by) VALUES (?, NULLIF(?, \'\'), ?, ?, ?, ?, NULLIF(?, \'\'), NULLIF(?, 255), ?)',
        { d.type, label or '', pos.x, pos.y, pos.z, pos.h, ped or '', blip or 255, GetPlayerName(src) or tostring(src) })
    id = math.tointeger(id)
    if not id then return fail('could not save the shop') end

    local shop = { id = id, type = d.type, label = label, x = pos.x, y = pos.y, z = pos.z, h = pos.h, ped = ped, blip = blip }
    shops[id] = shop
    ShopsSrv.InitStock(shop, nil)
    TFC.Log.Info('%s placed shop #%d (%s) at %.1f, %.1f, %.1f', actor(src), id, d.type, pos.x, pos.y, pos.z)
    return { ok = true, message = ('Placed %s (#%d)'):format(label or Types[d.type].label, id), changed = true }
end

function Actions.move(src, d)
    local shop = shops[math.tointeger(tonumber(d.id)) or -1]
    if not shop then return fail('that shop no longer exists') end
    local pos = adminPosition(src)
    if not pos then return fail('could not read your position') end
    MySQL.update.await('UPDATE tfc_shops SET x = ?, y = ?, z = ?, h = ? WHERE id = ?', { pos.x, pos.y, pos.z, pos.h, shop.id })
    shop.x, shop.y, shop.z, shop.h = pos.x, pos.y, pos.z, pos.h
    TFC.Log.Info('%s moved shop #%d to %.1f, %.1f, %.1f', actor(src), shop.id, pos.x, pos.y, pos.z)
    return { ok = true, message = ('Moved #%d to where you are standing'):format(shop.id), changed = true }
end

function Actions.edit(src, d)
    local shop = shops[math.tointeger(tonumber(d.id)) or -1]
    if not shop then return fail('that shop no longer exists') end
    if not Types[d.type] then return fail('pick a shop type') end
    local label = cleanLabel(d.label)
    local ped, pedErr = cleanPed(d.ped)
    if pedErr then return fail(pedErr) end
    local blip = BLIP_MODES[d.blip]

    MySQL.update.await(
        'UPDATE tfc_shops SET type = ?, label = NULLIF(?, \'\'), ped = NULLIF(?, \'\'), blip = NULLIF(?, 255) WHERE id = ?',
        { d.type, label or '', ped or '', blip or 255, shop.id })

    local typeChanged = shop.type ~= d.type
    shop.type, shop.label, shop.ped, shop.blip = d.type, label, ped, blip
    if typeChanged then
        -- Different goods: start the new type's stock fresh.
        MySQL.update.await('DELETE FROM tfc_shop_stock WHERE shop_id = ?', { shop.id })
        ShopsSrv.InitStock(shop, nil)
    end
    TFC.Log.Info('%s edited shop #%d (%s)', actor(src), shop.id, d.type)
    return { ok = true, message = ('Saved #%d'):format(shop.id), changed = true }
end

function Actions.delete(src, d)
    local shop = shops[math.tointeger(tonumber(d.id)) or -1]
    if not shop then return fail('that shop no longer exists') end
    MySQL.update.await('DELETE FROM tfc_shops WHERE id = ?', { shop.id })
    shops[shop.id] = nil
    ShopsSrv.ForgetStock(shop.id)
    TFC.Log.Info('%s removed shop #%d (%s)', actor(src), shop.id, shop.type)
    return { ok = true, message = ('Removed #%d'):format(shop.id), changed = true }
end

function Actions.restock(src, d)
    local id = math.tointeger(tonumber(d.id)) or -1
    if not shops[id] then return fail('that shop no longer exists') end
    if not ShopsSrv.Restock(id) then return fail('this shop has no stock to refill') end
    TFC.Log.Info('%s restocked shop #%d', actor(src), id)
    return { ok = true, message = ('Restocked #%d'):format(id) }
end

TFC.Callback.Register('shops:admin:data', function(src)
    if not TFC.IsAdmin(src) then return fail('admins only') end
    return adminData(src)
end, { rateLimit = 300 })

TFC.Callback.Register('shops:admin:action', function(src, action, d)
    if not TFC.IsAdmin(src) then return fail('admins only') end
    local fn = type(action) == 'string' and Actions[action]
    if not fn or type(d) ~= 'table' then return fail('unknown action') end

    local r = fn(src, d)
    if r.changed then ShopsSrv.Broadcast() end
    local data = adminData(src)
    data.ok, data.error, data.message = r.ok, r.error, r.message
    return data
end, { rateLimit = 300 })

TFC.RegisterCommand(Cfg.Command, {
    help = 'Admin: place and manage shops',
    permission = TFC.Permissions.Admin,
}, function(src)
    if src == 0 then return print('use /' .. Cfg.Command .. ' in game') end
    TriggerClientEvent('tfc-shops:client:admin', src)
end)
