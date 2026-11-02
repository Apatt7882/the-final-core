'use strict';

// Renders inventories and turns drags into move requests. The server decides everything;
// the page just redraws from the 'update' messages it sends back.

const IN_GAME = typeof GetParentResourceName === 'function';
const RESOURCE = IN_GAME ? GetParentResourceName() : 'tfc-inventory';
const $ = (id) => document.getElementById(id);

const state = {
    items: {},          // item definitions
    imagePath: 'images/',
    hotbar: 5,
    player: null,       // inventory views
    secondary: null,
};

// Bridge ---------------------------------------------------------------------------------

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
    switch (msg.action) {
        case 'open': open(msg); break;
        case 'close': hide(); break;
        case 'update': update(msg.inventory); break;
        case 'hotbar': flashHotbar(msg); break;
        case 'secondaryClosed':
            if (state.secondary && state.secondary.id === msg.id) {
                state.secondary = null;
                render();
            }
            break;
    }
});

// Helpers ----------------------------------------------------------------------------------

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const kg = (g) => (g > 0 && g < 1000 ? `${Math.round(g)} g` : `${(g / 1000).toFixed(g % 1000 === 0 ? 0 : 1)} kg`);

function def(name) {
    return state.items[name] || { label: name, weight: 0 };
}

const META_LABELS = { serial: 'Serial', durability: 'Condition', ammo: 'Loaded', name: 'Name', dob: 'Born', cid: 'Citizen ID', number: 'Number' };

function metaRows(item, d) {
    const m = item.metadata || {};
    const order = ['durability', 'ammo', 'serial'];
    const keys = [...order.filter((k) => k in m), ...Object.keys(m).filter((k) => !order.includes(k))];
    return keys
        .filter((k) => !k.startsWith('_') && k !== 'weight')
        .map((k) => {
            let v = m[k];
            if (k === 'durability') v = `${Math.round(v)}%${v <= 0 ? ' (jammed)' : ''}`;
            else if (k === 'ammo' && d.clip) v = `${v} / ${d.clip}`;
            else if (typeof v === 'object') v = JSON.stringify(v);
            return `<dt>${esc(META_LABELS[k] || k)}</dt><dd>${esc(v)}</dd>`;
        }).join('');
}

function initials(label) {
    const words = label.split(/\s+/).filter(Boolean);
    return (words.length > 1 ? words[0][0] + words[1][0] : label.slice(0, 2)).toUpperCase();
}

function countText(item) {
    if (item.name === 'cash') return '';
    return item.count > 1 ? `${item.count}x` : '';
}

function labelText(item, d) {
    return item.name === 'cash' ? `$${item.count.toLocaleString('en-US')}` : d.label;
}

let toastTimer;
function toast(text) {
    const el = $('toast');
    el.textContent = text.charAt(0).toUpperCase() + text.slice(1);
    el.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.add('hidden'), 2600);
}

// Rendering ----------------------------------------------------------------------------------

function slotHtml(inv, slot, item, withKey) {
    const key = withKey && slot <= state.hotbar ? `<span class="key">${slot}</span>` : '';
    if (!item) return `<div class="slot" data-inv="${esc(inv)}" data-slot="${slot}">${key}</div>`;

    const d = def(item.name);
    const img = `<img src="${esc(state.imagePath + item.name)}.png" alt="" data-fallback="${esc(initials(d.label))}">`;
    const cond = item.metadata && typeof item.metadata.durability === 'number'
        ? `<span class="cond"><span style="width:${Math.max(0, Math.min(100, item.metadata.durability))}%" class="${item.metadata.durability <= 0 ? 'zero' : item.metadata.durability < 30 ? 'low' : ''}"></span></span>`
        : '';
    return `<div class="slot filled" data-inv="${esc(inv)}" data-slot="${slot}">
        ${key}
        ${cond}
        <span class="count">${esc(countText(item))}</span>
        ${img}
        <span class="label${item.name === 'cash' ? ' money' : ''}">${esc(labelText(item, d))}</span>
    </div>`;
}

// Swap broken images for a lettered tile (no inline handlers needed).
document.addEventListener('error', (e) => {
    const img = e.target;
    if (img.tagName !== 'IMG' || !img.dataset.fallback) return;
    const tile = document.createElement('span');
    tile.className = 'tile';
    tile.textContent = img.dataset.fallback;
    img.replaceWith(tile);
}, true);

const KINDS = { drop: 'Ground', trunk: 'Trunk', glovebox: 'Glovebox', stash: 'Stash', shop: 'Shop' };

