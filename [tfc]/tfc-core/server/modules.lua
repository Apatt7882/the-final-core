-- Module loader.
-- A module is any resource that calls TFC.RegisterModule. The core tracks its version
-- and dependencies, marks it ready once every dependency is ready, and emits hooks:
--   moduleReady(name, resource)   moduleStopped(name, resource)

---@class TFCModuleEntry
---@field name string
---@field version string
---@field resource string
---@field dependencies table<string, string> module name -> version constraint
---@field state 'waiting'|'ready'

---@type table<string, TFCModuleEntry>
local modules = {}
---@type table<string, string> resource -> module name
local byResource = {}

---@param v string
---@return integer[]
local function parseVersion(v)
    local a, b, c = tostring(v):match('^(%d+)%.?(%d*)%.?(%d*)')
    return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

---@return integer -1, 0 or 1
local function compareVersions(a, b)
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
    end
    return 0
end

---Supports '*', '1.2.0', '=1.2.0', '>=1.2.0', '>1.2.0', '<=1.2.0', '<1.2.0'.
---@param version string
---@param constraint string
local function satisfies(version, constraint)
    if constraint == '*' or constraint == '' then return true end

    local op, want = constraint:match('^%s*([<>=]*)%s*(.-)%s*$')
    local c = compareVersions(parseVersion(version), parseVersion(want))

    if op == '>=' then return c >= 0 end
    if op == '>' then return c > 0 end
    if op == '<=' then return c <= 0 end
    if op == '<' then return c < 0 end
    return c == 0
end

---Accepts { 'accounts', jobs = '>=0.2.0' }.
---@return table<string, string>
local function normalizeDependencies(deps)
    local out = {}
    for k, v in pairs(deps or {}) do
        if type(k) == 'number' then
            out[tostring(v)] = '*'
        else
            out[k] = tostring(v)
        end
    end
    return out
end

---@param entry TFCModuleEntry
---@return string[]
local function unmetDependencies(entry)
    local unmet = {}
    for dep, constraint in pairs(entry.dependencies) do
        local d = modules[dep]
        if not d or d.state ~= 'ready' then
            unmet[#unmet + 1] = dep
        elseif not satisfies(d.version, constraint) then
            unmet[#unmet + 1] = ('%s %s (found %s)'):format(dep, constraint, d.version)
        end
    end
    return unmet
end

---@param entry TFCModuleEntry
local function markReady(entry)
    entry.state = 'ready'
    TFC.Log.Info('module ^5%s^7 v%s ready (%s)', entry.name, entry.version, entry.resource)
    TFC.Emit('moduleReady', entry.name, entry.resource)
end

-- Readiness can cascade: A ready -> B ready -> C ready.
local function resolveWaiting()
    local progressed = true
    while progressed do
        progressed = false
        for _, entry in pairs(modules) do
            if entry.state == 'waiting' and #unmetDependencies(entry) == 0 then
                markReady(entry)
                progressed = true
            end
        end
    end
end

---@param entry TFCModuleEntry
local function copy(entry)
    local deps = {}
    for k, v in pairs(entry.dependencies) do deps[k] = v end
    return {
        name = entry.name,
        version = entry.version,
        resource = entry.resource,
        dependencies = deps,
        state = entry.state,
    }
end

---@param def TFCModuleDefinition
---@return boolean ok
---@return string stateOrError 'ready', 'waiting' or an error message
local function registerModule(def)
    local resource = GetInvokingResource() or TFC.Resource

    if type(def) ~= 'table' or type(def.name) ~= 'string' or not def.name:match('^[%w_%-]+$') then
        return false, 'invalid module definition: name must use letters, numbers, _ or -'
    end

    local existing = modules[def.name]
    if existing and existing.resource ~= resource then
        return false, ('module "%s" is already registered by %s'):format(def.name, existing.resource)
    end

    ---@type TFCModuleEntry
    local entry = {
        name = def.name,
        version = tostring(def.version or '0.0.0'),
        resource = resource,
        dependencies = normalizeDependencies(def.dependencies),
        state = 'waiting',
    }

    modules[entry.name] = entry
    byResource[resource] = entry.name

    local unmet = unmetDependencies(entry)
    if #unmet == 0 then
        markReady(entry)
        resolveWaiting()
    else
        TFC.Log.Warn('module ^5%s^7 waiting on: %s', entry.name, table.concat(unmet, ', '))
    end

    return true, entry.state
end

AddEventHandler('onResourceStop', function(resource)
    local name = byResource[resource]
    if not name then return end

    byResource[resource] = nil
    modules[name] = nil
    TFC.Log.Info('module ^5%s^7 stopped', name)
    TFC.Emit('moduleStopped', name, resource)

    for _, entry in pairs(modules) do
        if entry.state == 'ready' and entry.dependencies[name] then
            entry.state = 'waiting'
            TFC.Log.Warn('module ^5%s^7 lost dependency %s and is waiting again', entry.name, name)
        end
    end
end)

exports('RegisterModule', registerModule)

---@param name string
---@return table|nil
exports('GetModule', function(name)
    local entry = modules[name]
    return entry and copy(entry) or nil
end)

---@param name string
---@return boolean
exports('IsModuleReady', function(name)
    local entry = modules[name]
    return entry ~= nil and entry.state == 'ready'
end)

---@return table[]
local function getModules()
    local list = {}
    for _, entry in pairs(modules) do list[#list + 1] = copy(entry) end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end
exports('GetModules', getModules)

-- Used inside tfc-core (console command, lifecycle).
TFC.Modules = {
    List = getModules,
    ---@param name string
    IsReady = function(name)
        local entry = modules[name]
        return entry ~= nil and entry.state == 'ready'
    end,
}
