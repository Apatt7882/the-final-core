'use strict';

// The menu only shows what the server says you can do; the server re-checks everything.

const IN_GAME = typeof GetParentResourceName === 'function';
const RESOURCE = IN_GAME ? GetParentResourceName() : 'tfc-jobs';
const $ = (id) => document.getElementById(id);

let data = null;       // last payload from the server
let jobs = [];         // jobs this player may open
let tab = 'overview';
let busy = false;

// Bridge ------------------------------------------------------------------------------

async function post(name, body = {}) {
    if (!IN_GAME) return preview(name, body);
    try {
        const res = await fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body),
        });
        return await res.json();
    } catch {
        return { ok: false, error: 'could not reach the game client' };
    }
}

window.addEventListener('message', (e) => {
    const msg = e.data || {};
    if (msg.action === 'open') open(msg.data);
    if (msg.action === 'close') $('backdrop').classList.add('hidden');
});

// Helpers -------------------------------------------------------------------------------

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => `$${Math.trunc(n || 0).toLocaleString('en-US')}`;
const cap = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : '');

function rankLabel(grade) {
    const r = data.ranks.find((x) => x.grade === grade);
    return r ? r.label : `Rank ${grade}`;
}

function ago(unix) {
    const s = Math.max(0, Date.now() / 1000 - unix);
    if (s < 60) return 'just now';
    if (s < 3600) return `${Math.floor(s / 60)} min ago`;
    if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
    return `${Math.floor(s / 86400)} d ago`;
}

let toastTimer;
function toast(text, good) {
    const el = $('toast');
    el.textContent = cap(text);
    el.className = `toast ${good ? 'good' : 'bad'}`;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.add('hidden'), 3200);
}

function confirmBox(text) {
    return new Promise((resolve) => {
        $('confirm-text').textContent = text;
        $('confirm').classList.remove('hidden');
        const finish = (v) => {
            $('confirm').classList.add('hidden');
            $('confirm-yes').onclick = $('confirm-no').onclick = null;
            resolve(v);
        };
        $('confirm-yes').onclick = () => finish(true);
        $('confirm-no').onclick = () => finish(false);
    });
}

// Permissions (display only) ---------------------------------------------------------------

const isAdmin = () => data.access.admin;
const isBoss = () => data.access.boss;
const myGrade = () => data.access.grade;

/** Ranks this player may move an employee to, or [] if they can't manage them. */
function rankOptions(emp) {
    if (isAdmin()) return data.ranks.map((r) => r.grade);
    if (!isBoss() || emp.cid === data.me || emp.grade >= myGrade()) return [];
    return data.ranks.filter((r) => r.grade < myGrade()).map((r) => r.grade);
}

function canFire(emp) {
    if (!isBoss() || emp.cid === data.me) return false;
    return isAdmin() || emp.grade < myGrade();
}

function hireRanks() {
    if (!isBoss()) return [];
    return data.ranks.filter((r) => isAdmin() || r.grade < myGrade()).map((r) => r.grade);
}

// Rendering ---------------------------------------------------------------------------------

function renderHeader() {
    $('title').textContent = data.job.label;
    const select = $('job-select');
    // With several jobs the dropdown replaces the title.
    select.classList.toggle('hidden', jobs.length < 2);
    $('title').classList.toggle('hidden', jobs.length >= 2);
    select.innerHTML = jobs.map((j) => `<option value="${esc(j.name)}" ${j.name === data.job.name ? 'selected' : ''}>${esc(j.label)}</option>`).join('');

    let badge = 'Admin';
    if (isBoss()) badge = `${isAdmin() ? 'Admin · ' : ''}${rankLabel(myGrade())}`;
    $('access').textContent = badge;

    document.querySelector('.tab[data-tab="hire"]').classList.toggle('hidden', !isBoss());
    if (tab === 'hire' && !isBoss()) setTab('overview');
}

function renderOverview() {
    const s = data.stats;
    const cards = [
        { label: 'Employees', value: s.total, sub: `${data.ranks.length} ranks` },
        { label: 'Online now', value: s.online, sub: `of ${s.total}` },
        { label: 'On duty', value: data.job.noDuty ? '—' : s.onDuty, sub: data.job.noDuty ? 'no duty for this job' : `of ${s.online} online` },
        { label: 'Payroll today', value: money(s.payroll.today), sub: `${money(s.payroll.week)} last 7 days` },
    ];
    $('stats').innerHTML = cards.map((c) => `
        <div class="stat">
            <div class="stat-label">${esc(c.label)}</div>
            <div class="stat-value">${esc(c.value)}</div>
            <div class="stat-sub">${esc(c.sub)}</div>
        </div>`).join('');

    const max = Math.max(1, ...data.ranks.map((r) => r.count));
    $('bars').innerHTML = [...data.ranks].reverse().map((r) => `
        <div class="bar-row">
            <span class="bar-label">${esc(r.label)}${r.boss ? '<span class="tag">Boss</span>' : ''}</span>
            <span class="bar-track"><span class="bar-fill" style="width:${(r.count / max) * 100}%"></span></span>
            <span class="bar-count">${r.count} · ${money(r.pay)}</span>
        </div>`).join('');
}