function renderPanel(panel, inv, isPlayer) {
    if (!inv) {
        panel.classList.add('hidden');
        return;
    }
    panel.classList.remove('hidden');
    panel.querySelector('[data-title]').textContent = inv.label || '';
    const kicker = panel.querySelector('[data-kicker]');
    if (kicker) kicker.textContent = KINDS[inv.type] || inv.type || '';

    const pct = Math.min(100, (inv.weight / inv.maxWeight) * 100);
    panel.querySelector('[data-weight-text]').textContent = `${kg(inv.weight)} / ${kg(inv.maxWeight)}`;
    const fill = panel.querySelector('[data-weight-fill]');
    fill.style.width = `${pct}%`;
    fill.classList.toggle('full', pct >= 90);

    const bySlot = {};
    for (const it of inv.items) bySlot[it.slot] = it;
    const html = [];
    for (let s = 1; s <= inv.slots; s++) html.push(slotHtml(inv.id, s, bySlot[s], isPlayer));
    panel.querySelector('[data-grid]').innerHTML = html.join('');
}

function render() {
    renderPanel($('panel-player'), state.player, true);
    renderPanel($('panel-secondary'), state.secondary, false);
}

function findInv(id) {
    if (state.player && state.player.id === id) return state.player;
    if (state.secondary && state.secondary.id === id) return state.secondary;
    return null;
}

function itemAt(invId, slot) {
    const inv = findInv(invId);
    return inv ? inv.items.find((i) => i.slot === slot) : null;
}

// Flow ------------------------------------------------------------------------------------------

function open(msg) {
    state.items = msg.items || state.items;
    state.imagePath = msg.imagePath || state.imagePath;
    state.hotbar = msg.hotbar || state.hotbar;
    state.player = msg.player;
    state.secondary = msg.secondary || null;
    $('amount').value = '';
    $('hotbar').classList.add('hidden');
    render();
    $('screen').classList.remove('hidden');
}

function hide() {
    $('screen').classList.add('hidden');
    $('tooltip').classList.add('hidden');
    endDrag();
}

function close() {
    hide();
    post('close');
}

function update(inv) {
    if (!inv) return;
    if (state.player && inv.id === state.player.id) state.player = inv;
    else if (state.secondary && inv.id === state.secondary.id) state.secondary = inv;
    else if (inv.type === 'player') state.player = inv;
    if (!$('screen').classList.contains('hidden')) render();
}

document.addEventListener('keydown', (e) => {
    if ($('screen').classList.contains('hidden')) return;
    if (e.key === 'Escape' || e.key === 'F2' || (e.key === 'Tab' && document.activeElement !== $('amount'))) {
        e.preventDefault();
        close();
    }
});

// Use ---------------------------------------------------------------------------------------------

async function useSlot(invId, slot) {
    if (!state.player || invId !== state.player.id) return;
    const r = await post('use', { slot });
    if (!r.ok) toast(r.error || 'could not use that');
}

document.addEventListener('dblclick', (e) => {
    const el = e.target.closest('.slot.filled');
    if (el) useSlot(el.dataset.inv, Number(el.dataset.slot));
});

document.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    const el = e.target.closest('.slot.filled');
    if (el) useSlot(el.dataset.inv, Number(el.dataset.slot));
});

// Drag and drop (pointer-based; works the same in FiveM's browser) ---------------------------------

let drag = null; // { invId, slot, el, startX, startY, active }
let lastTarget = null;

document.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    const el = e.target.closest('.slot.filled');
    if (!el || !$('ghost').classList.contains('hidden')) return;
    drag = { invId: el.dataset.inv, slot: Number(el.dataset.slot), el, startX: e.clientX, startY: e.clientY, active: false };
});

document.addEventListener('mousemove', (e) => {
    moveTooltip(e);
    if (!drag) return;

    if (!drag.active) {
        if (Math.hypot(e.clientX - drag.startX, e.clientY - drag.startY) < 5) return;
        drag.active = true;
        drag.el.classList.add('dragging');
        const ghost = $('ghost');
        ghost.innerHTML = drag.el.outerHTML;
        ghost.classList.remove('hidden');
        $('tooltip').classList.add('hidden');
    }

    const ghost = $('ghost');
    ghost.style.left = `${e.clientX}px`;
    ghost.style.top = `${e.clientY}px`;

    const target = slotUnder(e.clientX, e.clientY);
    if (lastTarget && lastTarget !== target) lastTarget.classList.remove('drop-target');
    if (target && target !== drag.el) target.classList.add('drop-target');
    lastTarget = target;
});

