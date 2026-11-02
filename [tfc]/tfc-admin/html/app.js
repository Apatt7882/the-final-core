// Admin menu: players (actions) and the item browser. The server checks every action.

const $ = (id) => document.getElementById(id);
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'tfc-admin';

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
const money = (n) => (n < 0 ? '-$' : '$') + Math.abs(Math.round(n)).toLocaleString('en-US');
const grams = (g) => (g >= 1000 ? `${(g / 1000).toFixed(1)} kg` : `${g} g`);

function setMsg(el, text, ok) {
    el.textContent = text || '';
    el.className = 'msg' + (text ? (ok ? ' ok' : ' err') : '');
}

const S = {
    me: null,
    players: [],
    items: [],
    maxGive: 1000,
    imagePath: '',
    tab: 'players',
    selected: null,     // player id
    search: '',
    item: null,         // item name
    itemSearch: '',
    cat: 'all',
    giveTarget: null,
    qty: 1,
    busy: false,
};

function close() {
    $('backdrop').classList.add('hidden');
    nui('close');
}

$('close').addEventListener('click', close);
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('backdrop').classList.contains('hidden')) close();
});

document.querySelectorAll('[data-self]').forEach((b) => b.addEventListener('click', () => {
    $('backdrop').classList.add('hidden');
    nui('self', { action: b.dataset.self });
}));

function setTab(tab) {
    S.tab = tab;
    document.querySelectorAll('.tab').forEach((t) => t.setAttribute('aria-selected', String(t.dataset.tab === tab)));
    document.querySelectorAll('[data-panel]').forEach((p) => p.classList.toggle('hidden', p.dataset.panel !== tab));
    if (tab === 'items') renderItems();
    else renderPlayers();
}

document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => setTab(t.dataset.tab)));

// Players -----------------------------------------------------------------------------------

function player(id) {
    return S.players.find((p) => p.id === id) || null;
}

function pills(p) {
    const out = [];
    if (!p.loaded) out.push('<span class="pill">Character select</span>');
    if (p.down) out.push('<span class="pill down">Down</span>');
    if (p.cuffed) out.push('<span class="pill cuffed">Cuffed</span>');
    if (p.jailed) out.push('<span class="pill jailed">Jailed</span>');
    if (p.frozen) out.push('<span class="pill frozen">Frozen</span>');
    if (p.admin) out.push('<span class="pill admin">Admin</span>');
    return `<div class="pills">${out.join('')}</div>`;
}

function renderPlayers() {
    const q = S.search.trim().toLowerCase();
    const rows = S.players.filter((p) => !q
        || String(p.id) === q
        || (p.name && p.name.toLowerCase().includes(q))
        || p.account.toLowerCase().includes(q));

    $('player-count').textContent = S.players.length;
    $('p-empty').classList.toggle('hidden', rows.length > 0);
    $('p-rows').innerHTML = rows.map((p) => `
        <tr data-id="${p.id}" class="${p.id === S.selected ? 'current' : ''}">
            <td class="id">${p.id}${p.id === S.me ? ' (you)' : ''}</td>
            <td><div class="pname">${esc(p.name || p.account)}</div><div class="acct">${p.name ? esc(p.account) : ''}</div></td>
            <td>${p.job ? `<div class="job">${esc(p.job)}</div>${p.onDuty === true ? '<div class="duty on">On duty</div>' : p.onDuty === false ? '<div class="duty">Off duty</div>' : ''}` : '<span class="muted">–</span>'}</td>
            <td>${pills(p)}</td>
            <td class="num">${p.ping} ms</td>
        </tr>`).join('');
    $('p-rows').querySelectorAll('tr').forEach((tr) => tr.addEventListener('click', () => {
        S.selected = Number(tr.dataset.id);
        setMsg($('p-msg'), '');
        renderPlayers();
    }));
    renderDetail();
}

