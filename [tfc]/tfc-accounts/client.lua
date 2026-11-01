-- Client copy of the player's balances (read-only; the server is the source of truth).
-- Client exports: GetBalance(account), GetBalances()
-- Client hook: moneyChanged(account, balance, delta, reason)

local balances = {}

local function formatMoney(n)
    local s = ('%d'):format(math.abs(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (n < 0 and '-$' or '$') .. s
end

TFC.OnNet('tfc-accounts:client:sync', function(all)
    balances = all or {}
end)

TFC.OnNet('tfc-accounts:client:changed', function(account, balance, delta, reason)
    balances[account] = balance
    TFC.Emit('moneyChanged', account, balance, delta, reason)

    if AccountsConfig.NotifyChanges then
        local def = AccountsConfig.Accounts[account]
        local label = def and def.label or account
        local sign = delta > 0 and '+' or '-'
        local text = ('%s%s'):format(sign, formatMoney(math.abs(delta)))
        if reason and reason ~= '' then text = text .. '  ' .. reason end

        TFC.UI.Notify({
            title = ('%s  %s'):format(label, formatMoney(balance)),
            description = text,
            type = delta > 0 and 'success' or 'inform',
        })
    end
end)

TFC.OnPlayerUnloaded(function()
    balances = {}
end)

exports('GetBalance', function(account) return balances[account] end)
exports('GetBalances', function()
    local copy = {}
    for k, v in pairs(balances) do copy[k] = v end
    return copy
end)
