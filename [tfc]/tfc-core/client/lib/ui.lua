-- UI wrapper. Modules call TFC.UI.* instead of ox_lib directly, so the UI library can be
-- swapped later by changing only this file. Falls back to GTA's feed if ox_lib isn't running.

TFC.UI = {}

---@alias TFCNotifyType 'inform'|'success'|'error'|'warning'

---@param data string|{ title?: string, description?: string, type?: TFCNotifyType, duration?: integer }
function TFC.UI.Notify(data)
    if type(data) == 'string' then data = { description = data } end

    if GetResourceState('ox_lib') == 'started' then
        TriggerEvent('ox_lib:notify', data)
        return
    end

    local text = data.description or ''
    if data.title then text = ('~h~%s~h~~n~%s'):format(data.title, text) end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, true)
end

-- Interaction prompt ("[E] Open shop"). ox_lib's text UI if running, otherwise GTA help text.
-- Call ShowPrompt whenever the text should change; HidePrompt when the player walks away.

local promptText = nil
local promptDrawing = false

local function oxPrompt(fn, ...)
    if GetResourceState('ox_lib') ~= 'started' then return false end
    return pcall(function(...) exports.ox_lib[fn](exports.ox_lib, ...) end, ...)
end

---@param text string e.g. '[E] Open 24/7 Store'
function TFC.UI.ShowPrompt(text)
    if text == promptText then return end
    promptText = text
    if oxPrompt('showTextUI', text) then return end

    -- Fallback: draw the help box every frame while the prompt is up.
    if promptDrawing then return end
    promptDrawing = true
    CreateThread(function()
        while promptText do
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName((promptText:gsub('^%[E%]', '~INPUT_CONTEXT~')))
            EndTextCommandDisplayHelp(0, false, false, -1)
            Wait(0)
        end
        promptDrawing = false
    end)
end

function TFC.UI.HidePrompt()
    if not promptText then return end
    promptText = nil
    oxPrompt('hideTextUI')
end

-- Menus, input dialogs and progress bars (phase 7). ox_lib when running; without it, menus and
-- dialogs return false/nil (callers then point players to the matching chat command) and
-- progress bars just wait.

---@class TFCMenuOption
---@field title string
---@field description? string
---@field icon? string          Font Awesome name, e.g. 'handcuffs'
---@field disabled? boolean
---@field event? string         client event to trigger when picked
---@field args? table           passed to that event

---Show a context menu. Returns false if no menu library is running.
---@param menu { id: string, title: string, options: TFCMenuOption[] }
---@return boolean shown
function TFC.UI.Menu(menu)
    if GetResourceState('ox_lib') ~= 'started' then return false end
    local ok = pcall(function()
        exports.ox_lib:registerContext({ id = menu.id, title = menu.title, options = menu.options })
        exports.ox_lib:showContext(menu.id)
    end)
    return ok
end

---Ask for values. rows use ox_lib's inputDialog format, e.g.
---{ { type = 'number', label = 'Amount', min = 1, required = true }, { type = 'input', label = 'Reason' } }
---@return table|nil values in row order, or nil if cancelled / unavailable
function TFC.UI.Input(heading, rows)
    if GetResourceState('ox_lib') ~= 'started' then return nil end
    local ok, values = pcall(function() return exports.ox_lib:inputDialog(heading, rows) end)
    if not ok then return nil end
    return values
end

---Progress bar; returns true when it finished, false if cancelled.
---@param data { duration: integer, label: string, anim?: { dict: string, clip: string, flag?: integer }, canCancel?: boolean }
function TFC.UI.Progress(data)
    if GetResourceState('ox_lib') == 'started' then
        local ok, done = pcall(function()
            return exports.ox_lib:progressBar({
                duration = data.duration,
                label = data.label,
                canCancel = data.canCancel ~= false,
                disable = { move = true, car = true, combat = true },
                anim = data.anim,
            })
        end)
        if ok then return done == true end
    end

    -- Fallback: play the animation and wait.
    local ped = PlayerPedId()
    if data.anim then
        RequestAnimDict(data.anim.dict)
        local t = GetGameTimer() + 2000
        while not HasAnimDictLoaded(data.anim.dict) and GetGameTimer() < t do Wait(0) end
        TaskPlayAnim(ped, data.anim.dict, data.anim.clip, 8.0, -8.0, data.duration, data.anim.flag or 1, 0.0, false, false, false)
    end
    Wait(data.duration)
    if data.anim then StopAnimTask(ped, data.anim.dict, data.anim.clip, 1.0) end
    return true
end