document.addEventListener('mouseup', async (e) => {
    if (!drag) return;
    const d = drag;
    const wasActive = d.active;
    const target = slotUnder(e.clientX, e.clientY);
    endDrag();
    if (!wasActive || !target) return;

    const item = itemAt(d.invId, d.slot);
    if (!item) return;
    let count = item.count;
    const typed = parseInt($('amount').value, 10);
    if (e.shiftKey) count = Math.max(1, Math.floor(item.count / 2));
    else if (e.ctrlKey) count = 1;
    else if (typed > 0) count = Math.min(typed, item.count);

    if (target.dataset.give) {
        const g = await post('give', { slot: d.slot, count });
        if (!g.ok) toast(g.error || 'could not give that');
        return;
    }

    const toId = target.dataset.inv;
    const toSlot = Number(target.dataset.slot);
    if (toId === d.invId && toSlot === d.slot) return;

    const r = await post('move', { fromId: d.invId, fromSlot: d.slot, toId, toSlot, count });
    if (!r.ok) toast(r.error || 'could not move that');
});

function slotUnder(x, y) {
    const ghost = $('ghost');
    const hidden = ghost.classList.contains('hidden');
    if (!hidden) ghost.style.display = 'none';
    const el = document.elementFromPoint(x, y);
    if (!hidden) ghost.style.display = '';
    if (!el) return null;
    // Giving only works from your own inventory.
    const give = el.closest('#give-zone');
    if (give) return drag && state.player && drag.invId === state.player.id ? give : null;
    return el.closest('#screen .slot');
}

function endDrag() {
    if (drag && drag.el) drag.el.classList.remove('dragging');
    if (lastTarget) lastTarget.classList.remove('drop-target');
    lastTarget = null;
    drag = null;
    $('ghost').classList.add('hidden');
    $('ghost').innerHTML = '';
}

// Tooltip ------------------------------------------------------------------------------------------

function moveTooltip(e) {
    const tip = $('tooltip');
    if (drag && drag.active) return;
    const el = e.target.closest ? e.target.closest('#screen .slot.filled') : null;
    if (!el) {
        tip.classList.add('hidden');
        return;
    }
    const item = itemAt(el.dataset.inv, Number(el.dataset.slot));
    if (!item) return;
    const d = def(item.name);

    const meta = metaRows(item, d);
    const weight = (item.metadata && item.metadata.weight) || d.weight || 0;

    tip.innerHTML = `
        <div class="t-name">${esc(d.label)}${item.count > 1 && item.name !== 'cash' ? ` <span style="color:var(--muted)">x${item.count}</span>` : ''}</div>
        ${d.description ? `<div class="t-desc">${esc(d.description)}</div>` : ''}
        <dl class="t-meta">
            <dt>Weight</dt><dd>${kg(weight * item.count)}${item.count > 1 && weight ? ` (${kg(weight)} each)` : ''}</dd>
            ${meta}
        </dl>
        ${d.usable && el.dataset.inv === state.player.id ? `<div class="t-use">${d.weapon ? 'Double-click or use its hotbar key to hold / put away' : 'Double-click or right-click to use'}</div>` : ''}`;
    tip.classList.remove('hidden');

    const pad = 16;
    const w = tip.offsetWidth;
    const h = tip.offsetHeight;
    let x = e.clientX + pad;
    let y = e.clientY + pad;
    if (x + w > window.innerWidth) x = e.clientX - w - pad;
    if (y + h > window.innerHeight) y = e.clientY - h - pad;
    tip.style.left = `${x}px`;
    tip.style.top = `${y}px`;
}

// Hotbar flash ---------------------------------------------------------------------------------------

let hotbarTimer;
function flashHotbar(msg) {
    if (!$('screen').classList.contains('hidden')) return;
    state.items = msg.items || state.items;
    state.imagePath = msg.imagePath || state.imagePath;
    state.hotbar = msg.hotbar || state.hotbar;
    if (msg.player) state.player = msg.player;
    if (!state.player) return;

    const bySlot = {};
    for (const it of state.player.items) bySlot[it.slot] = it;
    const bar = $('hotbar');
    const html = [];
    for (let s = 1; s <= state.hotbar; s++) html.push(slotHtml('', s, bySlot[s], true));
    bar.innerHTML = html.join('');
    if (msg.used) {
        const used = bar.querySelector(`.slot[data-slot="${msg.used}"]`);
        if (used) used.classList.add('used');
    }

    bar.classList.remove('hidden', 'fade');
    clearTimeout(hotbarTimer);
    hotbarTimer = setTimeout(() => {
        bar.classList.add('fade');
        hotbarTimer = setTimeout(() => bar.classList.add('hidden'), 260);
    }, 2200);
}

// Browser preview (never runs in game) ------------------------------------------------------------------

