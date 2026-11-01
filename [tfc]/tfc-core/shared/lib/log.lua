-- Prefixed, levelled logging. Debug lines only print when the tfc_debug convar is 1.

local prefix = ('^5[%s]^7'):format(TFC.Resource)

local function debugEnabled()
    return GetConvarInt('tfc_debug', 0) == 1
end

---@param color string
---@param level string
---@param msg any
local function write(color, level, msg, ...)
    msg = tostring(msg)
    if select('#', ...) > 0 then
        msg = msg:format(...)
    end
    print(('%s %s%s^7 %s'):format(prefix, color, level, msg))
end

TFC.Log = {}

---@param msg any
---@param ... any format arguments
function TFC.Log.Debug(msg, ...)
    if debugEnabled() then write('^6', 'DEBUG', msg, ...) end
end

---@param msg any
---@param ... any format arguments
function TFC.Log.Info(msg, ...)
    write('^2', 'INFO', msg, ...)
end

---@param msg any
---@param ... any format arguments
function TFC.Log.Warn(msg, ...)
    write('^3', 'WARN', msg, ...)
end

---@param msg any
---@param ... any format arguments
function TFC.Log.Error(msg, ...)
    write('^1', 'ERROR', msg, ...)
end
