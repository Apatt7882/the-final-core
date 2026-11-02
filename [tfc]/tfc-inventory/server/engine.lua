-- Inventory engine: pure data operations on inventories (no database, no networking).
-- An inventory is { id, type, label, slots, maxWeight, weight, items = { [slot] = item }, dirty }
-- and an item is { name, count, metadata? }. Empty metadata is always stored as nil, so two
-- items with "no metadata" compare equal and stack.

Inv = { list = {} }

local INF = math.huge

-- Helpers ----------------------------------------------------------------------------------

local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

---nil for nil/empty tables, otherwise a deep copy.
local function cleanMeta(meta)
    if type(meta) ~= 'table' or next(meta) == nil then return nil end
    return copy(meta)
end

local function equal(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do
        if not equal(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

Inv.Copy = copy
Inv.CleanMeta = cleanMeta
Inv.MetaEqual = equal

---@param name string
function Inv.Def(name)
    return Items[name]
end

local function maxStack(def)
    if not def.stack then return 1 end
    return def.maxStack or INF
end

---Weight of `count` units (metadata.weight, if set, overrides the item's weight per unit).
function Inv.ItemWeight(name, count, metadata)
    local def = Items[name]
    local per = (metadata and tonumber(metadata.weight)) or (def and def.weight) or 0
    return per * count
end

local function validCount(n)
    n = tonumber(n)
    if not n or n ~= n or n < 1 or math.floor(n) ~= n then return nil end
    return math.tointeger(n)
end
Inv.ValidCount = validCount

-- Lifecycle --------------------------------------------------------------------------------

function Inv.Create(id, kind, label, slots, maxWeight, items)
    local inv = {
        id = id,
        type = kind,
        label = label,
        slots = slots,
        maxWeight = maxWeight,
        items = items or {},
        weight = 0,
        dirty = false,
    }
    Inv.Recalc(inv)
    Inv.list[id] = inv
    return inv
end

function Inv.Get(id)
    return Inv.list[id]
end

function Inv.Remove(id)
    Inv.list[id] = nil
end

function Inv.Recalc(inv)
    local w = 0
    for _, item in pairs(inv.items) do
        w = w + Inv.ItemWeight(item.name, item.count, item.metadata)
    end
    inv.weight = w
end

-- Queries ----------------------------------------------------------------------------------

---Units of `name` in the inventory (only those with matching metadata, if given).
function Inv.Count(inv, name, metadata)
    local total = 0
    for _, item in pairs(inv.items) do
        if item.name == name and (metadata == nil or equal(item.metadata, cleanMeta(metadata))) then
            total = total + item.count
        end
    end
    return total
end

---Slots holding `name`, in slot order.
function Inv.Find(inv, name)
    local found = {}
    for slot = 1, inv.slots do
        local item = inv.items[slot]
        if item and item.name == name then
            found[#found + 1] = { slot = slot, count = item.count, metadata = copy(item.metadata) }
        end
    end
    return found
end

---Work out where `count` units would go, without changing anything.
---@return table|nil plan list of { slot, add }
---@return string|nil err
local function plan(inv, name, count, metadata, preferSlot)
    local def = Items[name]
    local max = maxStack(def)
    local steps, remaining = {}, count

    if preferSlot then
        if preferSlot < 1 or preferSlot > inv.slots then return nil, 'invalid slot' end
        local here = inv.items[preferSlot]
        if not here then
            if count > max then return nil, 'that slot cannot hold that many' end
            return { { slot = preferSlot, add = count } }
        end
        if def.stack and here.name == name and equal(here.metadata, metadata) and here.count + count <= max then
            return { { slot = preferSlot, add = count } }
        end
        return nil, 'that slot is taken'
    end

    -- Top up matching stacks first.
    if def.stack then
        for slot = 1, inv.slots do
            local here = inv.items[slot]
            if remaining == 0 then break end
            if here and here.name == name and equal(here.metadata, metadata) and here.count < max then
                local n = math.min(remaining, max - here.count)
                steps[#steps + 1] = { slot = slot, add = n }
                remaining = remaining - n
            end
        end
    end

    -- Then empty slots.
    for slot = 1, inv.slots do
        if remaining == 0 then break end
        if not inv.items[slot] then
            local n = math.min(remaining, max)
            steps[#steps + 1] = { slot = slot, add = n }
            remaining = remaining - n
        end
    end

    if remaining > 0 then return nil, 'not enough space' end
    return steps
end

---@return boolean ok
---@return string|nil err
function Inv.CanFit(inv, name, count, metadata, slot)
    if not Items[name] then return false, ('unknown item "%s"'):format(tostring(name)) end
    count = validCount(count)
    if not count then return false, 'count must be a whole number above 0' end
    if inv.weight + Inv.ItemWeight(name, count, metadata) > inv.maxWeight then return false, 'too heavy' end
    local steps, err = plan(inv, name, count, cleanMeta(metadata), slot)
    if not steps then return false, err end
    return true
end

-- Changes ----------------------------------------------------------------------------------

---@return boolean ok
---@return string|nil err
function Inv.Add(inv, name, count, metadata, slot)
    local def = Items[name]
    if not def then return false, ('unknown item "%s"'):format(tostring(name)) end
    count = validCount(count)
    if not count then return false, 'count must be a whole number above 0' end

    metadata = cleanMeta(metadata)
    if inv.weight + Inv.ItemWeight(name, count, metadata) > inv.maxWeight then return false, 'too heavy' end

    local steps, err = plan(inv, name, count, metadata, slot)
    if not steps then return false, err end

    for _, step in ipairs(steps) do
        local here = inv.items[step.slot]
        if here then
            here.count = here.count + step.add
        else
            inv.items[step.slot] = { name = name, count = step.add, metadata = copy(metadata) }
        end
    end

    Inv.Recalc(inv)
    inv.dirty = true
    return true
end

---Remove `count` units. With `slot`, only from that slot; otherwise from the last slots first
---(so the hotbar empties last). With `metadata`, only matching items.
function Inv.RemoveItem(inv, name, count, metadata, slot)
    count = validCount(count)
    if not count then return false, 'count must be a whole number above 0' end
    local wanted = metadata ~= nil and cleanMeta(metadata) or nil
    local matchAny = metadata == nil

    local function matches(item)
        return item and item.name == name and (matchAny or equal(item.metadata, wanted))
    end

    if slot then
        local item = inv.items[slot]
        if not matches(item) then return false, 'that item is not in that slot' end
        if item.count < count then return false, ('only %d in that slot'):format(item.count) end
        item.count = item.count - count
        if item.count == 0 then inv.items[slot] = nil end
    else
        local have = 0
        for _, item in pairs(inv.items) do
            if matches(item) then have = have + item.count end
        end
        if have < count then return false, ('not enough %s'):format((Items[name] and Items[name].label or name):lower()) end

        local remaining = count
        for s = inv.slots, 1, -1 do
            local item = inv.items[s]
            if remaining == 0 then break end
            if matches(item) then
                local n = math.min(remaining, item.count)
                item.count = item.count - n
                remaining = remaining - n
                if item.count == 0 then inv.items[s] = nil end
            end
        end
    end

    Inv.Recalc(inv)
    inv.dirty = true
    return true
end

---Move, merge, split or swap between two slots (possibly in different inventories).
---@return boolean ok
---@return string|nil err
function Inv.Move(from, fromSlot, to, toSlot, count)
    fromSlot, toSlot = math.tointeger(tonumber(fromSlot)), math.tointeger(tonumber(toSlot))
    if not fromSlot or fromSlot < 1 or fromSlot > from.slots then return false, 'invalid slot' end
    if not toSlot or toSlot < 1 or toSlot > to.slots then return false, 'invalid slot' end

    local item = from.items[fromSlot]
    if not item then return false, 'that slot is empty' end
    if from == to and fromSlot == toSlot then return true end

    count = validCount(count) or item.count
    if count > item.count then count = item.count end

    local def = Items[item.name]
    local crossing = from ~= to
    local target = to.items[toSlot]

    if not target then
        if crossing and to.weight + Inv.ItemWeight(item.name, count, item.metadata) > to.maxWeight then
            return false, 'too heavy'
        end
        to.items[toSlot] = { name = item.name, count = count, metadata = copy(item.metadata) }
        item.count = item.count - count
        if item.count == 0 then from.items[fromSlot] = nil end

    elseif def.stack and target.name == item.name and equal(target.metadata, item.metadata) then
        local room = maxStack(def) - target.count
        if room <= 0 then return false, 'that stack is full' end
        local n = math.min(count, room)
        if crossing and to.weight + Inv.ItemWeight(item.name, n, item.metadata) > to.maxWeight then
            return false, 'too heavy'
        end
        target.count = target.count + n
        item.count = item.count - n
        if item.count == 0 then from.items[fromSlot] = nil end

    else
        -- Different items: swap whole stacks.
        if count ~= item.count then return false, 'move the whole stack to swap items' end
        if crossing then
            local wItem = Inv.ItemWeight(item.name, item.count, item.metadata)
            local wTarget = Inv.ItemWeight(target.name, target.count, target.metadata)
            if to.weight - wTarget + wItem > to.maxWeight then return false, 'too heavy' end
            if from.weight - wItem + wTarget > from.maxWeight then return false, 'too heavy' end
        end
        to.items[toSlot], from.items[fromSlot] = item, target
    end

    Inv.Recalc(from)
    from.dirty = true
    if crossing then
        Inv.Recalc(to)
        to.dirty = true
    end
    return true
end

function Inv.SetMetadata(inv, slot, metadata)
    local item = inv.items[slot]
    if not item then return false, 'that slot is empty' end
    item.metadata = cleanMeta(metadata)
    Inv.Recalc(inv)
    inv.dirty = true
    return true
end

function Inv.Clear(inv, keep)
    for slot, item in pairs(inv.items) do
        if not (keep and keep[item.name]) then inv.items[slot] = nil end
    end
    Inv.Recalc(inv)
    inv.dirty = true
end

-- Views and storage ------------------------------------------------------------------------

---Client-friendly copy: items as an array (no sparse tables over the network).
function Inv.View(inv)
    local items = {}
    for slot = 1, inv.slots do
        local item = inv.items[slot]
        if item then
            items[#items + 1] = { slot = slot, name = item.name, count = item.count, metadata = copy(item.metadata) }
        end
    end
    return {
        id = inv.id,
        type = inv.type,
        label = inv.label,
        slots = inv.slots,
        maxWeight = inv.maxWeight,
        weight = inv.weight,
        items = items,
    }
end

function Inv.Serialize(inv)
    local items = {}
    for slot = 1, inv.slots do
        local item = inv.items[slot]
        if item then
            items[#items + 1] = { slot = slot, name = item.name, count = item.count, metadata = item.metadata }
        end
    end
    return json.encode(items)
end

---Parse stored items, dropping anything invalid (unknown item, bad slot) with a warning.
function Inv.Deserialize(raw, slots, id)
    local items = {}
    if not raw or raw == '' then return items end
    local ok, list = pcall(json.decode, raw)
    if not ok or type(list) ~= 'table' then
        TFC.Log.Error('inventory %s has unreadable data; starting empty', id)
        return items
    end
    for _, it in ipairs(list) do
        local slot, count = math.tointeger(tonumber(it.slot)), validCount(it.count)
        if not Items[it.name] then
            TFC.Log.Warn('inventory %s: dropped unknown item "%s" x%s', id, tostring(it.name), tostring(it.count))
        elseif slot and count and slot >= 1 and slot <= slots and not items[slot] then
            items[slot] = { name = it.name, count = count, metadata = cleanMeta(it.metadata) }
        end
    end
    return items
end
