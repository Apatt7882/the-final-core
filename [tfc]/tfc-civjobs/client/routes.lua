-- Garbage and delivery routes (client).

local G = CivJobsConfig.Garbage
local D = CivJobsConfig.Delivery

local function backOfVehicle(here)
    local veh = Civ.myVehicle()
    if not veh then return nil end
    local rear = Civ.vehicleRear(veh)
    return #(here - rear) < 2.5, rear
end

local function returnStep(t, here, label)
    Civ.ground(t.depot)
    Civ.marker(t.depot, { 76, 195, 138 }, 2.0)
    if Civ.dist2d(here, t.depot) < 25.0 then
        Civ.offer('[E] Finish route', function() Civ.act('finish') end)
    end
end

-- Garbage ------------------------------------------------------------------------------------------------

local GM = { job = G.Job }
Civ.modules.garbage = GM

local dumpsterModels = {}
for _, m in ipairs(G.DumpsterModels) do dumpsterModels[joaat(m)] = true end

local scanning = false
local looseBags = {}   -- props we put down when an area has no dumpsters

local function clearLoose()
    for _, obj in ipairs(looseBags) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    looseBags = {}
end

---Find dumpsters in the zone (or put out bag piles if there are none) and send them to the server.
local function scan(t)
    if scanning then return end
    scanning = true
    clearLoose()
    CreateThread(function()
        local here = Civ.me()
        local found = {}
        for _, obj in ipairs(GetGamePool('CObject')) do
            if dumpsterModels[GetEntityModel(obj)] then
                local c = GetEntityCoords(obj)
                if Civ.dist2d(c, t.zone) <= G.ZoneRadius + 60.0 then
                    local spaced = true
                    for _, f in ipairs(found) do
                        if Civ.dist2d(f, c) < 8.0 then spaced = false break end
                    end
                    if spaced then found[#found + 1] = { x = c.x, y = c.y, z = c.z, d = #(here - c) } end
                end
            end
        end
        table.sort(found, function(a, b) return a.d < b.d end)
        local stops = {}
        for i = 1, math.min(#found, G.BagsPerZone) do stops[i] = { x = found[i].x, y = found[i].y, z = found[i].z } end

        -- Not enough dumpsters: put out bag piles on nearby sidewalks.
        if #stops < G.BagsPerZone then
            local model = Civ.loadModel('prop_rub_binbag_sd_01')
            local tries = 0
            while #stops < G.BagsPerZone and tries < 40 do
                tries = tries + 1
                local a, r = math.random() * math.pi * 2, 15.0 + math.random() * 90.0
                local ok, pos = GetSafeCoordForPed(here.x + math.cos(a) * r, here.y + math.sin(a) * r, here.z, true, 16)
                if ok and Civ.dist2d(pos, t.zone) <= G.ZoneRadius + 60.0 then
                    local spaced = true
                    for _, s in ipairs(stops) do if Civ.dist2d(s, pos) < 8.0 then spaced = false break end end
                    if spaced then
                        stops[#stops + 1] = { x = pos.x, y = pos.y, z = pos.z }
                        if model then
                            local obj = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
                            PlaceObjectOnGroundProperly(obj)
                            FreezeEntityPosition(obj, true)
                            looseBags[#looseBags + 1] = obj
                        end
                    end
                end
            end
            if model then SetModelAsNoLongerNeeded(model) end
        end

        if #stops > 0 then Civ.act('stops', { stops = stops }) end
        Wait(3000)
        scanning = false
    end)
end

function GM.onTask(t, old)
    if not t or t.kind ~= 'garbage' then
        if old and old.kind == 'garbage' then Civ.clearBlips('g_') clearLoose() end
        return
    end
    Civ.clearBlips('g_')
    if t.phase == 'drive' then
        Civ.blip('g_zone', t.zone, { sprite = 318, color = 25, label = 'Garbage: ' .. t.zone.label, route = true })
        Civ.radiusBlip('g_area', t.zone, t.zone.radius, 25)
    elseif t.phase == 'collect' then
        for i, s in ipairs(t.stops) do
            if not s.done then Civ.blip('g_stop' .. i, s, { sprite = 1, color = 25, scale = 0.6, label = 'Dumpster' }) end
            Civ.ground(s)
        end
    elseif t.phase == 'return' then
        clearLoose()
        Civ.blip('g_depot', t.depot, { sprite = 318, color = 2, label = G.Label, route = true })
    end
    if t.carrying then Civ.carry('bag') elseif Civ.carrying() == 'bag' then Civ.stopCarry() end
end

function GM.describe(t)
    if t.kind ~= 'garbage' then return nil end
    if t.phase == 'drive' then return ('Drive to %s (area %d of %d).'):format(t.zone.label, t.zoneIndex, t.zones) end
    if t.phase == 'collect' then
        return t.carrying and 'Throw the bag in the back of your truck.' or ('Empty the marked dumpsters: %d left here.'):format(t.left)
    end
    if t.phase == 'return' then return 'Take the truck back to the depot and finish the route.' end
end

function GM.tick(here, t)
    if not t or t.kind ~= 'garbage' then return false end
    if t.phase == 'drive' then
        if Civ.dist2d(here, t.zone) < t.zone.radius then scan(t) end
        return false
    elseif t.phase == 'collect' then
        if t.carrying then
            local atBack, rear = backOfVehicle(here)
            if rear then
                Civ.marker({ x = rear.x, y = rear.y, z = rear.z, gz = rear.z - 0.9 }, { 76, 195, 138 })
                if atBack then
                    Civ.offer('[E] Throw it in the truck', function()
                        if Civ.loadDict('missfbi4prepp1') then
                            TaskPlayAnim(PlayerPedId(), 'missfbi4prepp1', '_bag_throw_garbage_man', 8.0, -8.0, 1100, 48, 0.0, false, false, false)
                        end
                        Wait(800)
                        Civ.stopCarry()
                        Civ.act('toss')
                    end)
                end
            end
            return true
        end
        local active = false
        for i, s in ipairs(t.stops) do
            if not s.done then
                local d = Civ.dist2d(here, s)
                if d < CivJobsConfig.MarkerDistance then
                    active = true
                    Civ.marker(s)
                    if d < 2.5 then
                        Civ.offer('[E] Grab a garbage bag', function()
                            if TFC.UI.Progress({ duration = 1500, label = 'Grabbing a bag', anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 } }) then
                                Civ.act('grab', { stop = i })
                            end
                        end)
                    end
                end
            end
        end
        return active
    elseif t.phase == 'return' then
        if Civ.dist2d(here, t.depot) < 60.0 then returnStep(t, here) return true end
    end
    return false
end

-- Delivery --------------------------------------------------------------------------------------------------

local DM = { job = D.Job }
Civ.modules.delivery = DM

function DM.onTask(t, old)
    if not t or t.kind ~= 'delivery' then
        if old and old.kind == 'delivery' then Civ.clearBlips('d_') end
        return
    end
    Civ.clearBlips('d_')
    if t.phase == 'deliver' then
        local s = t.stops[t.stop]
        Civ.ground(s)
        Civ.blip('d_stop', s, { sprite = 478, color = 5, label = 'Delivery: ' .. s.label, route = true })
    elseif t.phase == 'return' then
        Civ.blip('d_depot', t.depot, { sprite = 478, color = 2, label = D.Label, route = true })
    end
    if t.carrying then Civ.carry('package') elseif Civ.carrying() == 'package' then Civ.stopCarry() end
end

function DM.describe(t)
    if t.kind ~= 'delivery' then return nil end
    if t.phase == 'deliver' then
        local s = t.stops[t.stop]
        return t.carrying and ('Take the package to the counter at %s.'):format(s.label)
            or ('Stop %d of %d: drive to %s and take a package from the back of the van.'):format(t.stop, #t.stops, s.label)
    end
    if t.phase == 'return' then return 'Take the van back to the depot and finish the route.' end
end

function DM.tick(here, t)
    if not t or t.kind ~= 'delivery' then return false end
    if t.phase == 'deliver' then
        local s = t.stops[t.stop]
        local d = Civ.dist2d(here, s)
        if d > 90.0 then return false end
        if t.carrying then
            Civ.marker(s, { 76, 195, 138 })
            if d < 2.5 then
                Civ.offer('[E] Deliver the package', function()
                    Civ.stopCarry()
                    if TFC.UI.Progress({ duration = 2000, label = 'Getting a signature', anim = { dict = 'mp_common', clip = 'givetake1_a', flag = 48 } }) then
                        Civ.act('deliver')
                    elseif Civ.task and Civ.task.carrying then
                        Civ.carry('package')
                    end
                end)
            end
        elseif not IsPedInAnyVehicle(PlayerPedId(), false) then
            local atBack, rear = backOfVehicle(here)
            if rear then
                Civ.marker({ x = rear.x, y = rear.y, z = rear.z, gz = rear.z - 0.9 })
                if atBack then
                    Civ.offer('[E] Take a package', function() Civ.act('grab') end)
                end
            end
        end
        return true
    elseif t.phase == 'return' then
        if Civ.dist2d(here, t.depot) < 60.0 then returnStep(t, here) return true end
    end
    return false
end
