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