function renderDetail() {
    const p = S.selected !== null ? player(S.selected) : null;
    $('p-none').classList.toggle('hidden', !!p);
    $('p-detail').classList.toggle('hidden', !p);
    if (!p) return;

    $('d-id').textContent = `ID ${p.id}${p.cid ? ` · ${p.cid}` : ''}`;
    $('d-name').textContent = p.name || p.account;
    $('d-account').textContent = p.name ? `FiveM: ${p.account}` : 'No character loaded';

    const facts = [];
    if (p.loaded) {
        if (p.job) facts.push(['Job', p.job + (p.onDuty === true ? ' (on duty)' : p.onDuty === false ? ' (off duty)' : '')]);
        if (p.cash !== undefined) facts.push(['Cash', money(p.cash)]);
        if (p.bank !== undefined) facts.push(['Bank', money(p.bank)]);
        facts.push(['Health', p.down ? 'Down' : `${Math.max(0, p.health - 100)}%`]);
    }
    facts.push(['Ping', `${p.ping} ms`]);
    $('d-facts').innerHTML = facts.map(([k, v]) => `<dt>${k}</dt><dd>${esc(v)}</dd>`).join('');

    const self = p.id === S.me;
    document.querySelectorAll('[data-act]').forEach((b) => {
        const a = b.dataset.act;
        b.disabled = (self && ['bring', 'spectate', 'freeze'].includes(a)) || (!p.loaded && ['revive', 'heal'].includes(a));
    });
    $('freeze-btn').textContent = p.frozen ? 'Unfreeze' : 'Freeze';
    $('freeze-btn').classList.toggle('active', !!p.frozen);
    $('give-to').disabled = !p.loaded;
    $('kick').disabled = self;
}

async function act(action, data) {
    if (S.busy || S.selected === null) return;
    S.busy = true;
    const r = await nui('action', { action, target: S.selected, data });
    S.busy = false;
    if (r.players) S.players = r.players;
    if (r.close) { $('backdrop').classList.add('hidden'); return; }
    setMsg($('p-msg'), r.ok ? r.message : r.error, r.ok);
    renderPlayers();
}

document.querySelectorAll('[data-act]').forEach((b) => b.addEventListener('click', () => act(b.dataset.act)));

$('give-to').addEventListener('click', () => {
    S.giveTarget = S.selected;
    setTab('items');
});

let kickTimer = null;
function disarmKick() { clearTimeout(kickTimer); $('kick').classList.remove('armed'); $('kick').textContent = 'Kick'; }
$('kick').addEventListener('click', () => {
    const reason = $('kick-reason').value.trim();
    if (reason.length < 3) { setMsg($('p-msg'), 'Give a reason to kick.', false); return; }
    if ($('kick').classList.contains('armed')) {
        disarmKick();
        $('kick-reason').value = '';
        act('kick', { reason });
        return;
    }
    $('kick').classList.add('armed');
    $('kick').textContent = 'Sure?';
    kickTimer = setTimeout(disarmKick, 3000);
});

$('p-search').addEventListener('input', (e) => { S.search = e.target.value; renderPlayers(); });
$('refresh').addEventListener('click', async () => {
    const r = await nui('refresh');
    if (r && r.ok) { S.players = r.players; S.items = r.items; renderPlayers(); }
});

// Items -------------------------------------------------------------------------------------

function itemByName(name) {
    return S.items.find((i) => i.name === name) || null;
}

function renderTargets() {
    const sel = $('i-target');
    const loaded = S.players.filter((p) => p.loaded);
    if (S.giveTarget === null || !loaded.some((p) => p.id === S.giveTarget)) S.giveTarget = S.me;
    sel.innerHTML = loaded.map((p) => `<option value="${p.id}"${p.id === S.giveTarget ? ' selected' : ''}>${p.id === S.me ? 'Me' : esc(p.name || p.account)} (${p.id})</option>`).join('');
}