function renderEmployees() {
    const q = $('emp-search').value.trim().toLowerCase();
    const list = data.employees.filter((e) => !q || e.name.toLowerCase().includes(q) || rankLabel(e.grade).toLowerCase().includes(q));
    $('emp-count').textContent = `${data.employees.length} total`;
    $('emp-empty').classList.toggle('hidden', data.employees.length > 0);

    $('emp-body').innerHTML = list.map((e) => {
        const opts = rankOptions(e);
        // Include their current rank so the select shows it even if it's above what we may assign.
        const shown = opts.includes(e.grade) ? opts : [e.grade, ...opts];
        const rankCell = opts.length
            ? `<select data-act="setgrade" data-cid="${esc(e.cid)}">${[...shown].sort((a, b) => b - a).map((g) =>
                `<option value="${g}" ${g === e.grade ? 'selected' : ''} ${!opts.includes(g) ? 'disabled' : ''}>${esc(rankLabel(g))}</option>`).join('')}</select>`
            : esc(rankLabel(e.grade));

        let status = '<span class="status"><span class="dot"></span>Offline</span>';
        if (e.onDuty) status = '<span class="status"><span class="dot duty"></span>On duty</span>';
        else if (e.online) status = '<span class="status"><span class="dot online"></span>Online</span>';

        return `<tr>
            <td>${esc(e.name)}${e.cid === data.me ? '<span class="tag">You</span>' : ''}</td>
            <td>${rankCell}</td>
            <td>${status}</td>
            <td class="num">${e.hoursWeek.toFixed(1)}</td>
            <td class="actions-cell">${canFire(e) ? `<button class="btn btn-ghost btn-small" data-act="fire" data-cid="${esc(e.cid)}">Fire</button>` : ''}</td>
        </tr>`;
    }).join('');
}

let nearby = [];

function renderHire() {
    const ranks = hireRanks();
    $('hire-empty').classList.toggle('hidden', nearby.length > 0);
    $('hire-body').innerHTML = nearby.map((p) => `<tr>
        <td>${esc(p.name)}</td>
        <td class="muted">${esc(p.job)}</td>
        <td><select id="hire-grade-${p.id}">${ranks.map((g) => `<option value="${g}">${esc(rankLabel(g))}</option>`).join('')}</select></td>
        <td class="actions-cell"><button class="btn btn-primary btn-small" data-act="hire" data-id="${p.id}">Hire</button></td>
    </tr>`).join('');
}

async function loadNearby() {
    const r = await post('nearby', { job: data.job.name });
    if (!r.ok) return toast(r.error, false);
    nearby = r.players || [];
    renderHire();
}

function renderRanks() {
    const range = data.payRange;
    const hints = [];
    if (isBoss()) hints.push(`Bosses set pay from ${money(range.min)} to ${money(range.max)} per check (every ${data.paycheckMinutes} min).`);
    if (isAdmin()) hints.push('Admins can rename, add and remove ranks, and choose which ranks are bosses. Ranks with people in them cannot be removed.');
    $('ranks-hint').textContent = hints.join(' ');

    const top = data.ranks.length - 1;
    $('ranks-body').innerHTML = [...data.ranks].reverse().map((r) => {
        const name = isAdmin()
            ? `<input class="rank-input" value="${esc(r.label)}" maxlength="48" data-act="rename" data-grade="${r.grade}">`
            : `${esc(r.label)}`;
        const pay = isBoss()
            ? `<input class="pay-input" type="number" min="${range.min}" max="${range.max}" step="1" value="${r.pay}" data-act="pay" data-grade="${r.grade}">`
            : money(r.pay);
        const boss = isAdmin() && !data.job.isDefault
            ? `<input type="checkbox" class="switch" data-act="boss" data-grade="${r.grade}" ${r.boss ? 'checked' : ''}>`
            : (r.boss ? 'Yes' : '—');
        const remove = isAdmin() && top > 0
            ? `<button class="btn btn-ghost btn-small" data-act="removerank" data-grade="${r.grade}" ${r.count > 0 ? 'disabled title="Move everyone out of this rank first"' : ''}>Remove</button>`
            : '';
        return `<tr>
            <td class="num">${r.grade}</td>
            <td>${name}</td>
            <td>${pay}</td>
            <td>${boss}</td>
            <td class="num">${r.count}</td>
            <td class="actions-cell">${remove}</td>
        </tr>`;
    }).join('');

    const form = $('add-rank');
    const canAdd = isAdmin() && data.ranks.length < data.maxRanks;
    form.classList.toggle('hidden', !canAdd);
    if (canAdd) {
        form.pay.min = range.min;
        form.pay.max = range.max;
        if (!form.pay.value) form.pay.value = range.min;
        const options = [`<option value="${data.ranks.length}">Top (new highest rank)</option>`];
        for (let g = data.ranks.length - 1; g >= 0; g--) {
            options.push(`<option value="${g}">Below ${esc(rankLabel(g))}</option>`);
        }
        $('add-position').innerHTML = options.join('');
    }
}