const sampleItems = {
    cash: { label: 'Cash', weight: 0, description: 'Paper money. Counts as your cash balance.' },
    phone: { label: 'Phone', weight: 190, description: 'A smartphone.' },
    bandage: { label: 'Bandage', weight: 100, description: 'Stops minor bleeding. Restores some health.', usable: true },
    lockpick: { label: 'Lockpick', weight: 150, description: 'For locks that are not yours.' },
    radio: { label: 'Radio', weight: 600, description: 'A handheld two-way radio.' },
    id_card: { label: 'ID Card', weight: 10, description: 'Government-issued identification.' },
    repair_kit: { label: 'Repair Kit', weight: 2500, description: 'Basic tools to get a car running again.' },
    pistol: { label: 'Pistol', weight: 900, description: 'Uses 9mm Rounds.', usable: true, weapon: true, clip: 12 },
    carbinerifle: { label: 'Carbine Rifle', weight: 3400, description: 'Uses 5.56 Rounds.', usable: true, weapon: true, clip: 30 },
    ammo_9mm: { label: '9mm Rounds', weight: 8, description: 'For most pistols and SMGs.', usable: true },
    weed_bag: { label: 'Bag of Weed', weight: 30, description: 'A dime bag. Use with rolling papers to roll two joints.', usable: true },
    joint: { label: 'Joint', weight: 3, description: 'Takes the edge off.', usable: true },
    coke_bag: { label: 'Bag of Coke', weight: 10, description: 'Brief burst of speed.', usable: true },
    knife: { label: 'Knife', weight: 300, usable: true, weapon: true },
};

const sample = {
    id: 'player:1', type: 'player', label: 'Dev Tester', slots: 40, maxWeight: 30000, weight: 0,
    items: [
        { slot: 1, name: 'pistol', count: 1, metadata: { serial: 'TFC-7K2M9QXA', ammo: 9, durability: 86.4 } },
        { slot: 2, name: 'carbinerifle', count: 1, metadata: { serial: 'TFC-PL3NW8RD', ammo: 30, durability: 22 } },
        { slot: 3, name: 'bandage', count: 6 },
        { slot: 5, name: 'knife', count: 1 },
        { slot: 9, name: 'ammo_9mm', count: 48 },
        { slot: 13, name: 'weed_bag', count: 5 },
        { slot: 14, name: 'joint', count: 3 },
        { slot: 15, name: 'coke_bag', count: 2 },
        { slot: 4, name: 'phone', count: 1, metadata: { number: '555-0142' } },
        { slot: 6, name: 'cash', count: 1250 },
        { slot: 7, name: 'id_card', count: 1, metadata: { name: 'Dev Tester', dob: '1994-03-12', cid: 'K7Q2M9PA' } },
        { slot: 8, name: 'radio', count: 1 },
        { slot: 11, name: 'lockpick', count: 4 },
        { slot: 12, name: 'repair_kit', count: 2 },
    ],
};

function previewWeight(inv) {
    inv.weight = inv.items.reduce((w, i) => w + (sampleItems[i.name].weight || 0) * i.count, 0);
}

function preview(name, body) {
    if (name === 'move') {
        if (body.fromId !== body.toId) return { ok: false, error: 'preview: moving between inventories needs the game' };
        const inv = findInv(body.fromId);
        const a = inv.items.find((i) => i.slot === body.fromSlot);
        const b = inv.items.find((i) => i.slot === body.toSlot);
        if (!b) {
            if (body.count < a.count) {
                a.count -= body.count;
                inv.items.push({ ...a, slot: body.toSlot, count: body.count });
            } else a.slot = body.toSlot;
        } else if (b.name === a.name) {
            b.count += body.count;
            a.count -= body.count;
            if (a.count === 0) inv.items = inv.items.filter((i) => i !== a);
        } else {
            [a.slot, b.slot] = [b.slot, a.slot];
        }
        previewWeight(inv);
        setTimeout(() => update({ ...inv, items: inv.items.map((i) => ({ ...i })) }), 30);
        return { ok: true };
    }
    if (name === 'use') return { ok: false, error: 'preview: using items needs the game' };
    if (name === 'give') return { ok: false, error: 'nobody is close enough' };
    return { ok: true };
}

if (!IN_GAME) {
    document.body.style.background = 'linear-gradient(160deg, #6d8fb3 0%, #b9a27c 55%, #4b5a3c 100%)';
    previewWeight(sample);
    open({
        items: sampleItems, player: sample, imagePath: 'images/', hotbar: 5,
        secondary: { id: 'trunk:46LPZE29', type: 'trunk', label: 'Trunk (46LPZE29)', slots: 20, maxWeight: 40000, weight: 7600,
            items: [{ slot: 1, name: 'repair_kit', count: 2 }, { slot: 2, name: 'lockpick', count: 6 }, { slot: 5, name: 'radio', count: 1 }] },
    });
}