function renderItems() {
    const q = S.itemSearch.trim().toLowerCase();
    const list = S.items.filter((i) => (S.cat === 'all' || i.category === S.cat)
        && (!q || i.label.toLowerCase().includes(q) || i.name.includes(q)));

    $('item-count').textContent = S.items.length;
    document.querySelectorAll('#i-cats .chip').forEach((c) => c.setAttribute('aria-pressed', String(c.dataset.cat === S.cat)));
    $('i-empty').classList.toggle('hidden', list.length > 0);
    $('i-grid').innerHTML = list.map((i) => `
        <button class="card${i.name === S.item ? ' selected' : ''}" data-name="${esc(i.name)}">
            <img src="${S.imagePath}${esc(i.name)}.png" alt="" onerror="this.style.visibility='hidden'">
            <span class="name">${esc(i.label)}</span><span class="code">${esc(i.name)}</span>
        </button>`).join('');
    $('i-grid').querySelectorAll('.card').forEach((c) => c.addEventListener('click', () => {
        S.item = c.dataset.name;
        setMsg($('i-msg'), '');
        renderItems();
    }));
    renderTargets();
    renderItemDetail();
}

function renderItemDetail() {
    const i = S.item ? itemByName(S.item) : null;
    $('i-none').classList.toggle('hidden', !!i);
    $('i-detail').classList.toggle('hidden', !i);
    if (!i) return;
    $('i-img').src = `${S.imagePath}${i.name}.png`;
    $('i-img').style.visibility = 'visible';
    $('i-img').onerror = function () { this.style.visibility = 'hidden'; };
    $('i-name').textContent = i.label;
    $('i-code').textContent = `${i.name} · ${grams(i.weight)}${i.stack ? '' : ' · unique'}`;
    $('i-desc').textContent = i.description;
    $('i-qty').value = S.qty;
    const target = player(S.giveTarget);
    $('give').textContent = `Give ${S.qty}× to ${S.giveTarget === S.me ? 'me' : (target ? (target.name || target.account) : '?')}`;
}

function setQty(n) {
    S.qty = Math.min(Math.max(1, Math.floor(Number(n) || 1)), S.maxGive);
    renderItemDetail();
}

$('q-minus').addEventListener('click', () => setQty(S.qty - 1));
$('q-plus').addEventListener('click', () => setQty(S.qty + 1));
$('i-qty').addEventListener('change', (e) => setQty(e.target.value));
document.querySelectorAll('#i-quick [data-q]').forEach((b) => b.addEventListener('click', () => setQty(b.dataset.q)));
$('i-target').addEventListener('change', (e) => { S.giveTarget = Number(e.target.value); renderItemDetail(); });
$('i-search').addEventListener('input', (e) => { S.itemSearch = e.target.value; renderItems(); });
document.querySelectorAll('#i-cats .chip').forEach((c) => c.addEventListener('click', () => { S.cat = c.dataset.cat; renderItems(); }));

$('give').addEventListener('click', async () => {
    if (S.busy || !S.item) return;
    S.busy = true;
    $('give').disabled = true;
    const r = await nui('action', { action: 'give', target: S.giveTarget, data: { item: S.item, count: S.qty } });
    S.busy = false;
    $('give').disabled = false;
    if (r.players) S.players = r.players;
    setMsg($('i-msg'), r.ok ? r.message : r.error, r.ok);
});

// Messages ----------------------------------------------------------------------------------------

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') {
        S.me = m.data.me;
        S.players = m.data.players;
        S.items = m.data.items;
        S.maxGive = m.data.maxGive;
        S.imagePath = m.imagePath || '';
        if (S.selected !== null && !player(S.selected)) S.selected = null;
        setMsg($('p-msg'), '');
        setMsg($('i-msg'), '');
        $('backdrop').classList.remove('hidden');
        setTab(m.tab || 'players');
    } else if (m.action === 'close') {
        $('backdrop').classList.add('hidden');
    }
});
