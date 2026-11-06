-- The City Accountant: reads a player's real finances and gives advice. Built-in rules always;
-- answers to free-form questions from Claude when a tfc_ai_key is set in server.cfg.

local Cfg = FinanceConfig
local A = Cfg.Advisor
local fail = FinSrv.fail

local function int(v) return math.tointeger(tonumber(v)) end

-- AI --------------------------------------------------------------------------------------------

local function aiKey() return GetConvar('tfc_ai_key', '') end
function FinSrv.aiEnabled() return aiKey() ~= '' end

-- Snapshot of a player's finances ---------------------------------------------------------------

local CATEGORIES = {
    { key = 'Paychecks', match = { '^Paycheck' }, income = true },
    { key = 'Sales shares', match = { '^Sales share' }, income = true },
    { key = 'Transfers', match = { '^Transfer' } },
    { key = 'Bills & fines', match = { '^Bill #', '^Fine', 'Hospital bill', '^Hospital' } },
    { key = 'Credit interest', match = { '^Credit interest' } },
    { key = 'Stocks', match = { '^Stocks:' } },
    { key = 'Licenses & fees', match = { '^DMV', '^Government Center' } },
}
-- Moves between a player's own accounts aren't income or spending.
local INTERNAL = { '^Deposit$', '^Withdrawal$', '^credit repayment', '^Refund', '^cash moved', '^Deposit to .* savings', '^Withdrawal from .* savings' }

local function matchesAny(text, patterns)
    for _, p in ipairs(patterns) do
        if text:find(p) then return true end
    end
    return false
end

local function categorize(reason)
    for _, c in ipairs(CATEGORIES) do
        if matchesAny(reason, c.match) then return c.key end
    end
    return 'Shopping & other'
end

