-- Weapons (phase 6c). Weapons are unique items whose metadata holds:
--   serial      e.g. TFC-7K2M9QXA (guns only)
--   ammo        rounds loaded in the gun
--   durability  100 = new, 0 = jammed (guns only)
--   mods        fitted weapon mods, e.g. { 'suppressor', 'flashlight' } (see WeaponMods in items.lua)
-- The client reports shots; the server takes the rounds and wear off the item. Reloading
-- takes ammo items from the inventory. Only one weapon can be held at a time.

local Cfg = InventoryConfig.Weapons
local SERIAL_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

---@type table<integer, { name: string, serial: string|nil, slot: integer }>
local equipped = {}

local function newSerial()
    local out = {}
    for i = 1, 8 do
        local n = math.random(#SERIAL_CHARS)
        out[i] = SERIAL_CHARS:sub(n, n)
    end
    return ('%s-%s'):format(Cfg.SerialPrefix, table.concat(out))
end

---Fill in the metadata a new weapon needs (serial, ammo, durability).
function InvSrv.weaponMeta(name, metadata)
    local def = Items[name]
    local meta = Inv.Copy(metadata) or {}
    if def.serial and not meta.serial then meta.serial = newSerial() end
    if def.ammo and meta.ammo == nil then meta.ammo = 0 end
    if (def.wear or 0) > 0 and meta.durability == nil then meta.durability = 100 end
    return next(meta) and meta or nil
end

-- Mods ----------------------------------------------------------------------------------------------

local modByItem = {}
for key, t in pairs(WeaponMods.Types) do modByItem[t.item] = key end

local function modsOf(item)
    local list = item.metadata and item.metadata.mods
    return type(list) == 'table' and list or {}
end

local function hasMod(item, key)
    for _, k in ipairs(modsOf(item)) do if k == key then return true end end
    return false
end

---GTA component names for the mods on this gun.
local function componentsOf(item)
    local fits = WeaponMods.Weapons[item.name] or {}
    local out = {}
    for _, key in ipairs(modsOf(item)) do
        if fits[key] then out[#out + 1] = fits[key] end
    end
    return out
end

---Rounds per magazine, counting an extended magazine.
local function clipOf(item)
    local def = Items[item.name]
    if hasMod(item, 'extclip') and WeaponMods.Clips[item.name] then return WeaponMods.Clips[item.name] end
    return def.clip
end

InvSrv.weaponClip = clipOf

local function round1(n)
    return math.floor(n * 10 + 0.5) / 10
end

---Where the held weapon is now (it may have been moved to another slot).
---@return table|nil inv, integer|nil slot, table|nil item
local function heldItem(src)
    local eq = equipped[src]
    local inv = eq and InvSrv.ensure(src)
    if not inv then return nil end

    if eq.serial then
        for slot = 1, inv.slots do
            local item = inv.items[slot]
            if item and item.name == eq.name and item.metadata and item.metadata.serial == eq.serial then
                eq.slot = slot
                return inv, slot, item
            end
        end
        return nil
    end

    local item = inv.items[eq.slot]
    if item and item.name == eq.name then return inv, eq.slot, item end
    return nil
end

local function setMeta(inv, slot, item, changes)
    local meta = Inv.Copy(item.metadata) or {}
    for k, v in pairs(changes) do meta[k] = v end
    Inv.SetMetadata(inv, slot, meta)
    InvSrv.sync(inv)
    return meta
end

-- Reload -----------------------------------------------------------------------------------------

---@return boolean ok, string|integer errOrAmmo
local function reload(src)
    local inv, slot, item = heldItem(src)
    if not inv then return false, 'you are not holding a gun' end
    local def = Items[item.name]
    if not def.ammo then return false, ('%s does not use ammo'):format(def.label) end

    local loaded = item.metadata and item.metadata.ammo or 0
    local need = (clipOf(item) or 0) - loaded
    if need <= 0 then return false, 'already fully loaded' end

    local have = Inv.Count(inv, def.ammo)
    if have == 0 then return false, ('no %s'):format(Items[def.ammo].label) end

    local n = math.min(need, have)
    local ok, err = InvSrv.RemoveItem(src, def.ammo, n, nil, nil, 'reload')
    if not ok then return false, err end

    -- The slot may have shifted if the ammo stack emptied; find the gun again.
    inv, slot, item = heldItem(src)
    if not inv then return false, 'you are not holding a gun' end
    local meta = setMeta(inv, slot, item, { ammo = loaded + n })
    return true, meta.ammo
end

-- Using weapon-related items ---------------------------------------------------------------------

---Does server/weapons.lua handle using this item?
function InvSrv.handlesUse(name)
    local def = Items[name]
    if not def then return false end
    if def.weapon or name == 'weapon_kit' or modByItem[name] then return true end
    for _, w in pairs(Items) do
        if w.weapon and w.ammo == name then return true end
    end
    return false
end

---Use a weapon, ammo or the gun kit from a slot. Returns the callback result.
function InvSrv.useWeaponItem(src, slot, item)
    local def = Items[item.name]

    -- Weapon: hold it, or put it away if it's already in hand.
    if def.weapon then
        local serial = item.metadata and item.metadata.serial
        local eq = equipped[src]
        if eq and eq.name == item.name and eq.serial == serial and (serial or eq.slot == slot) then
            equipped[src] = nil
            return { ok = true, weapon = { action = 'holster' } }
        end

        equipped[src] = { name = item.name, serial = serial, slot = slot }
        local meta = item.metadata or {}
        return {
            ok = true,
            close = true,
            weapon = {
                action = 'equip',
                name = item.name,
                label = def.label,
                hash = def.hash,
                serial = serial,
                ammo = meta.ammo,
                durability = meta.durability,
                ammoItem = def.ammo,
                clip = clipOf(item),
                components = componentsOf(item),
                infinite = def.infinite == true,
            },
        }
    end

    -- Gun kit: restore the held gun.
    if item.name == 'weapon_kit' then
        local inv, wSlot, wItem = heldItem(src)
        if not inv then return { ok = false, error = 'hold the gun you want to clean' } end
        local durability = wItem.metadata and wItem.metadata.durability
        if durability == nil then return { ok = false, error = ('%s does not need cleaning'):format(Items[wItem.name].label) } end
        if durability >= 100 then return { ok = false, error = 'that gun is already in perfect condition' } end

        local removed, err = InvSrv.RemoveItem(src, 'weapon_kit', 1, nil, nil, 'used')
        if not removed then return { ok = false, error = err } end
        inv, wSlot, wItem = heldItem(src)
        if inv then setMeta(inv, wSlot, wItem, { durability = 100 }) end
        return { ok = true, close = true, weaponUpdate = { durability = 100 } }
    end

    -- Weapon mod: fit it to the held gun.
    local modKey = modByItem[item.name]
    if modKey then
        local inv, wSlot, wItem = heldItem(src)
        if not inv then return { ok = false, error = 'hold the gun you want to fit it to' } end
        local fits = WeaponMods.Weapons[wItem.name]
        if not fits or not fits[modKey] then
            return { ok = false, error = ('a %s doesn\'t fit the %s'):format(def.label:lower(), Items[wItem.name].label) }
        end
        if hasMod(wItem, modKey) then return { ok = false, error = ('the %s already has one'):format(Items[wItem.name].label) } end

        local removed, err = InvSrv.RemoveItem(src, item.name, 1, nil, nil, 'fitted to ' .. Items[wItem.name].label)
        if not removed then return { ok = false, error = err } end
        inv, wSlot, wItem = heldItem(src)
        if not inv then return { ok = false, error = 'you are not holding a gun' } end
        local list = Inv.Copy(modsOf(wItem))
        list[#list + 1] = modKey
        setMeta(inv, wSlot, wItem, { mods = list })
        inv, wSlot, wItem = heldItem(src)
        TFC.UI.Notify(src, { title = 'Weapons', description = ('%s fitted to your %s.'):format(def.label, Items[wItem.name].label), type = 'success' })
        return { ok = true, close = true, weaponUpdate = { components = componentsOf(wItem), clip = clipOf(wItem) } }
    end

    -- Ammo: reload the held gun if it takes this ammo.
    local inv, _, wItem = heldItem(src)
    if not inv or Items[wItem.name].ammo ~= item.name then
        return { ok = false, error = ('hold a gun that uses %s'):format(def.label) }
    end
    local ok, result = reload(src)
    if not ok then return { ok = false, error = result } end
    return { ok = true, weaponUpdate = { ammo = result } }
end

-- Callbacks from the client while a weapon is held -------------------------------------------------

TFC.Callback.Register('weapons:reload', function(src)
    local ok, result = reload(src)
    if not ok then return { ok = false, error = result } end
    return { ok = true, ammo = result }
end, { rateLimit = 500 })

---The client reports shots fired since its last report.
TFC.Callback.Register('weapons:shots', function(src, shots)
    shots = math.tointeger(tonumber(shots)) or 0
    if shots < 1 or shots > 1000 then return { ok = false } end

    local inv, slot, item = heldItem(src)
    if not inv then
        equipped[src] = nil
        return { ok = false, gone = true }
    end

    local def = Items[item.name]
    local meta = item.metadata or {}
    local changes = {}
    if def.ammo then changes.ammo = math.max(0, (meta.ammo or 0) - shots) end
    if (def.wear or 0) > 0 and meta.durability then
        changes.durability = math.max(0, round1(meta.durability - shots * def.wear))
    end
    if next(changes) == nil then return { ok = true } end

    meta = setMeta(inv, slot, item, changes)
    return { ok = true, ammo = meta.ammo, durability = meta.durability }
end, { rateLimit = 200 })

-- /removemods: take every mod off the held gun and give the items back.
TFC.RegisterCommand('removemods', { help = 'Take the mods off the gun in your hands' }, function(src)
    if src == 0 then return end
    local inv, slot, item = heldItem(src)
    if not inv then return TFC.UI.Notify(src, { title = 'Weapons', description = 'Hold the gun first.', type = 'error' }) end
    local list = modsOf(item)
    if #list == 0 then return TFC.UI.Notify(src, { title = 'Weapons', description = 'That gun has no mods.', type = 'error' }) end

    -- Make sure the items fit back in the inventory before touching the gun.
    local def = Items[item.name]
    local baseClip = def.clip or 0
    local extra = hasMod(item, 'extclip') and math.max(0, ((item.metadata or {}).ammo or 0) - baseClip) or 0
    for _, key in ipairs(list) do
        local ok = Inv.CanFit(inv, WeaponMods.Types[key].item, 1)
        if not ok then return TFC.UI.Notify(src, { title = 'Weapons', description = 'Make room in your inventory first.', type = 'error' }) end
    end

    local meta = Inv.Copy(item.metadata) or {}
    meta.mods = nil
    if extra > 0 then meta.ammo = baseClip end
    Inv.SetMetadata(inv, slot, meta)
    InvSrv.sync(inv)
    for _, key in ipairs(list) do InvSrv.AddItem(src, WeaponMods.Types[key].item, 1, nil, nil, 'removed from ' .. def.label) end
    if extra > 0 and def.ammo then InvSrv.AddItem(src, def.ammo, extra, nil, nil, 'unloaded extended magazine') end

    TriggerClientEvent('tfc-inventory:client:weaponUpdate', src, { components = {}, clip = baseClip, ammo = extra > 0 and baseClip or nil })
    TFC.UI.Notify(src, { title = 'Weapons', description = ('Took %d mod(s) off your %s.'):format(#list, def.label), type = 'success' })
end)

TFC.Callback.Register('weapons:holster', function(src)
    equipped[src] = nil
    return { ok = true }
end, { rateLimit = 100 })

TFC.On('playerUnloaded', function(src)
    equipped[src] = nil
end)

AddEventHandler('playerDropped', function()
    equipped[tonumber(source)] = nil
end)
