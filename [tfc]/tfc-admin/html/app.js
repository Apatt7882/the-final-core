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
    jobs: [],
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
    else if (tab === 'world') loadWorld();
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
    renderJobPicker(p);
    $('freeze-btn').textContent = p.frozen ? 'Unfreeze' : 'Freeze';
    $('freeze-btn').classList.toggle('active', !!p.frozen);
    $('give-to').disabled = !p.loaded;
    $('kick').disabled = self;
}

// Set job: pick a job, then a rank. Starts on the player's current job.
let jobFor = null;
function renderJobPicker(p) {
    const jobSel = $('job-select');
    const disabled = !p.loaded || S.jobs.length === 0;
    if (jobFor !== p.id) {
        jobFor = p.id;
        jobSel.innerHTML = S.jobs.map((j) => `<option value="${esc(j.name)}">${esc(j.label)}</option>`).join('');
        if (p.jobName) jobSel.value = p.jobName;
        renderGrades(p.jobName === jobSel.value ? p.jobGrade : null);
    }
    jobSel.disabled = disabled;
    $('grade-select').disabled = disabled;
    $('set-job').disabled = disabled;
}

function renderGrades(selected) {
    const job = S.jobs.find((j) => j.name === $('job-select').value);
    const grades = job ? job.grades : [];
    $('grade-select').innerHTML = grades.map((g) => `<option value="${g.grade}">${esc(g.label)} · ${money(g.pay)}</option>`).join('');
    if (selected !== null && selected !== undefined && grades.some((g) => g.grade === selected)) $('grade-select').value = String(selected);
}

$('job-select').addEventListener('change', () => renderGrades(null));
$('set-job').addEventListener('click', () => {
    jobFor = null; // re-read their job after the change
    act('setjob', { job: $('job-select').value, grade: Number($('grade-select').value) });
});

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
    if (r && r.ok) { S.players = r.players; S.items = r.items; S.jobs = r.jobs || S.jobs; jobFor = null; renderPlayers(); }
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


// World -------------------------------------------------------------------------------------

const W = { state: null, busy: false, timer: null };
const pad = (n) => String(n).padStart(2, '0');

const PRIO = [['available', 'Available'], ['active', 'In progress'], ['cooldown', 'Cooldown'], ['hold', 'On hold']];

function renderWorld() {
    const w = W.state;
    $('w-off').classList.toggle('hidden', !!w);
    document.querySelectorAll('.world-card').forEach((c) => c.classList.toggle('hidden', !w));
    if (!w) return;

    $('w-aop-now').textContent = w.aop || '';
    if (document.activeElement !== $('w-aop')) $('w-aop').value = '';
    $('w-aop-presets').innerHTML = (w.aopPresets || []).map((a) => `<button class="ghost small" data-aop="${esc(a)}">${esc(a)}</button>`).join('');
    $('w-aop-presets').querySelectorAll('[data-aop]').forEach((b) => b.addEventListener('click', () => worldSet('aop', b.dataset.aop)));
    if (!W.coolSet && w.cooldownMinutes) { $('w-cool').value = w.cooldownMinutes; W.coolSet = true; }
    const prio = w.prio || {};
    $('w-prio').innerHTML = [['city', 'City'], ['county', 'County']].map(([zone, name]) => {
        const p = prio[zone] || {};
        return `<div class="prio-line"><span class="zone">${name}<small>${esc(p.label || '')}${p.detail ? ' · ' + esc(p.detail) : ''}</small></span>
            <div class="prio-btns">${PRIO.map(([st, l]) => `<button class="${st}${p.status === st ? ' on' : ''}" data-zone="${zone}" data-st="${st}">${l}</button>`).join('')}</div></div>`;
    }).join('');
    $('w-prio').querySelectorAll('[data-zone]').forEach((b) => b.addEventListener('click', () =>
        worldSet('prio', b.dataset.zone, { status: b.dataset.st, minutes: Number($('w-cool').value) || undefined })));

    $('w-now').textContent = `${pad(w.hour)}:${pad(w.minute)}${w.frozen ? ' (frozen)' : ''}`;
    $('w-freeze').checked = !!w.frozen;
    $('w-blackout').checked = !!w.blackout;
    $('w-snow').checked = !!w.snow;
    const current = (w.weathers || []).find((x) => x.id === w.weather);
    $('w-weather-now').textContent = w.snow ? 'Holiday snow' : (current ? current.label : w.weather);
    $('w-weathers').innerHTML = (w.weathers || []).map((x) =>
        `<button data-w="${esc(x.id)}" class="${x.id === w.weather ? 'on' : ''}"${w.snow ? ' disabled' : ''}>${esc(x.label)}</button>`).join('');
    $('w-weathers').querySelectorAll('[data-w]').forEach((b) => b.addEventListener('click', () => worldSet('weather', b.dataset.w)));
}

async function loadWorld() {
    const r = await nui('world', { action: 'state' });
    W.state = r && r.ok ? r : null;
    if (W.state) { $('w-hour').value = W.state.hour; $('w-minute').value = pad(W.state.minute); }
    renderWorld();
    clearInterval(W.timer);
    // Keep the clock display fresh while the tab is open.
    W.timer = setInterval(async () => {
        if (S.tab !== 'world' || $('backdrop').classList.contains('hidden')) return clearInterval(W.timer);
        const s = await nui('world', { action: 'state' });
        if (s && s.ok) { W.state = s; renderWorld(); }
    }, 4000);
}

async function worldSet(action, a, b) {
    if (W.busy) return;
    W.busy = true;
    const r = await nui('world', { action, a, b });
    W.busy = false;
    if (r && r.weathers) W.state = r;
    setMsg($('w-msg'), r && r.ok ? 'Done.' : ((r && r.error) || 'something went wrong'), r && r.ok);
    renderWorld();
}

$('w-set-aop').addEventListener('click', () => {
    const v = $('w-aop').value.trim();
    if (v) worldSet('aop', v); else setMsg($('w-msg'), 'Type an area of play first.', false);
});
$('w-aop').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('w-set-aop').click(); });

$('w-set-time').addEventListener('click', () => worldSet('time', Number($('w-hour').value), Number($('w-minute').value)));
document.querySelectorAll('#w-quick [data-h]').forEach((b) => b.addEventListener('click', () => {
    $('w-hour').value = b.dataset.h; $('w-minute').value = pad(b.dataset.m);
    worldSet('time', Number(b.dataset.h), Number(b.dataset.m));
}));
$('w-freeze').addEventListener('change', (e) => worldSet('freeze', e.target.checked));
$('w-blackout').addEventListener('change', (e) => worldSet('blackout', e.target.checked));
$('w-snow').addEventListener('change', (e) => worldSet('snow', e.target.checked));

// Messages ----------------------------------------------------------------------------------------

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') {
        S.me = m.data.me;
        S.players = m.data.players;
        S.items = m.data.items;
        S.jobs = m.data.jobs || [];
        jobFor = null;
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