function FinSrv.snapshot(src)
    local p = TFC.GetPlayer(src)
    local acc = exports['tfc-accounts']
    local b = acc:GetBalances(src) or {}
    local terms = GetResourceState('tfc-banking') == 'started' and exports['tfc-banking']:GetCreditTerms() or { rate = 0.02, everyDays = 7, limit = 2500 }
    local bills = GetResourceState('tfc-banking') == 'started' and exports['tfc-banking']:GetPendingBills(src) or {}
    local job = GetResourceState('tfc-jobs') == 'started' and exports['tfc-jobs']:GetJob(src) or nil
    local portfolio = FinSrv.portfolio(src)

    -- Last 7 days of money in and out, by category (own-account moves left out).
    local income, spend, byCat = 0, 0, {}
    for _, r in ipairs(MySQL.query.await('SELECT amount, reason FROM tfc_transactions WHERE character_id = ? AND created_at >= NOW() - INTERVAL 7 DAY',
        { p.characterId }) or {}) do
        local amt, reason = int(r.amount) or 0, r.reason or ''
        if not matchesAny(reason, INTERNAL) then
            local cat = categorize(reason)
            if amt > 0 then income = income + amt else spend = spend - amt end
            byCat[cat] = (byCat[cat] or 0) + amt
        end
    end
    local categories = {}
    for k, v in pairs(byCat) do categories[#categories + 1] = { name = k, amount = v } end
    table.sort(categories, function(x, y) return math.abs(x.amount) > math.abs(y.amount) end)

    local billsTotal, mandatory, mandatoryTotal = 0, 0, 0
    for _, bill in ipairs(bills) do
        billsTotal = billsTotal + (bill.amount or 0)
        if bill.mandatory then mandatory, mandatoryTotal = mandatory + 1, mandatoryTotal + (bill.amount or 0) end
    end

    local hasDriver = true
    if GetResourceState('tfc-government') == 'started' then hasDriver = exports['tfc-government']:HasLicense(src, 'driver') end

    local cash, bank, credit = b.cash or 0, b.bank or 0, b.credit or 0
    return {
        name = p:GetFullName(),
        cash = cash, bank = bank, creditOwed = math.max(0, -credit), creditLimit = terms.limit or 0,
        creditRate = terms.rate, creditEveryDays = terms.everyDays,
        netWorth = cash + bank + credit + portfolio.value,
        bills = { count = #bills, total = billsTotal, mandatory = mandatory, mandatoryTotal = mandatoryTotal },
        job = job and { label = job.label, rank = job.gradeLabel or '', pay = job.pay or 0, onDuty = job.onDuty, unemployed = job.name == 'unemployed' } or nil,
        week = { income = income, spend = spend, categories = categories },
        portfolio = { value = portfolio.value, cost = portfolio.cost, holdings = portfolio.holdings },
        hasDriversLicense = hasDriver,
    }
end

-- Built-in advice --------------------------------------------------------------------------------

local function money(n)
    local s = tostring(math.floor(math.abs(n))):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (n < 0 and '-$' or '$') .. s
end

function FinSrv.advice(s)
    local out = {}
    local function add(level, title, text) out[#out + 1] = { level = level, title = title, text = text } end

    if s.bills.mandatory > 0 then
        add('urgent', ('Pay your %d police/EMS bill%s (%s)'):format(s.bills.mandatory, s.bills.mandatory == 1 and '' or 's', money(s.bills.mandatoryTotal)),
            'These can\'t be declined. Pay them with /bills or at any bank so they don\'t hang over you.')
    end
    local other = s.bills.count - s.bills.mandatory
    if other > 0 then
        add('warn', ('You have %d other unpaid bill%s (%s)'):format(other, other == 1 and '' or 's', money(s.bills.total - s.bills.mandatoryTotal)),
            'Pay the ones you agree with and decline any you don\'t. Unpaid bills don\'t go away on their own.')
    end

    if s.creditOwed > 0 then
        local weekly = math.ceil(s.creditOwed * s.creditRate)
        local urgent = s.creditLimit > 0 and s.creditOwed >= s.creditLimit * 0.5
        local text = ('At %g%% every %d days that costs you about %s a week. Paying it off is a guaranteed return no stock can beat.'):format(
            s.creditRate * 100, s.creditEveryDays, money(weekly))
        if s.bank >= s.creditOwed then
            text = text .. (' You have %s in the bank: clear it today at any bank (Credit tab).'):format(money(s.bank))
        else
            text = text .. ' Put part of every paycheck toward it at any bank (Credit tab).'
        end
        add(urgent and 'urgent' or 'warn', ('You owe %s on credit'):format(money(s.creditOwed)), text)
    end

    if s.cash > A.CashWarning then
        add('warn', ('You\'re carrying %s in cash'):format(money(s.cash)),
            'Cash can be dropped, stolen or seized by police. Keep what you need for the day and deposit the rest at a bank or ATM.')
    end

    if s.job then
        if s.job.unemployed then
            add('tip', 'Get a job', 'Sign up for a public job at the Government Center. Every job pays a paycheck every 15 minutes while you\'re on duty.')
        elseif s.job.onDuty == false and s.job.pay > 0 then
            add('tip', ('Clock in to earn %s per paycheck'):format(money(s.job.pay)),
                ('As %s you\'re paid %s four times an hour, but only while on duty (/duty). That\'s %s an hour.'):format(
                    s.job.label, money(s.job.pay), money(s.job.pay * 4)))
        end
    end

    if s.bank < A.EmergencyFund then
        add('tip', ('Build a %s safety cushion'):format(money(A.EmergencyFund)),
            'Hospital bills ($1,000 for an early respawn), fines and repairs come out of your bank. Keep a cushion so they don\'t push you onto credit.')
    end

    if s.week.spend > s.week.income and s.week.spend > 0 then
        local where = ''
        for _, c in ipairs(s.week.categories) do
            if c.amount < 0 then where = (' Most of it went to %s (%s).'):format(c.name:lower(), money(-c.amount)) break end
        end
        add('warn', 'You spent more than you earned this week',
            ('In the last 7 days you earned %s and spent %s.%s'):format(money(s.week.income), money(s.week.spend), where))
    end

    local pv, pc = s.portfolio.value, s.portfolio.cost
    if #s.portfolio.holdings > 0 then
        local biggest = s.portfolio.holdings[1]
        if pv > 0 and #s.portfolio.holdings >= 1 and biggest.value / pv > 0.7 and pv > 1000 then
            add('warn', ('%d%% of your stocks are in %s'):format(math.floor(biggest.value / pv * 100), biggest.name),
                'If that one company has bad news you\'ll feel all of it. Spreading money over 3 or 4 companies smooths out the bumps.')
        end
        if pc > 0 and (pv - pc) / pc < -0.15 then
            add('tip', ('Your stocks are down %d%%'):format(math.floor((pc - pv) / pc * 100)),
                'Prices bounce around and tend to drift back toward their usual level. Selling in a panic locks in the loss; only sell if you need the money.')
        elseif pc > 0 and (pv - pc) / pc > 0.25 then
            add('tip', ('Your stocks are up %d%%'):format(math.floor((pv - pc) / pc * 100)),
                'Nice. Consider taking some profit: selling part locks in the gain while the rest keeps working.')
        end
    elseif s.creditOwed == 0 and s.bills.count == 0 and s.bank >= A.InvestFrom then
        add('tip', 'Put some money to work',
            ('You have %s in the bank and no debt. Consider investing a part (never all of it) in the stock market at any bank. Spread it over a few companies; each trade costs a 1%% fee, so don\'t trade too often.'):format(money(s.bank)))
    end

    if not s.hasDriversLicense then
        add('tip', 'Get your driver\'s license', 'It\'s $500 at the DMV, no test needed. Getting caught without one can cost a lot more.')
    end

    if s.creditOwed == 0 and s.bills.count == 0 then
        add('good', 'You\'re debt-free', 'No credit owed and no unpaid bills. Keep it that way and your money grows.')
    end
    return out
end

-- Ask a question (Claude API) ------------------------------------------------------------------------

local asked = {}   -- src -> { last = os.time(), day = 'YYYY-MM-DD', count = n }

local SYSTEM = [[You are the City Accountant at the Government Center in a GTA V roleplay city (The Final Core).
You help one citizen with their in-game money. All money is in-game dollars; never give real-world financial,
legal or tax advice, and if asked about real money say you only handle the city's finances.
How the city works: paychecks are paid by the government every 15 minutes while on duty; jobs are at the
Government Center; banks and ATMs handle deposits, withdrawals and transfers; police/EMS bills can't be declined;
the credit line charges interest weekly; the stock market (at banks or with you) has fictional companies and a 1%
fee per trade; prices swing and drift back toward their usual level; businesses can be owned (ask an admin).
Use the citizen's data below. Be warm, practical and specific, with numbers. Answer in at most 120 words, plain
text, no markdown headings.]]

local function ask(src, question)
    local key = aiKey()
    if key == '' then return fail('the Accountant can\'t take questions right now') end
    question = type(question) == 'string' and question:gsub('[%c]', ' '):sub(1, 300) or ''
    if #question:gsub('%s', '') < 3 then return fail('ask a question') end

    local now, today = os.time(), os.date('%Y-%m-%d')
    local a = asked[src]
    if not a or a.day ~= today then a = { last = 0, day = today, count = 0 } asked[src] = a end
    if now - a.last < Cfg.AI.CooldownSeconds then return fail(('one moment, please (%d s)'):format(Cfg.AI.CooldownSeconds - (now - a.last))) end
    if a.count >= Cfg.AI.DailyLimit then return fail('that\'s enough questions for today; come back tomorrow') end
    a.last, a.count = now, a.count + 1

    local snap = FinSrv.snapshot(src)
    local market = {}
    for _, st in ipairs(FinSrv.market().stocks) do
        market[#market + 1] = ('%s %s $%.2f (%+.1f%% 24h)'):format(st.symbol, st.name, st.price, st.change * 100)
    end
    local body = json.encode({
        model = GetConvar('tfc_ai_model', Cfg.AI.Model),
        max_tokens = Cfg.AI.MaxTokens,
        system = SYSTEM .. '\n\nCitizen data (JSON): ' .. json.encode(snap) .. '\nMarket: ' .. table.concat(market, '; '),
        messages = { { role = 'user', content = question } },
    })

    local p = promise.new()
    PerformHttpRequest('https://api.anthropic.com/v1/messages', function(status, response)
        p:resolve({ status = status, body = response })
    end, 'POST', body, {
        ['Content-Type'] = 'application/json',
        ['x-api-key'] = key,
        ['anthropic-version'] = '2023-06-01',
    })
    local res = Citizen.Await(p)
    if res.status ~= 200 or not res.body then
        TFC.Log.Warn('AI accountant request failed (HTTP %s): %s', tostring(res.status), tostring(res.body and res.body:sub(1, 200)))
        return fail('the Accountant is busy right now; try again later')
    end
    local ok, decoded = pcall(json.decode, res.body)
    local text = ok and decoded and decoded.content and decoded.content[1] and decoded.content[1].text
    if not text then return fail('the Accountant didn\'t have an answer') end
    return { ok = true, answer = text, left = Cfg.AI.DailyLimit - a.count }
end

-- Callbacks ----------------------------------------------------------------------------------------

local function data(src)
    local snap = FinSrv.snapshot(src)
    local m = FinSrv.market()
    return {
        ok = true,
        snapshot = snap,
        advice = FinSrv.advice(snap),
        market = m,
        portfolio = FinSrv.portfolio(src),
        canTrade = FinSrv.canTrade(src),
        ai = FinSrv.aiEnabled(),
    }
end

TFC.Callback.Register('finance:open', function(src)
    if not TFC.GetPlayer(src) then return fail('no character loaded') end
    return data(src)
end, { rateLimit = 500 })

TFC.Callback.Register('finance:refresh', function(src)
    if not TFC.GetPlayer(src) then return fail('no character loaded') end
    return data(src)
end, { rateLimit = 2000 })

TFC.Callback.Register('finance:trade', function(src, side, symbol, shares)
    local r
    if side == 'buy' then r = FinSrv.buy(src, symbol, shares)
    elseif side == 'sell' then r = FinSrv.sell(src, symbol, shares)
    else r = fail('unknown') end
    local d = data(src)
    d.ok, d.error, d.message = r.ok, r.error, r.message
    return d
end, { rateLimit = 500 })

TFC.Callback.Register('finance:ask', function(src, question)
    return ask(src, question)
end, { rateLimit = 2000 })

TFC.RegisterCommand(Cfg.ViewCommand, { help = 'See the stock market (trade at a bank or the City Accountant)' }, function(src)
    if src == 0 then return end
    TriggerClientEvent('tfc-finance:client:open', src, 'stocks')
end)

TFC.On('playerUnloaded', function(src) asked[src] = nil end)

CreateThread(FinSrv.start)
