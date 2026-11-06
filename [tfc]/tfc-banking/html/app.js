// Bank / ATM / bills window. The server checks everything; this page shows data and asks.

const $ = (id) => document.getElementById(id);
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'tfc-banking';

async function nui(name, data = {}) {
    try {
        const res = await fetch(`https://${resource}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        });
        return await res.json();
    } catch (e) {
        return { ok: false, error: 'no response, try again' };
    }
}

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => (n < 0 ? '-$' : '$') + Math.abs(Math.round(n || 0)).toLocaleString('en-US');
const signed = (n) => (n > 0 ? '+' : '') + money(n);
const when = (t) => {
    if (!t) return '';
    const d = new Date(t * 1000);
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) + ' ' + d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
};

const S = { data: null, page: 'overview', histPage: 1, lookup: null, busy: false, pin: '' };

function setMsg(el, text, ok) {
    el.textContent = text || '';
    el.className = el.className.replace(/\b(ok|err)\b/g, '').trim() + (text ? (ok ? ' ok' : ' err') : '');
}

function close() {
    $('backdrop').classList.add('hidden');
    $('bank').classList.add('hidden');
    $('atm').classList.add('hidden');
    nui('close');
}

document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', close));
document.addEventListener('keydown', (e) => {
    if ($('backdrop').classList.contains('hidden')) return;
    if (e.key === 'Escape') return close();
    // Type the PIN on the keyboard too.
    if (!$('atm').classList.contains('hidden') && !$('atm-pin').classList.contains('hidden')) {
        if (/^\d$/.test(e.key)) pinKey(e.key);
        else if (e.key === 'Backspace') pinKey('clear');
        else if (e.key === 'Enter') pinKey('ok');
    }
});

async function act(action, data, msgEl) {
    if (S.busy) return null;
    S.busy = true;
    const r = await nui('action', { action, data });
    S.busy = false;
    if (r && r.balances) { S.data.balances = r.balances; S.data.billsPending = r.billsPending; }
    if (msgEl) setMsg(msgEl, r && r.ok ? (r.message || '') : ((r && r.error) || 'something went wrong'), r && r.ok);
    renderWallet();
    return r;
}

// Bank ----------------------------------------------------------------------------------------

function renderWallet() {
    const b = S.data.balances || {};
    const chips = [['cash', 'Cash'], ['bank', 'Bank']];
    $('b-wallet').innerHTML = chips.map(([k, l]) => `<div class="chip"><span>${l}</span><strong>${money(b[k] || 0)}</strong></div>`).join('');
    const n = S.data.billsPending || 0;
    $('b-bills-badge').textContent = n;
    $('b-bills-badge').classList.toggle('hidden', n === 0);
    if (!$('atm').classList.contains('hidden')) renderAtm();
    if (S.page === 'overview') renderOverview();
    if (S.page === 'credit') renderCredit();
}

function cards(list) {
    return list.map(([k, v, s, cls]) => `<div class="card"><div class="k">${k}</div><div class="v ${cls || ''}">${v}</div>${s ? `<div class="s">${s}</div>` : ''}</div>`).join('');
}

function renderOverview() {
    const b = S.data.balances || {};
    const credit = b.credit || 0;
    const limit = S.data.creditLimit || 0;
    $('o-cards').innerHTML = cards([
        ['Bank', money(b.bank)],
        ['Cash', money(b.cash), 'in your wallet'],
        ['Credit available', money(limit + credit), credit < 0 ? `<span class="neg">${money(-credit)} owed</span>` : `of ${money(limit)}`],
    ]);
    const rows = ((S.data.history && S.data.history.rows) || []).slice(0, 6);
    $('o-recent').innerHTML = rows.length ? rows.map(activityHtml).join('') : '<p class="empty">No activity yet.</p>';
}

function activityHtml(r) {
    return `<div class="activity"><span>${esc(r.reason || r.account)}</span><span class="amt ${r.amount < 0 ? 'neg' : 'pos'}">${signed(r.amount)}</span>
        <span class="when">${when(r.at)} · ${esc(r.account)}</span></div>`;
}

function renderHistory() {
    const h = S.data.history || { rows: [], page: 1, more: false };
    $('h-rows').innerHTML = h.rows.length ? h.rows.map((r) => `<tr>
        <td class="muted">${when(r.at)}</td><td>${esc(r.reason)}</td><td class="acct">${esc(r.account)}</td>
        <td class="num ${r.amount < 0 ? 'neg' : 'pos'}">${signed(r.amount)}</td><td class="num">${money(r.balance)}</td></tr>`).join('')
        : '<tr><td colspan="5" class="empty">No activity yet.</td></tr>';
    $('h-page').textContent = `Page ${h.page}`;
    $('h-prev').disabled = h.page <= 1;
    $('h-next').disabled = !h.more;
}

async function loadHistory(page) {
    const r = await act('history', { page }, null);
    if (r && r.ok) { S.data.history = { rows: r.rows, page: r.page, more: r.more }; renderHistory(); }
}

function billHtml(b, pending) {
    if (!pending) {
        return `<div class="bill closed"><div><span class="from">${esc(b.sourceLabel)}</span> <span class="status ${esc(b.status)}">${esc(b.status)}</span>
            <div class="reason">${esc(b.reason)} · ${when(b.closedAt || b.createdAt)}</div></div><div class="amt">${money(b.amount)}</div></div>`;
    }
    return `<div class="bill"><div><div class="from">${esc(b.sourceLabel)}</div><div class="reason">${esc(b.reason)}</div>
        <div class="meta">#${b.id} · ${when(b.createdAt)}${b.senderName ? ' · from ' + esc(b.senderName) : ''}</div></div>
        <div class="amt">${money(b.amount)}</div>
        <div class="acts"><button class="primary small" data-pay="${b.id}">Pay ${money(b.amount)}</button>
        ${b.mandatory ? '<span class="lock">Can\'t be declined</span>' : `<button class="ghost small" data-decline="${b.id}">Decline</button>`}</div></div>`;
}

function renderBills() {
    const bills = S.data.bills || { pending: [], closed: [] };
    $('bills-pending').innerHTML = bills.pending.length ? bills.pending.map((b) => billHtml(b, true)).join('') : '<p class="empty">You have no bills to pay.</p>';
    $('bills-closed').innerHTML = bills.closed.length ? bills.closed.map((b) => billHtml(b, false)).join('') : '<p class="empty">Nothing yet.</p>';
    document.querySelectorAll('[data-pay]').forEach((b) => b.addEventListener('click', async () => {
        const r = await act('payBill', { id: Number(b.dataset.pay) }, $('b-msg'));
        if (r && r.bills) { S.data.bills = r.bills; renderBills(); }
    }));
    document.querySelectorAll('[data-decline]').forEach((b) => b.addEventListener('click', async () => {
        const r = await act('declineBill', { id: Number(b.dataset.decline) }, $('b-msg'));
        if (r && r.bills) { S.data.bills = r.bills; renderBills(); }
    }));
}

async function loadBills() {
    const r = await act('bills', {}, null);
    if (r && r.ok) { S.data.bills = { pending: r.pending, closed: r.closed }; renderBills(); }
}

function renderCredit() {
    const credit = (S.data.balances || {}).credit || 0;
    const limit = S.data.creditLimit || 0;
    const i = S.data.interest || {};
    $('c-cards').innerHTML = cards([
        ['Owed', money(-credit), '', credit < 0 ? 'neg' : ''],
        ['Available', money(limit + credit)],
        ['Credit limit', money(limit)],
    ]);
    const next = i.nextAt ? new Date(i.nextAt * 1000).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' }) : 'in a week';
    $('c-info').textContent = credit < 0
        ? `${(i.rate * 100).toFixed(1).replace(/\.0$/, '')}% interest is added to what you owe every ${i.everyDays} days (next: ${next}). Repaying comes out of your bank.`
        : 'You don\'t owe anything. Purchases and bills that your bank can\'t cover use your credit line.';
    $('c-repay').disabled = credit >= 0;
    $('c-all').disabled = credit >= 0;
}

function renderPin() {
    const has = !!S.data.hasPin;
    $('p-title').textContent = has ? 'Change your ATM PIN' : 'Set up your ATM PIN';
    $('p-old-wrap').classList.toggle('hidden', !has);
}

function showPage(page) {
    S.page = page;
    document.querySelectorAll('#b-nav [data-page]').forEach((b) => b.classList.toggle('on', b.dataset.page === page));
    document.querySelectorAll('.page').forEach((p) => p.classList.toggle('hidden', p.dataset.page !== page));
    setMsg($('b-msg'), '');
    if (page === 'overview') renderOverview();
    if (page === 'history') renderHistory();
    if (page === 'bills') renderBills();
    if (page === 'credit') renderCredit();
    if (page === 'settings') renderPin();
}

document.querySelectorAll('#b-nav [data-page]').forEach((b) => b.addEventListener('click', () => showPage(b.dataset.page)));
document.querySelector('#b-nav [data-finance]').addEventListener('click', () => {
    $('backdrop').classList.add('hidden');
    nui('finance');
});

// Overview actions
async function cashMove(action) {
    const amount = Number($('o-amount').value);
    const r = await act(action, { amount }, $('b-msg'));
    if (r && r.ok) { $('o-amount').value = ''; loadHistory(1); }
}
$('o-deposit').addEventListener('click', () => cashMove('deposit'));
$('o-withdraw').addEventListener('click', () => cashMove('withdraw'));
document.querySelectorAll('[data-quick]').forEach((b) => b.addEventListener('click', () => {
    $('o-amount').value = b.dataset.quick === 'cash' ? ((S.data.balances || {}).cash || '') : b.dataset.quick;
}));

// Transfer
$('t-id').addEventListener('input', () => { S.lookup = null; $('t-who').textContent = ''; $('t-send').disabled = true; });
$('t-lookup').addEventListener('click', async () => {
    const r = await act('lookup', { id: Number($('t-id').value) }, $('b-msg'));
    if (r && r.ok) {
        S.lookup = r.id;
        $('t-who').textContent = `✓ ${r.name} (ID ${r.id})`;
        $('t-send').disabled = false;
    }
});
$('t-send').addEventListener('click', async () => {
    if (!S.lookup) return;
    const r = await act('transfer', { id: S.lookup, amount: Number($('t-amount').value), note: $('t-note').value }, $('b-msg'));
    if (r && r.ok) { $('t-amount').value = ''; $('t-note').value = ''; loadHistory(1); }
});

// History paging
$('h-prev').addEventListener('click', () => loadHistory((S.data.history.page || 1) - 1));
$('h-next').addEventListener('click', () => loadHistory((S.data.history.page || 1) + 1));

// Credit
$('c-repay').addEventListener('click', async () => {
    const r = await act('repay', { amount: Number($('c-amount').value) }, $('b-msg'));
    if (r && r.ok) { $('c-amount').value = ''; loadHistory(1); }
});
$('c-all').addEventListener('click', async () => {
    const r = await act('repay', { amount: 'all' }, $('b-msg'));
    if (r && r.ok) loadHistory(1);
});

// PIN
$('p-save').addEventListener('click', async () => {
    const pin = $('p-new').value;
    if (!/^\d{4}$/.test(pin)) return setMsg($('b-msg'), 'Your PIN must be 4 digits.', false);
    if (pin !== $('p-new2').value) return setMsg($('b-msg'), 'The two new PINs don\'t match.', false);
    const r = await act('setPin', { old: $('p-old').value, new: pin }, $('b-msg'));
    if (r && r.ok) {
        S.data.hasPin = true;
        ['p-old', 'p-new', 'p-new2'].forEach((id) => { $(id).value = ''; });
        renderPin();
    }
});

function openBank(d) {
    const billsOnly = d.kind === 'bills';
    $('b-brand').textContent = billsOnly ? 'Bills' : d.label;
    $('b-title').textContent = billsOnly ? 'Your bills' : `Welcome, ${d.name}`;
    $('b-nav').classList.toggle('hidden', billsOnly);
    document.querySelector('#b-nav [data-finance]').classList.toggle('hidden', !d.finance);
    $('bank').querySelector('.bank-body').style.gridTemplateColumns = billsOnly ? '1fr' : '';
    $('atm').classList.add('hidden');
    $('bank').classList.remove('hidden');
    $('backdrop').classList.remove('hidden');
    renderWallet();
    showPage(billsOnly ? 'bills' : 'overview');
}

// ATM -----------------------------------------------------------------------------------------------

function renderDots() {
    document.querySelectorAll('#atm-dots span').forEach((d, i) => d.classList.toggle('on', i < S.pin.length));
}

function renderAtm() {
    const b = S.data.balances || {};
    $('atm-balances').innerHTML = `<div><span>Bank</span><strong>${money(b.bank)}</strong></div><div><span>Cash</span><strong>${money(b.cash)}</strong></div>`;
}

async function pinKey(k) {
    if (k === 'clear') { S.pin = ''; renderDots(); return; }
    if (k === 'ok') {
        if (S.pin.length !== 4) return;
        const r = await act('pin', { pin: S.pin }, $('atm-msg'));
        S.pin = '';
        renderDots();
        if (r && r.ok) {
            setMsg($('atm-msg'), '');
            $('atm-pin').classList.add('hidden');
            $('atm-main').classList.remove('hidden');
            renderAtm();
        }
        return;
    }
    if (S.pin.length < 4) { S.pin += k; renderDots(); }
    if (S.pin.length === 4) pinKey('ok');
}

$('atm-keys').querySelectorAll('button').forEach((b) => b.addEventListener('click', () => pinKey(b.dataset.k || b.textContent.trim())));
$('atm-quick').querySelectorAll('[data-w]').forEach((b) => b.addEventListener('click', () => act('withdraw', { amount: Number(b.dataset.w) }, $('atm-msg'))));
$('atm-withdraw').addEventListener('click', async () => {
    const r = await act('withdraw', { amount: Number($('atm-amount').value) }, $('atm-msg'));
    if (r && r.ok) $('atm-amount').value = '';
});
$('atm-deposit').addEventListener('click', async () => {
    const r = await act('deposit', { amount: Number($('atm-amount').value) }, $('atm-msg'));
    if (r && r.ok) $('atm-amount').value = '';
});

function openAtm() {
    S.pin = '';
    renderDots();
    setMsg($('atm-msg'), '');
    $('atm-pin').classList.remove('hidden');
    $('atm-main').classList.add('hidden');
    $('bank').classList.add('hidden');
    $('atm').classList.remove('hidden');
    $('backdrop').classList.remove('hidden');
}

// Messages ------------------------------------------------------------------------------------------

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') {
        S.data = m.data;
        S.lookup = null;
        if (m.data.kind === 'atm') openAtm(); else openBank(m.data);
    } else if (m.action === 'close') {
        $('backdrop').classList.add('hidden');
    } else if (m.action === 'billsChanged') {
        if (S.data && S.data.kind !== 'atm') loadBills();
    }
});
