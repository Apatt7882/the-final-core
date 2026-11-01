-- Player lifecycle: connect -> clientReady -> character select or auto-load -> drop.
-- Server hooks: characterSelect(source, userId), playerLoaded(source, cid), playerUnloaded(source, cid)

---@type table<integer, { id: integer, license: string }>
local sessions = {}
---@type table<integer, boolean>
local loading = {}

local REQUIRED_LICENSE = 'A Rockstar license is required to join. Restart FiveM, make sure you are signed in to Rockstar, and try again.'

---@param v any
---@return string|nil
local function cleanName(v)
    if type(v) ~= 'string' then return nil end
    v = v:match('^%s*(.-)%s*$')
    if #v < 1 or #v > 32 or not v:match("^%a[%a%s'%-]*$") then return nil end
    return v
end

---@param data any
---@return table|nil clean
---@return string|nil err
local function validateCharacter(data)
    if type(data) ~= 'table' then return nil, 'character data must be a table' end

    local firstname, lastname = cleanName(data.firstname), cleanName(data.lastname)
    if not firstname or not lastname then
        return nil, 'names must be 1-32 letters (spaces, hyphens and apostrophes allowed)'
    end

    if data.dob ~= nil and (type(data.dob) ~= 'string' or not data.dob:match('^%d%d%d%d%-%d%d%-%d%d$')) then
        return nil, 'dob must be YYYY-MM-DD'
    end

    if data.sex ~= nil and data.sex ~= 'm' and data.sex ~= 'f' then
        return nil, "sex must be 'm' or 'f'"
    end

    return { firstname = firstname, lastname = lastname, dob = data.dob, sex = data.sex }
end

---Upsert the user row and linked identifiers.
---@param src integer
---@return integer|nil userId
---@return string|nil license
local function resolveUser(src)
    local license = TFC.Adapter.GetIdentifier(src, 'license')
    if not license then return nil end

    local userId = TFC.Users.Upsert(license, TFC.Adapter.GetName(src))
    TFC.Users.SyncIdentifiers(userId, src)
    return userId, license
end

-- Character API --------------------------------------------------------------

---Summaries of this player's characters, ordered by slot.
---@param src integer
---@return table[]
function TFC.GetCharacters(src)
    local session = sessions[tonumber(src)]
    if not session then return {} end

    local list = {}
    for i, c in ipairs(TFC.Characters.ListForUser(session.id)) do
        list[i] = {
            id = c.id, cid = c.cid, slot = c.slot,
            firstname = c.firstname, lastname = c.lastname,
            dob = c.dob, sex = c.sex, lastPlayed = c.last_played,
        }
    end
    return list
end

---@param src integer
---@param data { firstname: string, lastname: string, dob?: string, sex?: 'm'|'f' }
---@return integer|nil charId
---@return string|nil err
function TFC.CreateCharacter(src, data)
    src = tonumber(src) --[[@as integer]]
    local session = sessions[src]
    if not session then return nil, 'player has no session' end

    local clean, err = validateCharacter(data)
    if not clean then return nil, err end

    local slot = TFC.Characters.FreeSlot(session.id)
    if not slot then
        return nil, ('character limit reached (%d)'):format(math.min(TFC.Config.MaxCharacters, 10))
    end

    local charId = TFC.Characters.Insert(session.id, slot, clean)
    TFC.Log.Info('player %d created character %s %s (slot %d)', src, clean.firstname, clean.lastname, slot)
    return charId
end

---Permanently delete one of this player's characters (not the one currently loaded).
---Emits characterDeleted(source, cid).
---@param src integer
---@param charId integer
---@return boolean ok
---@return string|nil err
function TFC.DeleteCharacter(src, charId)
    src = tonumber(src) --[[@as integer]]
    local session = sessions[src]
    if not session then return false, 'player has no session' end

    local character = TFC.Characters.Get(tonumber(charId))
    if not character or character.user_id ~= session.id then
        return false, 'character not found'
    end

    local loaded = TFC.GetPlayer(src)
    if loaded and loaded.character.id == character.id then
        return false, 'cannot delete the character you are playing'
    end

    if not TFC.Characters.Delete(character.id) then
        return false, 'delete failed'
    end

    TFC.Log.Info('player %d deleted character %s %s (%s)', src, character.firstname, character.lastname, character.cid)
    TFC.Emit('characterDeleted', src, character.cid)
    return true
end

---Save and remove the loaded character.
---@param src integer
---@param opts? { dropped?: boolean }
---@return boolean
function TFC.UnloadCharacter(src, opts)
    src = tonumber(src) --[[@as integer]]
    local p = TFC.GetPlayer(src)
    if not p then return false end

    TFC.SavePlayers({ p }, { force = true })
    TFC.RemovePlayer(src)

    if not (opts and opts.dropped) then
        TFC.Adapter.SetPublicState(src, 'tfc:loaded', false)
        TFC.Adapter.SetPublicState(src, 'tfc:cid', nil)
        TFC.Adapter.SetPublicState(src, 'tfc:name', nil)
        TriggerClientEvent('tfc:client:playerUnloaded', src)
    end

    TFC.Emit('playerUnloaded', src, p.character.cid)
    return true
