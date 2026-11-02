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
