-- Bills: jobs (and later businesses) send bills to players; players pay them from the bank
-- (going into credit if needed) or decline them (unless the bill is mandatory, e.g. police/EMS).
-- Paid money goes into the sender's department/business account.
--
-- Exports (server):
--   CreateBill({ target = src, amount, reason, sourceType = 'job'|'business', sourceName, sourceLabel,
--                sender = src?, mandatory = bool? }) -> ok, idOrError
--   GetPendingBills(src) -> list
-- Server hooks: billCreated(bill), billPaid(bill), billDeclined(bill)

local Cfg = BankingConfig
local BillCfg = Cfg.Billing
local fail, notify, clean, name = BankSrv.fail, BankSrv.notify, BankSrv.clean, BankSrv.name

local SCHEMA = [[
    CREATE TABLE IF NOT EXISTS `tfc_bills` (
        `id`           INT UNSIGNED     NOT NULL AUTO_INCREMENT,
        `character_id` INT UNSIGNED     NOT NULL,
        `source_type`  VARCHAR(16)      NOT NULL,
        `source_name`  VARCHAR(32)      NOT NULL,
        `source_label` VARCHAR(64)      NOT NULL,
        `sender_cid`   VARCHAR(16)      NULL,
        `sender_name`  VARCHAR(64)      NULL,
        `amount`       INT UNSIGNED     NOT NULL,
        `reason`       VARCHAR(128)     NOT NULL DEFAULT '',
        `mandatory`    TINYINT(1)       NOT NULL DEFAULT 0,
        `status`       VARCHAR(12)      NOT NULL DEFAULT 'pending',
        `created_at`   TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `closed_at`    TIMESTAMP        NULL,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_bills_character` (`character_id`, `status`),
        CONSTRAINT `fk_tfc_bills_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]]

function BankSrv.createBillTable()
    MySQL.query.await(SCHEMA)
end

local function rowToBill(r)
    return {
        id = math.tointeger(r.id), amount = math.tointeger(r.amount), reason = r.reason,
        sourceType = r.source_type, sourceName = r.source_name, sourceLabel = r.source_label,
        senderCid = r.sender_cid, senderName = r.sender_name,
        mandatory = r.mandatory == 1 or r.mandatory == true, status = r.status,
        createdAt = math.tointeger(r.created), closedAt = math.tointeger(r.closed),
    }
end

local COLUMNS = 'id, source_type, source_name, source_label, sender_cid, sender_name, amount, reason, mandatory, status, UNIX_TIMESTAMP(created_at) AS created, UNIX_TIMESTAMP(closed_at) AS closed'

---Pending bills plus the last 20 closed ones.
function BankSrv.bills(src)
    local p = TFC.GetPlayer(src)
    if not p then return { pending = {}, closed = {} } end
    local pending, closed = {}, {}
    for _, r in ipairs(MySQL.query.await(('SELECT %s FROM tfc_bills WHERE character_id = ? AND status = \'pending\' ORDER BY id DESC'):format(COLUMNS),
        { p.characterId }) or {}) do
        pending[#pending + 1] = rowToBill(r)
    end
    for _, r in ipairs(MySQL.query.await(('SELECT %s FROM tfc_bills WHERE character_id = ? AND status <> \'pending\' ORDER BY id DESC LIMIT 20'):format(COLUMNS),
        { p.characterId }) or {}) do
        closed[#closed + 1] = rowToBill(r)
    end
    return { pending = pending, closed = closed }
end

-- Creating bills ------------------------------------------------------------------------------------

local function CreateBill(b)
    if type(b) ~= 'table' then return false, 'invalid bill' end
    local target = math.tointeger(tonumber(b.target))
    local tp = target and TFC.GetPlayer(target)
    if not tp then return false, 'that player is not online' end
    local amount = BankSrv.amountOf(b.amount, BillCfg.MaxAmount)
    if not amount then return false, ('amount must be $1 to $%d'):format(BillCfg.MaxAmount) end
    local reason = clean(b.reason, 120)
    if #reason < 3 then return false, 'give a reason' end
    if type(b.sourceName) ~= 'string' or type(b.sourceLabel) ~= 'string' then return false, 'bill needs a sender' end

    local sender = math.tointeger(tonumber(b.sender))
    local sp = sender and TFC.GetPlayer(sender)
    local id = MySQL.insert.await(
        'INSERT INTO tfc_bills (character_id, source_type, source_name, source_label, sender_cid, sender_name, amount, reason, mandatory) VALUES (?, ?, ?, ?, NULLIF(?, \'\'), NULLIF(?, \'\'), ?, ?, ?)',
        { tp.characterId, b.sourceType or 'job', b.sourceName, clean(b.sourceLabel, 64), sp and sp.cid or '', sp and name(sender) or '',
          amount, reason, b.mandatory and 1 or 0 })
    id = math.tointeger(id)
    if not id then return false, 'could not save the bill' end

    local bill = { id = id, target = target, amount = amount, reason = reason, sourceType = b.sourceType or 'job',
        sourceName = b.sourceName, sourceLabel = b.sourceLabel, sender = sender, mandatory = b.mandatory == true }
    notify(target, ('New bill from %s: $%d for %s. Use /%s or any bank to pay.'):format(b.sourceLabel, amount, reason, BillCfg.ListCommand), 'warning')
    TriggerClientEvent('tfc-banking:client:billsChanged', target)
    TFC.Emit('billCreated', bill)
    return true, id
end

exports('CreateBill', CreateBill)
exports('GetPendingBills', function(src) return BankSrv.bills(src).pending end)

---A job member bills someone (job menu / command).
local function jobBill(src, target, amount, reason)
    if GetResourceState('tfc-jobs') ~= 'started' then return fail('jobs are not running') end
    local job = exports['tfc-jobs']:GetJob(src)
    local rule = job and BillCfg.Jobs[job.name]
    if not rule then return fail('your job can\'t send bills') end
    if job.onDuty == false then return fail('go on duty first') end
    target = math.tointeger(tonumber(target))
    if not target or target == src then return fail('pick someone else to bill') end
    local ok, err = CreateBill({
        target = target, amount = amount, reason = reason, sourceType = 'job',
        sourceName = job.name, sourceLabel = job.label, sender = src, mandatory = rule.mandatory == true,
    })
    if not ok then return fail(err) end
    TFC.Log.Info('%s (%s) billed %s $%s: %s', name(src), job.name, name(target), tostring(amount), tostring(reason))
    return { ok = true, message = ('Sent a $%d bill to %s'):format(math.tointeger(tonumber(amount)) or 0, name(target)) }
end

TFC.Callback.Register('banking:sendBill', function(src, target, amount, reason)
    return jobBill(src, target, amount, reason)
end, { rateLimit = 1000 })

-- Paying and declining ------------------------------------------------------------------------------

local function senderOnline(bill)
    if not bill.senderCid then return nil end
    local p = TFC.GetPlayerByCid(bill.senderCid)
    return p and p.source or nil
end

local function getBill(src, id)
    local p = TFC.GetPlayer(src)
    id = math.tointeger(tonumber(id))
    if not p or not id then return nil end
    local r = MySQL.single.await(('SELECT %s FROM tfc_bills WHERE id = ? AND character_id = ?'):format(COLUMNS), { id, p.characterId })
    return r and rowToBill(r) or nil, p
end

function BankSrv.Actions.payBill(src, d)
    local bill, p = getBill(src, d.id)
    if not bill then return fail('bill not found') end
    if bill.status ~= 'pending' then return fail('that bill is already ' .. bill.status) end

    -- Claim it first so it can't be paid twice.
    local claimed = MySQL.update.await("UPDATE tfc_bills SET status = 'paid', closed_at = CURRENT_TIMESTAMP WHERE id = ? AND character_id = ? AND status = 'pending'",
        { bill.id, p.characterId })
    if (claimed or 0) < 1 then return fail('that bill was already handled') end

    local reason = ('Bill #%d: %s (%s)'):format(bill.id, bill.sourceLabel, bill.reason)
    local paid, from = BankSrv.payFromBank(src, bill.amount, reason)
    if not paid then
        MySQL.update.await("UPDATE tfc_bills SET status = 'pending', closed_at = NULL WHERE id = ?", { bill.id })
        return fail('not enough in your bank and credit')
    end

    local society = bill.sourceType == 'business' and ('business:' .. bill.sourceName) or bill.sourceName
    BankSrv.AddSociety(society, bill.amount, ('Bill #%d paid by %s: %s'):format(bill.id, name(src), bill.reason))
    local s = senderOnline(bill)
    if s then notify(s, ('%s paid your $%d bill (%s).'):format(name(src), bill.amount, bill.reason), 'success') end
    bill.status = 'paid'
    TFC.Emit('billPaid', bill)
    return { ok = true, message = ('Paid $%d to %s (from %s)'):format(bill.amount, bill.sourceLabel, from), bills = BankSrv.bills(src) }
end

function BankSrv.Actions.declineBill(src, d)
    local bill, p = getBill(src, d.id)
    if not bill then return fail('bill not found') end
    if bill.status ~= 'pending' then return fail('that bill is already ' .. bill.status) end
    if bill.mandatory then return fail(('bills from %s can\'t be declined'):format(bill.sourceLabel)) end
    local n = MySQL.update.await("UPDATE tfc_bills SET status = 'declined', closed_at = CURRENT_TIMESTAMP WHERE id = ? AND character_id = ? AND status = 'pending'",
        { bill.id, p.characterId })
    if (n or 0) < 1 then return fail('that bill was already handled') end
    local s = senderOnline(bill)
    if s then notify(s, ('%s declined your $%d bill (%s).'):format(name(src), bill.amount, bill.reason), 'warning') end
    bill.status = 'declined'
    TFC.Emit('billDeclined', bill)
    return { ok = true, message = 'Bill declined.', bills = BankSrv.bills(src) }
end

function BankSrv.Actions.bills(src)
    local r = BankSrv.bills(src)
    r.ok = true
    return r
end

-- Commands -------------------------------------------------------------------------------------------

TFC.RegisterCommand(BillCfg.Command, {
    help = 'Bill a player (police, EMS, mechanics... on duty)',
    params = {
        { name = 'id', help = 'Player ID' },
        { name = 'amount', help = 'Dollars' },
        { name = 'reason', help = 'What for' },
    },
}, function(src, args)
    if src == 0 then return end
    local r = jobBill(src, args[1], args[2], table.concat(args, ' ', 3))
    notify(src, r.ok and r.message or r.error, r.ok and 'success' or 'error')
end)

TFC.RegisterCommand(BillCfg.ListCommand, { help = 'See and pay your bills' }, function(src)
    if src == 0 then return end
    TriggerClientEvent('tfc-banking:client:openBills', src)
end)

CreateThread(BankSrv.start)
