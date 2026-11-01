-- Characters: storage only. Validation of who may load what lives in server/player.
-- Never put nil inside a parameter list (it breaks the array sent to oxmysql);
-- pass '' and use NULLIF in the SQL instead.

TFC.Characters = {}

local CID_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' -- no 0/O or 1/I
local SELECT_COLUMNS = [[
    id, cid, user_id, slot, firstname, lastname,
    DATE_FORMAT(dob, '%Y-%m-%d') AS dob, sex, position, metadata,
    UNIX_TIMESTAMP(last_played) AS last_played
]]

---@param s string|nil
local function decode(s)
    if not s or s == '' then return nil end
    local ok, value = pcall(json.decode, s)
    return ok and value or nil
end

---@param row table|nil
local function hydrate(row)
    if not row then return nil end
    row.position = decode(row.position)
    row.metadata = decode(row.metadata) or {}
    return row
end

local function generateCid()
    for _ = 1, 10 do
        local chars = {}
        for i = 1, 8 do
            local n = math.random(#CID_CHARS)
            chars[i] = CID_CHARS:sub(n, n)
        end
        local cid = table.concat(chars)
        if not MySQL.scalar.await('SELECT 1 FROM tfc_characters WHERE cid = ?', { cid }) then
            return cid
        end
    end
    error('could not generate a unique cid')
end

---Characters for a user, ordered by slot.
---@param userId integer
---@return table[]
function TFC.Characters.ListForUser(userId)
    local rows = MySQL.query.await(('SELECT %s FROM tfc_characters WHERE user_id = ? ORDER BY slot'):format(SELECT_COLUMNS), { userId }) or {}
    for _, row in ipairs(rows) do hydrate(row) end
    return rows
end

---@param charId integer
---@return table|nil
function TFC.Characters.Get(charId)
    return hydrate(MySQL.single.await(('SELECT %s FROM tfc_characters WHERE id = ?'):format(SELECT_COLUMNS), { charId }))
end

---Lowest free slot, or nil when the user is at Config.MaxCharacters.
---@param userId integer
---@return integer|nil
function TFC.Characters.FreeSlot(userId)
    local max = math.min(TFC.Config.MaxCharacters, 10)
    local used = {}
    for _, row in ipairs(MySQL.query.await('SELECT slot FROM tfc_characters WHERE user_id = ?', { userId }) or {}) do
        used[row.slot] = true
    end
    for slot = 1, max do
        if not used[slot] then return slot end
    end
    return nil
end

---Insert a character. Data must already be validated.
---@param userId integer
---@param slot integer
---@param data { firstname: string, lastname: string, dob?: string, sex?: string }
---@return integer charId
function TFC.Characters.Insert(userId, slot, data)
    return MySQL.insert.await([[
        INSERT INTO tfc_characters (cid, user_id, slot, firstname, lastname, dob, sex, metadata)
        VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), '{}')
    ]], { generateCid(), userId, slot, data.firstname, data.lastname, data.dob or '', data.sex or '' })
end

---Build the save query for one character (used for batched transactions).
---@param charId integer
---@param metadata table
---@param position table|nil
function TFC.Characters.SaveQuery(charId, metadata, position)
    return {
        query = "UPDATE tfc_characters SET metadata = ?, position = COALESCE(NULLIF(?, ''), position), last_played = CURRENT_TIMESTAMP WHERE id = ?",
        values = { json.encode(metadata), position and json.encode(position) or '', charId },
    }
end
