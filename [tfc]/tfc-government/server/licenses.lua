-- Licenses: records per character, printed cards in the inventory, DMV purchases and quizzes,
-- and police suspensions / revocations with supervisor-approved reinstatement.
--
-- Exports (server):
--   HasLicense(src, id) -> bool                 valid (not suspended / revoked)
--   GetLicenses(src) -> { [id] = { status, issued, reason } }
--   GetLicensesByCid(cid) -> same, for offline characters (MDT)
-- Server hooks: licenseIssued(src, id), licenseStatusChanged(cid, id, status, by)

local Cfg = GovConfig
local INV, ACC = 'tfc-inventory', 'tfc-accounts'

GovSrv = {}

local defs = {}
for _, l in ipairs(Cfg.Licenses) do defs[l.id] = l end
GovSrv.defs = defs

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `tfc_licenses` (
        `character_id` INT UNSIGNED NOT NULL,
        `type`         VARCHAR(16)  NOT NULL,
        `status`       VARCHAR(12)  NOT NULL DEFAULT 'valid',
        `reason`       VARCHAR(128) NOT NULL DEFAULT '',
        `issued_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`character_id`, `type`),
        CONSTRAINT `fk_tfc_licenses_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_license_events` (
        `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        `character_id` INT UNSIGNED    NOT NULL,
        `type`         VARCHAR(16)     NOT NULL,
        `action`       VARCHAR(16)     NOT NULL,
        `reason`       VARCHAR(128)    NOT NULL DEFAULT '',
        `by_cid`       VARCHAR(16)     NULL,
        `by_name`      VARCHAR(64)     NULL,
        `created_at`   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_license_events_character` (`character_id`, `created_at`),
        CONSTRAINT `fk_tfc_license_events_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `tfc_license_requests` (
        `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `character_id` INT UNSIGNED NOT NULL,
        `cid`          VARCHAR(16)  NOT NULL,
        `name`         VARCHAR(64)  NOT NULL,
        `type`         VARCHAR(16)  NOT NULL,
        `status`       VARCHAR(12)  NOT NULL DEFAULT 'pending',
        `handled_by`   VARCHAR(64)  NULL,
        `created_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `closed_at`    TIMESTAMP    NULL,
        PRIMARY KEY (`id`),
        KEY `idx_tfc_license_requests` (`status`),
        CONSTRAINT `fk_tfc_license_requests_character` FOREIGN KEY (`character_id`) REFERENCES `tfc_characters` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- Helpers --------------------------------------------------------------------------------------

local function fail(err) return { ok = false, error = err } end
GovSrv.fail = fail

local function notify(src, text, kind)
    TFC.UI.Notify(src, { title = 'Government', description = text, type = kind or 'inform' })
end
GovSrv.notify = notify

local function clean(text, max)
    if type(text) ~= 'string' then return '' end
    return (text:gsub('<[^>]*>', ''):gsub('[%c<>]', ''):match('^%s*(.-)%s*$')):sub(1, max or 100)
end
GovSrv.clean = clean

local function int(v) return math.tointeger(tonumber(v)) end

local function player(src) return TFC.GetPlayer(src) end

local function near(src, place, extra)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local p, c = GetEntityCoords(ped), place.coords
    local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= Cfg.InteractDistance + (extra or 3.0)
end
GovSrv.near = near

---Take a fee (bank first, then cash). Fees go into the 'government' account.
function GovSrv.pay(src, amount, reason)
    if amount <= 0 then return true end
    local ok = exports[ACC]:Charge(src, amount, reason, Cfg.PayFrom)
    if not ok then return false end
    if GetResourceState('tfc-banking') == 'started' then
        exports['tfc-banking']:AddSociety('government', amount, reason)
    end
    return true
end

-- Records --------------------------------------------------------------------------------------

---@return table<string, { status: string, reason: string, issued: integer }>
local function recordsByCharId(charId)
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT type, status, reason, UNIX_TIMESTAMP(issued_at) AS issued FROM tfc_licenses WHERE character_id = ?', { charId }) or {}) do
        out[r.type] = { status = r.status, reason = r.reason, issued = int(r.issued) }
    end
    return out
end

local function records(src)
    local p = player(src)
    return p and recordsByCharId(p.characterId) or {}
end
GovSrv.records = records

local function event(charId, id, action, reason, by)
    local bp = by and by > 0 and player(by) or nil
    MySQL.insert('INSERT INTO tfc_license_events (character_id, type, action, reason, by_cid, by_name) VALUES (?, ?, ?, ?, NULLIF(?, \'\'), NULLIF(?, \'\'))',
        { charId, id, action, reason or '', bp and bp.cid or '', bp and bp:GetFullName() or '' })
end

local function HasLicense(src, id)
    local p = player(src)
    if not p then return false end
    local n = int((MySQL.scalar.await("SELECT COUNT(*) FROM tfc_licenses WHERE character_id = ? AND type = ? AND status = 'valid'", { p.characterId, id }))) or 0
    return n > 0
end

exports('HasLicense', HasLicense)
exports('GetLicenses', function(src) return records(src) end)
exports('GetLicensesByCid', function(cid)
    local id = MySQL.scalar.await('SELECT id FROM tfc_characters WHERE cid = ?', { cid })
    return id and recordsByCharId(id) or {}
end)

-- Cards in the inventory -------------------------------------------------------------------------

local CARD_ITEM = { driver = 'drivers_license', weapon = 'weapon_permit', other = 'license_card' }

---Remove a card from the player's inventory. For 'other' cards only the one for `id`.
local function removeCard(src, card, id)
    local item = CARD_ITEM[card]
    local removed = 0
    for _, it in ipairs(exports[INV]:Search(src, item) or {}) do
        if card ~= 'other' or (it.metadata and it.metadata.type == id) then
            if exports[INV]:RemoveItem(src, item, 1, nil, it.slot, 'license card replaced/removed') then removed = removed + 1 end
        end
    end
    return removed
end

local function hasCard(src, card, id)
    for _, it in ipairs(exports[INV]:Search(src, CARD_ITEM[card]) or {}) do
        if card ~= 'other' or (it.metadata and it.metadata.type == id) then return true end
    end
    return false
end
GovSrv.hasCard = hasCard

---Print a fresh card. Driver's License lists every valid driving class.
local function giveCard(src, card, id)
    local p = player(src)
    if not p then return false end
    local recs = records(src)
    local meta = { name = p:GetFullName(), cid = p.cid, issued = os.date('%Y-%m-%d') }
    local dob = p:GetDob()
    if dob then meta.dob = dob end
    if card == 'driver' then
        local classes = {}
        for _, l in ipairs(Cfg.Licenses) do
            if l.card == 'driver' and recs[l.id] and recs[l.id].status == 'valid' then classes[#classes + 1] = l.short or l.id end
        end
        if #classes == 0 then return false end
        meta.classes = table.concat(classes, ', ')
        meta.number = ('DL-%s'):format(p.cid)
    elseif card == 'weapon' then
        meta.number = ('WP-%s'):format(p.cid)
    else
        meta.license = defs[id].label
        meta.type = id
    end
    removeCard(src, card, id)
    return exports[INV]:AddItem(src, CARD_ITEM[card], 1, meta, nil, 'license card issued')
end
GovSrv.giveCard = giveCard

-- DMV ------------------------------------------------------------------------------------------------

local quizzes = {}   -- src -> { id, answers, passed = { [id] = expires } }

local function shuffled(list)
    local idx = {}
    for i = 1, #list do idx[i] = i end
    for i = #idx, 2, -1 do
        local j = math.random(i)
        idx[i], idx[j] = idx[j], idx[i]
    end
    return idx
end

function GovSrv.dmvData(src)
    local recs = records(src)
    local list = {}
    for _, l in ipairs(Cfg.Licenses) do
        local r = recs[l.id]
        local pending = false
        if r and r.status ~= 'valid' then
            local p = player(src)
            pending = (int((MySQL.scalar.await("SELECT COUNT(*) FROM tfc_license_requests WHERE character_id = ? AND type = ? AND status = 'pending'",
                { p.characterId, l.id }))) or 0) > 0
        end
        list[#list + 1] = {
            id = l.id, label = l.label, description = l.description, price = l.price, quiz = l.quiz ~= nil,
            requires = l.requires and defs[l.requires].label or false,
            requiresOk = not l.requires or (recs[l.requires] and recs[l.requires].status == 'valid') or false,
            status = r and r.status or 'none', reason = r and r.reason or '',
            hasCard = r and r.status == 'valid' and hasCard(src, l.card, l.id) or false,
            pending = pending,
        }
    end
    return { ok = true, licenses = list, replacementFee = Cfg.ReplacementFee, passScore = Cfg.PassScore }
end

local DmvActions = {}
GovSrv.DmvActions = DmvActions

function DmvActions.quiz(src, d)
    local l = defs[d.id]
    if not l or not l.quiz or not GovQuizzes[l.quiz] then return fail('that license has no test') end
    local questions, answers = {}, {}
    for _, qi in ipairs(shuffled(GovQuizzes[l.quiz])) do
        local q = GovQuizzes[l.quiz][qi]
        local order = shuffled(q.c)
        local choices = {}
        for pos, ci in ipairs(order) do
            choices[pos] = q.c[ci]
            if ci == q.a then answers[#questions + 1] = pos end
        end
        questions[#questions + 1] = { q = q.q, c = choices }
    end
    quizzes[src] = quizzes[src] or { passed = {} }
    quizzes[src].id, quizzes[src].answers = l.id, answers
    return { ok = true, id = l.id, label = l.label, questions = questions }
end

function DmvActions.submit(src, d)
    local s = quizzes[src]
    if not s or s.id ~= d.id or not s.answers then return fail('start the test first') end
    local given = type(d.answers) == 'table' and d.answers or {}
    local right = 0
    for i, a in ipairs(s.answers) do
        if int(given[i]) == a then right = right + 1 end
    end
    s.answers = nil
    local passed = right >= Cfg.PassScore
    if passed then s.passed[d.id] = os.time() + 600 end
    return { ok = true, passed = passed, score = right, total = #GovQuizzes[defs[d.id].quiz], message = passed
        and ('Passed with %d/5. You can now pay for your %s.'):format(right, defs[d.id].label)
        or ('%d/5. You need %d to pass. Try again.'):format(right, Cfg.PassScore) }
end

function DmvActions.buy(src, d)
    local l = defs[d.id]
    if not l then return fail('unknown license') end
    local recs = records(src)
    local r = recs[l.id]
    if r and r.status == 'valid' then return fail('you already have it') end
    if r and r.status ~= 'valid' then return fail(('your %s is %s: request reinstatement first'):format(l.label, r.status)) end
    if l.requires and not (recs[l.requires] and recs[l.requires].status == 'valid') then
        return fail(('you need a valid %s first'):format(defs[l.requires].label))
    end
    if l.quiz then
        local s = quizzes[src]
        if not s or not s.passed[l.id] or s.passed[l.id] < os.time() then return fail('pass the test first') end
    end
    if not GovSrv.pay(src, l.price, ('DMV: %s'):format(l.label)) then return fail(('you need $%d'):format(l.price)) end

    local p = player(src)
    MySQL.update.await("INSERT INTO tfc_licenses (character_id, type, status, reason) VALUES (?, ?, 'valid', '') ON DUPLICATE KEY UPDATE status = 'valid', reason = '', issued_at = CURRENT_TIMESTAMP",
        { p.characterId, l.id })
    event(p.characterId, l.id, 'issued', '', 0)
    if quizzes[src] then quizzes[src].passed[l.id] = nil end
    giveCard(src, l.card, l.id)
    TFC.Emit('licenseIssued', src, l.id)
    TFC.Log.Info('%s got %s', p:GetFullName(), l.label)
    return { ok = true, message = ('Here is your %s.'):format(l.label) }
end

function DmvActions.replace(src, d)
    local l = defs[d.id]
    if not l then return fail('unknown license') end
    local r = records(src)[l.id]
    if not r or r.status ~= 'valid' then return fail('you need a valid license to get a replacement card') end
    if hasCard(src, l.card, l.id) then return fail('you already have the card') end
    if not GovSrv.pay(src, Cfg.ReplacementFee, ('DMV: replacement %s card'):format(l.label)) then
        return fail(('you need $%d'):format(Cfg.ReplacementFee))
    end
    giveCard(src, l.card, l.id)
    return { ok = true, message = 'Here is your replacement card.' }
end

local function isAuthority(src, supervisor)
    if GetResourceState('tfc-jobs') ~= 'started' then return false end
    local job = exports['tfc-jobs']:GetJob(src)
    if not job or not job.onDuty then return false end
    for _, j in ipairs(Cfg.Authority.jobs) do
        if job.name == j then return not supervisor or job.grade >= Cfg.Authority.supervisorGrade end
    end
    return false
end
GovSrv.isAuthority = isAuthority

function DmvActions.reinstate(src, d)
    local l = defs[d.id]
    if not l then return fail('unknown license') end
    local r = records(src)[l.id]
    if not r or r.status == 'valid' then return fail('that license isn\'t suspended or revoked') end
    local p = player(src)
    local pending = int((MySQL.scalar.await("SELECT COUNT(*) FROM tfc_license_requests WHERE character_id = ? AND type = ? AND status = 'pending'",
        { p.characterId, l.id }))) or 0
    if pending > 0 then return fail('you already asked; a supervisor will review it') end
    MySQL.insert.await('INSERT INTO tfc_license_requests (character_id, cid, name, type) VALUES (?, ?, ?, ?)', { p.characterId, p.cid, p:GetFullName(), l.id })
    for _, other in ipairs(TFC.GetPlayers()) do
        if isAuthority(other, true) then
            notify(other, ('%s asks to have their %s reinstated. /%s'):format(p:GetFullName(), l.label, Cfg.RequestsCommand))
        end
    end
    return { ok = true, message = 'Request sent. A police supervisor has to approve it.' }
end

-- Police: view, suspend, revoke, reinstate --------------------------------------------------------------

local function targetInfo(target)
    local p = player(target)
    if not p then return nil end
    local recs = recordsByCharId(p.characterId)
    local list = {}
    for _, l in ipairs(Cfg.Licenses) do
        local r = recs[l.id]
        list[#list + 1] = { id = l.id, label = l.label, status = r and r.status or 'none', reason = r and r.reason or '' }
    end
    local events = MySQL.query.await('SELECT type, action, reason, by_name, UNIX_TIMESTAMP(created_at) AS at FROM tfc_license_events WHERE character_id = ? ORDER BY id DESC LIMIT 15',
        { p.characterId }) or {}
    for _, e in ipairs(events) do e.at = int(e.at) end
    return { id = target, name = p:GetFullName(), cid = p.cid, licenses = list, events = events }
end

local function dist(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or pa == 0 or not pb or pb == 0 then return math.huge end
    local x, y = GetEntityCoords(pa), GetEntityCoords(pb)
    local dx, dy, dz = x.x - y.x, x.y - y.y, x.z - y.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function GovSrv.policeView(src, target)
    if not isAuthority(src) then return fail('you need to be police on duty') end
    target = int(target)
    if not target or target == src or not player(target) then return fail('nobody there') end
    if dist(src, target) > Cfg.PoliceDistance + 1.0 then return fail('they are too far away') end
    return { ok = true, target = targetInfo(target), supervisor = isAuthority(src, true) }
end

---@param action 'suspend'|'revoke'|'reinstate'
local function setStatus(by, charId, cid, id, action, reason)
    local status = action == 'reinstate' and 'valid' or (action == 'suspend' and 'suspended' or 'revoked')
    MySQL.update.await('UPDATE tfc_licenses SET status = ?, reason = ? WHERE character_id = ? AND type = ?',
        { status, action == 'reinstate' and '' or reason, charId, id })
    event(charId, id, action, reason, by)
    TFC.Emit('licenseStatusChanged', cid, id, status, by)
    return status
end

function GovSrv.policeSet(src, target, id, action, reason)
    local view = GovSrv.policeView(src, target)
    if not view.ok then return view end
    local l = defs[id]
    if not l then return fail('unknown license') end
    target = int(target)
    local p = player(target)
    local r = recordsByCharId(p.characterId)[id]
    if not r then return fail(('they don\'t have a %s'):format(l.label)) end
    reason = clean(reason, 120)

    if action == 'reinstate' then
        if not isAuthority(src, true) then return fail('only a supervisor can reinstate') end
        if r.status == 'valid' then return fail('it is already valid') end
        setStatus(src, p.characterId, p.cid, id, 'reinstate', reason)
        MySQL.update.await("UPDATE tfc_license_requests SET status = 'approved', handled_by = ?, closed_at = CURRENT_TIMESTAMP WHERE character_id = ? AND type = ? AND status = 'pending'",
            { player(src):GetFullName(), p.characterId, id })
        notify(target, ('Your %s was reinstated. Get a replacement card at the DMV.'):format(l.label), 'success')
    elseif action == 'suspend' or action == 'revoke' then
        if #reason < 3 then return fail('give a reason') end
        if r.status == (action == 'suspend' and 'suspended' or 'revoked') then return fail('it already is') end
        setStatus(src, p.characterId, p.cid, id, action, reason)
        -- Take the card. Driving classes: the Driver's License card is reprinted without them
        -- (or taken if nothing valid is left).
        removeCard(target, l.card, id)
        if l.card == 'driver' then giveCard(target, 'driver', id) end
        notify(target, ('Your %s was %s: %s'):format(l.label, action == 'suspend' and 'suspended' or 'revoked', reason), 'error')
    else
        return fail('unknown action')
    end
    TFC.Log.Info('%s: %s %s of %s (%s)', player(src):GetFullName(), action, l.label, p:GetFullName(), reason)
    local fresh = GovSrv.policeView(src, target)
    fresh.message = ('%s: %s'):format(l.label, action == 'reinstate' and 'reinstated' or (action == 'suspend' and 'suspended' or 'revoked'))
    return fresh
end

function GovSrv.requests(src)
    if not isAuthority(src, true) then return fail('only police supervisors on duty can review requests') end
    local rows = MySQL.query.await([[
        SELECT r.id, r.cid, r.name, r.type, UNIX_TIMESTAMP(r.created_at) AS at, l.status, l.reason
        FROM tfc_license_requests r LEFT JOIN tfc_licenses l ON l.character_id = r.character_id AND l.type = r.type
        WHERE r.status = 'pending' ORDER BY r.id
    ]]) or {}
    for _, r in ipairs(rows) do
        r.id, r.at = int(r.id), int(r.at)
        r.label = defs[r.type] and defs[r.type].label or r.type
    end
    return { ok = true, requests = rows }
end

function GovSrv.decide(src, requestId, approve)
    if not isAuthority(src, true) then return fail('only police supervisors on duty can review requests') end
    local r = MySQL.single.await("SELECT id, character_id, cid, name, type FROM tfc_license_requests WHERE id = ? AND status = 'pending'", { int(requestId) or -1 })
    if not r then return fail('that request was already handled') end
    local by = player(src):GetFullName()
    MySQL.update.await("UPDATE tfc_license_requests SET status = ?, handled_by = ?, closed_at = CURRENT_TIMESTAMP WHERE id = ?",
        { approve and 'approved' or 'denied', by, r.id })
    local online = TFC.GetPlayerByCid(r.cid)
    local label = defs[r.type] and defs[r.type].label or r.type
    if approve then
        setStatus(src, math.tointeger(r.character_id), r.cid, r.type, 'reinstate', 'approved by ' .. by)
        if online then notify(online.source, ('Your %s was reinstated. Get a replacement card at the DMV.'):format(label), 'success') end
    else
        event(math.tointeger(r.character_id), r.type, 'denied', 'reinstatement denied by ' .. by, src)
        if online then notify(online.source, ('Your request to reinstate your %s was denied.'):format(label), 'error') end
    end
    TFC.Log.Info('%s %s reinstatement of %s for %s', by, approve and 'approved' or 'denied', label, r.name)
    local list = GovSrv.requests(src)
    list.message = approve and ('Reinstated %s for %s'):format(label, r.name) or 'Request denied'
    return list
end

TFC.On('playerUnloaded', function(src) quizzes[src] = nil end)

function GovSrv.createTables()
    for _, q in ipairs(SCHEMA) do MySQL.query.await(q) end
end
