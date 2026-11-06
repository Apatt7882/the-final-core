// Store manager and admin businesses panel. The server checks everything.

const $ = (id) => document.getElementById(id);
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'tfc-business';

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
const ago = (t) => {
    const s = Math.max(0, Date.now() / 1000 - t);
    if (s < 60) return 'just now';
    if (s < 3600) return `${Math.floor(s / 60)} min ago`;
    if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
    return `${Math.floor(s / 86400)} d ago`;
};

const S = { view: null, data: null, imagePath: '', busy: false, selected: null, search: '', filter: 'all' };

function setMsg(id, text, ok) {
    const el = $(id);
    el.textContent = text || '';
    el.className = 'msg' + (text ? (ok ? ' ok' : ' err') : '');
}

function close() {
    $('backdrop').classList.add('hidden');
    nui('close');
}
document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', close));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !$('backdrop').classList.contains('hidden')) close(); });

// Store manager -----------------------------------------------------------------------------------

const ROLE = { owner: 'Owner', manager: 'Manager', staff: 'Staff' };

function renderBiz() {
    const d = S.data;
    const owner = d.business.role === 'owner';
    $('biz-role').textContent = `Business · ${ROLE[d.business.role] || ''}`;
    $('biz-title').textContent = d.business.label;
    $('biz-hint').textContent = owner
        ? `Restocking costs ${Math.round(d.wholesaleRate * 100)}% of the base price, paid from the store savings.`
        : `Restocking is paid from the store savings. Only the owner can change prices.`;

    const savings = d.savings === false
        ? `<div class="card locked"><div class="k">Savings</div><div class="v">Owner only</div></div>`
        : `<div class="card"><div class="k">Savings</div><div class="v">${money(d.savings)}</div><div class="s">Deposit or withdraw in the Boss Menu</div></div>`;
    $('biz-cards').innerHTML = savings + [
        ['Sales today', money(d.today.total), `${d.today.count} sale${d.today.count === 1 ? '' : 's'} · ${money(d.today.staff)} to staff`],
        ['Last 7 days', money(d.week.total), `${d.week.count} sales`],
        ['Staff on duty', String(d.staffOnDuty), 'Paid a share of sales at the store'],
    ].map(([k, v, s]) => `<div class="card"><div class="k">${k}</div><div class="v">${v}</div><div class="s">${s}</div></div>`).join('');

    $('biz-items').innerHTML = d.items.map((it) => {
        const pct = it.max ? Math.round((it.stock / it.max) * 100) : 0;
        const level = it.stock === 0 ? 'out' : (pct <= 20 ? 'low' : '');
        const price = owner
            ? `<input class="price-in" type="number" min="${it.minPrice}" max="${it.maxPrice}" value="${it.price}" data-price="${esc(it.name)}" title="$${it.minPrice} to $${it.maxPrice}">`
            : money(it.price);
        const room = Math.max(0, d.shelf - it.stock);
        const qty = Math.min(10, room) || 0;
        return `<tr>
            <td><div class="item"><img src="${S.imagePath}${esc(it.name)}.png" alt="" onerror="this.style.visibility='hidden'">
                <div><div>${esc(it.label)}</div><div class="base">Base ${money(it.basePrice)} · wholesale ${money(it.wholesale)}</div></div></div></td>
            <td class="shelf"><span class="n ${level}">${it.stock === 0 ? 'Sold out' : `${it.stock} / ${it.max}`}</span>
                <div class="track"><div class="fill ${level}" style="width:${pct}%"></div></div></td>
            <td>${price}</td>
            <td><div class="restock">
                <input class="qty-in" type="number" min="1" max="${room}" value="${qty}" data-qty="${esc(it.name)}" ${room === 0 ? 'disabled' : ''}>
                <button class="secondary small" data-restock="${esc(it.name)}" ${room === 0 ? 'disabled' : ''}>${room === 0 ? 'Full' : `Restock · ${money(qty * it.wholesale)}`}</button>
            </div></td>
        </tr>`;
    }).join('');

    $('biz-sales').innerHTML = d.recent.length ? d.recent.map((r) => {
        const it = d.items.find((x) => x.name === r.item);
        return `<div class="sale"><span>${r.count}× ${esc(it ? it.label : r.item)}</span><span class="amt">${money(r.total)}</span>
            <span class="meta">${ago(r.at)} · ${r.staff ? `${money(r.to_staff)} to ${r.staff} staff, ` : ''}${money(r.to_savings)} to savings</span></div>`;
    }).join('') : '<p class="muted">No sales yet.</p>';
}

