-- Client player data, available in tfc-core and every importing resource.
--   TFC.PlayerData                 nil until a character is loaded
--   TFC.OnPlayerLoaded(fn)         fn(data); runs immediately if already loaded
--   TFC.OnPlayerUnloaded(fn)
--   TFC.OnMetadataChanged(fn)      fn(key, value)

TFC.PlayerData = nil

local onLoaded, onUnloaded, onMetadata = {}, {}, {}

local function run(list, ...)
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then TFC.Log.Error('player handler failed: %s', err) end
    end
end

---@param fn fun(data: table)
function TFC.OnPlayerLoaded(fn)
    onLoaded[#onLoaded + 1] = fn
    if TFC.PlayerData then
        local ok, err = pcall(fn, TFC.PlayerData)
        if not ok then TFC.Log.Error('player handler failed: %s', err) end
    end
end

---@param fn fun()
function TFC.OnPlayerUnloaded(fn)
    onUnloaded[#onUnloaded + 1] = fn
end

---@param fn fun(key: string, value: any)
function TFC.OnMetadataChanged(fn)
    onMetadata[#onMetadata + 1] = fn
end

TFC.OnNet('tfc:client:playerLoaded', function(data)
    TFC.PlayerData = data
    run(onLoaded, data)
end)

TFC.OnNet('tfc:client:playerUnloaded', function()
    TFC.PlayerData = nil
    run(onUnloaded)
end)

TFC.OnNet('tfc:client:metadataChanged', function(key, value)
    if TFC.PlayerData then
        TFC.PlayerData.metadata[key] = value
    end
    run(onMetadata, key, value)
end)

-- A resource that (re)starts while a character is already loaded fetches the data once.
if TFC.Resource ~= TFC.CoreResource then
    CreateThread(function()
        if not LocalPlayer.state['tfc:loaded'] then return end

        local data = TFC.Callback.Await('tfc:core:getPlayerData')
        if data and not TFC.PlayerData then
            TFC.PlayerData = data
            run(onLoaded, data)
        end
    end)
end
