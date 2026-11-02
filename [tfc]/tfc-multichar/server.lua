-- Character select: the core asks us (characterSelect hook) and we drive the UI on the client.
-- All rules are enforced here and in tfc-core; the NUI page is never trusted.

local CORE = exports['tfc-core']

---@type table<integer, boolean> players currently on the select screen
local selecting = {}

TFC.RegisterModule({ name = 'multichar', version = '0.1.0' }, function()
    TFC.Log.Info('character select active')
end)

local function open(src)
    selecting[src] = true
    TriggerClientEvent('tfc-multichar:client:open', src)
end

TFC.On('characterSelect', function(src)
    open(src)
end)

AddEventHandler('playerDropped', function()
    selecting[tonumber(source)] = nil
end)

---@param dob string YYYY-MM-DD
---@return boolean
local function oldEnough(dob)
    local y, m, d = dob:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or m < 1 or m > 12 or d < 1 or d > 31 or y < 1900 then return false end

    local now = os.date('*t')
    local age = now.year - y
    if now.month < m or (now.month == m and now.day < d) then age = age - 1 end
    return age >= MulticharConfig.MinAge and age <= 120
end

-- Every callback answers with one table: { ok, error?, characters?, max? }

---@param src integer
local function result(src)
    return {
        ok = true,
        characters = CORE:GetCharacters(src),
        max = CORE:GetConfig('MaxCharacters'),
    }
end

---@param err string
local function fail(err)
    return { ok = false, error = err }
end

TFC.Callback.Register('multichar:getCharacters', function(src)
    if not selecting[src] then return fail('not on character select') end
    return result(src)
end, { rateLimit = 500 })

TFC.Callback.Register('multichar:create', function(src, data)
    if not selecting[src] then return fail('not on character select') end
    if type(data) ~= 'table' then return fail('invalid data') end

    if type(data.dob) ~= 'string' or not oldEnough(data.dob) then
        return fail(('date of birth must be valid and at least %d years ago'):format(MulticharConfig.MinAge))
    end
    if data.sex ~= 'm' and data.sex ~= 'f' then
        return fail('choose male or female')
    end

    local id, err = CORE:CreateCharacter(src, {
        firstname = data.firstname,
        lastname = data.lastname,
        dob = data.dob,
        sex = data.sex,
    })
    if not id then return fail(err) end

    return result(src)
end, { rateLimit = 1500 })

TFC.Callback.Register('multichar:delete', function(src, charId, confirmName)
    if not selecting[src] then return fail('not on character select') end

    local target
    for _, c in ipairs(CORE:GetCharacters(src)) do
        if c.id == charId then target = c break end
    end
    if not target then return fail('character not found') end

    local fullName = ('%s %s'):format(target.firstname, target.lastname)
    if type(confirmName) ~= 'string' or confirmName:lower():match('^%s*(.-)%s*$') ~= fullName:lower() then
        return fail('the name you typed does not match')
    end

    local ok, err = CORE:DeleteCharacter(src, charId)
    if not ok then return fail(err) end

    return result(src)
end, { rateLimit = 1500 })

TFC.Callback.Register('multichar:select', function(src, charId)
    if not selecting[src] then return fail('not on character select') end

    local ok, err = CORE:LoadCharacter(src, charId)
    if not ok then return fail(err) end

    selecting[src] = nil
    return { ok = true }
end, { rateLimit = 1500 })

if MulticharConfig.LogoutCommand then
    TFC.RegisterCommand(MulticharConfig.LogoutCommand, {
        help = 'Return to character select',
    }, function(src)
        if src == 0 or selecting[src] then return end
        if CORE:UnloadCharacter(src) then
            open(src)
        end
    end)
end
