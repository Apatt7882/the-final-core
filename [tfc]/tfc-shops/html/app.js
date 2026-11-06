// Shops NUI: the shop window (buy / sell) and the admin shop manager.
// The server checks everything; this page only shows data and sends requests.

const $ = (id) => document.getElementById(id);
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'tfc-shops';

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

const money = (n) => (n < 0 ? '-$' : '$') + Math.abs(Math.round(n)).toLocaleString('en-US');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const grams = (g) => (g >= 1000 ? `${(g / 1000).toFixed(1)} kg` : `${g} g`);

function setMsg(el, text, ok) {
    el.textContent = text || '';
    el.className = 'msg' + (text ? (ok ? ' ok' : ' err') : '');
}

function closeAll() {
    $('backdrop').classList.add('hidden');
    $('shop').classList.add('hidden');
    $('admin').classList.add('hidden');
}

document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => { closeAll(); nui('close'); }));
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('backdrop').classList.contains('hidden')) { closeAll(); nui('close'); }
});

// =============================================================================================
// Shop window
// =============================================================================================

const S = {
    shop: null,
    imagePath: '',
    mode: 'buy',
    selected: null,
    qty: 1,
    payment: null,
    busy: false,
};

const KICKERS = { general: 'Store', ammunation: 'Gun store', pawn: 'Pawn shop', drugdealer: 'Street', armsdealer: 'Black market', police_armory: 'Armory', ems_supply: 'Supply' };

function openShop(shop, imagePath) {
    S.shop = shop;
    S.imagePath = imagePath || '';
    S.mode = shop.items.length ? 'buy' : 'sell';
    S.selected = null;
    S.qty = 1;
    S.payment = shop.payment[0] ? shop.payment[0].id : null;

    $('shop-kicker').textContent = KICKERS[shop.type] || 'Shop';
    $('shop-title').textContent = shop.label;
    $('shop-tabs').classList.toggle('hidden', !(shop.items.length && shop.buys.length));
    renderStore();

    $('admin').classList.add('hidden');
    $('shop').classList.remove('hidden');
    $('backdrop').classList.remove('hidden');
    renderShop();
}

// Business info: owner line, and a "for sale" banner with a purchase request button.
function renderStore() {
    const st = S.shop.store;
    $('shop-owner').classList.toggle('hidden', !(st && st.owned && st.ownerName));
    if (st && st.ownerName) $('shop-owner').textContent = `Owned by ${st.ownerName}`;
    const sale = st && st.forSale;
    $('sale-banner').classList.toggle('hidden', !sale);
    if (sale) $('sale-text').innerHTML = `This store is for sale: <strong>${money(st.price)}</strong>`;
    $('sale-request').classList.remove('hidden');
}

$('sale-request').addEventListener('click', async () => {
    const st = S.shop && S.shop.store;
    if (!st) return;
    $('sale-request').disabled = true;
    const r = await nui('requestBuy', { business: st.business });
    $('sale-request').disabled = false;
    $('sale-text').textContent = r && r.ok ? r.message : `Couldn't request: ${(r && r.error) || 'something went wrong'}`;
    if (r && r.ok) $('sale-request').classList.add('hidden');
});

function list() {
    return S.mode === 'buy' ? S.shop.items : S.shop.buys;
}

function current() {
    return list().find((i) => i.name === S.selected) || null;
}

function maxFor(item) {
    if (!item) return 1;
    let max = S.shop.maxQuantity;
    if (S.mode === 'buy') {
        if (item.max !== false) max = Math.min(max, item.stock);
    } else {
        max = Math.min(max, item.have);
    }
    return Math.max(0, max);
}