async function bizAct(action, data) {
    if (S.busy) return;
    S.busy = true;
    const r = await nui('action', { action, data });
    S.busy = false;
    if (r && r.business) S.data = r;
    setMsg('biz-msg', r && r.ok ? r.message : ((r && r.error) || 'something went wrong'), r && r.ok);
    renderBiz();
}

$('biz-items').addEventListener('input', (e) => {
    const name = e.target.dataset.qty;
    if (!name) return;
    const it = S.data.items.find((x) => x.name === name);
    const n = Math.max(0, Math.floor(Number(e.target.value) || 0));
    const btn = document.querySelector(`[data-restock="${CSS.escape(name)}"]`);
    if (btn) btn.textContent = `Restock · ${money(n * it.wholesale)}`;
});
$('biz-items').addEventListener('change', (e) => {
    const name = e.target.dataset.price;
    if (name) bizAct('setPrice', { item: name, price: Number(e.target.value) });
});
$('biz-items').addEventListener('click', (e) => {
    const btn = e.target.closest('[data-restock]');
    if (!btn) return;
    const name = btn.dataset.restock;
    const qty = Number(document.querySelector(`[data-qty="${CSS.escape(name)}"]`).value);
    bizAct('restock', { item: name, count: qty });
});

// Admin ---------------------------------------------------------------------------------------------

function statusOf(row) {
    const b = row.business;
    if (!b) return '<span class="pill">Not a business</span>';
    if (b.forSale) return `<span class="pill sale">For sale · ${money(b.price)}</span>`;
    if (b.ownerName) return '<span class="pill owned">Owned</span>';
    return '<span class="pill vacant">No owner</span>';
}

function renderAdmin() {
    const d = S.data;
    const q = S.search.trim().toLowerCase();
    const rows = d.list.filter((r) => {
        const b = r.business;
        if (S.filter === 'biz' && !b) return false;
        if (S.filter === 'owned' && !(b && b.ownerName)) return false;
        if (S.filter === 'sale' && !(b && b.forSale)) return false;
        if (S.filter === 'none' && b) return false;
        if (!q) return true;
        return String(r.shopId) === q.replace('#', '') || r.shopLabel.toLowerCase().includes(q)
            || (b && (b.label.toLowerCase().includes(q) || (b.ownerName || '').toLowerCase().includes(q)));
    });
    const count = d.list.filter((r) => r.business).length;
    $('adm-count').textContent = `${count} business${count === 1 ? '' : 'es'} · ${d.list.length} stores`;

    $('adm-rows').innerHTML = rows.map((r) => {
        const b = r.business;
        return `<tr class="click${r.shopId === S.selected ? ' current' : ''}" data-shop="${r.shopId}">
            <td class="muted">${r.shopId}</td>
            <td><div>${esc(b ? b.label : r.shopLabel)}</div><div class="sub">${esc(r.typeLabel)}${b ? ` · job ${esc(b.job)}` : ''}</div></td>
            <td>${b && b.ownerName ? esc(b.ownerName) + `<div class="sub">${esc(b.ownerCid)}</div>` : '<span class="muted">–</span>'}</td>
            <td>${statusOf(r)}</td>
            <td class="num">${b ? money(b.savings) : '–'}</td>
        </tr>`;
    }).join('');
    $('adm-rows').querySelectorAll('[data-shop]').forEach((tr) => tr.addEventListener('click', () => {
        S.selected = Number(tr.dataset.shop);
        setMsg('adm-msg', '');
        renderAdmin();
    }));

    const reqs = d.requests || [];
    $('adm-requests').classList.toggle('hidden', reqs.length === 0);
    $('adm-requests').innerHTML = `<h2>Purchase requests (${reqs.length})</h2>` + reqs.map((r) => `
        <div class="req"><span class="who"><span class="dot ${r.online ? 'on' : ''}" title="${r.online ? 'In the city' : 'Offline'}"></span>
            <strong>${esc(r.name)}</strong> wants <strong>${esc(r.label)}</strong> for ${money(r.price)} <span class="sub">· ${ago(r.at)}</span></span>
            <button class="primary small" data-approve="${r.id}" ${r.online ? '' : 'disabled title="They must be in the city to pay"'}>Approve</button>
            <button class="ghost small" data-deny="${r.id}">Deny</button></div>`).join('');
    $('adm-requests').querySelectorAll('[data-approve]').forEach((b) => b.addEventListener('click', () => admAct('approve', { request: Number(b.dataset.approve) })));
    $('adm-requests').querySelectorAll('[data-deny]').forEach((b) => b.addEventListener('click', () => admAct('deny', { request: Number(b.dataset.deny) })));

    renderAdminDetail();
}

