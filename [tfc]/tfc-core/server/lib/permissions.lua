-- Permissions (phase 4c). TFC uses FiveM ACE, so txAdmin, server.cfg and other scripts all agree.
--
-- server.cfg:
--   add_ace group.admin tfc.admin allow                        # everything admin in TFC
--   add_ace group.mod tfc.mod allow                            # moderator features (future)
--   add_principal identifier.license:<license> group.admin     # make someone an admin
--
-- The server console (source 0) always has every permission.

TFC.Permissions = {
    Admin = 'tfc.admin',
    Mod = 'tfc.mod',
}

---@param src integer
---@param permission string ACE object, e.g. 'tfc.admin'
---@return boolean
function TFC.HasPermission(src, permission)
    src = tonumber(src) or -1
    if src == 0 then return true end
    if src < 0 then return false end
    return IsPlayerAceAllowed(tostring(src), permission)
end

---@param src integer
---@return boolean
function TFC.IsAdmin(src)
    return TFC.HasPermission(src, TFC.Permissions.Admin)
end