function renderWallet() {
    const b = S.shop.balances || {};
    const chips = [['cash', 'Cash'], ['bank', 'Bank']];
    if (S.shop.payment.some((p) => p.id === 'credit')) chips.push(['credit', 'Credit']);
    $('wallet').innerHTML = chips
        .filter(([id]) => b[id] !== undefined)
        .map(([id, label]) => `<div class="chip${b[id] < 0 ? ' neg' : ''}"><span>${label}</span><strong>${money(b[id])}</strong></div>`)
        .join('');
}

function renderTabs() {
    document.querySelectorAll('#shop-tabs .tab').forEach((t) => t.setAttribute('aria-selected', String(t.dataset.mode === S.mode)));
}

function cardHtml(item) {
    const img = `<img src="${S.imagePath}${esc(item.name)}.png" alt="" onerror="this.style.visibility='hidden'">`;
    let tag = '';
    let off = false;
    let sub = '';
    let price;

    if (S.mode === 'buy') {
        price = item.price > 0 ? money(item.price) : 'Free';
        if (item.locked) { tag = `<span class="tag lock">Rank ${item.grade}+</span>`; off = true; }
        else if (item.max !== false) {
            if (item.stock <= 0) { tag = '<span class="tag out">Sold out</span>'; off = true; }
            else tag = `<span class="tag${item.stock <= Math.max(1, Math.floor(item.max / 5)) ? ' low' : ''}">${item.stock} left</span>`;
        }
    } else {
        price = `${money(item.price)} each`;
        sub = `<span class="sub">You have ${item.have}</span>`;
        if (item.have <= 0) off = true;
    }

    return `<button class="card${off ? ' off' : ''}${item.name === S.selected ? ' selected' : ''}" data-name="${esc(item.name)}">
        ${tag}${img}<span class="name">${esc(item.label)}</span><span class="price">${price}</span>${sub}
    </button>`;
}

function renderGrid() {
    const items = list();
    $('grid').innerHTML = items.map(cardHtml).join('');
    const empty = $('grid-empty');
    empty.classList.toggle('hidden', items.length > 0);
    empty.textContent = S.mode === 'buy' ? 'Nothing for sale here.' : 'They are not buying anything.';
    $('grid').querySelectorAll('.card').forEach((c) => c.addEventListener('click', () => select(c.dataset.name)));
}

function select(name) {
    if (S.selected !== name) S.qty = 1;
    S.selected = name;
    setMsg($('msg'), '');
    renderGrid();
    renderPick();
}

function renderPayment(total) {
    const pay = $('pay');
    if (S.mode === 'sell') {
        $('pay-label').textContent = 'Paid into';
        pay.innerHTML = `<span class="note">${esc(S.shop.sellTo.label)}</span>`;
        $('pay-block').classList.remove('hidden');
        return;
    }
    $('pay-label').textContent = 'Pay with';
    $('pay-block').classList.toggle('hidden', total === 0);
    pay.innerHTML = S.shop.payment.map((p) => `<label><input type="radio" name="pay" value="${esc(p.id)}"${p.id === S.payment ? ' checked' : ''}><span>${esc(p.label)}</span></label>`).join('');
    pay.querySelectorAll('input').forEach((i) => i.addEventListener('change', () => { S.payment = i.value; }));
}