function renderAdminDetail() {
    const row = S.data.list.find((r) => r.shopId === S.selected);
    $('adm-none').classList.toggle('hidden', !!row);
    $('adm-detail').classList.toggle('hidden', !row);
    if (!row) return;
    const b = row.business;

    if (!b) {
        $('adm-detail').innerHTML = `
            <p class="detail-title">${esc(row.shopLabel)}</p>
            <p class="note">Shop #${row.shopId} (${esc(row.typeLabel)}) isn't a business yet. Make it one to give it an owner, staff and savings.</p>
            <label class="field-label" for="d-label">Business name</label>
            <div class="row"><input id="d-label" maxlength="48" placeholder="e.g. Strawberry 24/7"><button class="primary" id="d-create">Create</button></div>`;
        $('d-create').addEventListener('click', () => admAct('create', { shopId: row.shopId, label: $('d-label').value }));
        return;
    }

    $('adm-detail').innerHTML = `
        <p class="detail-title">${esc(b.label)}</p>
        <p class="note">Shop #${row.shopId} · ${esc(row.typeLabel)} · job <code>${esc(b.job)}</code><br>Savings ${money(b.savings)}</p>

        <label class="field-label" for="d-rename">Name</label>
        <div class="row"><input id="d-rename" maxlength="48" value="${esc(b.label)}"><button class="secondary" id="d-save">Save</button></div>

        <label class="field-label" for="d-owner">Owner</label>
        <p class="note">${b.ownerName ? `Owned by <strong>${esc(b.ownerName)}</strong> (${esc(b.ownerCid)})` : 'No owner. The store works like a normal shop until it has one.'}</p>
        <div class="row" style="margin-top:8px"><input id="d-owner" placeholder="Player ID or CID"><button class="secondary" id="d-setowner">${b.ownerName ? 'Change' : 'Set owner'}</button></div>
        ${b.ownerName ? '<div class="row" style="margin-top:8px"><button class="danger" id="d-removeowner">Remove owner</button></div>' : ''}

        <label class="field-label" for="d-price">For sale</label>
        <p class="note">${b.forSale ? `Listed at <strong>${money(b.price)}</strong>. Players can request to buy it in the store.` : 'Not listed. Listed stores show a "Request to buy" button in the shop.'}</p>
        <div class="row" style="margin-top:8px"><input id="d-price" type="number" min="1" placeholder="Price" value="${b.forSale ? b.price : ''}">
            <button class="secondary" id="d-list">${b.forSale ? 'Update price' : 'List for sale'}</button></div>
        ${b.forSale ? '<div class="row" style="margin-top:8px"><button class="ghost" id="d-unlist">Take off the market</button></div>' : ''}`;

    $('d-save').addEventListener('click', () => admAct('rename', { id: b.id, label: $('d-rename').value }));
    $('d-setowner').addEventListener('click', () => {
        const v = $('d-owner').value.trim();
        admAct('setOwner', { id: b.id, who: /^\d+$/.test(v) ? Number(v) : v });
    });
    if ($('d-removeowner')) $('d-removeowner').addEventListener('click', () => admAct('removeOwner', { id: b.id }));
    $('d-list').addEventListener('click', () => admAct('list', { id: b.id, price: Number($('d-price').value) }));
    if ($('d-unlist')) $('d-unlist').addEventListener('click', () => admAct('unlist', { id: b.id }));
}

async function admAct(action, data) {
    if (S.busy) return;
    S.busy = true;
    const r = await nui('admin', { action, data });
    S.busy = false;
    if (r && r.list) S.data = r;
    setMsg('adm-msg', r && r.ok ? r.message : ((r && r.error) || 'something went wrong'), r && r.ok);
    renderAdmin();
}

$('adm-search').addEventListener('input', (e) => { S.search = e.target.value; renderAdmin(); });
$('adm-filter').addEventListener('change', (e) => { S.filter = e.target.value; renderAdmin(); });

// Messages ------------------------------------------------------------------------------------------

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') {
        S.view = m.view;
        S.data = m.data;
        S.imagePath = m.imagePath || '';
        $('biz').classList.toggle('hidden', m.view !== 'business');
        $('adm').classList.toggle('hidden', m.view !== 'admin');
        $('backdrop').classList.remove('hidden');
        setMsg('biz-msg', '');
        setMsg('adm-msg', '');
        if (m.view === 'admin') renderAdmin(); else renderBiz();
    } else if (m.action === 'close') {
        $('backdrop').classList.add('hidden');
    }
});
