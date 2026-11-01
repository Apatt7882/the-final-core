'use strict';

// Inside FiveM, GetParentResourceName exists. In a normal browser we run a preview with sample data.
const IN_GAME = typeof GetParentResourceName === 'function';
const RESOURCE = IN_GAME ? GetParentResourceName() : 'tfc-multichar';
const NAME_RE = /^[A-Za-z][A-Za-z '\-]{0,31}$/;

const state = { characters: [], max: 0, selectedId: null, busy: false };
const $ = (id) => document.getElementById(id);

// ---------------------------------------------------------------------------
// Bridge

async function post(name, data = {}) {
    if (!IN_GAME) return preview(name, data);
    try {
        const res = await fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        });
        return await res.json();
    } catch {
        return { ok: false, error: 'could not reach the game client' };
    }
}

window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'open') open(msg);
    if (msg.action === 'close') close();
});

// ---------------------------------------------------------------------------
// Rendering

function escapeHtml(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function fullName(c) {
    return `${c.firstname} ${c.lastname}`;
}

function lastPlayed(seconds) {
    if (!seconds) return 'Never played';
    const days = Math.floor((Date.now() / 1000 - seconds) / 86400);
    if (days <= 0) return 'Played today';
    if (days === 1) return 'Played yesterday';
    return `Played ${days} days ago`;
}

function describe(c) {
    const parts = [];
    if (c.sex) parts.push(c.sex === 'f' ? 'Female' : 'Male');
    if (c.dob) parts.push(`Born ${c.dob}`);
    parts.push(lastPlayed(c.lastPlayed));
    return parts.join(' · ');
}

function selected() {
    return state.characters.find((c) => c.id === state.selectedId) || null;
}

function render() {
    const used = state.characters.length;
    $('slots').textContent = `${used} of ${state.max} character slots used`;

    const items = state.characters.map((c) => `
        <li>
            <button class="char" data-id="${c.id}" aria-pressed="${c.id === state.selectedId}">
                <span class="avatar">${escapeHtml(c.firstname[0])}${escapeHtml(c.lastname[0])}</span>
                <span class="name">${escapeHtml(fullName(c))}</span>
                <span class="meta">${escapeHtml(describe(c))}</span>
            </button>
        </li>`);

    if (used < state.max) {
        items.push(`<li><button class="new" id="new">+ ${used === 0 ? 'Create your first character' : 'New character'}</button></li>`);
    }

    $('list').innerHTML = items.join('');

    const hasSelection = selected() !== null;
    $('play').disabled = !hasSelection || state.busy;
    $('delete').disabled = !hasSelection || state.busy;
}

function showError(message) {
    const el = $('error');
    el.textContent = message ? capitalise(message) : '';
    el.classList.toggle('hidden', !message);
}

function capitalise(s) {
    return s.charAt(0).toUpperCase() + s.slice(1);
}

function applyResult(r) {
    if (r && Array.isArray(r.characters)) {
        state.characters = r.characters;
        if (typeof r.max === 'number') state.max = r.max;
        if (!selected()) state.selectedId = state.characters[0]?.id ?? null;
    }
}

// ---------------------------------------------------------------------------
// Screen

function open(msg) {
    state.characters = msg.characters || [];
    state.max = msg.max || 0;
    state.busy = false;
    state.selectedId = state.characters[0]?.id ?? null;
    showError(msg.error);
    render();
    $('app').classList.remove('hidden');
}

function close() {
    $('app').classList.add('hidden');
    closeModals();
}

$('list').addEventListener('click', (e) => {
    const card = e.target.closest('.char');
    if (card) {
        state.selectedId = Number(card.dataset.id);
        render();
        return;
    }
    if (e.target.closest('#new')) openCreate();
});

$('list').addEventListener('dblclick', (e) => {
    if (e.target.closest('.char')) play();
});

$('play').addEventListener('click', play);
$('delete').addEventListener('click', openDelete);

async function play() {
    const c = selected();
    if (!c || state.busy) return;
    state.busy = true;
    render();
    await post('play', { id: c.id, sex: c.sex });
}

// ---------------------------------------------------------------------------
// Modals

function closeModals() {
    document.querySelectorAll('.modal').forEach((m) => m.classList.add('hidden'));
}

document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', closeModals));

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeModals();
});

function setFormError(id, message) {
    const el = $(id);
    el.textContent = message ? capitalise(message) : '';
    el.classList.toggle('hidden', !message);
}

function openCreate() {
    const form = $('create-form');
    form.reset();
    setFormError('create-error', '');
    $('create-modal').classList.remove('hidden');
    form.firstname.focus();
}

$('create-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target;
    const data = {
        firstname: form.firstname.value.trim(),
        lastname: form.lastname.value.trim(),
        dob: form.dob.value,
        sex: form.sex.value,
    };

    if (!NAME_RE.test(data.firstname) || !NAME_RE.test(data.lastname)) {
        return setFormError('create-error', 'names must start with a letter and use letters, spaces, hyphens or apostrophes');
    }
    if (!data.dob) return setFormError('create-error', 'enter a date of birth');

    const before = new Set(state.characters.map((c) => c.id));

    $('create-submit').disabled = true;
    const r = await post('create', data);
    $('create-submit').disabled = false;

    if (!r || !r.ok) return setFormError('create-error', r?.error || 'could not create character');

    applyResult(r);
    const created = state.characters.find((c) => !before.has(c.id));
    if (created) state.selectedId = created.id;
    showError('');
    closeModals();
    render();
});

function openDelete() {
    const c = selected();
    if (!c) return;
    $('delete-name').textContent = fullName(c);
    $('delete-input').value = '';
    $('delete-submit').disabled = true;
    setFormError('delete-error', '');
    $('delete-modal').classList.remove('hidden');
    $('delete-input').focus();
}

$('delete-input').addEventListener('input', (e) => {
    const c = selected();
    $('delete-submit').disabled = !c || e.target.value.trim().toLowerCase() !== fullName(c).toLowerCase();
});

$('delete-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const c = selected();
    if (!c || $('delete-submit').disabled) return;

    $('delete-submit').disabled = true;
    const r = await post('delete', { id: c.id, confirm: $('delete-input').value });

    if (!r || !r.ok) {
        $('delete-submit').disabled = false;
        return setFormError('delete-error', r?.error || 'could not delete character');
    }

    state.selectedId = null;
    applyResult(r);
    closeModals();
    render();
});

// ---------------------------------------------------------------------------
// Browser preview (never runs in game)

let previewChars = [
    { id: 1, cid: 'K7Q2M9PA', slot: 1, firstname: 'Dev', lastname: 'Tester', dob: '1994-03-12', sex: 'm', lastPlayed: Date.now() / 1000 - 3600 },
    { id: 2, cid: 'HRX3REYC', slot: 2, firstname: 'Mary-Jo', lastname: "O'Neil", dob: '1990-05-04', sex: 'f', lastPlayed: Date.now() / 1000 - 86400 * 4 },
];

function preview(name, data) {
    if (name === 'create') {
        previewChars = [...previewChars, { id: Date.now(), slot: previewChars.length + 1, ...data, lastPlayed: null }];
    } else if (name === 'delete') {
        previewChars = previewChars.filter((c) => c.id !== data.id);
    } else if (name === 'play') {
        close();
        return { ok: true };
    }
    // Copy, like a real response, so the page never shares arrays with this preview.
    return { ok: true, characters: previewChars.map((c) => ({ ...c })), max: 10 };
}

if (!IN_GAME) {
    document.body.style.background = 'linear-gradient(135deg, #3b4a5e, #a07a55)';
    open({ characters: previewChars, max: 10 });
}
