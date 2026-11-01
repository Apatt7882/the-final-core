-- The player object: one per loaded character. Lives only in tfc-core; other resources
-- get a proxy (server/lib/player.lua) whose method calls are forwarded here.
-- Methods starting with _ are internal and cannot be called through the proxy.

---@class TFCPlayer
---@field source integer
---@field userId integer
---@field license string
---@field character table
---@field _dirty boolean
---@field _lastSavedPos table|nil
---@field _cachedPos table|nil
local PlayerClass = {}
PlayerClass.__index = PlayerClass
TFC.PlayerClass = PlayerClass

---@param src integer
---@param user { id: integer, license: string }
---@param character table row from TFC.Characters.Get
---@return TFCPlayer
function PlayerClass.new(src, user, character)
    return setmetatable({
        source = src,
        userId = user.id,
        license = user.license,
        character = character,
        _dirty = false,
        _lastSavedPos = character.position,
        _cachedPos = character.position,
    }, PlayerClass)
end

---@return integer
function PlayerClass:GetSource() return self.source end
---@return integer
function PlayerClass:GetUserId() return self.userId end
---@return integer
function PlayerClass:GetCharacterId() return self.character.id end
---@return string
function PlayerClass:GetCid() return self.character.cid end
---@return integer
function PlayerClass:GetSlot() return self.character.slot end
---@return string
function PlayerClass:GetFirstName() return self.character.firstname end
---@return string
function PlayerClass:GetLastName() return self.character.lastname end
---@return string
function PlayerClass:GetFullName() return ('%s %s'):format(self.character.firstname, self.character.lastname) end
---@return string|nil YYYY-MM-DD
function PlayerClass:GetDob() return self.character.dob end
---@return 'm'|'f'|nil
function PlayerClass:GetSex() return self.character.sex end

---Private, persistent data for this character. Sent only to the owning client.
---@param key? string omit to get the whole table
---@return any
function PlayerClass:GetMetadata(key)
    if key == nil then return self.character.metadata end
    return self.character.metadata[key]
end

---Set a metadata value. Saved with the next batch, synced to the owning client,
---and emits the server hook metadataChanged(source, key, value, old).
---@param key string
---@param value any must be JSON-serialisable; nil removes the key
function PlayerClass:SetMetadata(key, value)
    if type(key) ~= 'string' or key == '' then
        error('metadata key must be a non-empty string', 2)
    end

    local old = self.character.metadata[key]
    if old == value and type(value) ~= 'table' then return end

    self.character.metadata[key] = value
    self._dirty = true
    TriggerClientEvent('tfc:client:metadataChanged', self.source, key, value)
    TFC.Emit('metadataChanged', self.source, key, value, old)
end

---Public, non-persistent value every client can read through state bags as 'tfc:<key>'.
---@param key string
---@param value any
function PlayerClass:SetState(key, value)
    if type(key) ~= 'string' or key == '' then
        error('state key must be a non-empty string', 2)
    end
    TFC.Adapter.SetPublicState(self.source, 'tfc:' .. key, value)
end

---@param key string
---@return any
function PlayerClass:GetState(key)
    return TFC.Adapter.GetPublicState(self.source, 'tfc:' .. key)
end

---Live position, or the last known one if the ped isn't available.
---@return { x: number, y: number, z: number, w: number }|nil
function PlayerClass:GetPosition()
    return TFC.Adapter.GetPosition(self.source) or self._cachedPos
end

---Save now instead of waiting for the next batch.
---@return integer saved number of characters written (0 or 1)
function PlayerClass:Save()
    return TFC.SavePlayers({ self }, { force = true })
end

---Plain data sent to clients and returned by exports.
---@return table
function PlayerClass:Serialize()
    local c = self.character
    return {
        source = self.source,
        userId = self.userId,
        characterId = c.id,
        cid = c.cid,
        slot = c.slot,
        firstname = c.firstname,
        lastname = c.lastname,
        dob = c.dob,
        sex = c.sex,
        metadata = c.metadata,
    }
end