function renderPick() {
    const item = current();
    $('pick-empty').classList.toggle('hidden', !!item);
    $('pick').classList.toggle('hidden', !item);
    if (!item) return;

    const max = maxFor(item);
    S.qty = Math.min(Math.max(1, S.qty), Math.max(1, max));

    $('pick-img').src = `${S.imagePath}${item.name}.png`;
    $('pick-img').onerror = function () { this.style.visibility = 'hidden'; };
    $('pick-img').style.visibility = 'visible';
    $('pick-name').textContent = item.label;
    $('pick-desc').textContent = item.description || '';
    $('pick-desc').classList.toggle('hidden', !item.description);

    const facts = [];
    if (S.mode === 'buy') {
        facts.push(['Price', item.price > 0 ? money(item.price) : 'Free']);
        if (item.weight) facts.push(['Weight', grams(item.weight)]);
        if (item.max !== false) facts.push(['In stock', `${item.stock} / ${item.max}`]);
        if (item.grade !== false) facts.push(['Rank needed', `${item.grade}+`]);
    } else {
        facts.push(['They pay', `${money(item.price)} each`]);
        facts.push(['You have', String(item.have)]);
    }
    $('pick-facts').innerHTML = facts.map(([k, v]) => `<dt>${k}</dt><dd>${esc(v)}</dd>`).join('');

    $('qty').value = S.qty;
    $('qty').max = Math.max(1, max);

    const total = item.price * S.qty;
    $('total').textContent = S.mode === 'buy' && total === 0 ? 'Free' : money(total);
    renderPayment(total);

    const btn = $('confirm');
    let blocked = '';
    if (S.mode === 'buy') {
        if (item.locked) blocked = `Needs rank ${item.grade} or higher`;
        else if (max <= 0) blocked = 'Sold out';
        btn.textContent = total === 0 ? `Take ${S.qty}` : `Buy ${S.qty} for ${money(total)}`;
    } else {
        if (max <= 0) blocked = 'You have none to sell';
        btn.textContent = `Sell ${S.qty} for ${money(total)}`;
    }
    btn.disabled = !!blocked || S.busy;
    if (blocked && !$('msg').textContent) setMsg($('msg'), blocked, false);
}

function setQty(n) {
    const item = current();
    S.qty = Math.min(Math.max(1, Math.floor(Number(n) || 1)), Math.max(1, maxFor(item)));
    renderPick();
}

$('qty-minus').addEventListener('click', () => setQty(S.qty - 1));
$('qty-plus').addEventListener('click', () => setQty(S.qty + 1));
$('qty-max').addEventListener('click', () => setQty(maxFor(current())));
$('qty').addEventListener('change', (e) => setQty(e.target.value));

document.querySelectorAll('#shop-tabs .tab').forEach((t) => t.addEventListener('click', () => {
    if (S.mode === t.dataset.mode) return;
    S.mode = t.dataset.mode;
    S.selected = null;
    setMsg($('msg'), '');
    renderShop();
}));

$('confirm').addEventListener('click', async () => {
    const item = current();
    if (!item || S.busy) return;
    S.busy = true;
    $('confirm').disabled = true;

    const r = S.mode === 'buy'
        ? await nui('buy', { name: item.name, count: S.qty, payment: S.payment })
        : await nui('sell', { name: item.name, count: S.qty });

    S.busy = false;
    if (r && r.ok) {
        S.shop = r.shop;
        S.qty = 1;
        renderShop();
        setMsg($('msg'), r.message, true);
    } else {
        setMsg($('msg'), (r && r.error) || 'something went wrong', false);
        renderPick();
    }
});

function renderShop() {
    renderWallet();
    renderTabs();
    renderGrid();
    renderPick();
}

// =============================================================================================
// Admin shop manager
// =============================================================================================

const A = {
    data: null,
    editing: null,
    search: '',
    sort: 'distance',
    busy: false,
};

function distance(s) {
    const p = A.data.position;
    if (!p) return null;
    return Math.hypot(s.x - p.x, s.y - p.y, s.z - p.z);
}

function fmtDistance(d) {
    if (d === null) return '–';
    return d < 1000 ? `${Math.round(d)} m` : `${(d / 1000).toFixed(1)} km`;
}

function typeByName(name) {
    return A.data.types.find((t) => t.name === name) || null;
}

function openAdmin(data) {
    A.data = data;
    A.editing = null;
    $('shop').classList.add('hidden');
    $('admin').classList.remove('hidden');
    $('backdrop').classList.remove('hidden');
    fillTypes();
    resetForm();
    renderAdmin();
}

function fillTypes() {
    $('f-type').innerHTML = A.data.types.map((t) => `<option value="${esc(t.name)}">${esc(t.label)} (${esc(t.name)})</option>`).join('');
}