function renderLog() {
    $('log-empty').classList.toggle('hidden', data.log.length > 0);
    $('log').innerHTML = data.log.map((l) => `<li>
        <time title="${new Date(l.at * 1000).toLocaleString()}">${ago(l.at)}</time>
        <div class="what">
            <span>${esc(l.actor)}</span> <span class="action">${esc(l.action)}</span>
            ${l.target ? `<span>${esc(l.target)}</span>` : ''}
            ${l.details ? `<div class="detail">${esc(l.details)}</div>` : ''}
        </div>
    </li>`).join('');
}

function render() {
    renderHeader();
    renderOverview();
    renderEmployees();
    renderRanks();
    renderLog();
    if (tab === 'hire') renderHire();
}

function setTab(name) {
    tab = name;
    document.querySelectorAll('.tab').forEach((t) => t.setAttribute('aria-selected', String(t.dataset.tab === name)));
    document.querySelectorAll('.panel').forEach((p) => p.classList.toggle('hidden', p.dataset.panel !== name));
    if (name === 'hire') loadNearby();
}

// Flow ------------------------------------------------------------------------------------------

function open(payload) {
    jobs = payload.jobs || [];
    data = payload;
    nearby = [];
    $('emp-search').value = '';
    setTab('overview');
    render();
    $('backdrop').classList.remove('hidden');
}

function close() {
    $('backdrop').classList.add('hidden');
    post('close');
}

/** Send an action, then re-render from the fresh data the server returns. */
async function act(action, body, successText) {
    if (busy) return;
    busy = true;
    const r = await post('action', { job: data.job.name, action, data: body });
    busy = false;

    if (r && r.ok) {
        data = { ...r, jobs };
        render();
    }
    if (!r || !r.actionOk) {
        toast((r && (r.actionError || r.error)) || 'something went wrong', false);
        if (r && r.ok) render(); // put inputs back to the real values
        return false;
    }
    toast(successText, true);
    return true;
}

// Events --------------------------------------------------------------------------------------------

$('close').addEventListener('click', close);
document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || $('backdrop').classList.contains('hidden')) return;
    if (!$('confirm').classList.contains('hidden')) $('confirm-no').click();
    else close();
});

document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => setTab(t.dataset.tab)));
$('emp-search').addEventListener('input', renderEmployees);
$('hire-refresh').addEventListener('click', loadNearby);

$('job-select').addEventListener('change', async (e) => {
    const r = await post('get', { job: e.target.value });
    if (!r.ok) return toast(r.error, false);
    data = { ...r, jobs };
    nearby = [];
    render();
    if (tab === 'hire') loadNearby();
});

$('emp-body').addEventListener('change', async (e) => {
    const el = e.target;
    if (el.dataset.act !== 'setgrade') return;
    const emp = data.employees.find((x) => x.cid === el.dataset.cid);
    const grade = Number(el.value);
    await act('setgrade', { cid: el.dataset.cid, grade }, `${emp.name} is now ${rankLabel(grade)}`);
});

$('emp-body').addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-act="fire"]');
    if (!btn) return;
    const emp = data.employees.find((x) => x.cid === btn.dataset.cid);
    if (!(await confirmBox(`Fire ${emp.name} from ${data.job.label}?`))) return;
    await act('fire', { cid: emp.cid }, `${emp.name} was fired`);
});

$('hire-body').addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-act="hire"]');
    if (!btn) return;
    const id = Number(btn.dataset.id);
    const p = nearby.find((x) => x.id === id);
    const grade = Number($(`hire-grade-${id}`).value);
    if (await act('hire', { target: id, grade }, `Hired ${p.name} as ${rankLabel(grade)}`)) loadNearby();
});

