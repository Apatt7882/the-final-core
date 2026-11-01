-- The Final Core: shared bootstrap.
-- Runs inside tfc-core and inside every resource that imports @tfc-core/import.lua,
-- so each resource gets its own TFC table in its own Lua state.

---@type TFC
TFC = TFC or {}

TFC.Name = 'The Final Core'
TFC.CoreResource = 'tfc-core'
TFC.Resource = GetCurrentResourceName()
TFC.IsServer = IsDuplicityVersion()
TFC.Context = TFC.IsServer and 'server' or 'client'
TFC.Version = GetResourceMetadata(TFC.CoreResource, 'version', 0) or '0.0.0'