function typeInfo() {
    const t = typeByName($('f-type').value);
    if (!t) { $('type-info').textContent = ''; return; }
    const pay = t.payment.map((p) => ({ cash: 'cash', bank: 'bank', credit: 'card' }[p] || p)).join(', ');
    const parts = [
        `Sells ${t.sells}`,
        t.buys ? `buys ${t.buys}` : 'buys nothing',
        `pays with ${pay}`,
        t.hours ? `open ${String(t.hours[0]).padStart(2, '0')}:00–${String(t.hours[1]).padStart(2, '0')}:00` : 'always open',
        t.blip ? 'blip' : 'no blip',
    ];
    if (t.job) parts.push(`${t.job} only`);
    if (t.limited) parts.push('limited stock');
    $('type-info').textContent = parts.join(' · ');
    $('f-label').placeholder = t.label;
    $('f-ped').placeholder = t.ped;
}

$('f-type').addEventListener('change', typeInfo);

function setBlip(mode) {
    document.querySelectorAll('#f-blip input').forEach((i) => { i.checked = i.value === mode; });
}

function getBlip() {
    const i = document.querySelector('#f-blip input:checked');
    return i ? i.value : 'default';
}

function resetForm() {
    A.editing = null;
    $('form-title').textContent = 'Place a new shop';
    $('form-cancel').classList.add('hidden');
    $('new-actions').classList.remove('hidden');
    $('edit-actions').classList.add('hidden');
    $('f-label').value = '';
    $('f-ped').value = '';
    setBlip('default');
    disarm();
    typeInfo();
    renderPos();
}

function editShop(id) {
    const s = A.data.shops.find((x) => x.id === id);
    if (!s) return resetForm();
    A.editing = id;
    $('form-title').textContent = `Edit #${s.id}`;
    $('form-cancel').classList.remove('hidden');
    $('new-actions').classList.add('hidden');
    $('edit-actions').classList.remove('hidden');
    if (typeByName(s.type)) $('f-type').value = s.type;
    $('f-label').value = s.customLabel;
    $('f-ped').value = s.customPed;
    setBlip(s.blip);
    disarm();
    typeInfo();
    renderPos();
    setMsg($('admin-msg'), s.valid ? '' : 'This shop has a type that is no longer in config.lua. Pick a type and save.', false);
    renderAdmin();
}

function renderPos() {
    const p = A.data.position;
    const s = A.editing && A.data.shops.find((x) => x.id === A.editing);
    let text = p ? `You: ${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)} · heading ${Math.round(p.h)}°` : '';
    if (s) text = `Shop: ${s.x.toFixed(1)}, ${s.y.toFixed(1)}, ${s.z.toFixed(1)} · ${fmtDistance(distance(s))} away`;
    $('my-pos').textContent = text;
    $('place-hint').firstChild.textContent = s
        ? '“Move to me” puts this shopkeeper where you stand, facing your way. '
        : 'Stand where the shopkeeper should stand, facing the way they should face. ';
}