end

---Load one of this player's characters (unloading the current one first).
---@param src integer
---@param charId integer
---@return boolean ok
---@return string|nil err
function TFC.LoadCharacter(src, charId)
    src = tonumber(src) --[[@as integer]]
    local session = sessions[src]
    if not session then return false, 'player has no session' end

    local character = TFC.Characters.Get(tonumber(charId))
    if not character or character.user_id ~= session.id then
        return false, 'character not found'
    end

    -- The player may have dropped while we were querying.
    if not sessions[src] then return false, 'player left' end

    if TFC.GetPlayer(src) then TFC.UnloadCharacter(src) end

    local p = TFC.PlayerClass.new(src, session, character)
    TFC.AddPlayer(p)

    TFC.Adapter.SetPublicState(src, 'tfc:loaded', true)
    TFC.Adapter.SetPublicState(src, 'tfc:cid', character.cid)
    TFC.Adapter.SetPublicState(src, 'tfc:name', p:GetFullName())

    TriggerClientEvent('tfc:client:playerLoaded', src, p:Serialize(), character.position or TFC.Config.DefaultSpawn)
    TFC.Log.Info('%s loaded %s (%s)', TFC.Adapter.GetName(src) or src, p:GetFullName(), character.cid)
    TFC.Emit('playerLoaded', src, character.cid)
    return true
end

-- Lifecycle events -------------------------------------------------------------

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update(('%s: checking your account...'):format(TFC.Name))

    if not TFC.Adapter.GetIdentifier(src, 'license') then
        deferrals.done(REQUIRED_LICENSE)
        return
    end

    if not TFC.DB.AwaitReady() then
        deferrals.done('The server database is not ready yet. Please try again in a minute.')
        return
    end

    local ok, err = pcall(resolveUser, src)
    if not ok then
        TFC.Log.Error('account check failed for %s: %s', GetPlayerName(src) or src, err)
        deferrals.done('Could not load your account. Please try again.')
        return
    end

    deferrals.done()
end)

-- Sent by the client once its session has started (and again if tfc-core restarts).
TFC.OnNet('tfc:server:clientReady', function(src)
    if loading[src] or TFC.GetPlayer(src) then return end
    loading[src] = true

    local ok, err = pcall(function()
        if not TFC.DB.AwaitReady() then error('database not ready') end

        -- The user row was written at connect; only create it here if it's somehow missing.
        local license = TFC.Adapter.GetIdentifier(src, 'license')
        if not license then error('no Rockstar license') end
        local user = TFC.Users.GetByLicense(license)
        local userId = user and user.id or resolveUser(src)
        if not userId then error('could not resolve user') end
        sessions[src] = { id = userId, license = license --[[@as string]] }

        if TFC.Modules.IsReady('multichar') then
            TFC.Emit('characterSelect', src, userId)
            return
        end

        if not TFC.Config.AutoLoadCharacter then
            TFC.Log.Warn('player %d is waiting: no multichar module and AutoLoadCharacter is off', src)
            return
        end

        local characters = TFC.Characters.ListForUser(userId)
        local charId = characters[1] and characters[1].id
        if not charId then
            charId = assert(TFC.CreateCharacter(src, TFC.Config.DevCharacter))
        end

        local loaded, loadErr = TFC.LoadCharacter(src, charId)
        if not loaded then error(loadErr) end
    end)

    loading[src] = nil
    if not ok then
        TFC.Log.Error('could not load player %d: %s', src, err)
    end
end, { rateLimit = 2000 })

AddEventHandler('playerDropped', function()
    local src = tonumber(source) --[[@as integer]]
    TFC.UnloadCharacter(src, { dropped = true })
    sessions[src] = nil
    loading[src] = nil
end)

-- Lets client-side importers fetch the current data after they restart mid-session.
TFC.Callback.Register('tfc:core:getPlayerData', function(src)
    local p = TFC.GetPlayer(src)
    return p and p:Serialize() or nil
end)

-- Exports ----------------------------------------------------------------------

exports('GetCharacters', TFC.GetCharacters)
exports('CreateCharacter', TFC.CreateCharacter)
exports('LoadCharacter', TFC.LoadCharacter)
exports('DeleteCharacter', TFC.DeleteCharacter)
exports('UnloadCharacter', function(src) return TFC.UnloadCharacter(src) end)

---@param src integer
---@return integer|nil userId
exports('GetUserId', function(src)
    local session = sessions[tonumber(src)]
    return session and session.id or nil
end)
