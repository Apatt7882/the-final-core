-- Users: one row per Rockstar license, plus linked identifiers.

TFC.Users = {}

---Create the user if new, refresh name and last_seen if not. Returns the user id.
---@param license string
---@param name string|nil
---@return integer userId
function TFC.Users.Upsert(license, name)
    -- Update first: INSERT ... ON DUPLICATE KEY would burn an auto-increment id on every join.
    local existing = MySQL.scalar.await('SELECT id FROM tfc_users WHERE license = ?', { license })
    if existing then
        MySQL.update.await('UPDATE tfc_users SET name = ?, last_seen = CURRENT_TIMESTAMP WHERE id = ?', { name or '', existing })
        return existing
    end

    local ok, id = pcall(MySQL.insert.await, 'INSERT INTO tfc_users (license, name) VALUES (?, ?)', { license, name or '' })
    if ok and id then return id end

    -- Lost a race with another connect for the same license.
    return MySQL.scalar.await('SELECT id FROM tfc_users WHERE license = ?', { license })
end

---@param license string
---@return { id: integer, license: string, name: string }|nil
function TFC.Users.GetByLicense(license)
    return MySQL.single.await('SELECT id, license, name FROM tfc_users WHERE license = ?', { license })
end

---Record the linked identifiers (Config.LinkedIdentifiers) this player connected with.
---@param userId integer
---@param src integer
function TFC.Users.SyncIdentifiers(userId, src)
    local queries = {}
    for _, idType in ipairs(TFC.Config.LinkedIdentifiers) do
        local value = TFC.Adapter.GetIdentifier(src, idType)
        if value then
            queries[#queries + 1] = {
                query = [[
                    INSERT INTO tfc_user_identifiers (user_id, type, value) VALUES (?, ?, ?)
                    ON DUPLICATE KEY UPDATE last_seen = CURRENT_TIMESTAMP
                ]],
                values = { userId, idType, value },
            }
        end
    end

    if #queries > 0 then
        MySQL.transaction.await(queries)
    end
end

---Find every user that has ever connected with this identifier (for bans, lookups).
---@param idType string e.g. 'discord'
---@param value string without the 'discord:' prefix
---@return integer[] userIds
function TFC.Users.FindByIdentifier(idType, value)
    local rows = MySQL.query.await('SELECT user_id FROM tfc_user_identifiers WHERE type = ? AND value = ?', { idType, value })
    local ids = {}
    for i, row in ipairs(rows or {}) do ids[i] = row.user_id end
    return ids
end