function renderAdmin() {
    const q = A.search.trim().toLowerCase();
    let rows = A.data.shops.filter((s) => !q
        || s.label.toLowerCase().includes(q)
        || s.type.toLowerCase().includes(q)
        || s.typeLabel.toLowerCase().includes(q)
        || `#${s.id}` === q || String(s.id) === q);

    if (A.sort === 'distance') rows.sort((a, b) => (distance(a) ?? 0) - (distance(b) ?? 0));
    else if (A.sort === 'id') rows.sort((a, b) => b.id - a.id);
    else rows.sort((a, b) => a.typeLabel.localeCompare(b.typeLabel) || a.id - b.id);

    $('admin-count').textContent = `${A.data.shops.length} shop${A.data.shops.length === 1 ? '' : 's'}`;
    $('admin-empty').classList.toggle('hidden', rows.length > 0);

    const blipPill = (s) => {
        const t = typeByName(s.type);
        const shown = s.blip === 'show' || (s.blip === 'default' && t && t.blip);
        const why = s.blip === 'default' ? '' : ' *';
        return `<span class="pill ${shown ? 'on' : 'off'}">${shown ? 'Shown' : 'Hidden'}${why}</span>`;
    };

    $('admin-rows').innerHTML = rows.map((s) => `
        <tr class="${s.id === A.editing ? 'current' : ''}${s.valid ? '' : ' bad'}">
            <td class="id">${s.id}</td>
            <td><div class="shop-name">${esc(s.label)}</div><div class="shop-type">${esc(s.typeLabel)}</div></td>
            <td>${blipPill(s)}</td>
            <td class="num">${fmtDistance(distance(s))}</td>
            <td><div class="row-actions">
                <button class="ghost small" data-go="${s.id}">Go</button>
                <button class="secondary small" data-edit="${s.id}">Edit</button>
            </div></td>
        </tr>`).join('');

    $('admin-rows').querySelectorAll('[data-edit]').forEach((b) => b.addEventListener('click', () => editShop(Number(b.dataset.edit))));
    $('admin-rows').querySelectorAll('[data-go]').forEach((b) => b.addEventListener('click', () => goTo(Number(b.dataset.go))));
}

async function goTo(id) {
    const s = A.data.shops.find((x) => x.id === id);
    if (!s) return;
    await nui('adminGoto', { x: s.x, y: s.y, z: s.z, h: s.h });
    setTimeout(refreshAdmin, 400);
}

async function refreshAdmin() {
    const r = await nui('adminRefresh');
    if (r && r.ok) {
        A.data = r;
        if (A.editing && !A.data.shops.some((s) => s.id === A.editing)) resetForm();
        renderPos();
        renderAdmin();
    }
}

async function act(action, data) {
    if (A.busy) return;
    A.busy = true;
    const r = await nui('adminAction', { action, data });
    A.busy = false;
    if (r && r.shops) {
        A.data = r;
    }
    if (r && r.ok) {
        if (action === 'place' || action === 'delete') resetForm();
        else if (A.editing) editShop(A.editing);
        setMsg($('admin-msg'), r.message, true);
    } else {
        setMsg($('admin-msg'), (r && r.error) || 'something went wrong', false);
    }
    renderPos();
    renderAdmin();
}

function formData() {
    return { type: $('f-type').value, label: $('f-label').value, ped: $('f-ped').value.trim(), blip: getBlip() };
}

$('place').addEventListener('click', () => act('place', formData()));
$('save').addEventListener('click', () => act('edit', { id: A.editing, ...formData() }));
$('move').addEventListener('click', () => act('move', { id: A.editing }));
$('restock').addEventListener('click', () => act('restock', { id: A.editing }));
$('form-cancel').addEventListener('click', () => { resetForm(); setMsg($('admin-msg'), ''); renderAdmin(); });

// Remove needs a second click within 3 seconds.
let armTimer = null;
function disarm() {
    clearTimeout(armTimer);
    $('delete').classList.remove('armed');
    $('delete').textContent = 'Remove';
}
$('delete').addEventListener('click', () => {
    if ($('delete').classList.contains('armed')) {
        disarm();
        act('delete', { id: A.editing });
        return;
    }
    $('delete').classList.add('armed');
    $('delete').textContent = 'Click again';
    armTimer = setTimeout(disarm, 3000);
});

$('admin-search').addEventListener('input', (e) => { A.search = e.target.value; renderAdmin(); });
$('admin-sort').addEventListener('change', (e) => { A.sort = e.target.value; renderAdmin(); });

// =============================================================================================
// Messages from the client script
// =============================================================================================

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'shop') openShop(m.shop, m.imagePath);
    else if (m.action === 'admin') openAdmin(m.data);
    else if (m.action === 'close') closeAll();
});
