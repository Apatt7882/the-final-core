-- Server side of the UI wrapper: sends to one player's client, which shows it with TFC.UI.

TFC.UI = {}

---@param src integer
---@param data string|{ title?: string, description?: string, type?: 'inform'|'success'|'error'|'warning', duration?: integer }
function TFC.UI.Notify(src, data)
    TriggerClientEvent('tfc:client:notify', src, data)
end