// Ranks: rename and pay save on change (Enter or leaving the field); boss flag on toggle.
$('ranks-body').addEventListener('change', async (e) => {
    const el = e.target;
    const grade = Number(el.dataset.grade);
    if (el.dataset.act === 'rename') await act('renamerank', { grade, label: el.value }, `Rank renamed to ${el.value.trim()}`);
    if (el.dataset.act === 'pay') await act('setpay', { grade, pay: Number(el.value) }, `${rankLabel(grade)} now earns ${money(Number(el.value))}`);
    if (el.dataset.act === 'boss') await act('setboss', { grade, boss: el.checked }, `${rankLabel(grade)} ${el.checked ? 'is now' : 'is no longer'} a boss rank`);
});

$('ranks-body').addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-act="removerank"]');
    if (!btn || btn.disabled) return;
    const grade = Number(btn.dataset.grade);
    if (!(await confirmBox(`Remove the rank "${rankLabel(grade)}"? Ranks above it move down one number.`))) return;
    await act('removerank', { grade }, 'Rank removed');
});

$('add-rank').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = e.target;
    const ok = await act('addrank', { label: f.label.value, pay: Number(f.pay.value), position: Number(f.position.value) }, `Added rank ${f.label.value.trim()}`);
    if (ok) f.reset();
});

// Browser preview (never runs in game) -----------------------------------------------------------------

function preview(name, body) {
    if (name === 'close') return {};
    if (name === 'nearby') return { ok: true, players: [{ id: 7, name: 'Jamie Cole', job: 'Unemployed' }, { id: 9, name: 'Sam Reed', job: 'Downtown Cab Co. Driver' }] };
    if (name === 'get') return { ...sample, job: { ...sample.job, label: jobs.find((j) => j.name === body.job).label } };
    if (name === 'action') return { ...sample, actionOk: true };
    return { ok: false, error: 'preview' };
}

const now = Date.now() / 1000;
const sample = {
    ok: true,
    me: 'K7Q2M9PA',
    jobs: [{ name: 'ambulance', label: 'EMS' }, { name: 'police', label: 'LSPD' }, { name: 'taxi', label: 'Downtown Cab Co.' }],
    job: { name: 'police', label: 'LSPD', noDuty: false, isDefault: false },
    access: { boss: true, admin: true, grade: 5 },
    payRange: { min: 200, max: 1200 },
    paycheckMinutes: 15,
    maxRanks: 20,
    ranks: [
        { grade: 0, label: 'Cadet', pay: 300, boss: false, count: 4 },
        { grade: 1, label: 'Officer', pay: 400, boss: false, count: 7 },
        { grade: 2, label: 'Sergeant', pay: 500, boss: false, count: 3 },
        { grade: 3, label: 'Lieutenant', pay: 600, boss: false, count: 1 },
        { grade: 4, label: 'Captain', pay: 700, boss: true, count: 1 },
        { grade: 5, label: 'Chief of Police', pay: 850, boss: true, count: 1 },
    ],
    employees: [
        { cid: 'K7Q2M9PA', name: 'Dev Tester', grade: 5, online: true, onDuty: true, hoursWeek: 12.5 },
        { cid: 'HRX3REYC', name: "Mary-Jo O'Neil", grade: 4, online: true, onDuty: false, hoursWeek: 9.0 },
        { cid: 'BUNW4SW3', name: 'Sam Reed', grade: 3, online: false, onDuty: false, hoursWeek: 6.2 },
        { cid: 'LATKRK3H', name: 'Jamie Cole', grade: 1, online: true, onDuty: true, hoursWeek: 14.8 },
        { cid: 'NPF8KXN4', name: 'Lee Park', grade: 0, online: false, onDuty: false, hoursWeek: 0.0 },
    ],
    stats: { total: 17, online: 9, onDuty: 6, payroll: { today: 18450, week: 96300 } },
    log: [
        { actor: 'Dev Tester (Andy)', action: 'promote', target: 'Jamie Cole', details: 'Cadet -> Officer', at: now - 300 },
        { actor: 'Dev Tester (Andy)', action: 'setpay', target: null, details: 'Officer: $350 -> $400', at: now - 5400 },
        { actor: "Mary-Jo O'Neil (MJ)", action: 'hire', target: 'Lee Park', details: 'as Cadet', at: now - 86400 * 2 },
    ],
};

if (!IN_GAME) {
    document.body.style.background = 'linear-gradient(160deg, #6d8fb3 0%, #b9a27c 55%, #4b5a3c 100%)';
    open(sample);
}
