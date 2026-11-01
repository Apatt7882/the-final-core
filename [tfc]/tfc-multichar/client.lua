-- Character select scene, NUI bridge and spawn hand-off.

local cam
local inScene = false
local awaitingSpawn = false

local function setModel(sex)
    local model = joaat(MulticharConfig.Models[sex] or MulticharConfig.Models.m)
    if GetEntityModel(PlayerPedId()) == model then return end

    RequestModel(model)
    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then
        TFC.Log.Error('could not load model %s', MulticharConfig.Models[sex])
        return
    end

    SetPlayerModel(PlayerId(), model)
    SetPedDefaultComponentVariation(PlayerPedId())
    SetModelAsNoLongerNeeded(model)
end

-- Park the player hidden and frozen at the scene's focus point.
local function parkPed()
    local s = MulticharConfig.Scene
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, s.lookAt.x, s.lookAt.y, s.lookAt.z, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
end

local function startScene()
    if inScene then return end
    inScene = true

    local s = MulticharConfig.Scene
    DoScreenFadeOut(0)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    parkPed()

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', s.camera.x, s.camera.y, s.camera.z, 0.0, 0.0, 0.0, s.fov, false, 0)
    PointCamAtCoord(cam, s.lookAt.x, s.lookAt.y, s.lookAt.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    DisplayRadar(false)

    Wait(500)
    DoScreenFadeIn(800)
end

local function endScene()
    if not inScene then return end
    inScene = false

    RenderScriptCams(false, false, 0, true, true)
    if cam then DestroyCam(cam, false) cam = nil end
    DisplayRadar(true)

    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
end

local NO_RESPONSE = { ok = false, error = 'no response from server, try again' }

local function showUI(err)
    local r = TFC.Callback.Await('multichar:getCharacters') or NO_RESPONSE
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', characters = r.characters or {}, max = r.max or 0, error = err or r.error })
end

RegisterNetEvent('tfc-multichar:client:open', function()
    while not NetworkIsSessionStarted() do Wait(100) end
    startScene()
    showUI()
end)

-- NUI -> client -> server ---------------------------------------------------------

RegisterNUICallback('create', function(data, cb)
    cb(TFC.Callback.Await('multichar:create', data) or NO_RESPONSE)
end)

RegisterNUICallback('delete', function(data, cb)
    cb(TFC.Callback.Await('multichar:delete', tonumber(data.id), data.confirm) or NO_RESPONSE)
end)

RegisterNUICallback('play', function(data, cb)
    cb({ ok = true })

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    DoScreenFadeOut(400)
    Wait(400)

    setModel(data.sex)
    -- SetPlayerModel creates a new ped: keep it hidden and frozen until we're placed.
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)

    awaitingSpawn = true
    local r = TFC.Callback.Await('multichar:select', tonumber(data.id)) or NO_RESPONSE
    if not r.ok then
        awaitingSpawn = false
        DoScreenFadeIn(400)
        showUI(r.error)
    end
end)

-- spawnmanager (if running) may spawn the player while they're choosing: park them again.
AddEventHandler('playerSpawned', function()
    if inScene and not awaitingSpawn then
        parkPed()
        DoScreenFadeIn(400)
    end
end)

-- The core places the character, then emits the TFC playerSpawned hook.
TFC.On('playerSpawned', function()
    if not awaitingSpawn then return end
    awaitingSpawn = false
    endScene()
    DoScreenFadeIn(800)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    if inScene then
        endScene()
        DoScreenFadeIn(0)
    end
end)
